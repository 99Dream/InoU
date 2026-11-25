import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:dio/dio.dart';
import 'package:inou_domain/inou_domain.dart';
import 'package:meta/meta.dart';
import 'package:uuid/uuid.dart';

import 'ai_endpoint_config.dart';
import 'ai_retry_policy.dart';
import 'capture_and_judge.dart';
import 'inou_llm_client.dart';
import 'llm_gateway.dart';
import 'prompt_library.dart';
import 'tutor_agent_service.dart';

/// Progress phases emitted during photo-search recognition & AI solving.
enum PhotoSearchStage {
  layoutAndOcr('layout_and_ocr', '1/3 识别图片题目内容'),
  aiSolving('ai_solving', '2/3 AI 独立求解与生成解析'),
  verifying('verifying', '3/3 核验答案与查重'),
  completed('completed', '搜题完成');

  const PhotoSearchStage(this.code, this.label);

  final String code;
  final String label;
}

typedef PhotoSearchProgressCallback = void Function(
  PhotoSearchStage stage,
  String note,
);

/// Output of [PhotoSearchService.searchAndSolveImage].
@immutable
class PhotoSearchResult {
  const PhotoSearchResult({
    required this.items,
    required this.suggestedTitle,
    required this.subject,
    required this.traceSteps,
    this.errorMessage,
  });

  final List<PhotoSearchItem> items;
  final String suggestedTitle;
  final String subject;
  final List<TutorToolTraceStep> traceSteps;
  final String? errorMessage;

  bool get ok => errorMessage == null || errorMessage!.isEmpty;
}

/// Photo-search pipeline for answer-free exam papers or single questions:
/// 1) `P-01` layout & subject detection,
/// 2) `P-02` structured question extraction + `P-03` envelope repair,
/// 3) `P-19` independent strong-tier AI solving with original photo context,
/// 4) SimHash duplicate check against existing library questions.
class PhotoSearchService {
  const PhotoSearchService({
    this.clientFactory = const InouLlmClientFactory(),
    this.jsonCaller = const StructuredJsonCaller(),
  });

  final InouLlmClientFactory clientFactory;
  final StructuredJsonCaller jsonCaller;
  static const Uuid _uuid = Uuid();

  Future<PhotoSearchResult> searchAndSolveImage({
    required StudentProfile profile,
    required Uint8List imageBytes,
    String imageMimeType = 'image/jpeg',
    String subject = SubjectCatalog.autoCode,
    bool lockSubject = false,
    required List<Question> existingQuestions,
    AiEndpointConfig? endpoint,
    String? apiKey,
    LLMClient? overrideClient,
    PhotoSearchProgressCallback? onProgress,
    CancelToken? cancelToken,
    bool runLayoutPrepass = false,
    void Function(
      List<PhotoSearchItem> initialItems, {
      required String suggestedTitle,
      required String subject,
    })?
    onItemsExtracted,
    void Function(
      PhotoSearchItem solvedItem, {
      required int completedCount,
      required int totalCount,
    })?
    onItemSolved,
  }) async {
    if (imageBytes.isEmpty) {
      return const PhotoSearchResult(
        items: [],
        suggestedTitle: '拍照搜题',
        subject: 'other',
        traceSteps: [],
        errorMessage: '未检测到题目图片，请先拍照或从相册选择照片。',
      );
    }

    final canRunRemote =
        overrideClient != null ||
        (endpoint != null && (apiKey ?? '').trim().isNotEmpty);
    if (!canRunRemote) {
      return const PhotoSearchResult(
        items: [],
        suggestedTitle: '拍照搜题',
        subject: 'other',
        traceSteps: [],
        errorMessage: '尚未配置 AI 视觉模型密钥，请先在「设置 → AI 接口」填入支持视觉的 API Key。',
      );
    }

    final client =
        overrideClient ??
        clientFactory.createClient(endpoint!, apiKey: apiKey!.trim());
    final effectiveEndpoint = endpoint ?? AiEndpointPresets.defaults().first;
    final streamApiKey = overrideClient == null ? apiKey?.trim() : null;
    final trace = <TutorToolTraceStep>[];

    var layoutMap = const <String, Object?>{};
    String? layoutSubject;
    final detectedKinds = <QuestionKind>{
      QuestionKind.choice,
      QuestionKind.fill,
      QuestionKind.solve,
      QuestionKind.response,
      QuestionKind.match,
    };

    if (runLayoutPrepass) {
      // Optional Stage 1: P-01 layout analysis
      onProgress?.call(PhotoSearchStage.layoutAndOcr, '正在定位图片中的题目区域与学科');
      final explicitHint = subject != SubjectCatalog.autoCode
          ? SubjectCatalog.labelOf(subject)
          : '';
      final p01 = PromptLibrary.get('P-01').render({
        'pageCount': '1',
        'subjectHint': explicitHint,
        'bboxOrder': effectiveEndpoint.bboxOrder.code,
      });
      final layoutRes = await jsonCaller.callJson(
        client: client,
        endpoint: effectiveEndpoint,
        tier: AiTier.fast,
        systemPrompt: p01.systemPrompt,
        userPrompt: p01.userPrompt,
        imageBytes: imageBytes,
        imageMimeType: imageMimeType,
        cancelToken: cancelToken,
        scene: 'photo_search',
        streamApiKey: streamApiKey,
        onRetry: (ev) =>
            onProgress?.call(PhotoSearchStage.layoutAndOcr, ev.statusMessage),
      );
      if (cancelToken?.isCancelled ?? false) {
        return PhotoSearchResult(
          items: const [],
          suggestedTitle: '拍照搜题',
          subject: subject,
          traceSteps: List.unmodifiable(trace),
          errorMessage: '已取消拍照搜题',
        );
      }

      layoutMap = layoutRes.asMap ?? const <String, Object?>{};
      layoutSubject = SubjectCatalog.tryParseCode(
        layoutMap['detectedSubject']?.toString(),
      );
      final regions = layoutMap['regions'] is List
          ? layoutMap['regions']! as List<Object?>
          : const <Object?>[];
      final guessedKinds = <QuestionKind>{};
      for (final r in regions) {
        final rMap = _asStringKeyMap(r);
        final guess = rMap?['kindGuess']?.toString();
        if (guess != null && guess.trim().isNotEmpty) {
          guessedKinds.add(_parseKindGuess(guess));
        }
      }
      if (guessedKinds.isNotEmpty) {
        detectedKinds
          ..clear()
          ..addAll(guessedKinds);
      }
      if (detectedKinds.contains(QuestionKind.response) ||
          detectedKinds.contains(QuestionKind.solve)) {
        detectedKinds.add(QuestionKind.fill);
      }
      trace.add(
        TutorToolTraceStep(
          toolName: 'P-01 layout_analysis',
          summary:
              'regions=${regions.length}, subject=${layoutSubject ?? subject}',
          isError: !layoutRes.ok,
          outputSnippet: layoutRes.ok
              ? '定位到 ${regions.length} 个候选题目区${layoutSubject != null ? '，学科：${SubjectCatalog.labelOf(layoutSubject)}' : ''}'
              : (layoutRes.errorMessage ?? '版面分析降级直抽'),
        ),
      );

      final rawLayoutErr =
          layoutRes.technicalError ?? layoutRes.errorMessage ?? '';
      if (!layoutRes.ok && layoutRes.isConnectionError) {
        InouDiagnosticsLogger.instance.error(
          'ai.photo_search',
          'P-01 layout analysis connection error',
          detail: rawLayoutErr,
        );
        return PhotoSearchResult(
          items: const [],
          suggestedTitle: '拍照搜题',
          subject: subject,
          traceSteps: List.unmodifiable(trace),
          errorMessage: AiUserErrorMessages.photoSearchFailedFallback(),
        );
      }
    }

    // Stage 2: P-02 structured question extraction
    onProgress?.call(PhotoSearchStage.layoutAndOcr, '正在识别题干、选项与学科');
    final gradeCode = _gradeCodeFor(profile.stage);
    final p02SubjectHint = subject != SubjectCatalog.autoCode
        ? subject
        : (layoutSubject ?? '');
    final p02 = PromptLibrary.get('P-02').render({
      'subjectHint': p02SubjectHint,
      'subjectLocked': lockSubject && subject != SubjectCatalog.autoCode,
      'gradeHint': gradeCode,
      'bboxOrder': effectiveEndpoint.bboxOrder.code,
      'layoutJson': layoutMap.isEmpty ? '' : jsonEncode(layoutMap),
      'schemaGuide': QuestionSchemaCatalog.promptGuideForKinds(detectedKinds),
    });
    final structRes = await jsonCaller.callJson(
      client: client,
      endpoint: effectiveEndpoint,
      tier: AiTier.balanced,
      systemPrompt: p02.systemPrompt,
      userPrompt: p02.userPrompt,
      imageBytes: imageBytes,
      imageMimeType: imageMimeType,
      cancelToken: cancelToken,
      scene: 'photo_search',
      streamApiKey: streamApiKey,
      onStreamProgress: (chars) => onProgress?.call(
        PhotoSearchStage.layoutAndOcr,
        '正在识别题目内容（已接收 $chars 字）…',
      ),
      onRetry: (ev) =>
          onProgress?.call(PhotoSearchStage.layoutAndOcr, ev.statusMessage),
    );
    if (cancelToken?.isCancelled ?? false) {
      return PhotoSearchResult(
        items: const [],
        suggestedTitle: '拍照搜题',
        subject: subject,
        traceSteps: List.unmodifiable(trace),
        errorMessage: '已取消拍照搜题',
      );
    }

    if (!structRes.ok) {
      InouDiagnosticsLogger.instance.error(
        'ai.photo_search',
        'P-02 structured extraction failed',
        detail: structRes.technicalError ?? structRes.errorMessage,
      );
      trace.add(
        TutorToolTraceStep(
          toolName: 'P-02 question_structuring',
          summary: 'ok=false',
          isError: true,
          outputSnippet: '结构化解析未通过（已尝试修复 ${structRes.repairAttempts} 次）',
        ),
      );
      return PhotoSearchResult(
        items: const [],
        suggestedTitle: '拍照搜题',
        subject: subject,
        traceSteps: List.unmodifiable(trace),
        errorMessage: AiUserErrorMessages.photoSearchFailedFallback(),
      );
    }

    final rawItems = _extractRawDraftList(structRes.decoded);
    final structMap = structRes.asMap;
    final structSubject = SubjectCatalog.tryParseCode(
      structMap?['detectedSubject']?.toString(),
    );
    trace.add(
      TutorToolTraceStep(
        toolName: 'P-02 question_structuring',
        summary: 'items=${rawItems.length}',
        outputSnippet: '成功抽取 ${rawItems.length} 道待求解题目',
      ),
    );

    if (rawItems.isEmpty) {
      return PhotoSearchResult(
        items: const [],
        suggestedTitle: '拍照搜题',
        subject: subject,
        traceSteps: List.unmodifiable(trace),
        errorMessage: '未在图片中识别到清晰的题目，请调整角度、保证光线充足后重试。',
      );
    }

    // Stage 3: Normalize & repair extracted questions, publish them early, then
    // concurrently run P-19 independent solving across up to 3 workers.
    final rawTitle =
        (structMap?['suggestedTitle'] as String?)?.trim().isNotEmpty == true
        ? (structMap!['suggestedTitle']! as String).trim()
        : ((layoutMap['suggestedTitle'] as String?)?.trim().isNotEmpty == true
              ? (layoutMap['suggestedTitle']! as String).trim()
              : '拍照搜题');

    final initialItems = await runBoundedPool<
      Map<String, Object?>,
      PhotoSearchItem
    >(
      rawItems,
      maxConcurrency: 3,
      cancelToken: cancelToken,
      worker: (i, rawItem) async {
        final qMap = Map<String, Object?>.from(
          _asStringKeyMap(rawItem['question']) ?? rawItem,
        );
        qMap['id'] ??= 'q_ps_${_uuid.v4().substring(0, 8)}';
        qMap['schema'] ??= 1;
        qMap['sourceType'] = 'photo_search';

        final rawBbox = qMap['bbox'] ?? rawItem['bbox'];
        final normalizedBbox = BboxNormalizer.normalize(
          rawBbox,
          order: effectiveEndpoint.bboxOrder,
        );
        if (normalizedBbox != null) {
          qMap['bbox'] = [
            normalizedBbox.ymin,
            normalizedBbox.xmin,
            normalizedBbox.ymax,
            normalizedBbox.xmax,
          ];
        }

        final aiItemSubject = SubjectCatalog.tryParseCode(
          _asStringKeyMap(qMap['meta'])?['subject']?.toString() ??
              rawItem['subject']?.toString(),
        );
        final candidateSubject =
            aiItemSubject ??
            structSubject ??
            layoutSubject ??
            (subject == SubjectCatalog.autoCode ? 'other' : subject);

        var question = Question.coerceFromAiMap(
          qMap,
          fallbackId: 'q_ps_${i + 1}',
          defaultSubject: candidateSubject,
          defaultGrade: gradeCode,
          defaultAnswerSource: AnswerSource.ai,
        ).copyWith(sourceType: 'photo_search');

        final issues = validateQuestionEnvelope(question);
        if (issues.isNotEmpty) {
          final repaired = await IngestionRepairAgent(
            jsonCaller: jsonCaller,
          ).repairQuestionMap(
            client: client,
            endpoint: effectiveEndpoint,
            brokenQuestionMap: question.toJson(),
            issues: issues,
            streamApiKey: streamApiKey,
          );
          if (repaired != null) {
            question = Question.coerceFromAiMap(
              repaired,
              fallbackId: question.id,
              defaultSubject: candidateSubject,
              defaultGrade: gradeCode,
              defaultAnswerSource: AnswerSource.ai,
            ).copyWith(sourceType: 'photo_search');
          }
        }

        question = _resolveQuestionSubject(
          question: question,
          aiItemSubject: aiItemSubject,
          aiDocSubject: structSubject ?? layoutSubject,
          requestedSubject: subject,
          lockSubject: lockSubject,
        );

        final rawAnswerHint =
            (qMap['answer'] ??
                    qMap['correctAnswer'] ??
                    rawItem['answer'] ??
                    rawItem['correctAnswer'])
                ?.toString();
        question =
            SequenceQuestionDetector.tryRescueAsSequence(
              question,
              rawAnswerHint: rawAnswerHint,
            ) ??
            question;

        final stem = question.plainText;
        final dupMatch = existingQuestions
            .where(
              (eq) => ContentTextUtils.isLikelyDuplicate(stem, eq.plainText),
            )
            .firstOrNull;
        final sortOrder = (rawItem['sortOrder'] as num?)?.toInt() ?? (i + 1);
        return PhotoSearchItem(
          id: 'psi_${_uuid.v4().substring(0, 8)}',
          sortOrder: sortOrder,
          question: question,
          answerSummary: '',
          confidence: question.meta.aiConfidence ?? 0.6,
          duplicateOfTitle: dupMatch?.header.title,
        );
      },
    );

    if (cancelToken?.isCancelled ?? false) {
      return PhotoSearchResult(
        items: const [],
        suggestedTitle: '拍照搜题',
        subject: subject,
        traceSteps: List.unmodifiable(trace),
        errorMessage: '已取消拍照搜题',
      );
    }

    final initialSubject = _dominantSubject(
      initialItems,
      fallback: structSubject ?? layoutSubject ?? subject,
    );
    onItemsExtracted?.call(
      List<PhotoSearchItem>.unmodifiable(initialItems),
      suggestedTitle: rawTitle,
      subject: initialSubject,
    );

    var completedCount = 0;
    onProgress?.call(
      PhotoSearchStage.aiSolving,
      '正在并发求解 ${initialItems.length} 道题（已完成 0/${initialItems.length}）',
    );
    final solvedEntries = await runBoundedPool<
      PhotoSearchItem,
      ({PhotoSearchItem item, TutorToolTraceStep trace})
    >(
      initialItems,
      maxConcurrency: 3,
      cancelToken: cancelToken,
      worker: (idx, baseItem) async {
        final solved = await solveSingleQuestion(
          profile: profile,
          question: baseItem.question,
          itemId: baseItem.id,
          sortOrder: baseItem.sortOrder,
          imageBytes: imageBytes,
          imageMimeType: imageMimeType,
          endpoint: effectiveEndpoint,
          apiKey: apiKey,
          overrideClient: client,
          cancelToken: cancelToken,
          onRetry: (ev) =>
              onProgress?.call(PhotoSearchStage.aiSolving, ev.statusMessage),
        );
        final withDup = solved.item.copyWith(
          duplicateOfTitle: baseItem.duplicateOfTitle,
        );
        completedCount++;
        onProgress?.call(
          PhotoSearchStage.aiSolving,
          '正在并发求解 ${initialItems.length} 道题（已完成 $completedCount/${initialItems.length}）',
        );
        onItemSolved?.call(
          withDup,
          completedCount: completedCount,
          totalCount: initialItems.length,
        );
        return (item: withDup, trace: solved.trace);
      },
    );

    if (cancelToken?.isCancelled ?? false) {
      return PhotoSearchResult(
        items: const [],
        suggestedTitle: '拍照搜题',
        subject: subject,
        traceSteps: List.unmodifiable(trace),
        errorMessage: '已取消拍照搜题',
      );
    }

    final solvedItems = <PhotoSearchItem>[];
    for (final entry in solvedEntries) {
      trace.add(entry.trace);
      solvedItems.add(entry.item);
    }

    final batchSubject = _dominantSubject(
      solvedItems,
      fallback: structSubject ?? layoutSubject ?? subject,
    );
    onProgress?.call(
      PhotoSearchStage.completed,
      '已求解 ${solvedItems.length} 题（${SubjectCatalog.labelOf(batchSubject)}）',
    );

    return PhotoSearchResult(
      items: List.unmodifiable(solvedItems),
      suggestedTitle: rawTitle,
      subject: batchSubject,
      traceSteps: List.unmodifiable(trace),
    );
  }

  /// Independently solves a single [Question] using `P-19` on `AiTier.strong`,
  /// optionally attaching the original [imageBytes] for diagrams/tables.
  /// Reusable both during batch photo search and single-question re-solve.
  Future<
    ({
      PhotoSearchItem item,
      TutorToolTraceStep trace,
      bool ok,
      String? errorMessage,
    })
  >
  solveSingleQuestion({
    required StudentProfile profile,
    required Question question,
    String? itemId,
    int sortOrder = 1,
    Uint8List? imageBytes,
    String imageMimeType = 'image/jpeg',
    AiEndpointConfig? endpoint,
    String? apiKey,
    LLMClient? overrideClient,
    CancelToken? cancelToken,
    void Function(AiRetryEvent)? onRetry,
    void Function(int charsReceived)? onStreamProgress,
  }) async {
    final effectiveId = itemId ?? 'psi_${_uuid.v4().substring(0, 8)}';
    final canRunRemote =
        overrideClient != null ||
        (endpoint != null && (apiKey ?? '').trim().isNotEmpty);
    if (!canRunRemote) {
      final fallbackQ = question.copyWith(
        meta: question.meta.copyWith(
          uncertainNote: '尚未配置 AI 接口密钥，无法独立生成答案与解析。',
        ),
      );
      return (
        item: PhotoSearchItem(
          id: effectiveId,
          sortOrder: sortOrder,
          question: fallbackQ,
          answerSummary: fallbackQ.formatReferenceAnswer(),
          confidence: 0.4,
        ),
        trace: const TutorToolTraceStep(
          toolName: 'P-19 photo_search_solve',
          summary: 'offline',
          isError: true,
          outputSnippet: '未配置 AI 密钥，跳过求解',
        ),
        ok: false,
        errorMessage: '尚未配置 AI 接口密钥',
      );
    }

    final client =
        overrideClient ??
        clientFactory.createClient(endpoint!, apiKey: apiKey!.trim());
    final effectiveEndpoint = endpoint ?? AiEndpointPresets.defaults().first;
    final p19 = PromptLibrary.get('P-19').render({
      'subject': SubjectCatalog.labelOf(question.meta.subject),
      'stage': profile.stage.label,
      'questionPublicJson': jsonEncode(question.toPublicView().toJson()),
      'schemaGuide': QuestionSchemaCatalog.promptGuideForKinds([question.kind]),
    });

    final res = await jsonCaller.callJson(
      client: client,
      endpoint: effectiveEndpoint,
      tier: AiTier.strong,
      systemPrompt: p19.systemPrompt,
      userPrompt: p19.userPrompt,
      imageBytes: (imageBytes != null && imageBytes.isNotEmpty)
          ? imageBytes
          : null,
      imageMimeType: imageMimeType,
      cancelToken: cancelToken,
      scene: 'photo_search',
      onRetry: onRetry,
      streamApiKey: apiKey?.trim(),
      disableThinkingForSpeed: false,
      onStreamProgress: onStreamProgress,
    );

    final map = res.asMap;
    if (!res.ok || map == null) {
      final techErr = res.technicalError ?? res.errorMessage ?? 'unknown';
      final userErr = AiUserErrorMessages.solveRetryHint();
      InouDiagnosticsLogger.instance.warn(
        'ai.photo_search',
        'P-19 solve failed for ${question.id}: $techErr',
      );
      final fallbackQ = question.copyWith(
        meta: question.meta.copyWith(
          answerSource: AnswerSource.ai,
          uncertainNote: userErr,
        ),
      );
      return (
        item: PhotoSearchItem(
          id: effectiveId,
          sortOrder: sortOrder,
          question: fallbackQ,
          answerSummary: fallbackQ.formatReferenceAnswer(),
          confidence: fallbackQ.meta.aiConfidence ?? 0.5,
        ),
        trace: TutorToolTraceStep(
          toolName: 'P-19 photo_search_solve',
          summary: 'q=${question.id}, ok=false',
          isError: true,
          outputSnippet: userErr,
        ),
        ok: false,
        errorMessage: userErr,
      );
    }

    final rawAnswerSummary = (map['answerSummary'] ?? map['answer'])
        ?.toString()
        .trim();
    var nextGrading = _asStringKeyMap(map['grading']) ?? question.grading;
    if (_needsGradingCoercion(question.kind, nextGrading) &&
        rawAnswerSummary != null &&
        rawAnswerSummary.isNotEmpty) {
      final coerced = Question.coerceFromAiMap({
        ...question.toJson(),
        if (nextGrading.isNotEmpty) 'grading': nextGrading,
        'answer': rawAnswerSummary,
      });
      nextGrading = coerced.grading;
    }

    final expBlocks = _parseExplanationBlocks(
      map['explanation'],
      fallback: question.explanation,
    );
    final keyPoints = _parseStringList(map['keyPoints']);
    final pitfallRaw = map['pitfallNote']?.toString().trim();
    final pitfallNote = (pitfallRaw != null && pitfallRaw.isNotEmpty)
        ? pitfallRaw
        : null;
    final conf = ((map['confidence'] as num?)?.toDouble() ?? 0.86).clamp(
      0.0,
      1.0,
    );
    final rawUncertain = map['uncertainNote']?.toString().trim();
    final uncertainNote = (rawUncertain != null && rawUncertain.isNotEmpty)
        ? rawUncertain
        : (conf < 0.75
              ? 'AI 求解置信度偏低（${(conf * 100).round()}%），建议结合原题人工核对'
              : null);

    final mergedTags = <String>[...question.meta.tags];
    for (final kp in keyPoints) {
      if (!mergedTags.contains(kp)) {
        mergedTags.add(kp);
      }
    }

    var updatedQ = question.copyWith(
      grading: Map<String, Object?>.unmodifiable(nextGrading),
      explanation: expBlocks,
      sourceType: 'photo_search',
      meta: QuestionMeta(
        subject: question.meta.subject,
        grade: question.meta.grade,
        difficulty: question.meta.difficulty,
        kpIds: question.meta.kpIds,
        tags: List.unmodifiable(mergedTags),
        sourceNo: question.meta.sourceNo,
        answerSource: conf >= 0.75
            ? AnswerSource.aiVerified
            : AnswerSource.ai,
        aiConfidence: conf,
        originQuestionId: question.meta.originQuestionId,
        variationNote: question.meta.variationNote,
        uncertainNote: uncertainNote,
      ),
    );
    updatedQ =
        SequenceQuestionDetector.tryRescueAsSequence(
          updatedQ,
          rawAnswerHint: rawAnswerSummary,
        ) ??
        updatedQ;

    final formattedSummary = updatedQ.formatReferenceAnswer();
    final effectiveSummary =
        (rawAnswerSummary != null && rawAnswerSummary.isNotEmpty)
        ? rawAnswerSummary
        : formattedSummary;

    return (
      item: PhotoSearchItem(
        id: effectiveId,
        sortOrder: sortOrder,
        question: updatedQ,
        answerSummary: effectiveSummary,
        keyPoints: keyPoints,
        pitfallNote: pitfallNote,
        confidence: conf,
      ),
      trace: TutorToolTraceStep(
        toolName: 'P-19 photo_search_solve',
        summary: 'q=${updatedQ.id}, conf=${conf.toStringAsFixed(2)}',
        outputSnippet: effectiveSummary.isNotEmpty
            ? '生成答案：$effectiveSummary'
            : '已完成步骤解析生成',
      ),
      ok: true,
      errorMessage: null,
    );
  }

  static bool _needsGradingCoercion(
    QuestionKind kind,
    Map<String, Object?> grading,
  ) {
    if (grading.isEmpty) return true;
    switch (kind) {
      case QuestionKind.choice:
      case QuestionKind.fill:
        final sets = grading['answerSets'];
        return sets is! List || sets.isEmpty;
      case QuestionKind.solve:
        return grading['finalAnswer'] is! Map;
      default:
        return false;
    }
  }

  static List<ContentBlock> _parseExplanationBlocks(
    Object? raw, {
    required List<ContentBlock> fallback,
  }) {
    if (raw is String && raw.trim().isNotEmpty) {
      return [TextBlock(raw.trim())];
    }
    if (raw is List) {
      final out = <ContentBlock>[];
      for (final item in raw) {
        if (item is String && item.trim().isNotEmpty) {
          out.add(TextBlock(item.trim()));
        } else if (item is Map) {
          final map = item.map((k, v) => MapEntry(k.toString(), v));
          try {
            out.add(ContentBlock.fromJson(map));
          } catch (_) {
            final text = (map['text'] ?? map['content'] ?? '').toString().trim();
            if (text.isNotEmpty) out.add(TextBlock(text));
          }
        }
      }
      if (out.isNotEmpty) return List.unmodifiable(out);
    }
    return fallback;
  }

  static List<String> _parseStringList(Object? raw) {
    if (raw is! List) return const [];
    final out = <String>[];
    for (final item in raw) {
      final s = item?.toString().trim() ?? '';
      if (s.isNotEmpty && !out.contains(s)) {
        out.add(s);
      }
    }
    return List.unmodifiable(out);
  }

  List<Map<String, Object?>> _extractRawDraftList(Object? decoded) {
    if (decoded is List) {
      return decoded
          .map(_asStringKeyMap)
          .whereType<Map<String, Object?>>()
          .toList();
    }
    if (decoded is Map) {
      final map = _asStringKeyMap(decoded) ?? const {};
      final list = map['items'] ?? map['questions'] ?? map['regions'];
      if (list is List) {
        return list
            .map(_asStringKeyMap)
            .whereType<Map<String, Object?>>()
            .toList();
      }
      if (map.containsKey('kind') || map.containsKey('question')) {
        return [map];
      }
    }
    return const [];
  }

  Map<String, Object?>? _asStringKeyMap(Object? raw) {
    if (raw is Map<String, Object?>) return raw;
    if (raw is Map) {
      return raw.map((k, v) => MapEntry(k.toString(), v));
    }
    return null;
  }

  String _gradeCodeFor(StudyStage stage) => switch (stage) {
    StudyStage.primary => 'g5',
    StudyStage.middle => 'g9',
    StudyStage.high => 'g11',
  };

  QuestionKind _parseKindGuess(String raw) {
    final lower = raw.trim().toLowerCase();
    if (lower.contains('sequence') ||
        lower.contains('sort') ||
        lower.contains('order') ||
        lower.contains('排序') ||
        lower.contains('连词成句') ||
        lower.contains('fill')) {
      return QuestionKind.fill;
    }
    return switch (lower) {
      'choice' ||
      'mcq' ||
      'judge' ||
      'true_false' ||
      '选择' => QuestionKind.choice,
      'match' || 'matching' || 'pair' || '连线' => QuestionKind.match,
      'classify' || '分类' => QuestionKind.classify,
      'response' || 'short_answer' || 'essay' || '简答' => QuestionKind.response,
      'group' || 'reading' => QuestionKind.group,
      'draw' => QuestionKind.draw,
      'spatial' => QuestionKind.spatial,
      'write' => QuestionKind.write,
      _ => QuestionKind.solve,
    };
  }

  Question _resolveQuestionSubject({
    required Question question,
    required String? aiItemSubject,
    required String? aiDocSubject,
    required String requestedSubject,
    required bool lockSubject,
  }) {
    if (lockSubject && requestedSubject != SubjectCatalog.autoCode) {
      final locked = SubjectCatalog.normalize(requestedSubject);
      return question.meta.subject == locked
          ? question
          : question.copyWith(meta: question.meta.copyWith(subject: locked));
    }

    final preferred =
        aiItemSubject ??
        aiDocSubject ??
        (requestedSubject == SubjectCatalog.autoCode ? null : requestedSubject);
    final searchable = SubjectDetector.searchableTextOfQuestion(question);
    final allowOverride = aiItemSubject == null || aiItemSubject == 'math';
    final resolved = SubjectDetector.resolveSubjectForText(
      searchable,
      preferredSubject: preferred,
      allowOverrideDefault: allowOverride,
    );
    return question.meta.subject == resolved
        ? question
        : question.copyWith(meta: question.meta.copyWith(subject: resolved));
  }

  String _dominantSubject(
    List<PhotoSearchItem> items, {
    required String fallback,
  }) {
    if (items.isEmpty) {
      return SubjectCatalog.normalize(fallback, fallback: 'other');
    }
    final counts = <String, int>{};
    for (final item in items) {
      final s = item.question.meta.subject;
      counts[s] = (counts[s] ?? 0) + 1;
    }
    final concrete = counts.entries.where((e) => e.key != 'other').toList();
    final pool = concrete.isNotEmpty ? concrete : counts.entries.toList();
    pool.sort((a, b) => b.value.compareTo(a.value));
    return pool.first.key;
  }
}
