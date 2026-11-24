import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:dio/dio.dart';
import 'package:inou_domain/inou_domain.dart';
import 'package:meta/meta.dart';
import 'package:uuid/uuid.dart';

import 'ai_endpoint_config.dart';
import 'inou_llm_client.dart';
import 'llm_gateway.dart';
import 'prompt_library.dart';
import 'tutor_agent_service.dart';

/// Normalizes bounding boxes from either `yxyx1000` (Gemini default) or
/// `xyxy1000` (OpenAI-compatible vision endpoints) into InoU's canonical
/// `NormalizedBbox(ymin, xmin, ymax, xmax)`.
abstract final class BboxNormalizer {
  static NormalizedBbox? normalize(Object? raw, {required BboxOrder order}) {
    if (raw is! List<Object?> || raw.length != 4) return null;
    final nums = raw.map((e) => (e as num?)?.round()).toList();
    if (nums.any((e) => e == null)) return null;
    final a = nums[0]!.clamp(0, 1000);
    final b = nums[1]!.clamp(0, 1000);
    final c = nums[2]!.clamp(0, 1000);
    final d = nums[3]!.clamp(0, 1000);

    final (ymin, xmin, ymax, xmax) = switch (order) {
      BboxOrder.yxyx1000 => (a, b, c, d),
      BboxOrder.xyxy1000 => (b, a, d, c),
    };
    return NormalizedBbox(
      math.min(ymin, ymax),
      math.min(xmin, xmax),
      math.max(ymin, ymax),
      math.max(xmin, xmax),
    );
  }
}

/// Progress phase emitted during two-stage capture & validation.
enum CaptureStage {
  layoutAnalysis('layout_analysis', '1/4 版面识别与红叉定位'),
  questionStructuring('question_structuring', '2/4 题型结构化抽取'),
  answerSelfCheck('answer_self_check', '3/4 答案核对与独立验算'),
  validationAndDedup('validation_and_dedup', '4/4 Schema 校验与 SimHash 去重'),
  completed('completed', '解析完成');

  const CaptureStage(this.code, this.label);
  final String code;
  final String label;
}

typedef CaptureProgressCallback = void Function(
  CaptureStage stage,
  String note,
);

/// Output of [IngestionPipeline].
@immutable
class IngestionBatchResult {
  const IngestionBatchResult({
    required this.drafts,
    required this.suggestedDocTitle,
    required this.subject,
    required this.traceSteps,
    required this.usedOfflineFallback,
    this.repairCount = 0,
    this.errorMessage,
  });

  final List<CaptureDraftItem> drafts;
  final String suggestedDocTitle;
  final String subject;
  final List<TutorToolTraceStep> traceSteps;
  final bool usedOfflineFallback;
  final int repairCount;
  final String? errorMessage;

  bool get ok => errorMessage == null || errorMessage!.isEmpty;
}

/// Two-stage OCR & AI Question Ingestion Pipeline (`P-01` -> `P-02` ->
/// `P-03` [IngestionRepairAgent] -> `P-04`/`P-05` selfCheck -> SimHash dedup).
class IngestionPipeline {
  const IngestionPipeline({
    this.clientFactory = const InouLlmClientFactory(),
    this.jsonCaller = const StructuredJsonCaller(),
  });

  final InouLlmClientFactory clientFactory;
  final StructuredJsonCaller jsonCaller;
  static const Uuid _uuid = Uuid();

  Future<IngestionBatchResult> ingestPage({
    required StudentProfile profile,
    Uint8List? examImageBytes,
    String examImageMimeType = 'image/jpeg',
    Uint8List? answerImageBytes,
    String subject = SubjectCatalog.autoCode,
    bool lockSubject = false,
    String docTitleHint = '拍照试卷',
    required List<Question> existingQuestions,
    AiEndpointConfig? endpoint,
    String? apiKey,
    LLMClient? overrideClient,
    CaptureProgressCallback? onProgress,
    CancelToken? cancelToken,
  }) async {
    if (examImageBytes == null || examImageBytes.isEmpty) {
      return IngestionBatchResult(
        drafts: const [],
        suggestedDocTitle: docTitleHint,
        subject: subject,
        traceSteps: const [],
        usedOfflineFallback: true,
        errorMessage: '未检测到试卷图片，请先拍照或从相册选择试卷照片。',
      );
    }

    final canRunRemote =
        overrideClient != null ||
        (endpoint != null && (apiKey ?? '').trim().isNotEmpty);

    if (!canRunRemote) {
      return IngestionBatchResult(
        drafts: const [],
        suggestedDocTitle: docTitleHint,
        subject: subject,
        traceSteps: const [],
        usedOfflineFallback: true,
        errorMessage: '尚未配置 AI 视觉模型密钥，请先在「设置 → AI 接口」填入支持视觉的 API Key。',
      );
    }

    final client =
        overrideClient ??
        clientFactory.createClient(endpoint!, apiKey: apiKey!.trim());
    final effectiveEndpoint = endpoint ?? AiEndpointPresets.defaults().first;
    final trace = <TutorToolTraceStep>[];
    var repairCount = 0;

    // Stage 1: P-01 layout analysis
    onProgress?.call(CaptureStage.layoutAnalysis, '识别版面区块、学科类型与批改标记');
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
      imageBytes: examImageBytes,
      imageMimeType: examImageMimeType,
      cancelToken: cancelToken,
    );
    if (cancelToken?.isCancelled ?? false) {
      return IngestionBatchResult(
        drafts: const [],
        suggestedDocTitle: docTitleHint,
        subject: subject,
        traceSteps: List.unmodifiable(trace),
        usedOfflineFallback: false,
        errorMessage: '已取消识题任务',
      );
    }

    final layoutMap = layoutRes.asMap ?? const <String, Object?>{};
    final layoutSubject = SubjectCatalog.tryParseCode(
      layoutMap['detectedSubject']?.toString(),
    );
    final regions = layoutMap['regions'] is List
        ? layoutMap['regions']! as List<Object?>
        : const <Object?>[];
    final detectedKinds = <QuestionKind>{};
    for (final r in regions) {
      final rMap = _asStringKeyMap(r);
      final guess = rMap?['kindGuess']?.toString();
      if (guess != null && guess.trim().isNotEmpty) {
        detectedKinds.add(_parseKindGuess(guess));
      }
    }
    // Always inject `fill` schema (covering `fill.sequence` sorting & blanks)
    // whenever layout guessed `response`/`solve` so P-02 does not misclassify
    // sorting or word-ordering items as open-ended short answers.
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
            ? '识别出 ${regions.length} 个候选题目区${layoutSubject != null ? '，学科判定：${SubjectCatalog.labelOf(layoutSubject)}' : ''}'
            : (layoutRes.errorMessage ?? '版面分析降级直抽'),
      ),
    );

    final rawLayoutErr = layoutRes.errorMessage ?? '';
    if (!layoutRes.ok &&
        (rawLayoutErr.contains('401') ||
            rawLayoutErr.contains('403') ||
            rawLayoutErr.contains('Unauthorized') ||
            rawLayoutErr.contains('SocketException') ||
            rawLayoutErr.contains('Failed host lookup'))) {
      InouDiagnosticsLogger.instance.error(
        'ai.capture',
        'P-01 layout analysis connection error',
        detail: rawLayoutErr,
      );
      return IngestionBatchResult(
        drafts: const [],
        suggestedDocTitle: docTitleHint,
        subject: subject,
        traceSteps: List.unmodifiable(trace),
        usedOfflineFallback: false,
        errorMessage: 'AI 接口连接失败：$rawLayoutErr',
      );
    }

    // Stage 2: P-02 structured question extraction guided by `res-hub` schemas
    onProgress?.call(CaptureStage.questionStructuring, '对照题型规范抽取题干、学科与答案');
    final gradeCode = _gradeCodeFor(profile.stage);
    final p02SubjectHint = subject != SubjectCatalog.autoCode
        ? subject
        : (layoutSubject ?? '');
    final p02 = PromptLibrary.get('P-02').render({
      'subjectHint': p02SubjectHint,
      'subjectLocked': lockSubject && subject != SubjectCatalog.autoCode,
      'gradeHint': gradeCode,
      'bboxOrder': effectiveEndpoint.bboxOrder.code,
      'layoutJson': jsonEncode(layoutMap),
      'schemaGuide': QuestionSchemaCatalog.promptGuideForKinds(detectedKinds),
    });
    final structRes = await jsonCaller.callJson(
      client: client,
      endpoint: effectiveEndpoint,
      tier: AiTier.balanced,
      systemPrompt: p02.systemPrompt,
      userPrompt: p02.userPrompt,
      imageBytes: examImageBytes,
      imageMimeType: examImageMimeType,
      cancelToken: cancelToken,
    );
    if (cancelToken?.isCancelled ?? false) {
      return IngestionBatchResult(
        drafts: const [],
        suggestedDocTitle: docTitleHint,
        subject: subject,
        traceSteps: List.unmodifiable(trace),
        usedOfflineFallback: false,
        repairCount: repairCount,
        errorMessage: '已取消识题任务',
      );
    }
    repairCount += structRes.repairAttempts;

    if (!structRes.ok) {
      InouDiagnosticsLogger.instance.error(
        'ai.capture',
        'P-02 structured question extraction failed',
        detail: structRes.errorMessage,
      );
      trace.add(
        TutorToolTraceStep(
          toolName: 'P-02 question_structuring',
          summary: 'ok=false',
          isError: true,
          outputSnippet: structRes.errorMessage ?? '结构化解析失败',
        ),
      );
      return IngestionBatchResult(
        drafts: const [],
        suggestedDocTitle: docTitleHint,
        subject: subject,
        traceSteps: List.unmodifiable(trace),
        usedOfflineFallback: false,
        repairCount: repairCount,
        errorMessage:
            'AI 识题失败：${structRes.errorMessage ?? '模型未能返回有效的题目结构，请确认当前模型支持图片识别'}',
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
        outputSnippet: '成功抽取 ${rawItems.length} 道候选题目',
      ),
    );

    if (rawItems.isEmpty) {
      return IngestionBatchResult(
        drafts: const [],
        suggestedDocTitle: docTitleHint,
        subject: subject,
        traceSteps: List.unmodifiable(trace),
        usedOfflineFallback: false,
        repairCount: repairCount,
        errorMessage: '未在图片中识别到清晰的题目，请调整角度、保证光线充足后重试。',
      );
    }

    // Stage 3 & 4: Normalize + Repair + Answer check + Dedup
    onProgress?.call(CaptureStage.answerSelfCheck, '核对答案与题目格式校验');
    final drafts = <CaptureDraftItem>[];

    for (var i = 0; i < rawItems.length; i++) {
      final item = rawItems[i];
      final qMap = Map<String, Object?>.from(
        _asStringKeyMap(item['question']) ?? item,
      );
      qMap['id'] ??= 'q_cap_${_uuid.v4().substring(0, 8)}';
      qMap['schema'] ??= 1;

      final rawBbox = qMap['bbox'] ?? item['bbox'];
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
            item['subject']?.toString(),
      );
      final candidateSubject =
          aiItemSubject ??
          structSubject ??
          layoutSubject ??
          (subject == SubjectCatalog.autoCode ? 'other' : subject);

      Question question = Question.coerceFromAiMap(
        qMap,
        fallbackId: 'q_cap_${i + 1}',
        defaultSubject: candidateSubject,
        defaultGrade: gradeCode,
      );

      final issues = validateQuestionEnvelope(question);
      if (issues.isNotEmpty) {
        final repaired = await IngestionRepairAgent(jsonCaller: jsonCaller)
            .repairQuestionMap(
              client: client,
              endpoint: effectiveEndpoint,
              brokenQuestionMap: question.toJson(),
              issues: issues,
            );
        if (repaired != null) {
          question = Question.coerceFromAiMap(
            repaired,
            fallbackId: question.id,
            defaultSubject: candidateSubject,
            defaultGrade: gradeCode,
          );
          repairCount++;
        }
      }

      question = _resolveIngestedQuestionSubject(
        question: question,
        aiItemSubject: aiItemSubject,
        aiDocSubject: structSubject ?? layoutSubject,
        requestedSubject: subject,
        lockSubject: lockSubject,
      );

      final rawAnswerHint =
          (qMap['answer'] ??
                  qMap['correctAnswer'] ??
                  item['answer'] ??
                  item['correctAnswer'])
              ?.toString();
      final rescuedSeq = SequenceQuestionDetector.tryRescueAsSequence(
        question,
        rawAnswerHint: rawAnswerHint,
      );
      if (rescuedSeq != null) {
        if (rescuedSeq.displayKindLabel != question.displayKindLabel) {
          trace.add(
            TutorToolTraceStep(
              toolName: 'sequence_kind_guard',
              summary: '${question.displayKindLabel} -> 排序题',
              outputSnippet:
                  '第 ${i + 1} 题包含排序特征（如词块/序号排列），自动纠正为交互式排序题 (${rescuedSeq.header.title})',
            ),
          );
        }
        question = rescuedSeq;
      }

      // Self-check answer when unverified or missing grading
      if (cancelToken?.isCancelled ?? false) break;
      if (answerImageBytes != null ||
          question.meta.answerSource == AnswerSource.ai ||
          question.grading.isEmpty ||
          (question.isSequence &&
              (question.grading['answerSets'] as List?)?.isEmpty != false)) {
        question = await _runAnswerSelfCheck(
          client: client,
          endpoint: effectiveEndpoint,
          profile: profile,
          question: question,
          answerImageBytes: answerImageBytes,
          cancelToken: cancelToken,
        );
        question =
            SequenceQuestionDetector.tryRescueAsSequence(question) ?? question;
      }

      onProgress?.call(CaptureStage.validationAndDedup, '检查重复题与准备入库清单');
      final teacherMark = (item['teacherMark'] as String?) ?? 'none';
      final flaggedWrong = teacherMark == 'wrong' || teacherMark == 'partial';
      final stem = question.plainText;
      final dupMatch = existingQuestions
          .where((eq) => ContentTextUtils.isLikelyDuplicate(stem, eq.plainText))
          .firstOrNull;

      drafts.add(
        CaptureDraftItem(
          id: 'draft_${_uuid.v4().substring(0, 8)}',
          sortOrder: (item['sortOrder'] as num?)?.toInt() ?? (i + 1),
          question: question,
          confidence:
              (item['confidence'] as num?)?.toDouble() ??
              (question.meta.aiConfidence ?? 0.88),
          teacherMark: teacherMark,
          studentAnswerSnippet: item['studentAnswerSnippet'] as String?,
          flaggedWrong: flaggedWrong,
          errorTags: flaggedWrong ? const [ErrorTag.calc] : const [],
          duplicateOfTitle: dupMatch?.header.title,
          confirmed: dupMatch == null,
        ),
      );
    }

    final batchSubject = _dominantSubject(
      drafts,
      fallback: structSubject ?? layoutSubject ?? subject,
    );
    onProgress?.call(
      CaptureStage.completed,
      '已就绪 ${drafts.length} 题（${SubjectCatalog.labelOf(batchSubject)}）',
    );
    final suggestedTitle =
        (structMap?['suggestedTitle'] as String?)?.trim().isNotEmpty == true
        ? (structMap!['suggestedTitle']! as String).trim()
        : ((layoutMap['suggestedTitle'] as String?)?.trim().isNotEmpty == true
              ? (layoutMap['suggestedTitle']! as String).trim()
              : docTitleHint);

    return IngestionBatchResult(
      drafts: List.unmodifiable(drafts),
      suggestedDocTitle: suggestedTitle,
      subject: batchSubject,
      traceSteps: List.unmodifiable(trace),
      usedOfflineFallback: false,
      repairCount: repairCount,
    );
  }

  /// Parses pasted raw text or JSON directly into editable [CaptureDraftItem]s.
  Future<IngestionBatchResult> importFromRawText({
    required String rawText,
    required StudentProfile profile,
    String subject = SubjectCatalog.autoCode,
    bool lockSubject = false,
    required List<Question> existingQuestions,
    AiEndpointConfig? endpoint,
    String? apiKey,
    LLMClient? overrideClient,
    CaptureProgressCallback? onProgress,
    CancelToken? cancelToken,
  }) async {
    final trimmed = rawText.trim();
    if (trimmed.isEmpty) {
      return const IngestionBatchResult(
        drafts: [],
        suggestedDocTitle: '文本导入题目',
        subject: 'other',
        traceSteps: [],
        usedOfflineFallback: true,
      );
    }

    onProgress?.call(CaptureStage.questionStructuring, '正在分析题目结构与学科归属');

    // Direct JSON / JSONL (`res-hub` schema or array) import support
    final structuredJsonList = StructuredQuestionTextParser.tryParseJsonOrJsonl(
      trimmed,
      subject: subject,
      grade: _gradeCodeFor(profile.stage),
      lockSubject: lockSubject,
    );
    if (structuredJsonList != null && structuredJsonList.isNotEmpty) {
      final drafts = <CaptureDraftItem>[];
      for (var i = 0; i < structuredJsonList.length; i++) {
        final q = structuredJsonList[i];
        final dup = existingQuestions.firstWhere(
          (e) => ContentTextUtils.isLikelyDuplicate(q.plainText, e.plainText),
          orElse: () => q,
        );
        final hasDup = dup.id != q.id;
        drafts.add(
          CaptureDraftItem(
            id: 'draft_${_uuid.v4().substring(0, 8)}',
            sortOrder: i + 1,
            question: q,
            confidence: 1.0,
            duplicateOfTitle: hasDup ? dup.header.title : null,
            confirmed: !hasDup,
          ),
        );
      }
      final batchSubject = _dominantSubject(drafts, fallback: subject);
      onProgress?.call(
        CaptureStage.completed,
        '结构化文档解析 ${drafts.length} 题（${SubjectCatalog.labelOf(batchSubject)}）',
      );
      return IngestionBatchResult(
        drafts: drafts,
        suggestedDocTitle: '结构化题目导入集',
        subject: batchSubject,
        traceSteps: [
          TutorToolTraceStep(
            toolName: 'json_schema_parser',
            summary: 'count=${drafts.length}, subject=$batchSubject',
            outputSnippet:
                '直通解析 ${drafts.length} 道结构化题目，学科：${SubjectCatalog.labelOf(batchSubject)}',
          ),
        ],
        usedOfflineFallback: true,
      );
    }

    final textSubjectHint = SubjectDetector.resolveSubjectForText(
      trimmed,
      preferredSubject: subject,
      allowOverrideDefault: !lockSubject,
    );

    final canRunRemote =
        overrideClient != null ||
        (endpoint != null && (apiKey ?? '').trim().isNotEmpty);
    if (canRunRemote) {
      final client =
          overrideClient ??
          clientFactory.createClient(endpoint!, apiKey: apiKey!.trim());
      final effectiveEndpoint = endpoint ?? AiEndpointPresets.defaults().first;
      final p02 = PromptLibrary.get('P-02').render({
        'subjectHint': subject == SubjectCatalog.autoCode
            ? (textSubjectHint == 'other' ? '' : textSubjectHint)
            : subject,
        'subjectLocked': lockSubject && subject != SubjectCatalog.autoCode,
        'gradeHint': profile.grade,
        'bboxOrder': effectiveEndpoint.bboxOrder.code,
        'layoutJson': jsonEncode({'rawText': trimmed}),
        'schemaGuide': QuestionSchemaCatalog.promptGuideForKinds(const [
          QuestionKind.choice,
          QuestionKind.fill,
          QuestionKind.match,
          QuestionKind.classify,
          QuestionKind.solve,
          QuestionKind.response,
          QuestionKind.group,
        ]),
      });
      final res = await jsonCaller.callJson(
        client: client,
        endpoint: effectiveEndpoint,
        tier: AiTier.balanced,
        systemPrompt: p02.systemPrompt,
        userPrompt: '${p02.userPrompt}\n\n待解析文本/Markdown 文档：\n$trimmed',
        cancelToken: cancelToken,
      );
      if (res.ok) {
        final resMap = res.asMap;
        final aiDocSubject = SubjectCatalog.tryParseCode(
          resMap?['detectedSubject']?.toString(),
        );
        final rawItems = _extractRawDraftList(res.decoded);
        final drafts = <CaptureDraftItem>[];
        for (var i = 0; i < rawItems.length; i++) {
          final qMap = _asStringKeyMap(rawItems[i]['question']) ?? rawItems[i];
          try {
            final aiItemSub = SubjectCatalog.tryParseCode(
              _asStringKeyMap(qMap['meta'])?['subject']?.toString() ??
                  rawItems[i]['subject']?.toString(),
            );
            var q = Question.coerceFromAiMap(
              qMap,
              fallbackId: 'q_txt_${i + 1}',
              defaultSubject: aiItemSub ?? aiDocSubject ?? textSubjectHint,
              defaultGrade: _gradeCodeFor(profile.stage),
            );
            q = _resolveIngestedQuestionSubject(
              question: q,
              aiItemSubject: aiItemSub,
              aiDocSubject: aiDocSubject,
              requestedSubject: subject,
              lockSubject: lockSubject,
            );
            q =
                SequenceQuestionDetector.tryRescueAsSequence(
                  q,
                  rawAnswerHint: (qMap['answer'] ?? rawItems[i]['answer'])
                      ?.toString(),
                ) ??
                q;
            drafts.add(
              CaptureDraftItem(
                id: 'draft_${_uuid.v4().substring(0, 8)}',
                sortOrder: i + 1,
                question: q,
                confidence: 0.92,
                confirmed: true,
              ),
            );
          } catch (_) {
            continue;
          }
        }
        if (drafts.isNotEmpty) {
          final batchSubject = _dominantSubject(
            drafts,
            fallback: aiDocSubject ?? textSubjectHint,
          );
          onProgress?.call(
            CaptureStage.completed,
            'AI 解析 ${drafts.length} 题（${SubjectCatalog.labelOf(batchSubject)}）',
          );
          return IngestionBatchResult(
            drafts: drafts,
            suggestedDocTitle: '文本粘贴导入',
            subject: batchSubject,
            traceSteps: [
              TutorToolTraceStep(
                toolName: 'P-02 text_structuring',
                summary: 'count=${drafts.length}, subject=$batchSubject',
                outputSnippet:
                    '文本已转为标准结构，识别学科：${SubjectCatalog.labelOf(batchSubject)}',
              ),
            ],
            usedOfflineFallback: false,
          );
        }
      }
    }

    // Deterministic offline Markdown / structured text parser (`答案：`/`解析：`/`____`/options)
    onProgress?.call(CaptureStage.validationAndDedup, '执行本地智能分段与学科识别');
    final chunks = trimmed
        .split(RegExp(r'\n\s*\n|(?=\n\s*\d+[\.、]\s)'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final now = DateTime.now().millisecondsSinceEpoch;
    final drafts = <CaptureDraftItem>[];
    for (var i = 0; i < chunks.length; i++) {
      final chunk = chunks[i];
      var q = StructuredQuestionTextParser.parseTextChunk(
        chunk,
        id: 'q_txt_${_uuid.v4().substring(0, 8)}',
        index: i + 1,
        subject: subject,
        grade: _gradeCodeFor(profile.stage),
        timestampMs: now + i,
        lockSubject: lockSubject,
      );
      if (!lockSubject &&
          q.meta.subject == 'other' &&
          textSubjectHint != 'other') {
        q = q.copyWith(meta: q.meta.copyWith(subject: textSubjectHint));
      }
      final dup = existingQuestions
          .where(
            (e) => ContentTextUtils.isLikelyDuplicate(q.plainText, e.plainText),
          )
          .firstOrNull;
      drafts.add(
        CaptureDraftItem(
          id: 'draft_${_uuid.v4().substring(0, 8)}',
          sortOrder: i + 1,
          question: q,
          confidence: q.meta.answerSource == AnswerSource.user ? 0.92 : 0.76,
          duplicateOfTitle: dup?.header.title,
          confirmed: dup == null,
        ),
      );
    }

    final batchSubject = _dominantSubject(drafts, fallback: textSubjectHint);
    onProgress?.call(
      CaptureStage.completed,
      '文本分段解析 ${drafts.length} 题（${SubjectCatalog.labelOf(batchSubject)}）',
    );
    return IngestionBatchResult(
      drafts: drafts,
      suggestedDocTitle: '粘贴文本整理卷',
      subject: batchSubject,
      traceSteps: [
        TutorToolTraceStep(
          toolName: 'local_text_segmenter',
          summary: 'chunks=${chunks.length}, subject=$batchSubject',
          outputSnippet:
              '本地规则切分生成 ${drafts.length} 道草案，学科：${SubjectCatalog.labelOf(batchSubject)}',
        ),
      ],
      usedOfflineFallback: true,
    );
  }

  Future<Question> _runAnswerSelfCheck({
    required LLMClient client,
    required AiEndpointConfig endpoint,
    required StudentProfile profile,
    required Question question,
    Uint8List? answerImageBytes,
    CancelToken? cancelToken,
  }) async {
    if (cancelToken?.isCancelled ?? false) return question;
    if (answerImageBytes != null) {
      final p04 = PromptLibrary.get('P-04').render({
        'questionsSummaryJson': jsonEncode(question.toPublicView().toJson()),
      });
      final res = await jsonCaller.callJson(
        client: client,
        endpoint: endpoint,
        tier: AiTier.balanced,
        systemPrompt: p04.systemPrompt,
        userPrompt: p04.userPrompt,
        imageBytes: answerImageBytes,
        cancelToken: cancelToken,
      );
      if (res.ok && res.asMap != null) {
        final matchedGrading = _asStringKeyMap(res.asMap!['grading']);
        return question.copyWith(
          grading: matchedGrading ?? question.grading,
          meta: question.meta.copyWith(
            answerSource: AnswerSource.paper,
            aiConfidence: 0.96,
            uncertainNote: null,
          ),
        );
      }
    }

    final p05 = PromptLibrary.get('P-05').render({
      'subject': SubjectCatalog.labelOf(question.meta.subject),
      'stage': profile.stage.label,
      'questionPublicJson': jsonEncode(question.toPublicView().toJson()),
    });
    final res = await jsonCaller.callJson(
      client: client,
      endpoint: endpoint,
      tier: AiTier.strong,
      systemPrompt: p05.systemPrompt,
      userPrompt: p05.userPrompt,
      cancelToken: cancelToken,
    );
    final map = res.asMap;
    if (res.ok && map != null) {
      final newGrading = _asStringKeyMap(map['grading']) ?? question.grading;
      final expList = map['explanation'] is List
          ? (map['explanation']! as List<Object?>)
                .whereType<Map<String, Object?>>()
                .map(ContentBlock.fromJson)
                .toList(growable: false)
          : question.explanation;
      final conf = (map['confidence'] as num?)?.toDouble() ?? 0.85;
      return question.copyWith(
        grading: newGrading,
        explanation: expList,
        meta: question.meta.copyWith(
          answerSource: AnswerSource.aiVerified,
          aiConfidence: conf,
        ),
      );
    }
    return question;
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

  Question _resolveIngestedQuestionSubject({
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
    List<CaptureDraftItem> drafts, {
    required String fallback,
  }) {
    if (drafts.isEmpty) {
      return SubjectCatalog.normalize(fallback, fallback: 'other');
    }
    final counts = <String, int>{};
    for (final d in drafts) {
      final s = d.question.meta.subject;
      counts[s] = (counts[s] ?? 0) + 1;
    }
    final concrete = counts.entries.where((e) => e.key != 'other').toList();
    final pool = concrete.isNotEmpty ? concrete : counts.entries.toList();
    pool.sort((a, b) => b.value.compareTo(a.value));
    return pool.first.key;
  }
}

/// Repairs malformed question JSON produced by vision LLMs using `P-03`.
class IngestionRepairAgent {
  const IngestionRepairAgent({this.jsonCaller = const StructuredJsonCaller()});

  final StructuredJsonCaller jsonCaller;

  Future<Map<String, Object?>?> repairQuestionMap({
    required LLMClient client,
    required AiEndpointConfig endpoint,
    required Map<String, Object?> brokenQuestionMap,
    required List<ValidationIssue> issues,
  }) async {
    final rendered = PromptLibrary.get('P-03').render({
      'errors': issues.map((e) => '${e.path}: ${e.message}').join('\n- '),
      'brokenJson': jsonEncode(brokenQuestionMap),
    });
    final res = await jsonCaller.callJson(
      client: client,
      endpoint: endpoint,
      tier: AiTier.fast,
      systemPrompt: rendered.systemPrompt,
      userPrompt: rendered.userPrompt,
      maxRepairRetries: 1,
    );
    final repaired = res.asMap;
    if (!res.ok || repaired == null) return null;
    try {
      final remaining = validateQuestionEnvelope(Question.fromJson(repaired));
      return remaining.isEmpty ? repaired : null;
    } catch (_) {
      return null;
    }
  }
}

/// Subjective & handwritten grading adapter implementing [SubjectiveJudge] via
/// cloud multimodal vision (`P-06`) with deterministic local heuristic fallback.
class CloudSubjectiveJudge implements SubjectiveJudge {
  const CloudSubjectiveJudge({
    this.endpoint,
    this.apiKey,
    this.overrideClient,
    this.strokeCountProvider,
    this.clientFactory = const InouLlmClientFactory(),
    this.jsonCaller = const StructuredJsonCaller(),
  });

  final AiEndpointConfig? endpoint;
  final String? apiKey;
  final LLMClient? overrideClient;
  final int Function(String questionId)? strokeCountProvider;
  final InouLlmClientFactory clientFactory;
  final StructuredJsonCaller jsonCaller;

  @override
  Future<JudgeResult> judge(JudgeInput input) async {
    final canRunRemote =
        overrideClient != null ||
        (endpoint != null && (apiKey ?? '').trim().isNotEmpty);

    String? remoteError;
    if (canRunRemote) {
      final client =
          overrideClient ??
          clientFactory.createClient(endpoint!, apiKey: apiKey!.trim());
      final effectiveEndpoint = endpoint ?? AiEndpointPresets.defaults().first;
      final rendered = PromptLibrary.get('P-07').render({
        'mode': input.mode.name,
        'stage': input.stage.label,
        'questionJson': jsonEncode(input.question.toJson()),
        'gradingJson': jsonEncode(input.grading),
        'responseJson': jsonEncode(input.response.toJson()),
      });

      final res = await jsonCaller.callJson(
        client: client,
        endpoint: effectiveEndpoint,
        tier: AiTier.balanced,
        systemPrompt: rendered.systemPrompt,
        userPrompt: rendered.userPrompt,
        imageBytes: input.images.isNotEmpty ? input.images.first : null,
        imageMimeType: 'image/png',
      );
      if (res.ok && res.asMap != null) {
        try {
          return JudgeResult.fromJson(res.asMap!);
        } catch (e) {
          remoteError = 'AI 判分格式异常：$e';
        }
      } else {
        remoteError = res.errorMessage ?? 'AI 批改请求失败';
      }
    }

    return _offlineFallbackJudge(input, remoteError: remoteError);
  }

  JudgeResult _offlineFallbackJudge(JudgeInput input, {String? remoteError}) {
    final maxScore =
        (input.grading['maxScore'] as num?)?.toDouble() ??
        input.question.header.score;
    final strokeCount = strokeCountProvider?.call(input.question.id) ?? 0;
    final hasImage = input.images.isNotEmpty;
    final prefix = remoteError == null ? '' : '（$remoteError）';

    switch (input.response) {
      case SolveResponse(:final steps, :final finalAnswer):
        final hasFinal = (finalAnswer ?? '').trim().isNotEmpty;
        final accepted = _extractFinalAcceptedStrings(input.grading);
        if (hasFinal && accepted.isNotEmpty) {
          final matched = accepted.any(
            (exp) =>
                ContentTextUtils.normalizeText(
                      finalAnswer!,
                      fullWidthToHalf: true,
                    ) ==
                    ContentTextUtils.normalizeText(
                      exp,
                      fullWidthToHalf: true,
                    ) ||
                MathVerifyEngine.verifyNumericEquality(finalAnswer, exp),
          );
          if (matched) {
            return JudgeResult(
              verdict: Verdict.correct,
              score: maxScore,
              maxScore: maxScore,
              confidence: 0.92,
              recognizedText: finalAnswer,
              steps: [
                StepFeedback(
                  stepId: 'fin',
                  ok: true,
                  comment: '最终数值「$finalAnswer」与参考答案一致。',
                ),
              ],
              summary: hasImage || strokeCount > 0
                  ? '最终结果正确，已结合本地算式核验通过；可在下方红笔覆盖或微调判定。'
                  : '最终答案核验正确！',
            );
          }
          return JudgeResult(
            verdict: steps.isNotEmpty || strokeCount > 0
                ? Verdict.partial
                : Verdict.wrong,
            score: (steps.isNotEmpty || strokeCount > 0)
                ? (maxScore * 0.4).roundToDouble()
                : 0,
            maxScore: maxScore,
            confidence: 0.85,
            recognizedText: finalAnswer,
            steps: [
              StepFeedback(
                stepId: 'st1',
                ok: steps.isNotEmpty || strokeCount > 0,
                comment: '终值「$finalAnswer」与参考结果「${accepted.first}」不符，请复核中间化简。',
                deduct: (maxScore * 0.6).roundToDouble(),
              ),
            ],
            errorTagSuggestions: const [ErrorTag.calc],
            summary: '终值计算偏差（参考答案 ${accepted.first}），已建议保留关键步骤分。',
          );
        }
        if (hasImage || strokeCount >= 3 || steps.isNotEmpty) {
          return JudgeResult(
            verdict: Verdict.ungraded,
            score: 0,
            maxScore: maxScore,
            confidence: 0.5,
            recognizedText: steps.isNotEmpty
                ? steps.join('\n')
                : '手写推导 $strokeCount 笔',
            steps: [
              StepFeedback(
                stepId: 'st1',
                ok: true,
                comment: '已记录作答过程$prefix，请在下方对照解析手动判定对错，或接入支持视觉的 AI 自动批改。',
              ),
            ],
            summary: '已保存解答过程$prefix，请对照参考答案点击「改判正确 / 部分 / 错误」。',
          );
        }
        return JudgeResult(
          verdict: Verdict.wrong,
          score: 0,
          maxScore: maxScore,
          confidence: 0.9,
          errorTagSuggestions: const [ErrorTag.writing],
          summary: '尚未检测到作答内容。',
        );

      case TextResponse(:final parts):
        final text = parts.values.join(' ').trim();
        if (text.isEmpty && !hasImage && strokeCount == 0) {
          return JudgeResult(
            verdict: Verdict.wrong,
            score: 0,
            maxScore: maxScore,
            confidence: 0.9,
            summary: '作答区为空。',
          );
        }
        final keywords =
            (input.grading['keywords'] as List<Object?>? ?? const [])
                .map((e) => e.toString())
                .toList();
        var hits = 0;
        for (final kw in keywords) {
          if (text.contains(kw)) hits++;
        }
        final ratio = keywords.isEmpty
            ? (text.length >= 12 || strokeCount >= 3 ? 0.75 : 0.4)
            : hits / keywords.length;
        final score = (maxScore * ratio).clamp(0, maxScore).toDouble();
        final verdict = ratio >= 0.85
            ? Verdict.correct
            : (ratio > 0 ? Verdict.partial : Verdict.wrong);
        return JudgeResult(
          verdict: verdict,
          score: double.parse(score.toStringAsFixed(1)),
          maxScore: maxScore,
          confidence: 0.72,
          recognizedText: text.isNotEmpty ? text : '手写简答 $strokeCount 笔',
          summary: keywords.isNotEmpty
              ? '关键词命中 $hits / ${keywords.length} 处；可对比参考答案微调评分。'
              : '已提交主观简答内容，支持一键手动改判。',
        );

      case DrawResponse():
      case WriteResponse():
        final touched = hasImage || strokeCount >= 2;
        return JudgeResult(
          verdict: touched ? Verdict.partial : Verdict.wrong,
          score: touched ? (maxScore * 0.7).roundToDouble() : 0,
          maxScore: maxScore,
          confidence: 0.58,
          summary: touched
              ? '已捕捉画板/书写区域作答（$strokeCount 笔），请对照标答图或使用红笔面板确认对错。'
              : '未检测到画板或格线作答内容。',
        );

      default:
        return JudgeResult(
          verdict: Verdict.ungraded,
          score: 0,
          maxScore: maxScore,
          confidence: 0.5,
          summary: '请通过客观判分引擎批改。',
        );
    }
  }

  List<String> _extractFinalAcceptedStrings(Map<String, Object?> grading) {
    final fin = grading['finalAnswer'];
    if (fin is Map) {
      final vals = fin['acceptedValues'] as List<Object?>? ?? const [];
      return vals
          .whereType<Map<Object?, Object?>>()
          .map((e) => (e['value'] ?? e['text'] ?? '').toString())
          .where((s) => s.isNotEmpty)
          .toList();
    }
    return const [];
  }
}
