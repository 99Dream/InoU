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
import 'ai_retry_policy.dart';
import 'blackboard_stream_transport.dart';
import 'inou_agent_hooks.dart';
import 'inou_llm_client.dart';
import 'inou_tutor_agent.dart';
import 'llm_gateway.dart';
import 'openai_compat_utils.dart';
import 'prompt_library.dart';

/// Ten reactive character expressions shared by `NuoNuoMascotView` and `P-10`.
enum MascotEmotion {
  neutral('neutral', '平静'),
  happy('happy', '开心'),
  thinking('thinking', '思考中'),
  encourage('encourage', '加油鼓励'),
  surprised('surprised', '惊讶'),
  serious('serious', '认真纠错'),
  sorry('sorry', '抱歉'),
  celebrate('celebrate', '庆祝'),
  sleepy('sleepy', '有点困'),
  wink('wink', '俏皮');

  const MascotEmotion(this.code, this.zhLabel);

  final String code;
  final String zhLabel;

  static MascotEmotion fromCode(String code) {
    final normalized = code.trim().toLowerCase();
    return MascotEmotion.values.firstWhere(
      (e) => e.code == normalized,
      orElse: () => MascotEmotion.neutral,
    );
  }
}

/// Parses the `[[emo=<id>]]` leading expression protocol emitted by P-10.
abstract final class EmotionProtocolParser {
  static final RegExp _leadingTag = RegExp(
    r'^\s*\[\[?\s*emo\s*=\s*([a-zA-Z_]+)\s*\]?\]\s*\n?',
  );

  static ({MascotEmotion emotion, String cleanText}) parse(String raw) {
    final match = _leadingTag.firstMatch(raw);
    if (match != null) {
      final emo = MascotEmotion.fromCode(match.group(1) ?? '');
      final clean = raw.substring(match.end).trimLeft();
      return (emotion: emo, cleanText: clean);
    }
    return (emotion: _inferFallbackEmotion(raw), cleanText: raw.trim());
  }

  static MascotEmotion _inferFallbackEmotion(String text) {
    if (text.contains('太棒') || text.contains('全对') || text.contains('掌握')) {
      return MascotEmotion.celebrate;
    }
    if (text.contains('加油') || text.contains('再试') || text.contains('别灰心')) {
      return MascotEmotion.encourage;
    }
    if (text.contains('提示') || text.contains('思路') || text.contains('想想')) {
      return MascotEmotion.thinking;
    }
    if (text.contains('注意') || text.contains('避坑') || text.contains('拦截')) {
      return MascotEmotion.serious;
    }
    return MascotEmotion.happy;
  }
}

/// Structured trace item surfaced in the collapsible "AI 思考过程" panel.
@immutable
class TutorToolTraceStep {
  const TutorToolTraceStep({
    required this.toolName,
    required this.summary,
    this.isBlocked = false,
    this.isError = false,
    this.outputSnippet = '',
  });

  final String toolName;
  final String summary;
  final bool isBlocked;
  final bool isError;
  final String outputSnippet;

  String toDisplayLine() {
    final prefix = isBlocked
        ? '[拦截]'
        : isError
        ? '[异常]'
        : '[工具]';
    return outputSnippet.isEmpty
        ? '$prefix $toolName($summary)'
        : '$prefix $toolName($summary) → $outputSnippet';
  }
}

/// Result returned by [TutorAgentService.sendMessage].
@immutable
class TutorReplyResult {
  const TutorReplyResult({
    required this.emotion,
    required this.content,
    required this.toolTrace,
    required this.antiSpoilerBlocked,
    required this.usedOfflineFallback,
    required this.hintLevel,
    this.usage,
  });

  final MascotEmotion emotion;
  final String content;
  final List<TutorToolTraceStep> toolTrace;
  final bool antiSpoilerBlocked;
  final bool usedOfflineFallback;
  final HintLevel hintLevel;
  final ModelUsage? usage;
}

/// Concrete discipline pedagogy [Skill] injected into the tutor [StatefulAgent].
class InouDisciplineSkill extends Skill {
  InouDisciplineSkill({
    required super.name,
    required super.description,
    required super.systemPrompt,
    super.tools,
    super.forceActivate = false,
  });

  static List<InouDisciplineSkill> defaultsForSubject(String? subjectId) => [
    InouDisciplineSkill(
      name: 'math_pedagogy',
      description: '数学代数方程、函数图像与几何辅助线分步教学技能',
      forceActivate: subjectId == 'math',
      systemPrompt: r'''
数学辅导规范：
1. 涉及代数运算或方程求解核验时，优先调用 run_math_verify 计算验证，不心算凑数。
2. 几何题先明确“已知条件→求证目标→常见辅助线触发特征”。
3. 数学公式使用 KaTeX 行内 `$...$` 或块级 `$$...$$`。
''',
    ),
    InouDisciplineSkill(
      name: 'physics_pedagogy',
      description: '物理受力分析、电路等效与守恒定律规范技能',
      forceActivate: subjectId == 'phy',
      systemPrompt: '''
物理辅导规范：
1. 先引导明确研究对象（隔离法/整体法）、受力或能量转化过程。
2. 严格写公式再代数值，注意国际单位制换算（cm→m, km/h→m/s），数值验算可调用 run_math_verify。
''',
    ),
    InouDisciplineSkill(
      name: 'english_chinese_pedagogy',
      description: '英语阅读定位、语法从句拆解与语文赏析技能',
      forceActivate: subjectId == 'eng' || subjectId == 'chn',
      systemPrompt: '''
语言与阅读辅导规范：
1. 英语先定位原文对应句，再分析长难句主干（主谓宾）与选项偷换概念陷阱。
2. 语文古诗文与现代文遵循“手法 + 内容情感 + 关键词赏析”结构。
''',
    ),
  ];
}

/// Input context for a single tutor copilot turn.
class TutorRequestContext {
  const TutorRequestContext({
    required this.profile,
    required this.userMessage,
    this.sessionId = 'tutor_default',
    this.boundQuestion,
    this.currentDraftText,
    this.isPostMortem = false,
    this.verdictLabel,
    this.hintLevel = HintLevel.l1Concept,
    this.relatedWrongItems = const [],
    this.history = const [],
    this.attachedImageBytes,
    this.attachedImageMimeType = 'image/png',
    this.endpoint,
    this.apiKey,
    this.overrideClient,
    this.mascotDisplayName = '诺诺学姐',
    this.mascotPersona = '耐心、温柔、循循善诱，善于把复杂问题拆成小台阶。',
  });

  final StudentProfile profile;
  final String userMessage;
  final String sessionId;
  final Question? boundQuestion;
  final String? currentDraftText;
  final bool isPostMortem;
  final String? verdictLabel;
  final HintLevel hintLevel;
  final List<WrongItem> relatedWrongItems;
  final List<TutorMessageRecord> history;
  final Uint8List? attachedImageBytes;
  final String attachedImageMimeType;
  final AiEndpointConfig? endpoint;
  final String? apiKey;
  final LLMClient? overrideClient;
  final String mascotDisplayName;
  final String mascotPersona;
}

/// Request payload for planning a step-by-step interactive blackboard lesson.
class BlackboardPlanRequest {
  const BlackboardPlanRequest({
    required this.profile,
    this.boundQuestion,
    this.currentDraftText,
    this.isPostMortem = false,
    this.hintLevel = HintLevel.l1Concept,
    this.relatedWrongItems = const [],
    this.attachedImageBytes,
    this.attachedImageMimeType = 'image/png',
    this.endpoint,
    this.apiKey,
    this.overrideClient,
    this.cancelToken,
    this.mascotDisplayName = '诺诺学姐',
    this.mascotPersona = '耐心、温柔、循循善诱，善于把复杂问题拆成小台阶。',
  });

  final StudentProfile profile;
  final Question? boundQuestion;
  final String? currentDraftText;
  final bool isPostMortem;
  final HintLevel hintLevel;
  final List<WrongItem> relatedWrongItems;
  final Uint8List? attachedImageBytes;
  final String attachedImageMimeType;
  final AiEndpointConfig? endpoint;
  final String? apiKey;
  final LLMClient? overrideClient;
  final CancelToken? cancelToken;
  final String mascotDisplayName;
  final String mascotPersona;
}

/// Result returned by [TutorAgentService.generateBlackboardLesson].
@immutable
class BlackboardLessonResult {
  const BlackboardLessonResult({
    required this.lesson,
    required this.toolTrace,
    required this.antiSpoilerBlocked,
    required this.usedOfflineFallback,
  });

  final BlackboardLessonRecord lesson;
  final List<TutorToolTraceStep> toolTrace;
  final bool antiSpoilerBlocked;
  final bool usedOfflineFallback;
}

/// Request payload for streaming a single progressive blackboard step (`P-17`).
class BlackboardStepRequest {
  const BlackboardStepRequest({
    required this.profile,
    required this.stepNumber,
    this.boundQuestion,
    this.previousSteps = const [],
    this.studentFeedbackSummary,
    this.currentDraftText,
    this.isPostMortem = false,
    this.hintLevel = HintLevel.l1Concept,
    this.attachedImageBytes,
    this.attachedImageMimeType = 'image/png',
    this.endpoint,
    this.apiKey,
    this.overrideClient,
    this.cancelToken,
    this.mascotDisplayName = '诺诺学姐',
    this.mascotPersona = '耐心、温柔、循循善诱，善于把复杂问题拆成小台阶。',
  });

  final StudentProfile profile;
  final int stepNumber;
  final Question? boundQuestion;
  final List<BlackboardStep> previousSteps;
  final String? studentFeedbackSummary;
  final String? currentDraftText;
  final bool isPostMortem;
  final HintLevel hintLevel;
  final Uint8List? attachedImageBytes;
  final String attachedImageMimeType;
  final AiEndpointConfig? endpoint;
  final String? apiKey;
  final LLMClient? overrideClient;
  final CancelToken? cancelToken;
  final String mascotDisplayName;
  final String mascotPersona;
}

/// Request payload for evaluating a student's open-ended reply or confusion
/// feedback on a specific blackboard step (`P-18`).
class BlackboardFeedbackRequest {
  const BlackboardFeedbackRequest({
    required this.profile,
    required this.step,
    required this.studentReply,
    this.boundQuestion,
    this.hintLevel = HintLevel.l1Concept,
    this.isConfused = false,
    this.endpoint,
    this.apiKey,
    this.overrideClient,
    this.cancelToken,
    this.mascotDisplayName = '诺诺学姐',
  });

  final StudentProfile profile;
  final BlackboardStep step;
  final String studentReply;
  final Question? boundQuestion;
  final HintLevel hintLevel;
  final bool isConfused;
  final AiEndpointConfig? endpoint;
  final String? apiKey;
  final LLMClient? overrideClient;
  final CancelToken? cancelToken;
  final String mascotDisplayName;
}

/// Result returned by [TutorAgentService.evaluateBlackboardFeedback].
@immutable
class BlackboardFeedbackResult {
  const BlackboardFeedbackResult({
    required this.verdict,
    required this.emotion,
    required this.feedback,
    required this.usedOfflineFallback,
  });

  final String verdict;
  final MascotEmotion emotion;
  final String feedback;
  final bool usedOfflineFallback;
}

/// Incremental parse snapshot emitted by [BlackboardStepStreamParser].
@immutable
class ParsedBlackboardStep {
  const ParsedBlackboardStep({
    required this.step,
    required this.hasMoreSteps,
    this.plannedTotalSteps,
    this.diagram,
    this.addedDiagramElements = const [],
    this.takeaway = '',
  });

  final BlackboardStep step;
  final bool hasMoreSteps;
  final int? plannedTotalSteps;
  final BlackboardDiagramSpec? diagram;
  final List<BlackboardDiagramElement> addedDiagramElements;
  final String takeaway;
}

/// Result returned by [TutorAgentService.generateBlackboardStep].
@immutable
class BlackboardStepResult {
  const BlackboardStepResult({
    required this.step,
    required this.hasMoreSteps,
    this.plannedTotalSteps,
    this.diagram,
    this.addedDiagramElements = const [],
    this.takeaway = '',
    this.toolTrace = const [],
    required this.antiSpoilerBlocked,
    required this.usedOfflineFallback,
  });

  final BlackboardStep step;
  final bool hasMoreSteps;
  final int? plannedTotalSteps;
  final BlackboardDiagramSpec? diagram;
  final List<BlackboardDiagramElement> addedDiagramElements;
  final String takeaway;
  final List<TutorToolTraceStep> toolTrace;
  final bool antiSpoilerBlocked;
  final bool usedOfflineFallback;
}

/// Request payload for asking a question on the blackboard (circle-to-ask or
/// grading student chalk strokes).
class BlackboardAskRequest {
  const BlackboardAskRequest({
    required this.profile,
    required this.userQuestion,
    required this.lesson,
    this.boundQuestion,
    this.targetStep,
    this.hintLevel = HintLevel.l1Concept,
    this.compositeSnapshotPng,
    this.studentStrokeCount = 0,
    this.requestAlternateMethod = false,
    this.endpoint,
    this.apiKey,
    this.overrideClient,
    this.mascotDisplayName = '诺诺学姐',
  });

  final StudentProfile profile;
  final String userQuestion;
  final BlackboardLessonRecord lesson;
  final Question? boundQuestion;
  final BlackboardStep? targetStep;
  final HintLevel hintLevel;
  final Uint8List? compositeSnapshotPng;
  final int studentStrokeCount;
  final bool requestAlternateMethod;
  final AiEndpointConfig? endpoint;
  final String? apiKey;
  final LLMClient? overrideClient;
  final String mascotDisplayName;
}

/// Result returned by [TutorAgentService.askOnBlackboard].
@immutable
class BlackboardAskResult {
  const BlackboardAskResult({
    required this.emotion,
    required this.spokenReply,
    this.sideNote,
    this.alternateTrack,
    this.toolTrace = const [],
    this.antiSpoilerBlocked = false,
    this.usedOfflineFallback = false,
  });

  final MascotEmotion emotion;
  final String spokenReply;
  final BlackboardSideNote? sideNote;
  final BlackboardSolutionTrack? alternateTrack;
  final List<TutorToolTraceStep> toolTrace;
  final bool antiSpoilerBlocked;
  final bool usedOfflineFallback;
}

/// Orchestrates the NuoNuo Copilot using `dart_agent_core`'s [StatefulAgent],
/// [AntiSpoilerHook], [InouDisciplineSkill]s, verification tools, and an
/// authentic Socratic offline fallback when no API key is configured.
class TutorAgentService {
  const TutorAgentService({
    this.agentBuilder = const InouTutorAgentBuilder(),
    this.clientFactory = const InouLlmClientFactory(),
  });

  static const Uuid _uuid = Uuid();

  final InouTutorAgentBuilder agentBuilder;
  final InouLlmClientFactory clientFactory;

  static final RegExp _streamCompleteThinkReg = RegExp(
    r'<think>[\s\S]*?</think>',
    caseSensitive: false,
  );
  static final RegExp _streamOpenThinkReg = RegExp(
    r'<think>[\s\S]*$',
    caseSensitive: false,
  );
  static final RegExp _streamLeadingEmoReg = RegExp(
    r'^\s*\[\[emo=[^\]]*\]\]\s*',
    caseSensitive: false,
  );
  static final RegExp _streamIncompleteEmoReg = RegExp(r'^\s*\[\[[^\]]*$');

  static String _cleanStreamingTutorText(String raw) {
    var s = raw
        .replaceAll(_streamCompleteThinkReg, '')
        .replaceAll(_streamOpenThinkReg, '');
    s = s.replaceFirst(_streamLeadingEmoReg, '');
    if (_streamIncompleteEmoReg.hasMatch(s)) return '';
    return s.trimLeft();
  }

  Future<TutorReplyResult> sendMessage(
    TutorRequestContext ctx, {
    void Function(String partialCleanText)? onPartialReply,
  }) async {
    final effectiveHintLevel = ctx.isPostMortem
        ? HintLevel.l3FullSolution
        : ctx.hintLevel;
    final boundFullPrompt = ctx.boundQuestion == null
        ? null
        : QuestionBlackboardFormatter.formatFullPromptForTutor(
            ctx.boundQuestion!,
          );
    final scope = StudyScopeGuard.check(
      userText: ctx.userMessage,
      boundQuestionText: boundFullPrompt,
      boundQuestionTitle: ctx.boundQuestion?.header.title,
      displayName: ctx.mascotDisplayName,
    );
    if (!scope.allowed) {
      return TutorReplyResult(
        emotion: MascotEmotion.serious,
        content: scope.redirectMessage!,
        toolTrace: const [],
        antiSpoilerBlocked: false,
        usedOfflineFallback: false,
        hintLevel: effectiveHintLevel,
      );
    }

    final canRunRemote =
        ctx.overrideClient != null ||
        (ctx.endpoint != null && (ctx.apiKey ?? '').trim().isNotEmpty);

    if (!canRunRemote) {
      return _buildOfflineFallbackReply(ctx);
    }

    final rawClient =
        ctx.overrideClient ??
        clientFactory.createClient(
          ctx.endpoint!,
          apiKey: ctx.apiKey!.trim(),
          scene: 'tutor',
        );
    final client = RetryingLlmClient.wrap(rawClient, scene: 'tutor');
    final requestedTier =
        ctx.hintLevel == HintLevel.l3FullSolution || ctx.isPostMortem
        ? AiTier.balanced
        : AiTier.fast;
    final modelCandidates = ctx.endpoint != null
        ? ctx.endpoint!.resolveModelCandidates(requestedTier)
        : const ['mock-model'];

    final p10 = PromptLibrary.get('P-10').render({
      'displayName': ctx.mascotDisplayName,
      'persona': ctx.mascotPersona,
      'studentNickname': ctx.profile.name,
      'studentStage': ctx.profile.stage.label,
      'studentGrade': ctx.profile.grade,
      'stageTone': _stageTone(ctx.profile.stage),
    });

    final hintPolicyPrompt = switch (effectiveHintLevel) {
      HintLevel.l1Concept => '当前处于【L1 思路引导】模式：只点明知识点与审题突破口，严禁直接给出答案或核心推导式。',
      HintLevel.l2KeyStep => '当前处于【L2 关键一步】模式：可演示第一步列式或辅助线方向，但必须把最后运算与结论留给学生。',
      HintLevel.l3FullSolution => '当前处于【L3 完整讲解】模式：给出清晰分步详解、易错避坑点与一个小检测追问。',
      HintLevel.none => '自由伴学答疑模式：根据学生提问作答；若学生主动索要正在做的题目答案，引导其分步思考。',
    };

    final traceSteps = <TutorToolTraceStep>[];
    var antiSpoilerBlocked = false;

    final controller = AgentController();
    final streamBuf = StringBuffer();
    var lastEmitLen = 0;
    var lastEmitMs = 0;
    final streamSw = Stopwatch()..start();

    final afterSub = controller.listen<AfterToolCallEvent>().listen((event) {
      streamBuf.clear();
      lastEmitLen = 0;
      final resultText = event.result.content
          .whereType<TextPart>()
          .map((e) => e.text)
          .join(' ')
          .trim();
      final blocked = resultText.contains('BLOCKED_BY_ANTI_SPOILER');
      if (blocked) antiSpoilerBlocked = true;
      traceSteps.add(
        TutorToolTraceStep(
          toolName: event.result.name,
          summary: _compactArgs(event.result.arguments),
          isBlocked: blocked,
          isError: event.result.isError && !blocked,
          outputSnippet: _truncate(resultText, 120),
        ),
      );
    });
    final retrySub = controller.listen<LLMRetryingEvent>().listen((_) {
      streamBuf.clear();
      lastEmitLen = 0;
    });
    final chunkSub = controller.listen<LLMChunkEvent>().listen((event) {
      if (onPartialReply == null) return;
      final delta = event.response.textOutput;
      if (delta == null || delta.isEmpty) return;
      streamBuf.write(delta);
      final cleaned = _cleanStreamingTutorText(streamBuf.toString());
      if (cleaned.isEmpty) return;
      final nowMs = streamSw.elapsedMilliseconds;
      if (cleaned.length - lastEmitLen >= 6 || nowMs - lastEmitMs >= 50) {
        lastEmitLen = cleaned.length;
        lastEmitMs = nowMs;
        onPartialReply(cleaned);
      }
    });

    try {
      final userPromptText = _composeUserPrompt(ctx, effectiveHintLevel);
      final userMsg = UserMessage([
        TextPart(userPromptText),
        if (ctx.attachedImageBytes != null)
          ImagePart(
            base64Encode(ctx.attachedImageBytes!),
            ctx.attachedImageMimeType,
            detail: ctx.endpoint?.sendImageDetail ?? true ? 'auto' : null,
          ),
      ]);

      for (var idx = 0; idx < modelCandidates.length; idx++) {
        streamBuf.clear();
        lastEmitLen = 0;
        final modelName = modelCandidates[idx];
        final effSubject = ctx.boundQuestion == null
            ? null
            : _resolveEffectiveSubject(ctx.boundQuestion!);
        final subjectGuidance = ctx.boundQuestion == null
            ? null
            : '当前题目学科为「${SubjectCatalog.labelOf(effSubject!)}」（${ctx.boundQuestion!.displayKindLabel}），'
                  '你已收到完整题干与所有词块/选项/小题内容，请直接结合全部题目内容讲解与答疑，'
                  '严禁向学生索要题目中已经给出的单词或选项，严禁跨学科套用数学模板。';
        final agent = agentBuilder.build(
          client: client,
          modelConfig: ModelConfig(
            model: modelName,
            temperature: 0.4,
            maxTokens: 1500,
          ),
          state: _buildAgentState(ctx),
          systemPrompts: [
            p10.systemPrompt,
            hintPolicyPrompt,
            ?subjectGuidance,
          ],
          tools: _buildTools(ctx),
          hintLevelProvider: () => effectiveHintLevel,
          skills: InouDisciplineSkill.defaultsForSubject(effSubject),
          controller: controller,
          maxTurns: 8,
        );
        try {
          final responses = await agent.run(
            [userMsg],
            useStream: ctx.endpoint?.preferSse ?? true,
          );
          final modelMessages = responses.whereType<ModelMessage>().toList();
          final lastText = modelMessages.isEmpty
              ? ''
              : (modelMessages.last.textOutput ?? '');
          final parsed = EmotionProtocolParser.parse(lastText);
          final totalUsage = modelMessages.isNotEmpty
              ? modelMessages.last.usage
              : null;

          return TutorReplyResult(
            emotion: parsed.emotion,
            content: parsed.cleanText.isEmpty
                ? '诺诺收到啦～我们一步步来看这道题。'
                : parsed.cleanText,
            toolTrace: List.unmodifiable(traceSteps),
            antiSpoilerBlocked: antiSpoilerBlocked,
            usedOfflineFallback: false,
            hintLevel: effectiveHintLevel,
            usage: totalUsage,
          );
        } catch (e) {
          if (idx + 1 < modelCandidates.length &&
              AiEndpointConfig.isModelUnavailableError(e)) {
            continue;
          }
          rethrow;
        }
      }
      throw StateError('No available model candidate succeeded');
    } catch (e, st) {
      InouDiagnosticsLogger.instance.error(
        'ai.tutor',
        'Copilot sendMessage failed',
        error: e,
        stackTrace: st,
      );
      final fallback = _buildOfflineFallbackReply(ctx, isRemoteFailure: true);
      final isCancelled = AiRetryRunner.isCancelled(e, null);
      return TutorReplyResult(
        emotion: MascotEmotion.sorry,
        content: isCancelled
            ? '已取消当前请求。'
            : '${AiUserErrorMessages.fallbackNotice()}\n\n${fallback.content}',
        toolTrace: [...traceSteps, ...fallback.toolTrace],
        antiSpoilerBlocked: antiSpoilerBlocked || fallback.antiSpoilerBlocked,
        usedOfflineFallback: true,
        hintLevel: effectiveHintLevel,
      );
    } finally {
      await chunkSub.cancel();
      await retrySub.cancel();
      await afterSub.cancel();
    }
  }

  /// Summarizes older tutor messages using `P-14` (or deterministic fallback).
  Future<String> summarizeThread({
    required List<TutorMessageRecord> messages,
    String previousSummary = '',
    AiEndpointConfig? endpoint,
    String? apiKey,
    LLMClient? overrideClient,
  }) async {
    if (messages.isEmpty) return previousSummary;
    final dialogue = messages
        .map((m) => '${m.role == "user" ? "学生" : "诺诺"}：${m.content}')
        .join('\n');

    final canRunRemote =
        overrideClient != null ||
        (endpoint != null && (apiKey ?? '').trim().isNotEmpty);
    if (!canRunRemote) {
      final lastUser = messages.lastWhere(
        (m) => m.role == 'user',
        orElse: () => messages.first,
      );
      return '累计对话 ${messages.length} 轮，近期关注：${_truncate(lastUser.content, 80)}';
    }

    final rendered = PromptLibrary.get(
      'P-14',
    ).render({'oldSummary': previousSummary, 'messagesToCompress': dialogue});
    final model = endpoint != null
        ? endpoint.resolveModel(AiTier.fast)
        : 'mock-model';
    final useSse =
        overrideClient == null &&
        endpoint != null &&
        endpoint.preferSse &&
        (apiKey ?? '').trim().isNotEmpty;
    final messagesPayload = [
      if (rendered.systemPrompt.isNotEmpty)
        SystemMessage(rendered.systemPrompt),
      UserMessage([TextPart(rendered.userPrompt)]),
    ];
    final modelConfig = ModelConfig(
      model: model,
      temperature: 0.2,
      maxTokens: 256,
    );
    try {
      String text;
      if (useSse) {
        const transport = BlackboardStreamTransport(
          timeout: Duration(seconds: 45),
          connectTimeout: Duration(seconds: 15),
        );
        text = (await transport
                .streamText(
                  endpoint: endpoint,
                  apiKey: apiKey!.trim(),
                  messages: messagesPayload,
                  modelConfig: modelConfig,
                  disableThinkingForSpeed: true,
                )
                .join())
            .trim();
      } else {
        final client =
            overrideClient ??
            clientFactory.createClient(endpoint!, apiKey: apiKey!.trim());
        final reply = await client.generate(
          messagesPayload,
          modelConfig: modelConfig,
        );
        text = (reply.textOutput ?? '').trim();
      }
      return text.isEmpty ? previousSummary : text;
    } catch (_) {
      return previousSummary;
    }
  }

  AgentState _buildAgentState(TutorRequestContext ctx) {
    final historyMsgs = <LLMMessage>[];
    for (final item in ctx.history.take(12)) {
      if (item.role == 'user') {
        historyMsgs.add(UserMessage([TextPart(item.content)]));
      } else if (item.role == 'assistant') {
        historyMsgs.add(
          ModelMessage(
            textOutput: '[[emo=${item.emotion}]]\n${item.content}',
            model: 'history',
            stopReason: 'stop',
          ),
        );
      }
    }
    return AgentState(
      sessionId: ctx.sessionId,
      history: AgentMessageHistory(messages: historyMsgs),
    );
  }

  List<Tool> _buildTools(TutorRequestContext ctx) {
    return [
      Tool(
        name: InouToolNames.readQuestionPublic,
        description: '读取当前题目的题干、选项、知识点与难度（已物理剥离标准答案与解析）。',
        parameterMode: ToolParameterMode.object,
        parameters: const {
          'type': 'object',
          'properties': {
            'questionId': {'type': 'string'},
          },
        },
        executable: (Map<String, dynamic> args) {
          final q = ctx.boundQuestion;
          if (q == null) {
            return jsonEncode({'found': false, 'message': '当前为自由提问，无绑定题目'});
          }
          return jsonEncode(q.toPublicView().toJson());
        },
      ),
      Tool(
        name: InouToolNames.readQuestionAnswer,
        description: '读取标准答案与详细解析（仅 L3 完整讲解或错题复盘可用，L1/L2 会被防剧透拦截）。',
        parameterMode: ToolParameterMode.object,
        parameters: const {
          'type': 'object',
          'properties': {
            'questionId': {'type': 'string'},
          },
        },
        executable: (Map<String, dynamic> args) {
          final q = ctx.boundQuestion;
          if (q == null) {
            return jsonEncode({'found': false});
          }
          return jsonEncode({
            'id': q.id,
            'grading': q.grading,
            'explanation': q.explanation.map((b) => b.toJson()).toList(),
          });
        },
      ),
      Tool(
        name: 'query_wrong_history',
        description: '查询学生在相同题目或相同知识点下的历史错因与掌握连对次数。',
        parameterMode: ToolParameterMode.object,
        parameters: const {
          'type': 'object',
          'properties': {
            'limit': {'type': 'integer'},
          },
        },
        executable: (Map<String, dynamic> args) {
          final limit = (args['limit'] as num?)?.toInt() ?? 5;
          final items = ctx.relatedWrongItems
              .take(limit)
              .map(
                (w) => {
                  'questionId': w.questionId,
                  'mastery': w.mastery.label,
                  'correctStreak': w.correctStreak,
                  'wrongCount': w.wrongCount,
                  'errorTags': w.errorTags.map((t) => t.label).toList(),
                  'note': w.note,
                },
              )
              .toList();
          return jsonEncode({'count': items.length, 'items': items});
        },
      ),
      Tool(
        name: 'run_math_verify',
        description: '本地精确数学计算与验算引擎，支持四则/乘方/根号/二次方程求根校验。',
        parameterMode: ToolParameterMode.object,
        parameters: const {
          'type': 'object',
          'properties': {
            'expression': {'type': 'string', 'description': '待求值或含等号的式子'},
            'expected': {'type': 'string', 'description': '期望等价表达式'},
            'a': {'type': 'number'},
            'b': {'type': 'number'},
            'c': {'type': 'number'},
            'roots': {
              'type': 'array',
              'items': {'type': 'number'},
            },
          },
        },
        executable: (Map<String, dynamic> args) {
          final res = MathVerifyEngine.verifyRun(
            expression: args['expression'] as String?,
            expected: args['expected'] as String?,
            a: (args['a'] as num?)?.toDouble(),
            b: (args['b'] as num?)?.toDouble(),
            c: (args['c'] as num?)?.toDouble(),
            roots: (args['roots'] as List<dynamic>?)
                ?.whereType<num>()
                .map((e) => e.toDouble())
                .toList(),
          );
          return jsonEncode(res);
        },
      ),
    ];
  }

  String _composeUserPrompt(TutorRequestContext ctx, HintLevel level) {
    final q = ctx.boundQuestion;
    if (q == null) {
      return PromptLibrary.get('P-13').render({
        'mode': ctx.attachedImageBytes != null ? '草稿圈选伴学提问' : '自由伴学问答',
        'userQuestion': ctx.userMessage,
      }).userPrompt;
    }

    final effSubject = _resolveEffectiveSubject(q);
    final subjectLabel = SubjectCatalog.labelOf(effSubject);
    final fullQuestionText = QuestionBlackboardFormatter.formatFullPromptForTutor(
      q,
    );
    final questionBlock =
        '【学科与题型】$subjectLabel · ${q.displayKindLabel}\n$fullQuestionText';

    if (ctx.isPostMortem) {
      final expText = ContentTextUtils.extractPlainText(q.explanation);
      return PromptLibrary.get('P-11').render({
        'questionText': questionBlock,
        'studentAnswer': ctx.currentDraftText ?? '（未填写）',
        'verdict': ctx.verdictLabel ?? '待复盘',
        'gradingText': jsonEncode(q.grading),
        'explanationText': expText,
      }).userPrompt;
    }

    final levelNum = switch (level) {
      HintLevel.l1Concept => '1',
      HintLevel.l2KeyStep => '2',
      HintLevel.l3FullSolution => '3',
      HintLevel.none => '1',
    };
    final baseHint = PromptLibrary.get('P-12').render({
      'hintLevel': levelNum,
      'questionText': questionBlock,
      'currentDraft': ctx.currentDraftText,
      'fullAnswerBlock': level == HintLevel.l3FullSolution
          ? '${jsonEncode(q.grading)}\n${ContentTextUtils.extractPlainText(q.explanation)}'
          : null,
    }).userPrompt;
    return '$baseHint\n\n学生补充提问：${ctx.userMessage}';
  }

  TutorReplyResult _buildOfflineFallbackReply(
    TutorRequestContext ctx, {
    bool isRemoteFailure = false,
  }) {
    final q = ctx.boundQuestion;
    final effectiveLevel = ctx.isPostMortem
        ? HintLevel.l3FullSolution
        : ctx.hintLevel;
    final asksAnswerDirectly =
        ctx.userMessage.contains('答案') ||
        ctx.userMessage.contains('直接给') ||
        ctx.userMessage.contains('直接说');
    final blockedByHook =
        asksAnswerDirectly &&
        q != null &&
        (effectiveLevel == HintLevel.l1Concept ||
            effectiveLevel == HintLevel.l2KeyStep);

    final trace = <TutorToolTraceStep>[
      if (q != null)
        TutorToolTraceStep(
          toolName: InouToolNames.readQuestionPublic,
          summary: 'questionId=${q.id}',
          outputSnippet:
              '已读取脱敏完整题面（${q.displayKindLabel}，难度 ${q.meta.difficulty.label}）',
        ),
      if (ctx.relatedWrongItems.isNotEmpty)
        TutorToolTraceStep(
          toolName: 'query_wrong_history',
          summary: 'count=${ctx.relatedWrongItems.length}',
          outputSnippet: '命中 ${ctx.relatedWrongItems.length} 条同类错题记录',
        ),
      if (blockedByHook)
        const TutorToolTraceStep(
          toolName: InouToolNames.readQuestionAnswer,
          summary: 'anti_spoiler_guard',
          isBlocked: true,
          outputSnippet: 'AntiSpoilerHook 已在 L1/L2 拦截标准答案访问',
        ),
    ];

    if (q == null) {
      final hasSketch = ctx.attachedImageBytes != null;
      final content = hasSketch
          ? '我看到你刚刚圈选了一块草稿区域！在本地离线模式下暂不解析手写像素，不过你可以把你卡住的那一步公式发给我，我们可以一起用本地验算工具校验每一步变形是否正确哦。'
          : (isRemoteFailure
                ? '你可以先打开任意题目切换到 L1/L2/L3 渐进提示，或直接输入算式让我帮你核对计算结果！'
                : '嗨 ${ctx.profile.name}！目前还没有配置云端 API Key（可在「设置 → AI 模型与接口」一键接入 Gemini 或 DeepSeek/OpenAI 兼容接口）。\n\n不过你可以先打开任意题目切换到 L1/L2/L3 渐进提示，或直接输入算式让我帮你核对计算结果！');
      return TutorReplyResult(
        emotion: hasSketch ? MascotEmotion.thinking : MascotEmotion.wink,
        content: content,
        toolTrace: trace,
        antiSpoilerBlocked: false,
        usedOfflineFallback: true,
        hintLevel: effectiveLevel,
      );
    }

    final stem = QuestionBlackboardFormatter.cleanStemText(q);
    final bodySummary = QuestionBlackboardFormatter.compactBodySummary(q);
    final effSubj = _resolveEffectiveSubject(q);
    final subjLabel = SubjectCatalog.labelOf(effSubj);
    final exp = ContentTextUtils.extractPlainText(q.explanation);
    final kps = q.meta.tags.isNotEmpty
        ? q.meta.tags.join(' · ')
        : (q.meta.kpIds.isNotEmpty ? q.meta.kpIds.join(' · ') : subjLabel);

    if (blockedByHook) {
      final bodyPart = bodySummary != null ? '\n\n题面已给出：$bodySummary' : '';
      final nextStepGuide = switch (effSubj) {
        'eng' => q.isSequence
            ? '先把词块按「主语 + 情态/谓语动词 + 宾语或地点/时间状语」分一分组，看看哪几个词块能先搭出句子主干？'
            : '结合语境、人称时态与选项差异，先说说你能排除哪几个选项？',
        _ when _isHumanitiesSubject(effSubj) =>
          '先圈出设问关键词，结合材料定位对应原话，再用自己的话归纳核心要点！',
        _ => '结合「${_truncate(stem, 32)}」的已知条件，你打算先列哪一条关键关系式？',
      };
      return TutorReplyResult(
        emotion: MascotEmotion.serious,
        content:
            '当前在「${effectiveLevel == HintLevel.l1Concept ? "思路点拨" : "关键提示"}」模式，先不直接看完整答案哦。\n\n'
            '先看考点 **$kps**：$nextStepGuide$bodyPart\n\n如果想直接看完整解析，点上方「详细解答」即可。',
        toolTrace: trace,
        antiSpoilerBlocked: true,
        usedOfflineFallback: true,
        hintLevel: effectiveLevel,
      );
    }

    if (ctx.isPostMortem || effectiveLevel == HintLevel.l3FullSolution) {
      final ansPreview = _formatGradingSummary(q);
      final mathCheck = MathVerifyEngine.evaluateExpression(ansPreview);
      if (mathCheck != null) {
        trace.add(
          TutorToolTraceStep(
            toolName: 'run_math_verify',
            summary: 'finalAnswer=$ansPreview',
            outputSnippet: '数值验算结果 = $mathCheck',
          ),
        );
      }
      final bodyNote = bodySummary != null ? '\n- 题面信息：$bodySummary' : '';
      final content =
          '''
**1. 先肯定**：愿意回来认真梳理 **${_truncate(stem, 28)}**，这就是提分最稳的一步！$bodyNote
**2. 关键拆解（L3 完整解析）**：
${exp.isNotEmpty ? exp : '先围绕核心考点逐层梳理已知条件与作答要点，最后结合题干要求复核。'}
**3. 参考答案核对**：$ansPreview
**4. 避坑一句话**：做完 **$subjLabel** 这类 $kps 题时，记得回读题干限定词再交卷。''';
      return TutorReplyResult(
        emotion: MascotEmotion.celebrate,
        content: content.trim(),
        toolTrace: trace,
        antiSpoilerBlocked: false,
        usedOfflineFallback: true,
        hintLevel: effectiveLevel,
      );
    }

    if (effectiveLevel == HintLevel.l2KeyStep) {
      final firstHint = _extractFirstSentence(exp);
      final bodyNote = bodySummary != null ? '\n\n题面已知：$bodySummary' : '';
      final defaultTip = effSubj == 'eng'
          ? '先确定句子主语和核心谓语/情态动词位置，再把修饰成分或固定搭配接上。'
          : (_isHumanitiesSubject(effSubj)
                ? '先紧扣设问关键词回原文划出对应句段，概括主要作用。'
                : '先标出所有已知量与目标量，列出它们之间最直接的关系式。');
      return TutorReplyResult(
        emotion: MascotEmotion.encourage,
        content:
            '【L2 关键一步提示】\n'
            '这道 **$subjLabel** 题主要考查 **$kps**。$bodyNote\n\n'
            '你可以先把最关键的突破口写出来：${firstHint.isNotEmpty ? firstHint : defaultTip}\n\n'
            '试着按这一步写一下，再发给我帮你把关～',
        toolTrace: trace,
        antiSpoilerBlocked: false,
        usedOfflineFallback: true,
        hintLevel: effectiveLevel,
      );
    }

    // L1 or none
    final bodyNote = bodySummary != null ? '\n\n题面已给出：$bodySummary' : '';
    final promptQ = effSubj == 'eng'
        ? (q.isSequence
              ? '试着先找一找这组词块里谁是主语、谁是动词，能不能先搭出前半句主干？'
              : '结合语境时间线索与前后搭配，能不能先划掉明显不符合语法的选项？')
        : (q.kind == QuestionKind.choice
              ? '能不能先结合题干限定条件用排除法去掉明显矛盾的选项？'
              : '哪个核心知识点或规律能把题目的已知和所求连接起来？');
    return TutorReplyResult(
      emotion: MascotEmotion.thinking,
      content:
          '【L1 思路引导】\n'
          '先结合完整题干看清考点 **$kps**，圈出最关键的已知线索或限定条件。$bodyNote\n\n'
          '思考一个小问题：$promptQ',
      toolTrace: trace,
      antiSpoilerBlocked: false,
      usedOfflineFallback: true,
      hintLevel: effectiveLevel,
    );
  }

  String _stageTone(StudyStage stage) => switch (stage) {
    StudyStage.primary => '亲切活泼、少用抽象术语，多举生活小例子',
    StudyStage.middle => '温和清晰、重视概念辨析与步骤条理',
    StudyStage.high => '理性精炼、直指模型本质与高考/模考易错点',
  };

  /// Synchronously creates an immediate subject-aware Step-1 chalk opening
  /// so the student sees chalk writing begin right away before the first
  /// remote token arrives.
  BlackboardLessonRecord buildStreamingOpeningStub(
    BlackboardPlanRequest req, {
    Map<String, Object?>? preserveInk,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final effectiveLevel = req.isPostMortem
        ? HintLevel.l3FullSolution
        : (req.hintLevel == HintLevel.none
              ? HintLevel.l1Concept
              : req.hintLevel);
    final q = req.boundQuestion;
    final subj = q == null ? 'other' : _resolveEffectiveSubject(q);
    final stem = q == null
        ? ''
        : _truncate(QuestionBlackboardFormatter.cleanStemText(q), 64);
    final bodySummary = q == null
        ? null
        : QuestionBlackboardFormatter.compactBodySummary(q);

    final (String stepTitle, String firstLineText) = switch (subj) {
      'eng' => ('审读语境与句子主干', stem.isNotEmpty ? '原句：$stem' : '抓主谓结构与语境搭配'),
      _ when _isHumanitiesSubject(subj) => (
        '审清设问与原文定位',
        stem.isNotEmpty ? '材料要点：$stem' : '定位题干关键词',
      ),
      'chem' || 'bio' => (
        '识别条件与核心变化',
        stem.isNotEmpty ? '题干条件：$stem' : '提取物质/过程条件',
      ),
      _ => (
        '审题圈画与条件整理',
        stem.isNotEmpty ? '已知条件：$stem' : '梳理题目已知量与求解目标',
      ),
    };

    return BlackboardLessonRecord(
      id: 'bb_${_uuid.v4().substring(0, 8)}',
      questionId: q?.id ?? '__free__',
      questionTitle: q?.header.title ?? '自由黑板讲堂',
      hintLevel: effectiveLevel.index,
      studentInkData: preserveInk,
      tracks: [
        BlackboardSolutionTrack(
          id: 'track_1',
          label: '正在板书',
          diagram: const BlackboardDiagramSpec(),
          revealedCount: 1,
          steps: [
            BlackboardStep(
              id: 'step_1',
              stepNumber: 1,
              title: stepTitle,
              spokenText: '诺诺拿起粉笔开始写板书啦，讲解马上一点一点呈现出来～',
              emotion: 'thinking',
              lines: [
                BlackboardLineItem(
                  id: 'l_stub_1',
                  tag: '',
                  text: firstLineText,
                  color: ChalkColor.white,
                ),
                if (bodySummary != null)
                  BlackboardLineItem(
                    id: 'l_stub_2',
                    tag: '',
                    text: bodySummary,
                    color: ChalkColor.white,
                  ),
              ],
            ),
          ],
        ),
      ],
      updatedAtMs: now,
    );
  }

  static int maxStepsForHintLevel(HintLevel level) => switch (level) {
    HintLevel.l1Concept => 2,
    HintLevel.l2KeyStep => 3,
    HintLevel.l3FullSolution => 4,
    HintLevel.none => 2,
  };

  /// Streams ONLY a single step (`P-17` BBSTREAM protocol) so Step 1 starts
  /// appearing on the blackboard within ~1-2s, and subsequent steps can be
  /// prefetched quietly in the background or streamed on demand.
  Future<BlackboardStepResult> generateBlackboardStep(
    BlackboardStepRequest req, {
    void Function(ParsedBlackboardStep partial)? onPartialStep,
  }) async {
    final effectiveLevel = req.isPostMortem
        ? HintLevel.l3FullSolution
        : (req.hintLevel == HintLevel.none
              ? HintLevel.l1Concept
              : req.hintLevel);
    final maxSteps = maxStepsForHintLevel(effectiveLevel);
    final q = req.boundQuestion;
    final effectiveSubject = q == null ? 'other' : _resolveEffectiveSubject(q);
    final isMathOrPhy =
        effectiveSubject == 'math' || effectiveSubject == 'phy';

    final canRunRemote =
        req.overrideClient != null ||
        (req.endpoint != null && (req.apiKey ?? '').trim().isNotEmpty);

    BlackboardStepResult offlineStepFallback({String? errorMsg}) {
      final offline = _buildOfflineBlackboardLesson(
        BlackboardPlanRequest(
          profile: req.profile,
          boundQuestion: q,
          currentDraftText: req.currentDraftText,
          isPostMortem: req.isPostMortem,
          hintLevel: effectiveLevel,
          mascotDisplayName: req.mascotDisplayName,
          mascotPersona: req.mascotPersona,
        ),
        effectiveLevel,
      );
      final track = offline.lesson.activeTrack!;
      final steps = track.steps;
      final idx = (req.stepNumber - 1).clamp(0, steps.length - 1);
      final step = steps[idx];
      final hasMore = idx + 1 < steps.length;
      return BlackboardStepResult(
        step: step,
        hasMoreSteps: hasMore,
        plannedTotalSteps: steps.length,
        diagram: req.stepNumber == 1 ? track.diagram : null,
        takeaway: hasMore ? '' : track.takeaway,
        toolTrace: [
          ...offline.toolTrace,
          if (errorMsg != null)
            TutorToolTraceStep(
              toolName: 'generate_blackboard_step',
              summary: 'step=${req.stepNumber} fallback',
              isError: true,
              outputSnippet: _truncate(errorMsg, 90),
            ),
        ],
        antiSpoilerBlocked: offline.antiSpoilerBlocked,
        usedOfflineFallback: true,
      );
    }

    if (!canRunRemote) {
      return offlineStepFallback();
    }

    final endpoint = req.endpoint ?? AiEndpointPresets.defaults().first;
    final levelNum = switch (effectiveLevel) {
      HintLevel.l1Concept => '1',
      HintLevel.l2KeyStep => '2',
      HintLevel.l3FullSolution => '3',
      HintLevel.none => '1',
    };
    final hintPolicy = switch (effectiveLevel) {
      HintLevel.l1Concept => '只写审题圈画、考点定位与破题方向，严禁写出最终答案或完整解出过程',
      HintLevel.l2KeyStep => '演示关键列式或句法桥梁，但保留最终数值运算或完整结论给学生自己完成',
      HintLevel.l3FullSolution => '分步讲透直到规范作答、检验与易错避坑点',
      HintLevel.none => '引导思考，不直接泄露答案',
    };
    final subjectLabel = q == null
        ? null
        : SubjectCatalog.labelOf(effectiveSubject);
    final fullAns = (q != null && effectiveLevel == HintLevel.l3FullSolution)
        ? '${jsonEncode(q.grading)}\n${ContentTextUtils.extractPlainText(q.explanation)}'
        : null;
    final prevSummary = req.previousSteps.isEmpty
        ? null
        : req.previousSteps
              .map(
                (s) =>
                    '第${s.stepNumber}步「${s.title}」：${s.lines.map((l) => l.text).join("；")}',
              )
              .join('\n');

    final p17 = PromptLibrary.get('P-17').render({
      'displayName': req.mascotDisplayName,
      'persona': req.mascotPersona,
      'studentNickname': req.profile.name,
      'studentStage': req.profile.stage.label,
      'studentGrade': req.profile.grade,
      'stageTone': _stageTone(req.profile.stage),
      'subjectLabel': ?subjectLabel,
      'stepNumber': '${req.stepNumber}',
      'maxSteps': '$maxSteps',
      'isStepOne': req.stepNumber <= 1,
      'isMathOrPhysics': isMathOrPhy,
      'diagramStepIndex': '${math.max(0, req.stepNumber - 1)}',
      'hintLevel': levelNum,
      'hintPolicy': hintPolicy,
      'questionText': q == null
          ? '自由黑板伴学提问（暂无绑定固定题目）'
          : QuestionBlackboardFormatter.formatFullPromptForTutor(q),
      'currentDraft': req.currentDraftText,
      'previousStepsSummary': prevSummary,
      'studentFeedbackSummary': req.studentFeedbackSummary,
      'fullAnswerBlock': fullAns,
    });

    final trace = <TutorToolTraceStep>[
      if (q != null)
        TutorToolTraceStep(
          toolName: InouToolNames.readQuestionPublic,
          summary: 'questionId=${q.id}',
          outputSnippet: '已载入脱敏题干（${q.displayKindLabel}）',
        ),
      if (q != null && effectiveLevel != HintLevel.l3FullSolution)
        const TutorToolTraceStep(
          toolName: InouToolNames.readQuestionAnswer,
          summary: 'anti_spoiler_guard',
          isBlocked: true,
          outputSnippet: 'L1/L2 阶段已屏蔽标准答案与解析输入',
        ),
    ];

    final parts = <UserContentPart>[
      TextPart(p17.userPrompt),
      if (req.stepNumber == 1 && req.attachedImageBytes != null)
        ImagePart(
          base64Encode(req.attachedImageBytes!),
          req.attachedImageMimeType,
          detail: endpoint.sendImageDetail ? 'high' : null,
        ),
    ];
    final messages = <LLMMessage>[
      if (p17.systemPrompt.trim().isNotEmpty) SystemMessage(p17.systemPrompt),
      UserMessage(parts),
    ];

    final candidates = endpoint.resolveModelCandidates(AiTier.fast);
    var attemptSeen = -1;
    var lastLineCount = 0;
    var lastTitle = '';
    var lastCharCount = 0;
    var lastEmitMs = 0;
    final sw = Stopwatch()..start();

    final streamRes = await _streamWithCandidateRetry<ParsedBlackboardStep>(
      candidates: candidates,
      endpoint: endpoint,
      apiKey: req.apiKey,
      messages: messages,
      buildModelConfig: (model) => ModelConfig(
        model: model,
        temperature: 0.35,
        maxTokens: 950,
      ),
      overrideClient: req.overrideClient,
      cancelToken: req.cancelToken,
      scene: 'blackboard',
      loggerContext: 'P-17 generateBlackboardStep (step=${req.stepNumber})',
      onDelta: (_, fullSoFar, attemptIndex) {
        if (onPartialStep == null) return;
        if (attemptIndex != attemptSeen) {
          attemptSeen = attemptIndex;
          lastLineCount = 0;
          lastTitle = '';
          lastCharCount = 0;
          lastEmitMs = 0;
          sw
            ..reset()
            ..start();
        }
        final parsed = BlackboardStepStreamParser.parse(
          fullSoFar,
          stepNumber: req.stepNumber,
          maxStepsForLevel: maxSteps,
          isMathOrPhysics: isMathOrPhy,
        );
        if (parsed == null) return;
        final lineCount = parsed.step.lines.length;
        final title = parsed.step.title;
        final chars =
            title.length +
            parsed.step.spokenText.length +
            parsed.step.lines.fold<int>(
              0,
              (s, l) => s + l.text.length + (l.latex?.length ?? 0),
            );
        final nowMs = sw.elapsedMilliseconds;
        final structuralChange =
            lineCount != lastLineCount || title != lastTitle;
        if (chars != lastCharCount &&
            (structuralChange || nowMs - lastEmitMs >= 45)) {
          lastLineCount = lineCount;
          lastTitle = title;
          lastCharCount = chars;
          lastEmitMs = nowMs;
          onPartialStep(parsed);
        }
      },
      tryFinalize: (raw) => BlackboardStepStreamParser.parse(
        raw,
        stepNumber: req.stepNumber,
        maxStepsForLevel: maxSteps,
        isMathOrPhysics: isMathOrPhy,
        isFinal: true,
      ),
    );

    if (req.cancelToken?.isCancelled ?? false) {
      return offlineStepFallback();
    }

    final finalParsed = streamRes.value;
    if (finalParsed != null) {
      onPartialStep?.call(finalParsed);
      trace.add(
        TutorToolTraceStep(
          toolName: 'generate_blackboard_step',
          summary:
              'L$levelNum · step=${req.stepNumber} · more=${finalParsed.hasMoreSteps}',
          outputSnippet:
              '已流式写完第 ${req.stepNumber} 步（${finalParsed.step.lines.length} 行）',
        ),
      );
      return BlackboardStepResult(
        step: finalParsed.step,
        hasMoreSteps: finalParsed.hasMoreSteps,
        plannedTotalSteps: finalParsed.plannedTotalSteps,
        diagram: finalParsed.diagram,
        addedDiagramElements: finalParsed.addedDiagramElements,
        takeaway: finalParsed.takeaway,
        toolTrace: List.unmodifiable(trace),
        antiSpoilerBlocked: effectiveLevel != HintLevel.l3FullSolution,
        usedOfflineFallback: false,
      );
    }

    return offlineStepFallback(
      errorMsg: AiUserErrorMessages.blackboardFallbackSpoken(),
    );
  }

  /// Evaluates a student's open-ended reply or confusion signal on a single
  /// blackboard step (`P-18`), returning a concrete verdict, emotion, and
  /// encouraging reaction without spoiling L1/L2 answers.
  Future<BlackboardFeedbackResult> evaluateBlackboardFeedback(
    BlackboardFeedbackRequest req,
  ) async {
    final effectiveLevel = req.hintLevel == HintLevel.none
        ? HintLevel.l1Concept
        : req.hintLevel;
    final trimmed = req.studentReply.trim();
    if (!req.isConfused) {
      final scope = StudyScopeGuard.check(
        userText: trimmed,
        boundQuestionText: req.boundQuestion == null
            ? null
            : QuestionBlackboardFormatter.formatFullPromptForTutor(
                req.boundQuestion!,
              ),
        boundQuestionTitle: req.boundQuestion?.header.title,
        displayName: req.mascotDisplayName,
      );
      if (!scope.allowed) {
        return BlackboardFeedbackResult(
          verdict: 'wrong',
          emotion: MascotEmotion.serious,
          feedback: scope.redirectMessage!,
          usedOfflineFallback: false,
        );
      }
    }
    final isConfused =
        req.isConfused ||
        trimmed.isEmpty ||
        trimmed.contains('不懂') ||
        trimmed.contains('不会') ||
        trimmed.contains('没懂') ||
        trimmed.contains('不明白') ||
        trimmed.contains('不知道') ||
        trimmed.contains('懵');

    final canRunRemote =
        req.overrideClient != null ||
        (req.endpoint != null && (req.apiKey ?? '').trim().isNotEmpty);

    if (!canRunRemote) {
      return _buildOfflineFeedbackResult(
        req,
        effectiveLevel: effectiveLevel,
        trimmedReply: trimmed,
        isConfused: isConfused,
      );
    }

    final endpoint = req.endpoint ?? AiEndpointPresets.defaults().first;
    final q = req.boundQuestion;
    final subj = q == null ? 'other' : _resolveEffectiveSubject(q);
    final subjectLabel = q == null ? null : SubjectCatalog.labelOf(subj);
    final levelNum = switch (effectiveLevel) {
      HintLevel.l1Concept => '1',
      HintLevel.l2KeyStep => '2',
      HintLevel.l3FullSolution => '3',
      HintLevel.none => '1',
    };
    final stepSummary =
        '第 ${req.step.stepNumber} 步「${req.step.title}」：'
        '${req.step.lines.map((l) => "${l.text} ${l.latex ?? ""}").join("；")}'
        '${req.step.checkpoint != null ? "\n互动问题：${req.step.checkpoint!.prompt}" : ""}';

    final p18 = PromptLibrary.get('P-18').render({
      'displayName': req.mascotDisplayName,
      'stageTone': _stageTone(req.profile.stage),
      'subjectLabel': ?subjectLabel,
      'hintLevel': levelNum,
      'questionText': q == null
          ? '自由黑板伴学提问'
          : QuestionBlackboardFormatter.formatFullPromptForTutor(q),
      'stepSummary': stepSummary,
      'expectedHint': req.step.checkpoint?.expectedHint,
      'isConfused': isConfused ? 'true' : 'false',
      'studentReply': trimmed.isEmpty ? '学生点击了「没太懂」' : trimmed,
    });

    final messages = <LLMMessage>[
      if (p18.systemPrompt.trim().isNotEmpty) SystemMessage(p18.systemPrompt),
      UserMessage([TextPart(p18.userPrompt)]),
    ];

    final candidates = endpoint.resolveModelCandidates(AiTier.fast);
    final streamRes =
        await _streamWithCandidateRetry<BlackboardFeedbackResult>(
          candidates: candidates,
          endpoint: endpoint,
          apiKey: req.apiKey,
          messages: messages,
          buildModelConfig: (model) => ModelConfig(
            model: model,
            temperature: 0.3,
            maxTokens: 320,
          ),
          overrideClient: req.overrideClient,
          cancelToken: req.cancelToken,
          scene: 'blackboard',
          loggerContext: 'P-18 evaluateBlackboardFeedback',
          onDelta: (_, _, _) {},
          tryFinalize: (raw) => raw.trim().isEmpty
              ? null
              : _parseFeedbackResponse(raw, isConfused: isConfused),
        );

    if (streamRes.value != null) return streamRes.value!;

    return _buildOfflineFeedbackResult(
      req,
      effectiveLevel: effectiveLevel,
      trimmedReply: trimmed,
      isConfused: isConfused,
    );
  }

  /// Shared bounded-retry runner for candidate-model blackboard streaming calls.
  Future<({T? value, bool streamFailed})> _streamWithCandidateRetry<T>({
    required List<String> candidates,
    required AiEndpointConfig endpoint,
    required String? apiKey,
    required List<LLMMessage> messages,
    required ModelConfig Function(String model) buildModelConfig,
    required LLMClient? overrideClient,
    CancelToken? cancelToken,
    bool? jsonOutput,
    required String scene,
    required String loggerContext,
    required void Function(String delta, String fullSoFar, int attemptIndex)
    onDelta,
    required T? Function(String fullText) tryFinalize,
  }) async {
    for (var idx = 0; idx < candidates.length; idx++) {
      if (cancelToken?.isCancelled ?? false) {
        return (value: null, streamFailed: false);
      }
      final model = candidates[idx];
      try {
        final res = await AiRetryRunner.run<T?>(
          scene: scene,
          cancelToken: cancelToken,
          loggerTag: 'ai.tutor',
          retryIfResult: (v) =>
              v == null && !(cancelToken?.isCancelled ?? false),
          action: (attemptIndex) async {
            final rawBuf = StringBuffer();
            final stream = const BlackboardStreamTransport().streamText(
              endpoint: endpoint,
              apiKey: apiKey,
              messages: messages,
              modelConfig: buildModelConfig(model),
              overrideClient: overrideClient,
              cancelToken: cancelToken,
              disableThinkingForSpeed: true,
              jsonOutput: jsonOutput,
              retryConfig: AiRetryConfig.none,
            );
            await for (final delta in stream) {
              if (cancelToken?.isCancelled ?? false) break;
              rawBuf.write(delta);
              onDelta(delta, rawBuf.toString(), attemptIndex);
            }
            if (cancelToken?.isCancelled ?? false) return null;
            return tryFinalize(rawBuf.toString());
          },
        );
        return (value: res, streamFailed: false);
      } catch (e, st) {
        if (idx + 1 < candidates.length &&
            AiEndpointConfig.isModelUnavailableError(e)) {
          continue;
        }
        InouDiagnosticsLogger.instance.error(
          'ai.tutor',
          '$loggerContext failed (model=$model)',
          error: e,
          stackTrace: st,
        );
        return (value: null, streamFailed: true);
      }
    }
    return (value: null, streamFailed: false);
  }

  BlackboardFeedbackResult? _parseFeedbackResponse(
    String raw, {
    required bool isConfused,
  }) {
    var verdict = isConfused ? 'confused' : 'partial';
    MascotEmotion? emotion;
    final feedbackBuf = StringBuffer();
    var inFeedback = false;

    for (final rawLine in raw.split(RegExp(r'\r?\n'))) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('```')) continue;
      final tagMatch = RegExp(r'^\[\[([A-Z_]+)\]\]\s*(.*)$').firstMatch(line);
      if (tagMatch != null) {
        final tag = tagMatch.group(1)!.toUpperCase();
        final val = tagMatch.group(2)?.trim() ?? '';
        inFeedback = false;
        switch (tag) {
          case 'VERDICT':
            final v = val.toLowerCase();
            if (v == 'correct' ||
                v == 'partial' ||
                v == 'wrong' ||
                v == 'confused') {
              verdict = v;
            }
          case 'EMO':
            if (val.isNotEmpty) {
              emotion = MascotEmotion.fromCode(
                val.split(RegExp(r'[\s|,]+')).first,
              );
            }
          case 'FEEDBACK':
            if (val.isNotEmpty) feedbackBuf.write(val);
            inFeedback = true;
        }
      } else if (inFeedback) {
        if (feedbackBuf.isNotEmpty) feedbackBuf.write(' ');
        feedbackBuf.write(line);
      }
    }

    final feedbackText = feedbackBuf.toString().trim().isNotEmpty
        ? feedbackBuf.toString().trim()
        : raw.replaceAll(RegExp(r'\[\[[A-Z_]+\]\]'), '').trim();
    if (feedbackText.isEmpty) return null;

    final resolvedEmo =
        emotion ??
        switch (verdict) {
          'correct' => MascotEmotion.celebrate,
          'partial' => MascotEmotion.happy,
          _ => MascotEmotion.encourage,
        };
    return BlackboardFeedbackResult(
      verdict: verdict,
      emotion: resolvedEmo,
      feedback: feedbackText,
      usedOfflineFallback: false,
    );
  }

  BlackboardFeedbackResult _buildOfflineFeedbackResult(
    BlackboardFeedbackRequest req, {
    required HintLevel effectiveLevel,
    required String trimmedReply,
    required bool isConfused,
  }) {
    final q = req.boundQuestion;
    final subj = q == null ? 'other' : _resolveEffectiveSubject(q);
    final stepTitle = req.step.title;

    if (isConfused) {
      final gentleTip = switch (subj) {
        'eng' =>
          '没关系！英语这步我们放慢一点：先别管长句，只要先找出「谁（主语）+ 做什么（动词）」，再把其余词往后排就清楚多啦，下面我用更直白的话继续带你看！',
        _ when _isHumanitiesSubject(subj) =>
          '没关系哦～这一步先不用记术语，你只要顺着题干问的关键词回材料里划出一句原话就行，下一步诺诺帮你拆得更白话一些！',
        'chem' || 'bio' =>
          '卡住很正常呀！这步先只看一个点：条件箭头前后到底谁变了、条件是什么，接下来老师拆细一点带你过～',
        _ =>
          '没关系，这步卡住了正好说明我们在找真问题！先只抓住这一步「$stepTitle」里最核心的一个已知条件，接下来诺诺放慢节奏再陪你推一遍～',
      };
      return BlackboardFeedbackResult(
        verdict: 'confused',
        emotion: MascotEmotion.encourage,
        feedback: gentleTip,
        usedOfflineFallback: true,
      );
    }

    final expectedHint = req.step.checkpoint?.expectedHint ?? '';
    final targetBank = <String>[
      expectedHint,
      for (final l in req.step.lines) '${l.text} ${l.latex ?? ""}',
      if (q != null) _formatGradingSummary(q),
    ].join(' ').toLowerCase();

    final replyLower = trimmedReply.toLowerCase();
    final tokens = RegExp(r'[a-z0-9]+|[\u4e00-\u9fff]{2,}')
        .allMatches(replyLower)
        .map((m) => m.group(0)!)
        .where((t) => t.length >= 2 || RegExp(r'^\d+$').hasMatch(t))
        .toSet();

    var hitCount = 0;
    for (final tok in tokens) {
      if (targetBank.contains(tok)) hitCount++;
    }
    if (tokens.isEmpty && trimmedReply.length >= 2) {
      if (targetBank.contains(replyLower)) hitCount++;
    }

    final expectedHintLower = expectedHint.toLowerCase();
    final hintTokens = RegExp(r'[a-z0-9]+|[\u4e00-\u9fff]{2,}')
        .allMatches(expectedHintLower)
        .map((m) => m.group(0)!)
        .toSet();
    final hitsExpectedHint =
        hintTokens.isNotEmpty && tokens.any(hintTokens.contains);

    if (hitsExpectedHint || hitCount >= 2 || (tokens.length == 1 && hitCount == 1)) {
      return BlackboardFeedbackResult(
        verdict: 'correct',
        emotion: MascotEmotion.celebrate,
        feedback: '太棒了！你提到的「$trimmedReply」正好抓住了「$stepTitle」的关键点，我们顺着这个思路继续往下写～',
        usedOfflineFallback: true,
      );
    }

    if (hitCount >= 1 || trimmedReply.length >= 6) {
      return BlackboardFeedbackResult(
        verdict: 'partial',
        emotion: MascotEmotion.happy,
        feedback:
            '很有想法！你已经注意到其中一部分线索啦～结合「$stepTitle」上面的重点再细扣一下条件，就会更完整！',
        usedOfflineFallback: true,
      );
    }

    final retryHint = effectiveLevel == HintLevel.l3FullSolution
        ? '还差一点点！再回头看看第 ${req.step.stepNumber} 步板书画线那一行，或者试试把已知量代进去再想一想。'
        : '思路还差一点点关键桥梁，先不急～重新看看第 ${req.step.stepNumber} 步的高亮重点，试着再抓一次关键词！';
    return BlackboardFeedbackResult(
      verdict: 'wrong',
      emotion: MascotEmotion.encourage,
      feedback: retryHint,
      usedOfflineFallback: true,
    );
  }

  /// Generates a step-by-step interactive blackboard lesson plan (with optional
  /// dynamic diagram elements and checkpoints) obeying [HintLevel] anti-spoiler rules.
  ///
  /// When running against a remote LLM, streams output incrementally and invokes
  /// [onPartialLesson] as steps & chalk lines arrive.
  Future<BlackboardLessonResult> generateBlackboardLesson(
    BlackboardPlanRequest req, {
    void Function(BlackboardLessonRecord partial)? onPartialLesson,
  }) async {
    final effectiveLevel = req.isPostMortem
        ? HintLevel.l3FullSolution
        : (req.hintLevel == HintLevel.none
              ? HintLevel.l1Concept
              : req.hintLevel);
    final canRunRemote =
        req.overrideClient != null ||
        (req.endpoint != null && (req.apiKey ?? '').trim().isNotEmpty);

    if (!canRunRemote) {
      return _buildOfflineBlackboardLesson(req, effectiveLevel);
    }

    final endpoint = req.endpoint ?? AiEndpointPresets.defaults().first;
    final client =
        req.overrideClient ??
        clientFactory.createClient(
          endpoint,
          apiKey: req.apiKey!.trim(),
          scene: 'blackboard',
        );
    final levelNum = switch (effectiveLevel) {
      HintLevel.l1Concept => '1',
      HintLevel.l2KeyStep => '2',
      HintLevel.l3FullSolution => '3',
      HintLevel.none => '1',
    };
    final hintPolicy = switch (effectiveLevel) {
      HintLevel.l1Concept => '只写审题圈画、考点定位与破题方向，严禁写出最终答案或完整解出过程',
      HintLevel.l2KeyStep => '演示关键列式或辅助线构造，但保留最终数值运算与结论给学生完成',
      HintLevel.l3FullSolution => '提供完整分步板书、易错警示，并尽量附带「解法二」拓展分支',
      HintLevel.none => '引导思考，不直接泄露答案',
    };

    final q = req.boundQuestion;
    final effectiveSubject = q == null ? 'other' : _resolveEffectiveSubject(q);
    final subjectLabel = q == null
        ? null
        : SubjectCatalog.labelOf(effectiveSubject);
    final fullAns = (q != null && effectiveLevel == HintLevel.l3FullSolution)
        ? '${jsonEncode(q.grading)}\n${ContentTextUtils.extractPlainText(q.explanation)}'
        : null;
    final p15 = PromptLibrary.get('P-15').render({
      'displayName': req.mascotDisplayName,
      'persona': req.mascotPersona,
      'studentNickname': req.profile.name,
      'studentStage': req.profile.stage.label,
      'studentGrade': req.profile.grade,
      'stageTone': _stageTone(req.profile.stage),
      'subjectLabel': ?subjectLabel,
      'hintLevel': levelNum,
      'hintPolicy': hintPolicy,
      'questionText': q == null
          ? '自由黑板伴学提问（暂无绑定固定题目）'
          : QuestionBlackboardFormatter.formatFullPromptForTutor(q),
      'currentDraft': req.currentDraftText,
      'fullAnswerBlock': fullAns,
    });

    final trace = <TutorToolTraceStep>[
      if (q != null)
        TutorToolTraceStep(
          toolName: InouToolNames.readQuestionPublic,
          summary: 'questionId=${q.id}',
          outputSnippet: '已载入脱敏题干（${q.displayKindLabel}）',
        ),
      if (q != null && effectiveLevel != HintLevel.l3FullSolution)
        const TutorToolTraceStep(
          toolName: InouToolNames.readQuestionAnswer,
          summary: 'anti_spoiler_guard',
          isBlocked: true,
          outputSnippet: 'L1/L2 阶段已屏蔽标准答案与解析输入',
        ),
    ];

    final lessonId = 'bb_${_uuid.v4().substring(0, 8)}';
    const tier = AiTier.fast;
    final jsonOutput = endpoint.jsonModeStrategy != JsonModeStrategy.promptOnly;
    final parts = <UserContentPart>[
      TextPart(p15.userPrompt),
      if (req.attachedImageBytes != null)
        ImagePart(
          base64Encode(req.attachedImageBytes!),
          req.attachedImageMimeType,
          detail: endpoint.sendImageDetail ? 'high' : null,
        ),
    ];
    final messages = <LLMMessage>[
      if (p15.systemPrompt.trim().isNotEmpty) SystemMessage(p15.systemPrompt),
      UserMessage(parts),
    ];

    // Stream tokens via quote-aware SSE transport so Gemini JSON array / SSE
    // payloads never split mid-chunk.
    final candidates = endpoint.resolveModelCandidates(tier);
    var attemptSeen = -1;
    var lastSig = '';
    var lastEmitMs = 0;
    final sw = Stopwatch()..start();

    final streamRes = await _streamWithCandidateRetry<String>(
      candidates: candidates,
      endpoint: endpoint,
      apiKey: req.apiKey,
      messages: messages,
      buildModelConfig: (model) => ModelConfig(
        model: model,
        temperature: 0.35,
        maxTokens: 4096,
      ),
      overrideClient: req.overrideClient,
      cancelToken: req.cancelToken,
      jsonOutput: jsonOutput,
      scene: 'blackboard',
      loggerContext: 'generateBlackboardLesson stream',
      onDelta: (_, fullSoFar, attemptIndex) {
        if (onPartialLesson == null) return;
        if (attemptIndex != attemptSeen) {
          attemptSeen = attemptIndex;
          lastSig = '';
          lastEmitMs = 0;
          sw
            ..reset()
            ..start();
        }
        final nowMs = sw.elapsedMilliseconds;
        final partial = IncrementalBlackboardParser.tryParsePartial(
          fullSoFar,
          lessonId: lessonId,
          questionId: q?.id ?? '__free__',
          questionTitle: q?.header.title ?? '自由黑板讲堂',
          hintLevel: effectiveLevel.index,
        );
        if (partial == null) return;
        final sig = IncrementalBlackboardParser.contentSignature(partial);
        final stepCountChanged =
            sig.split('|').first != lastSig.split('|').first;
        if (sig != lastSig &&
            (stepCountChanged || nowMs - lastEmitMs >= 50)) {
          lastSig = sig;
          lastEmitMs = nowMs;
          onPartialLesson(partial);
        }
      },
      tryFinalize: (raw) => raw.trim().isEmpty ? null : raw,
    );

    if (req.cancelToken?.isCancelled ?? false) {
      return _buildOfflineBlackboardLesson(req, effectiveLevel);
    }

    // Try direct JSON parse of the accumulated stream first (zero extra LLM call)
    final streamedRaw = streamRes.value;
    if (streamedRaw != null && streamedRaw.trim().isNotEmpty) {
      final parsed = _tryDecodeBlackboardTracks(streamedRaw);
      if (parsed.isNotEmpty) {
        trace.add(
          TutorToolTraceStep(
            toolName: 'plan_blackboard_lesson',
            summary: 'L$levelNum · stream · tracks=${parsed.length}',
            outputSnippet: '已流式生成 ${parsed.first.steps.length} 步动态板书',
          ),
        );
        final lesson = BlackboardLessonRecord(
          id: lessonId,
          questionId: q?.id ?? '__free__',
          questionTitle: q?.header.title ?? '自由黑板讲堂',
          hintLevel: effectiveLevel.index,
          tracks: parsed,
          activeTrackIndex: 0,
          updatedAtMs: DateTime.now().millisecondsSinceEpoch,
        );
        return BlackboardLessonResult(
          lesson: lesson,
          toolTrace: List.unmodifiable(trace),
          antiSpoilerBlocked: effectiveLevel != HintLevel.l3FullSolution,
          usedOfflineFallback: false,
        );
      }
    }

    // Fall back to StructuredJsonCaller (supports P-03 JSON repair) only if
    // stream returned non-empty malformed JSON.
    if (!streamRes.streamFailed && streamedRaw != null) {
      final jsonRes = await const StructuredJsonCaller().callJson(
        client: client,
        endpoint: endpoint,
        tier: tier,
        systemPrompt: p15.systemPrompt,
        userPrompt: p15.userPrompt,
        imageBytes: req.attachedImageBytes,
        imageMimeType: req.attachedImageMimeType,
        temperature: 0.35,
        cancelToken: req.cancelToken,
        scene: 'blackboard',
        validator: (decoded) {
          if (decoded is! Map) return ['Root must be a JSON object'];
          final tracks = decoded['tracks'];
          if (tracks is! List || tracks.isEmpty) {
            return ['tracks must be a non-empty array'];
          }
          final first = tracks.first;
          if (first is! Map ||
              first['steps'] is! List ||
              (first['steps'] as List).isEmpty) {
            return ['tracks[0].steps must be a non-empty array'];
          }
          return const [];
        },
      );

      if (jsonRes.ok && jsonRes.asMap != null) {
        final rawTracks = jsonRes.asMap!['tracks'] as List<Object?>? ?? const [];
        final parsedTracks = rawTracks
            .whereType<Map<Object?, Object?>>()
            .map(
              (m) => BlackboardSolutionTrack.fromJson(
                m.map((k, v) => MapEntry(k.toString(), v)),
              ),
            )
            .where((t) => t.steps.isNotEmpty)
            .toList(growable: false);
        if (parsedTracks.isNotEmpty) {
          trace.add(
            TutorToolTraceStep(
              toolName: 'plan_blackboard_lesson',
              summary: 'L$levelNum · tracks=${parsedTracks.length}',
              outputSnippet: '已生成 ${parsedTracks.first.steps.length} 步动态板书',
            ),
          );
          final lesson = BlackboardLessonRecord(
            id: lessonId,
            questionId: q?.id ?? '__free__',
            questionTitle: q?.header.title ?? '自由黑板讲堂',
            hintLevel: effectiveLevel.index,
            tracks: parsedTracks,
            activeTrackIndex: 0,
            updatedAtMs: DateTime.now().millisecondsSinceEpoch,
          );
          return BlackboardLessonResult(
            lesson: lesson,
            toolTrace: List.unmodifiable(trace),
            antiSpoilerBlocked: effectiveLevel != HintLevel.l3FullSolution,
            usedOfflineFallback: false,
          );
        }
      }
    }

    final fallback = _buildOfflineBlackboardLesson(req, effectiveLevel);
    return BlackboardLessonResult(
      lesson: fallback.lesson,
      toolTrace: [
        ...trace,
        TutorToolTraceStep(
          toolName: 'plan_blackboard_lesson',
          summary: 'fallback',
          isError: true,
          outputSnippet: AiUserErrorMessages.blackboardFallbackSpoken(),
        ),
        ...fallback.toolTrace,
      ],
      antiSpoilerBlocked: fallback.antiSpoilerBlocked,
      usedOfflineFallback: true,
    );
  }

  List<BlackboardSolutionTrack> _tryDecodeBlackboardTracks(String raw) {
    try {
      final cleaned = AiTextPostProcessor.extractJsonText(raw);
      final decoded = jsonDecode(cleaned);
      if (decoded is! Map) return const [];
      final rawTracks = decoded['tracks'];
      if (rawTracks is! List || rawTracks.isEmpty) return const [];
      return rawTracks
          .whereType<Map<Object?, Object?>>()
          .map(
            (m) => BlackboardSolutionTrack.fromJson(
              m.map((k, v) => MapEntry(k.toString(), v)),
            ),
          )
          .where((t) => t.steps.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  /// Answers a circled step question, grades student chalk strokes, or
  /// generates an alternate solution branch ([BlackboardSolutionTrack]).
  Future<BlackboardAskResult> askOnBlackboard(
    BlackboardAskRequest req,
  ) async {
    final effectiveLevel = req.hintLevel == HintLevel.none
        ? HintLevel.l1Concept
        : req.hintLevel;
    final scope = StudyScopeGuard.check(
      userText: req.userQuestion,
      boundQuestionText: req.boundQuestion == null
          ? null
          : QuestionBlackboardFormatter.formatFullPromptForTutor(
              req.boundQuestion!,
            ),
      boundQuestionTitle:
          req.boundQuestion?.header.title ?? req.lesson.questionTitle,
      displayName: req.mascotDisplayName,
    );
    if (!scope.allowed) {
      final msg = scope.redirectMessage!;
      final targetId =
          req.targetStep?.id ??
          req.lesson.activeTrack?.currentStep?.id ??
          'step_1';
      return BlackboardAskResult(
        emotion: MascotEmotion.serious,
        spokenReply: msg,
        usedOfflineFallback: false,
        sideNote: BlackboardSideNote(
          id: 'note_${_uuid.v4().substring(0, 8)}',
          targetStepId: targetId,
          studentQuestion: req.userQuestion.trim(),
          spokenReply: msg,
          chalkLines: const [],
        ),
      );
    }

    final asksAnswerDirectly =
        req.userQuestion.contains('答案') ||
        req.userQuestion.contains('直接给') ||
        req.userQuestion.contains('直接说');
    final asksAlternate =
        req.requestAlternateMethod ||
        req.userQuestion.contains('解法二') ||
        req.userQuestion.contains('别的解法') ||
        req.userQuestion.contains('换种解法') ||
        req.userQuestion.contains('换个方法');

    final blockedDirectAnswer =
        asksAnswerDirectly &&
        req.boundQuestion != null &&
        effectiveLevel != HintLevel.l3FullSolution;

    final canRunRemote =
        req.overrideClient != null ||
        (req.endpoint != null && (req.apiKey ?? '').trim().isNotEmpty);

    if (!canRunRemote || blockedDirectAnswer) {
      return _buildOfflineBlackboardAsk(
        req,
        effectiveLevel,
        asksAlternate: asksAlternate,
        blockedDirectAnswer: blockedDirectAnswer,
      );
    }

    final endpoint = req.endpoint ?? AiEndpointPresets.defaults().first;
    final levelNum = switch (effectiveLevel) {
      HintLevel.l1Concept => '1',
      HintLevel.l2KeyStep => '2',
      HintLevel.l3FullSolution => '3',
      HintLevel.none => '1',
    };
    final targetSummary = req.targetStep == null
        ? '未指定具体步骤（整体黑板）'
        : '第 ${req.targetStep!.stepNumber} 步「${req.targetStep!.title}」：'
              '${req.targetStep!.lines.map((l) => "${l.text} ${l.latex ?? ""}").join("；")}';
    final effectiveSubject = req.boundQuestion == null
        ? 'other'
        : _resolveEffectiveSubject(req.boundQuestion!);
    final subjectLabel = req.boundQuestion == null
        ? null
        : SubjectCatalog.labelOf(effectiveSubject);

    final p16 = PromptLibrary.get('P-16').render({
      'displayName': req.mascotDisplayName,
      'stageTone': _stageTone(req.profile.stage),
      'subjectLabel': ?subjectLabel,
      'hintLevel': levelNum,
      'questionText': req.boundQuestion == null
          ? req.lesson.questionTitle
          : QuestionBlackboardFormatter.formatFullPromptForTutor(
              req.boundQuestion!,
            ),
      'targetStepSummary': targetSummary,
      'hasSnapshot': req.compositeSnapshotPng != null ? 'true' : 'false',
      'studentStrokeCount': '${req.studentStrokeCount}',
      'userQuestion': req.userQuestion,
    });

    final askParts = <UserContentPart>[
      TextPart(p16.userPrompt),
      if (req.compositeSnapshotPng != null)
        ImagePart(
          base64Encode(req.compositeSnapshotPng!),
          'image/png',
          detail: endpoint.sendImageDetail ? 'high' : null,
        ),
    ];
    final askMessages = <LLMMessage>[
      if (p16.systemPrompt.trim().isNotEmpty) SystemMessage(p16.systemPrompt),
      UserMessage(askParts),
    ];

    final fastCandidates = endpoint.resolveModelCandidates(AiTier.fast);
    final jsonOutput = endpoint.jsonModeStrategy != JsonModeStrategy.promptOnly;
    final streamRes = await _streamWithCandidateRetry<String>(
      candidates: fastCandidates,
      endpoint: endpoint,
      apiKey: req.apiKey,
      messages: askMessages,
      buildModelConfig: (model) => ModelConfig(
        model: model,
        temperature: 0.35,
        maxTokens: 1200,
      ),
      overrideClient: req.overrideClient,
      jsonOutput: jsonOutput,
      scene: 'blackboard',
      loggerContext: 'P-16 askOnBlackboard fast stream',
      onDelta: (_, _, _) {},
      tryFinalize: (raw) => raw.trim().isEmpty ? null : raw,
    );

    final fastRaw = streamRes.value;
    if (fastRaw != null && fastRaw.trim().isNotEmpty) {
      try {
        final cleaned = AiTextPostProcessor.extractJsonText(fastRaw);
        final decoded = jsonDecode(cleaned);
        if (decoded is Map) {
          final parsed = _decodeAskJsonPayload(
            decoded.map((k, v) => MapEntry(k.toString(), v)),
            req: req,
          );
          if (parsed != null) return parsed;
        }
      } catch (_) {
        // Fall back to StructuredJsonCaller below if fast stream output needed repair.
      }
    }

    if (!streamRes.streamFailed && fastRaw != null) {
      final client =
          req.overrideClient ??
          clientFactory.createClient(
            endpoint,
            apiKey: req.apiKey!.trim(),
            scene: 'blackboard',
          );
      final jsonRes = await const StructuredJsonCaller().callJson(
        client: client,
        endpoint: endpoint,
        tier: AiTier.fast,
        systemPrompt: p16.systemPrompt,
        userPrompt: p16.userPrompt,
        imageBytes: req.compositeSnapshotPng,
        imageMimeType: 'image/png',
        temperature: 0.35,
        scene: 'blackboard',
        validator: (decoded) {
          if (decoded is! Map) return ['Root must be a JSON object'];
          final mode = decoded['mode'];
          if (mode == 'new_track' && decoded['newTrack'] is! Map) {
            return ['mode=new_track requires newTrack object'];
          }
          if (mode != 'new_track' && decoded['sideNote'] is! Map) {
            return ['sideNote object is required'];
          }
          return const [];
        },
      );

      if (jsonRes.ok && jsonRes.asMap != null) {
        final parsed = _decodeAskJsonPayload(jsonRes.asMap!, req: req);
        if (parsed != null) return parsed;
      }
    }

    return _buildOfflineBlackboardAsk(
      req,
      effectiveLevel,
      asksAlternate: asksAlternate,
      blockedDirectAnswer: blockedDirectAnswer,
    );
  }

  BlackboardAskResult? _decodeAskJsonPayload(
    Map<String, Object?> map, {
    required BlackboardAskRequest req,
  }) {
    final mode = map['mode'] as String? ?? 'side_note';
    final targetId =
        req.targetStep?.id ??
        req.lesson.activeTrack?.currentStep?.id ??
        'step_1';

    if (mode == 'new_track' && map['newTrack'] is Map) {
      final rawTrack = (map['newTrack']! as Map).map(
        (k, v) => MapEntry(k.toString(), v),
      );
      final track = BlackboardSolutionTrack.fromJson(rawTrack);
      if (track.steps.isNotEmpty) {
        return BlackboardAskResult(
          emotion: MascotEmotion.wink,
          spokenReply: '好呀！老师在黑板上另开一栏「${track.label}」，我们一步步看新思路～',
          alternateTrack: track,
          toolTrace: [
            TutorToolTraceStep(
              toolName: 'blackboard_alternate_track',
              summary: track.label,
              outputSnippet: '已生成 ${track.steps.length} 步拓展解法',
            ),
          ],
          usedOfflineFallback: false,
        );
      }
    }

    if (map['sideNote'] is Map) {
      final rawNote = (map['sideNote']! as Map).map(
        (k, v) => MapEntry(k.toString(), v),
      );
      final parsedNote = BlackboardSideNote.fromJson({
        ...rawNote,
        'id': 'sn_${_uuid.v4().substring(0, 8)}',
        'targetStepId': targetId,
        'studentQuestion': req.userQuestion,
        'createdAtMs': DateTime.now().millisecondsSinceEpoch,
      });
      final emo = MascotEmotion.fromCode(parsedNote.emotion);
      return BlackboardAskResult(
        emotion: emo,
        spokenReply: parsedNote.spokenReply,
        sideNote: parsedNote,
        toolTrace: [
          TutorToolTraceStep(
            toolName: 'blackboard_side_note',
            summary: 'target=$targetId, strokes=${req.studentStrokeCount}',
            outputSnippet: '已添加原位粉笔旁批（${parsedNote.chalkLines.length} 行）',
          ),
        ],
        usedOfflineFallback: false,
      );
    }
    return null;
  }

  BlackboardLessonResult _buildOfflineBlackboardLesson(
    BlackboardPlanRequest req,
    HintLevel level,
  ) {
    final q = req.boundQuestion;
    final now = DateTime.now().millisecondsSinceEpoch;
    final trace = <TutorToolTraceStep>[
      if (q != null)
        TutorToolTraceStep(
          toolName: InouToolNames.readQuestionPublic,
          summary: 'questionId=${q.id}',
          outputSnippet: '已提取题干结构与知识点（${q.displayKindLabel}）',
        ),
      if (q != null && level != HintLevel.l3FullSolution)
        const TutorToolTraceStep(
          toolName: InouToolNames.readQuestionAnswer,
          summary: 'anti_spoiler_guard',
          isBlocked: true,
          outputSnippet: 'AntiSpoilerHook 已保护标准答案，按分步启发模式书写板书',
        ),
    ];

    if (q == null) {
      const freeTrack = BlackboardSolutionTrack(
        id: 'track_free',
        label: '自由黑板课堂',
        diagram: BlackboardDiagramSpec(),
        revealedCount: 1,
        takeaway: '随时用「圈选提问」或「写粉笔」在黑板上划重点、圈出疑问直接问诺诺老师！',
        steps: [
          BlackboardStep(
            id: 'step_free_1',
            stepNumber: 1,
            title: '自由提问与草稿板书',
            spokenText: '欢迎来到诺诺的黑板小课堂！你可以在左下角开启「写粉笔」做标记，或者直接在下方输入框告诉我你想问的题目～',
            emotion: 'happy',
            lines: [
              BlackboardLineItem(
                id: 'lf_1',
                tag: '',
                text: '用「写粉笔」划重点或写下草稿，点批改即可点评',
                color: ChalkColor.white,
              ),
              BlackboardLineItem(
                id: 'lf_2',
                tag: '',
                text: '用「圈选提问」圈住任意内容，立刻在旁写出针对拆解',
                color: ChalkColor.white,
              ),
            ],
          ),
          BlackboardStep(
            id: 'step_free_2',
            stepNumber: 2,
            title: '三步审题通用思路',
            spokenText: '无论做哪一科题目，我们都可以按「抓线索 → 定考点/语境 → 核对作答」三步来梳理！',
            emotion: 'wink',
            lines: [
              BlackboardLineItem(
                id: 'lf_3',
                tag: '',
                text: '定位题干线索  →  锁定核心考点与规则  →  回读检验答案规范',
                color: ChalkColor.green,
                annotation: ChalkAnnotationKind.box,
              ),
            ],
          ),
        ],
      );
      return BlackboardLessonResult(
        lesson: BlackboardLessonRecord(
          id: 'bb_${_uuid.v4().substring(0, 8)}',
          questionId: '__free__',
          questionTitle: '自由黑板讲堂',
          hintLevel: level.index,
          tracks: [freeTrack],
          updatedAtMs: now,
        ),
        toolTrace: trace,
        antiSpoilerBlocked: false,
        usedOfflineFallback: true,
      );
    }

    final subj = _resolveEffectiveSubject(q);
    final stem = QuestionBlackboardFormatter.cleanStemText(q);
    final bodySummary = QuestionBlackboardFormatter.compactBodySummary(q);
    final exp = ContentTextUtils.extractPlainText(q.explanation);
    final kps = q.meta.tags.isNotEmpty
        ? q.meta.tags.join(' · ')
        : (q.meta.kpIds.isNotEmpty
              ? q.meta.kpIds.join(' · ')
              : SubjectCatalog.labelOf(subj));
    final diagram = _inferDiagramForQuestion(q, subj);
    final firstHint = _extractFirstSentence(exp);
    final ansSummary = _formatGradingSummary(q);

    if (subj == 'eng') {
      return _buildEnglishBlackboardLesson(
        q: q,
        level: level,
        now: now,
        trace: trace,
        stem: stem,
        exp: exp,
        kps: kps,
        firstHint: firstHint,
        ansSummary: ansSummary,
      );
    }
    if (_isHumanitiesSubject(subj)) {
      return _buildHumanitiesBlackboardLesson(
        q: q,
        subj: subj,
        level: level,
        now: now,
        trace: trace,
        stem: stem,
        exp: exp,
        kps: kps,
        firstHint: firstHint,
        ansSummary: ansSummary,
      );
    }
    if (subj == 'chem' || subj == 'bio') {
      return _buildChemBioBlackboardLesson(
        q: q,
        subj: subj,
        level: level,
        now: now,
        trace: trace,
        stem: stem,
        exp: exp,
        kps: kps,
        firstHint: firstHint,
        ansSummary: ansSummary,
      );
    }

    // Math & Physics path
    final step1 = BlackboardStep(
      id: 'step_1',
      stepNumber: 1,
      title: '审题圈画与考点定位',
      spokenText: '我们先别急着硬算，一起看题干里的关键数字和限定条件！这道题考查的核心考点是「$kps」。',
      emotion: 'thinking',
      lines: [
        BlackboardLineItem(
          id: 'l_1_1',
          tag: '',
          text: '$kps（${SubjectCatalog.labelOf(subj)} · ${q.displayKindLabel}）',
          color: ChalkColor.yellow,
          annotation: ChalkAnnotationKind.underline,
        ),
        BlackboardLineItem(
          id: 'l_1_2',
          tag: '',
          text: '已知条件：${_truncate(stem, 64)}',
          color: ChalkColor.white,
        ),
        if (bodySummary != null)
          BlackboardLineItem(
            id: 'l_1_opts',
            tag: '',
            text: bodySummary,
            color: ChalkColor.white,
          ),
        if (diagram.isNotEmpty)
          const BlackboardLineItem(
            id: 'l_1_3',
            tag: '',
            text: '对照左侧示意图，先把已知顶点/坐标/受力标注出来',
            color: ChalkColor.white,
            annotation: ChalkAnnotationKind.arrow,
          ),
      ],
    );

    if (level == HintLevel.l1Concept) {
      final step2 = BlackboardStep(
        id: 'step_2',
        stepNumber: 2,
        title: '锁定破题突破口',
        spokenText: '现在处于「思路点拨」模式，诺诺先不直接列完算式～先做个小选择，看看你的破题方向对不对！',
        emotion: 'encourage',
        lines: [
          BlackboardLineItem(
            id: 'l_2_1',
            tag: '',
            text: q.kind == QuestionKind.choice
                ? '优先观察各选项特征，考虑代入特值或直接建立等量关系'
                : '寻找把「已知量」与「待求目标」直接相连的核心定理或公式',
            color: ChalkColor.white,
            annotation: ChalkAnnotationKind.arrow,
          ),
          const BlackboardLineItem(
            id: 'l_2_2',
            tag: '',
            text: '试着用下方「写粉笔」在黑板上写出你的第一步列式',
            color: ChalkColor.green,
          ),
        ],
        checkpoint: _buildCheckpointForQuestion(q, subj, isL1: true),
      );

      final track1 = BlackboardSolutionTrack(
        id: 'track_1',
        label: '解法一：审题与思路点拨',
        diagram: diagram,
        steps: [step1, step2],
        revealedCount: 1,
        takeaway: '先圈已知与目标，再选核心关系式；想要看关键列式可切到「关键步骤」。',
      );
      return BlackboardLessonResult(
        lesson: BlackboardLessonRecord(
          id: 'bb_${_uuid.v4().substring(0, 8)}',
          questionId: q.id,
          questionTitle: q.header.title,
          hintLevel: level.index,
          tracks: [track1],
          updatedAtMs: now,
        ),
        toolTrace: trace,
        antiSpoilerBlocked: true,
        usedOfflineFallback: true,
      );
    }

    if (level == HintLevel.l2KeyStep) {
      final keySetup = firstHint.isNotEmpty
          ? firstHint
          : '根据题设条件建立核心等量关系式（注意符号与单位统一）';
      final step2 = BlackboardStep(
        id: 'step_2',
        stepNumber: 2,
        title: '关键第一步：列式 / 添辅助线',
        spokenText: '好，这一步我们把最关键的突破口写到黑板上！注意看重点下划线标出的转化方向。',
        emotion: 'happy',
        lines: [
          BlackboardLineItem(
            id: 'l_2_1',
            tag: '',
            text: keySetup,
            color: ChalkColor.yellow,
            annotation: ChalkAnnotationKind.underline,
          ),
          if (diagram.isNotEmpty)
            const BlackboardLineItem(
              id: 'l_2_2',
              tag: '',
              text: '观察黑板示意图上新画出的辅助线 / 关键点位',
              color: ChalkColor.white,
              annotation: ChalkAnnotationKind.arrow,
            ),
        ],
        checkpoint: _buildCheckpointForQuestion(q, subj, isL1: false),
      );
      const step3 = BlackboardStep(
        id: 'step_3',
        stepNumber: 3,
        title: '留白演算：请你接力完成最后一步',
        spokenText: '关键桥梁已经搭好啦！剩下的化简求解留给你亲自拿下，也可以用「写粉笔」写出来让我帮你看对不对～',
        emotion: 'encourage',
        lines: [
          BlackboardLineItem(
            id: 'l_3_1',
            tag: '',
            text: '将上一步关系式继续化简，得出最终结果并回代原题检验',
            color: ChalkColor.green,
            annotation: ChalkAnnotationKind.box,
          ),
          BlackboardLineItem(
            id: 'l_3_2',
            tag: '',
            text: '需要完整详解？点击顶部切至「详细解答」',
            color: ChalkColor.white,
          ),
        ],
      );

      final track1 = BlackboardSolutionTrack(
        id: 'track_1',
        label: '解法一：关键步骤拆解',
        diagram: diagram,
        steps: [step1, step2, step3],
        revealedCount: 1,
        takeaway: '突破卡点后，独立完成最后演算最有助于形成肌肉记忆。',
      );
      return BlackboardLessonResult(
        lesson: BlackboardLessonRecord(
          id: 'bb_${_uuid.v4().substring(0, 8)}',
          questionId: q.id,
          questionTitle: q.header.title,
          hintLevel: level.index,
          tracks: [track1],
          updatedAtMs: now,
        ),
        toolTrace: trace,
        antiSpoilerBlocked: true,
        usedOfflineFallback: true,
      );
    }

    // L3 Full Solution (Math / Physics)
    final mathCheck = MathVerifyEngine.evaluateExpression(ansSummary);
    if (mathCheck != null) {
      trace.add(
        TutorToolTraceStep(
          toolName: 'run_math_verify',
          summary: 'finalAnswer=$ansSummary',
          outputSnippet: '数值验算结果 = $mathCheck',
        ),
      );
    }

    final step2 = BlackboardStep(
      id: 'step_2',
      stepNumber: 2,
      title: '核心推导与公式变形',
      spokenText: '接下来是核心推导！注意重点划出的关键变形依据，遇到卡壳可以随时用「圈选提问」圈出来问我。',
      emotion: 'happy',
      lines: [
        BlackboardLineItem(
          id: 'l_2_1',
          tag: '',
          text: exp.isNotEmpty
              ? exp
              : '提取题设已知量建立主方程/逻辑链，逐步化简消元',
          color: ChalkColor.yellow,
          annotation: ChalkAnnotationKind.underline,
        ),
        if (diagram.isNotEmpty)
          const BlackboardLineItem(
            id: 'l_2_2',
            tag: '',
            text: '结合左侧图形关键点与辅助构造，验证各量之间的对应关系',
            color: ChalkColor.white,
            annotation: ChalkAnnotationKind.arrow,
          ),
      ],
      checkpoint: _buildCheckpointForQuestion(q, subj, isL1: false),
    );

    final step3 = BlackboardStep(
      id: 'step_3',
      stepNumber: 3,
      title: '规范作答与最终结论',
      spokenText: '把结果整理成标准书写格式！高亮总结的就是这道题的最终答案啦。',
      emotion: 'celebrate',
      lines: [
        BlackboardLineItem(
          id: 'l_3_1',
          tag: '',
          text: '最终结果：$ansSummary',
          color: ChalkColor.green,
          annotation: ChalkAnnotationKind.box,
        ),
        if (mathCheck != null)
          BlackboardLineItem(
            id: 'l_3_2',
            tag: '',
            text: '数值验算核对通过（$mathCheck）',
            color: ChalkColor.white,
          ),
      ],
    );

    final step4 = BlackboardStep(
      id: 'step_4',
      stepNumber: 4,
      title: '避坑提醒与复盘要点',
      spokenText: '最后别忘了「小提醒」标出的高频丢分点！讲完可以点右上角收藏笔记。',
      emotion: 'serious',
      lines: [
        BlackboardLineItem(
          id: 'l_4_1',
          tag: '',
          text: _pitfallForSubject(subj, kps),
          color: ChalkColor.pink,
          annotation: ChalkAnnotationKind.warn,
        ),
      ],
    );

    final track1 = BlackboardSolutionTrack(
      id: 'track_1',
      label: '解法一：标准分步精讲',
      diagram: diagram,
      steps: [step1, step2, step3, step4],
      revealedCount: 1,
      takeaway: _pitfallForSubject(subj, kps),
    );

    final track2 = _buildAlternateTrack(q, subj, diagram, ansSummary, kps);

    return BlackboardLessonResult(
      lesson: BlackboardLessonRecord(
        id: 'bb_${_uuid.v4().substring(0, 8)}',
        questionId: q.id,
        questionTitle: q.header.title,
        hintLevel: level.index,
        tracks: [track1, track2],
        updatedAtMs: now,
      ),
      toolTrace: trace,
      antiSpoilerBlocked: false,
      usedOfflineFallback: true,
    );
  }

  BlackboardLessonResult _buildEnglishBlackboardLesson({
    required Question q,
    required HintLevel level,
    required int now,
    required List<TutorToolTraceStep> trace,
    required String stem,
    required String exp,
    required String kps,
    required String firstHint,
    required String ansSummary,
  }) {
    final isReorder = q.isSequence;
    final bodySummary = QuestionBlackboardFormatter.compactBodySummary(q);
    final step1 = BlackboardStep(
      id: 'step_1',
      stepNumber: 1,
      title: '审读语境与句子主干',
      spokenText: '看英语题先抓句子主干和语境提示词～我们先把主语、谓语以及时间或搭配线索划出来（考点：$kps）。',
      emotion: 'thinking',
      lines: [
        BlackboardLineItem(
          id: 'l_1_1',
          tag: '',
          text: '英语 · ${q.displayKindLabel}｜考点：$kps',
          color: ChalkColor.yellow,
          annotation: ChalkAnnotationKind.underline,
        ),
        BlackboardLineItem(
          id: 'l_1_2',
          tag: '',
          text: '原句/题干：${_truncate(stem, 72)}',
          color: ChalkColor.white,
        ),
        if (bodySummary != null)
          BlackboardLineItem(
            id: 'l_1_opts',
            tag: '',
            text: bodySummary,
            color: ChalkColor.white,
          ),
        BlackboardLineItem(
          id: 'l_1_3',
          tag: '',
          text: isReorder
              ? '先给词块分类（主语/谓语动词/宾语/时间地点状语），再定疑问或陈述语序'
              : '圈出时间标志词、连词以及空前后的固定搭配线索',
          color: ChalkColor.white,
          annotation: ChalkAnnotationKind.arrow,
        ),
      ],
    );

    if (level == HintLevel.l1Concept) {
      final step2 = BlackboardStep(
        id: 'step_2',
        stepNumber: 2,
        title: '判断语法与词块搭配',
        spokenText: '现在是「思路点拨」模式，老师先不直接给出英文答案～选一下你觉得决定本题的关键点！',
        emotion: 'encourage',
        lines: [
          BlackboardLineItem(
            id: 'l_2_1',
            tag: '',
            text: isReorder
                ? '确认句式骨架：疑问句注意「疑问词 + 助动词/be + 主语 + 谓语」，陈述句看「主 + 谓 + 宾」'
                : '紧盯三要素：主谓人称单复数、句子时态语态、空前后的固定短语搭配',
            color: ChalkColor.white,
            annotation: ChalkAnnotationKind.arrow,
          ),
          const BlackboardLineItem(
            id: 'l_2_2',
            tag: '',
            text: '试着用下方「写粉笔」划出句子的主干成分或关键时间词',
            color: ChalkColor.green,
          ),
        ],
        checkpoint: _buildCheckpointForQuestion(q, 'eng', isL1: true),
      );
      return BlackboardLessonResult(
        lesson: BlackboardLessonRecord(
          id: 'bb_${_uuid.v4().substring(0, 8)}',
          questionId: q.id,
          questionTitle: q.header.title,
          hintLevel: level.index,
          tracks: [
            BlackboardSolutionTrack(
              id: 'track_1',
              label: '句法与语境点拨',
              diagram: const BlackboardDiagramSpec(),
              steps: [step1, step2],
              revealedCount: 1,
              takeaway: '先定主干语序与时态信号，再排查词形变化与固定搭配。',
            ),
          ],
          updatedAtMs: now,
        ),
        toolTrace: trace,
        antiSpoilerBlocked: true,
        usedOfflineFallback: true,
      );
    }

    if (level == HintLevel.l2KeyStep) {
      final step2 = BlackboardStep(
        id: 'step_2',
        stepNumber: 2,
        title: '锁定核心语法与语序',
        spokenText: '关键语法点已经重点标出来啦！顺着句型结构和词形规则，最后一步交给你自己完成～',
        emotion: 'happy',
        lines: [
          BlackboardLineItem(
            id: 'l_2_1',
            tag: '',
            text: firstHint.isNotEmpty
                ? firstHint
                : (isReorder
                      ? '按「句型骨架（主语+谓语）→ 修饰成分（定语/状语放句尾）」理顺词序'
                      : '依据主语单复数与语境时态确定核心动词形式，再检查介词/冠词搭配'),
            color: ChalkColor.yellow,
            annotation: ChalkAnnotationKind.underline,
          ),
          const BlackboardLineItem(
            id: 'l_2_2',
            tag: '',
            text: '排查句首字母大写、动词单三/过去式变形与标点符号',
            color: ChalkColor.white,
            annotation: ChalkAnnotationKind.arrow,
          ),
        ],
        checkpoint: _buildCheckpointForQuestion(q, 'eng', isL1: false),
      );
      const step3 = BlackboardStep(
        id: 'step_3',
        stepNumber: 3,
        title: '留白练习：连读整句检查语感',
        spokenText: '试着自己把完整表达拼出来，在心里默读一遍看看顺不顺畅！想看完整核对可以切到「详细解答」。',
        emotion: 'encourage',
        lines: [
          BlackboardLineItem(
            id: 'l_3_1',
            tag: '',
            text: '把确定好的词形或语序代入原句通读一遍，确认语法与句意双重通顺',
            color: ChalkColor.green,
            annotation: ChalkAnnotationKind.box,
          ),
        ],
      );
      return BlackboardLessonResult(
        lesson: BlackboardLessonRecord(
          id: 'bb_${_uuid.v4().substring(0, 8)}',
          questionId: q.id,
          questionTitle: q.header.title,
          hintLevel: level.index,
          tracks: [
            BlackboardSolutionTrack(
              id: 'track_1',
              label: '语法关键步拆解',
              diagram: const BlackboardDiagramSpec(),
              steps: [step1, step2, step3],
              revealedCount: 1,
              takeaway: '做英语题切忌只按中文逐字翻译，先抓句子主干和固定搭配更准。',
            ),
          ],
          updatedAtMs: now,
        ),
        toolTrace: trace,
        antiSpoilerBlocked: true,
        usedOfflineFallback: true,
      );
    }

    // English L3
    final step2 = BlackboardStep(
      id: 'step_2',
      stepNumber: 2,
      title: '句型结构与搭配精析',
      spokenText: '我们来把英语语言点讲透～注意重点划出的语法依据，对哪个单词或搭配不熟可以圈起来直接问我！',
      emotion: 'happy',
      lines: [
        BlackboardLineItem(
          id: 'l_2_1',
          tag: '',
          text: exp.isNotEmpty
              ? exp
              : (isReorder
                    ? '先确定主谓核心结构，再按「时间/地点状语后置」连接所有词块'
                    : '结合语境句意、句子时态以及前后词组固定搭配即可准确锁定答案'),
          color: ChalkColor.yellow,
          annotation: ChalkAnnotationKind.underline,
        ),
      ],
      checkpoint: _buildCheckpointForQuestion(q, 'eng', isL1: false),
    );
    final step3 = BlackboardStep(
      id: 'step_3',
      stepNumber: 3,
      title: '规范作答与整句回读',
      spokenText: '标注出来的是规范英文表达！放回原句默读两遍，顺便记住这组表达的语感～',
      emotion: 'celebrate',
      lines: [
        BlackboardLineItem(
          id: 'l_3_1',
          tag: '',
          text: '参考答案：$ansSummary',
          color: ChalkColor.green,
          annotation: ChalkAnnotationKind.box,
        ),
      ],
    );
    final step4 = BlackboardStep(
      id: 'step_4',
      stepNumber: 4,
      title: '高频丢分点提醒',
      spokenText: '这条「小提醒」是英语考试最容易扣分的细节：词形变化、大小写、介词搭配记得复查哦！',
      emotion: 'serious',
      lines: [
        BlackboardLineItem(
          id: 'l_4_1',
          tag: '',
          text: _pitfallForSubject('eng', kps),
          color: ChalkColor.pink,
          annotation: ChalkAnnotationKind.warn,
        ),
      ],
    );

    return BlackboardLessonResult(
      lesson: BlackboardLessonRecord(
        id: 'bb_${_uuid.v4().substring(0, 8)}',
        questionId: q.id,
        questionTitle: q.header.title,
        hintLevel: level.index,
        tracks: [
          BlackboardSolutionTrack(
            id: 'track_1',
            label: '句法与语境精讲',
            diagram: const BlackboardDiagramSpec(),
            steps: [step1, step2, step3, step4],
            revealedCount: 1,
            takeaway: _pitfallForSubject('eng', kps),
          ),
        ],
        updatedAtMs: now,
      ),
      toolTrace: trace,
      antiSpoilerBlocked: false,
      usedOfflineFallback: true,
    );
  }

  BlackboardLessonResult _buildHumanitiesBlackboardLesson({
    required Question q,
    required String subj,
    required HintLevel level,
    required int now,
    required List<TutorToolTraceStep> trace,
    required String stem,
    required String exp,
    required String kps,
    required String firstHint,
    required String ansSummary,
  }) {
    final subjName = SubjectCatalog.labelOf(subj);
    final bodySummary = QuestionBlackboardFormatter.compactBodySummary(q);
    final step1 = BlackboardStep(
      id: 'step_1',
      stepNumber: 1,
      title: '审清设问与原文定位',
      spokenText: '做$subjName题第一步是看清设问到底问什么，再回到材料或课文语境里找对应关键词句！',
      emotion: 'thinking',
      lines: [
        BlackboardLineItem(
          id: 'l_1_1',
          tag: '',
          text: '$subjName · ${q.displayKindLabel}｜考点：$kps',
          color: ChalkColor.yellow,
          annotation: ChalkAnnotationKind.underline,
        ),
        BlackboardLineItem(
          id: 'l_1_2',
          tag: '',
          text: '题干与材料要点：${_truncate(stem, 72)}',
          color: ChalkColor.white,
        ),
        if (bodySummary != null)
          BlackboardLineItem(
            id: 'l_1_opts',
            tag: '',
            text: bodySummary,
            color: ChalkColor.white,
          ),
        const BlackboardLineItem(
          id: 'l_1_3',
          tag: '',
          text: '圈出设问限定角度（时间/范围/表现手法/原因与影响）',
          color: ChalkColor.white,
          annotation: ChalkAnnotationKind.arrow,
        ),
      ],
    );

    if (level == HintLevel.l1Concept) {
      final step2 = BlackboardStep(
        id: 'step_2',
        stepNumber: 2,
        title: '提炼关键词与分析角度',
        spokenText: '现在是「思路点拨」模式，我们先把答题方向找准，不直接背现成答案～',
        emotion: 'encourage',
        lines: [
          const BlackboardLineItem(
            id: 'l_2_1',
            tag: '',
            text: '紧扣「设问关键词 → 原文对应句段 → 深层含义/教材原理」逐层定位',
            color: ChalkColor.white,
            annotation: ChalkAnnotationKind.arrow,
          ),
          const BlackboardLineItem(
            id: 'l_2_2',
            tag: '',
            text: '试着用下方「写粉笔」勾画出最核心的两三个关键词',
            color: ChalkColor.green,
          ),
        ],
        checkpoint: _buildCheckpointForQuestion(q, subj, isL1: true),
      );
      return BlackboardLessonResult(
        lesson: BlackboardLessonRecord(
          id: 'bb_${_uuid.v4().substring(0, 8)}',
          questionId: q.id,
          questionTitle: q.header.title,
          hintLevel: level.index,
          tracks: [
            BlackboardSolutionTrack(
              id: 'track_1',
              label: '审题与文本定位',
              diagram: const BlackboardDiagramSpec(),
              steps: [step1, step2],
              revealedCount: 1,
              takeaway: '先读懂设问指向，再回原文找依据，避免答非所问。',
            ),
          ],
          updatedAtMs: now,
        ),
        toolTrace: trace,
        antiSpoilerBlocked: true,
        usedOfflineFallback: true,
      );
    }

    if (level == HintLevel.l2KeyStep) {
      final step2 = BlackboardStep(
        id: 'step_2',
        stepNumber: 2,
        title: '梳理答题层次与核心要点',
        spokenText: '答题框架我写在黑板上啦！按这个层次把材料信息和学科术语连起来表达就对啦～',
        emotion: 'happy',
        lines: [
          BlackboardLineItem(
            id: 'l_2_1',
            tag: '',
            text: firstHint.isNotEmpty
                ? firstHint
                : '按「核心观点/手法 + 结合材料具体分析 + 情感或影响总结」两步走',
            color: ChalkColor.yellow,
            annotation: ChalkAnnotationKind.underline,
          ),
        ],
        checkpoint: _buildCheckpointForQuestion(q, subj, isL1: false),
      );
      const step3 = BlackboardStep(
        id: 'step_3',
        stepNumber: 3,
        title: '留白作答：用学科术语组织语言',
        spokenText: '试着自己用一两句条理清晰的话回答一下，然后切到「详细解答」对照踩分点！',
        emotion: 'encourage',
        lines: [
          BlackboardLineItem(
            id: 'l_3_1',
            tag: '',
            text: '分条标清①②点，确保既有概括结论又有材料例证',
            color: ChalkColor.green,
            annotation: ChalkAnnotationKind.box,
          ),
        ],
      );
      return BlackboardLessonResult(
        lesson: BlackboardLessonRecord(
          id: 'bb_${_uuid.v4().substring(0, 8)}',
          questionId: q.id,
          questionTitle: q.header.title,
          hintLevel: level.index,
          tracks: [
            BlackboardSolutionTrack(
              id: 'track_1',
              label: '文本层次与要点拆解',
              diagram: const BlackboardDiagramSpec(),
              steps: [step1, step2, step3],
              revealedCount: 1,
              takeaway: '文科作答讲求「要点明晰 + 结合材料 + 术语准确」。',
            ),
          ],
          updatedAtMs: now,
        ),
        toolTrace: trace,
        antiSpoilerBlocked: true,
        usedOfflineFallback: true,
      );
    }

    final step2 = BlackboardStep(
      id: 'step_2',
      stepNumber: 2,
      title: '材料逻辑与考点深析',
      spokenText: '我们把背后的命题逻辑和踩分角度拆开看一遍，哪一句没理解随时圈出来问我！',
      emotion: 'happy',
      lines: [
        BlackboardLineItem(
          id: 'l_2_1',
          tag: '',
          text: exp.isNotEmpty
              ? exp
              : '结合时代/语境背景提炼核心观点，并与原文关键表达一一印证',
          color: ChalkColor.yellow,
          annotation: ChalkAnnotationKind.underline,
        ),
      ],
      checkpoint: _buildCheckpointForQuestion(q, subj, isL1: false),
    );
    final step3 = BlackboardStep(
      id: 'step_3',
      stepNumber: 3,
      title: '规范作答与参考答案',
      spokenText: '对照高亮整理的标准答案，重点关注那些必须写出的踩分关键词！',
      emotion: 'celebrate',
      lines: [
        BlackboardLineItem(
          id: 'l_3_1',
          tag: '',
          text: '参考答案：$ansSummary',
          color: ChalkColor.green,
          annotation: ChalkAnnotationKind.box,
        ),
      ],
    );
    final step4 = BlackboardStep(
      id: 'step_4',
      stepNumber: 4,
      title: '失分避坑提示',
      spokenText: '这条「小提醒」标出的地方最容易漏掉采分点，复习时多看一眼！',
      emotion: 'serious',
      lines: [
        BlackboardLineItem(
          id: 'l_4_1',
          tag: '',
          text: _pitfallForSubject(subj, kps),
          color: ChalkColor.pink,
          annotation: ChalkAnnotationKind.warn,
        ),
      ],
    );

    return BlackboardLessonResult(
      lesson: BlackboardLessonRecord(
        id: 'bb_${_uuid.v4().substring(0, 8)}',
        questionId: q.id,
        questionTitle: q.header.title,
        hintLevel: level.index,
        tracks: [
          BlackboardSolutionTrack(
            id: 'track_1',
            label: '审题定位与规范作答',
            diagram: const BlackboardDiagramSpec(),
            steps: [step1, step2, step3, step4],
            revealedCount: 1,
            takeaway: _pitfallForSubject(subj, kps),
          ),
        ],
        updatedAtMs: now,
      ),
      toolTrace: trace,
      antiSpoilerBlocked: false,
      usedOfflineFallback: true,
    );
  }

  BlackboardLessonResult _buildChemBioBlackboardLesson({
    required Question q,
    required String subj,
    required HintLevel level,
    required int now,
    required List<TutorToolTraceStep> trace,
    required String stem,
    required String exp,
    required String kps,
    required String firstHint,
    required String ansSummary,
  }) {
    final subjName = SubjectCatalog.labelOf(subj);
    final isChem = subj == 'chem';
    final bodySummary = QuestionBlackboardFormatter.compactBodySummary(q);
    final step1 = BlackboardStep(
      id: 'step_1',
      stepNumber: 1,
      title: isChem ? '识别物质与反应条件' : '定位生理过程与结构',
      spokenText: '做$subjName题先把题干中的实验条件、关键物质或生理过程划出来（考点：$kps）！',
      emotion: 'thinking',
      lines: [
        BlackboardLineItem(
          id: 'l_1_1',
          tag: '',
          text: '$subjName · ${q.displayKindLabel}｜考点：$kps',
          color: ChalkColor.yellow,
          annotation: ChalkAnnotationKind.underline,
        ),
        BlackboardLineItem(
          id: 'l_1_2',
          tag: '',
          text: '关键信息：${_truncate(stem, 68)}',
          color: ChalkColor.white,
        ),
        if (bodySummary != null)
          BlackboardLineItem(
            id: 'l_1_opts',
            tag: '',
            text: bodySummary,
            color: ChalkColor.white,
          ),
      ],
    );

    if (level == HintLevel.l1Concept) {
      final step2 = BlackboardStep(
        id: 'step_2',
        stepNumber: 2,
        title: '锁定核心机理或守恒关系',
        spokenText: '当前在「思路点拨」模式，我们先找清变化本质～完成这个小选择热热身！',
        emotion: 'encourage',
        lines: [
          BlackboardLineItem(
            id: 'l_2_1',
            tag: '',
            text: isChem
                ? '关注物质转化链、元素/质量守恒以及典型现象（沉淀/气体/变色）'
                : '梳理结构与功能相适应的关系，理清实验变量（自变量/因变量/对照）',
            color: ChalkColor.white,
            annotation: ChalkAnnotationKind.arrow,
          ),
        ],
        checkpoint: _buildCheckpointForQuestion(q, subj, isL1: true),
      );
      return BlackboardLessonResult(
        lesson: BlackboardLessonRecord(
          id: 'bb_${_uuid.v4().substring(0, 8)}',
          questionId: q.id,
          questionTitle: q.header.title,
          hintLevel: level.index,
          tracks: [
            BlackboardSolutionTrack(
              id: 'track_1',
              label: '机理与条件点拨',
              diagram: const BlackboardDiagramSpec(),
              steps: [step1, step2],
              revealedCount: 1,
              takeaway: '先定位关键物质/实验条件，再结合原理与守恒分析变化。',
            ),
          ],
          updatedAtMs: now,
        ),
        toolTrace: trace,
        antiSpoilerBlocked: true,
        usedOfflineFallback: true,
      );
    }

    if (level == HintLevel.l2KeyStep) {
      final step2 = BlackboardStep(
        id: 'step_2',
        stepNumber: 2,
        title: isChem ? '关键转化与配平方向' : '核心生理与实验推导',
        spokenText: '核心切入点已经标出来了，最后一步试着自己推出结论！',
        emotion: 'happy',
        lines: [
          BlackboardLineItem(
            id: 'l_2_1',
            tag: '',
            text: firstHint.isNotEmpty
                ? firstHint
                : (isChem
                      ? '写出核心化学/离子方程式并核对反应条件与配平系数'
                      : '根据细胞结构或代谢路径判断物质流向与因果关系'),
            color: ChalkColor.yellow,
            annotation: ChalkAnnotationKind.underline,
          ),
        ],
        checkpoint: _buildCheckpointForQuestion(q, subj, isL1: false),
      );
      const step3 = BlackboardStep(
        id: 'step_3',
        stepNumber: 3,
        title: '留白检验：核对现象与专业表述',
        spokenText: '检查一下专业名词、化学式或实验结论表述是否严谨～想核对答案可切至「详细解答」。',
        emotion: 'encourage',
        lines: [
          BlackboardLineItem(
            id: 'l_3_1',
            tag: '',
            text: '复核条件、单位及核心专有名词无误后再确认作答',
            color: ChalkColor.green,
            annotation: ChalkAnnotationKind.box,
          ),
        ],
      );
      return BlackboardLessonResult(
        lesson: BlackboardLessonRecord(
          id: 'bb_${_uuid.v4().substring(0, 8)}',
          questionId: q.id,
          questionTitle: q.header.title,
          hintLevel: level.index,
          tracks: [
            BlackboardSolutionTrack(
              id: 'track_1',
              label: '关键步骤拆解',
              diagram: const BlackboardDiagramSpec(),
              steps: [step1, step2, step3],
              revealedCount: 1,
              takeaway: '把握「条件—变化—结论」逻辑链，细节表述零差错。',
            ),
          ],
          updatedAtMs: now,
        ),
        toolTrace: trace,
        antiSpoilerBlocked: true,
        usedOfflineFallback: true,
      );
    }

    final step2 = BlackboardStep(
      id: 'step_2',
      stepNumber: 2,
      title: isChem ? '反应原理与定量分析' : '过程机理与实验解析',
      spokenText: '我们来把每一步原理彻底理清，有疑问随时用画笔圈出来问我～',
      emotion: 'happy',
      lines: [
        BlackboardLineItem(
          id: 'l_2_1',
          tag: '',
          text: exp.isNotEmpty
              ? exp
              : '依题干条件确立反应/生理变化路径，逐项排除干扰说法',
          color: ChalkColor.yellow,
          annotation: ChalkAnnotationKind.underline,
        ),
      ],
      checkpoint: _buildCheckpointForQuestion(q, subj, isL1: false),
    );
    final step3 = BlackboardStep(
      id: 'step_3',
      stepNumber: 3,
      title: '标准答案与核对',
      spokenText: '高亮结论就是规范答法，注意专有名词或化学用语的准确写法！',
      emotion: 'celebrate',
      lines: [
        BlackboardLineItem(
          id: 'l_3_1',
          tag: '',
          text: '参考答案：$ansSummary',
          color: ChalkColor.green,
          annotation: ChalkAnnotationKind.box,
        ),
      ],
    );
    final step4 = BlackboardStep(
      id: 'step_4',
      stepNumber: 4,
      title: '避坑与细节复盘',
      spokenText: '记住这条「小提醒」标出的高频丢分点，下次遇到同类题就不会踩坑啦！',
      emotion: 'serious',
      lines: [
        BlackboardLineItem(
          id: 'l_4_1',
          tag: '',
          text: _pitfallForSubject(subj, kps),
          color: ChalkColor.pink,
          annotation: ChalkAnnotationKind.warn,
        ),
      ],
    );

    return BlackboardLessonResult(
      lesson: BlackboardLessonRecord(
        id: 'bb_${_uuid.v4().substring(0, 8)}',
        questionId: q.id,
        questionTitle: q.header.title,
        hintLevel: level.index,
        tracks: [
          BlackboardSolutionTrack(
            id: 'track_1',
            label: '原理精讲与复盘',
            diagram: const BlackboardDiagramSpec(),
            steps: [step1, step2, step3, step4],
            revealedCount: 1,
            takeaway: _pitfallForSubject(subj, kps),
          ),
        ],
        updatedAtMs: now,
      ),
      toolTrace: trace,
      antiSpoilerBlocked: false,
      usedOfflineFallback: true,
    );
  }

  BlackboardAskResult _buildOfflineBlackboardAsk(
    BlackboardAskRequest req,
    HintLevel level, {
    required bool asksAlternate,
    required bool blockedDirectAnswer,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final activeTrack = req.lesson.activeTrack;
    final targetStep = req.targetStep ?? activeTrack?.currentStep;
    final targetStepId = targetStep?.id ?? 'step_1';
    final subj = req.boundQuestion == null
        ? 'other'
        : _resolveEffectiveSubject(req.boundQuestion!);

    if (blockedDirectAnswer) {
      final guardLine = switch (subj) {
        'eng' => '先看看句子的主语、时态提示词和固定搭配，能不能自己推出关键空？',
        _ when _isHumanitiesSubject(subj) =>
          '先回到题干设问和原文对应句，试着用自己的话概括出要点？',
        'chem' || 'bio' => '先对照实验条件与变化机理，推一推这一步的直接变化？',
        _ => '先看当前步骤的「已知条件」能否直接建立核心关系式？',
      };
      final note = BlackboardSideNote(
        id: 'sn_${_uuid.v4().substring(0, 8)}',
        targetStepId: targetStepId,
        studentQuestion: req.userQuestion,
        spokenReply: '现在还在引导模式哦～先别急着看答案，顺着重点提示往前推一小步，想看完整解析可切到「详细解答」！',
        emotion: 'serious',
        chalkLines: [
          BlackboardLineItem(
            id: 'nl_guard',
            tag: '',
            text: guardLine,
            color: ChalkColor.pink,
            annotation: ChalkAnnotationKind.warn,
          ),
        ],
        createdAtMs: now,
      );
      return BlackboardAskResult(
        emotion: MascotEmotion.serious,
        spokenReply: note.spokenReply,
        sideNote: note,
        antiSpoilerBlocked: true,
        usedOfflineFallback: true,
        toolTrace: const [
          TutorToolTraceStep(
            toolName: InouToolNames.readQuestionAnswer,
            summary: 'anti_spoiler_guard',
            isBlocked: true,
            outputSnippet: 'L1/L2 黑板旁批已拦截直接索要答案请求',
          ),
        ],
      );
    }

    if (asksAlternate) {
      final q = req.boundQuestion;
      final diagram = activeTrack?.diagram ?? const BlackboardDiagramSpec();
      final altTrack = q != null
          ? _buildAlternateTrack(
              q,
              subj,
              diagram,
              level == HintLevel.l3FullSolution
                  ? _formatGradingSummary(q)
                  : '（完成最后一步即可核对结果）',
              q.meta.tags.isNotEmpty ? q.meta.tags.join('·') : '拓展视角',
            )
          : BlackboardSolutionTrack(
              id: 'track_alt_${req.lesson.tracks.length + 1}',
              label: '换个视角：逆向检验',
              diagram: diagram,
              revealedCount: 1,
              takeaway: '换个角度交叉检验，能大幅提高正确率。',
              steps: const [
                BlackboardStep(
                  id: 'alt_step_1',
                  stepNumber: 1,
                  title: '切换视角重新切入',
                  spokenText: '我们在黑板新栏换个角度梳理一次，对照验证刚才的判断！',
                  emotion: 'wink',
                  lines: [
                    BlackboardLineItem(
                      id: 'al_1',
                      tag: '',
                      text: '从选项或目标要求反推，排除明显不匹配的思路',
                      color: ChalkColor.blue,
                      annotation: ChalkAnnotationKind.arrow,
                    ),
                  ],
                ),
              ],
            );
      return BlackboardAskResult(
        emotion: MascotEmotion.wink,
        spokenReply: '好主意！老师已在黑板上开启「${altTrack.label}」，我们换个角度再看一遍！',
        alternateTrack: altTrack,
        usedOfflineFallback: true,
        toolTrace: [
          TutorToolTraceStep(
            toolName: 'blackboard_alternate_track',
            summary: altTrack.label,
            outputSnippet: '已生成拓展思路（${altTrack.steps.length} 步）',
          ),
        ],
      );
    }

    // Student chalk feedback or circled step explanation
    if (req.studentStrokeCount > 0) {
      final (String reply, String line1, String line2) = switch (subj) {
        'eng' => (
          '我看到你在黑板上画出了 ${req.studentStrokeCount} 笔标记！动手划主谓结构或时间线索是很棒的习惯～对照第 ${targetStep?.stepNumber ?? 1} 步的重点提示，检查一下词形单复数、时态和语序就更稳啦！',
          '已看到你的圈画笔记（${req.studentStrokeCount} 笔）：抓关键词很敏锐，注意核对动词形式与搭配',
          '对照「${targetStep?.title ?? '当前步骤'}」把整句英文连读一遍检查语感',
        ),
        _ when _isHumanitiesSubject(subj) => (
          '看到你在黑板上写画了 ${req.studentStrokeCount} 笔圈画！带着问题回原文标关键词特别棒～再检查一下得分角度有没有遗漏哦！',
          '已看到你的圈画笔记（${req.studentStrokeCount} 笔）：核心词抓取准确，注意分条凝练表达',
          '对照「${targetStep?.title ?? '当前步骤'}」核对「结论 + 原文依据」是否完整',
        ),
        'chem' || 'bio' => (
          '收到你在黑板上的 ${req.studentStrokeCount} 笔板书记录！顺着反应条件和守恒逻辑往下核对，注意专有名词和条件写法即可～',
          '已捕捉板书笔记（${req.studentStrokeCount} 笔）：分析思路积极，注意核对条件与术语规范',
          '对照「${targetStep?.title ?? '当前步骤'}」复核变化前后是否一致',
        ),
        _ => (
          '我看到你在黑板上写画了 ${req.studentStrokeCount} 笔思路！动手比划是非常棒的习惯。对照第 ${targetStep?.stepNumber ?? 1} 步的关键式，注意检查正负号与已知条件对应关系！',
          '已捕捉手写笔迹（${req.studentStrokeCount} 笔）：思路方向积极，注意核对等量关系与符号',
          '对照「${targetStep?.title ?? '当前步骤'}」继续化简或代入检验',
        ),
      };
      final note = BlackboardSideNote(
        id: 'sn_${_uuid.v4().substring(0, 8)}',
        targetStepId: targetStepId,
        studentQuestion: req.userQuestion,
        spokenReply: reply,
        emotion: 'encourage',
        chalkLines: [
          BlackboardLineItem(
            id: 'nl_chalk_1',
            tag: '',
            text: line1,
            color: ChalkColor.white,
            annotation: ChalkAnnotationKind.underline,
          ),
          BlackboardLineItem(
            id: 'nl_chalk_2',
            tag: '',
            text: line2,
            color: ChalkColor.green,
            annotation: ChalkAnnotationKind.arrow,
          ),
        ],
        createdAtMs: now,
      );
      return BlackboardAskResult(
        emotion: MascotEmotion.encourage,
        spokenReply: note.spokenReply,
        sideNote: note,
        usedOfflineFallback: true,
        toolTrace: [
          TutorToolTraceStep(
            toolName: 'grade_blackboard_chalk',
            summary: 'strokes=${req.studentStrokeCount}',
            outputSnippet: '已生成原位粉笔批改旁批',
          ),
        ],
      );
    }

    final stepTitle = targetStep?.title ?? '当前板书';
    final stepLinePreview = targetStep?.lines.isNotEmpty == true
        ? targetStep!.lines.first.text
        : '';
    final isAboutDiagram =
        (subj == 'math' || subj == 'phy') &&
        (req.userQuestion.contains('图') ||
            req.userQuestion.contains('线') ||
            req.userQuestion.contains('符号'));

    final addedDiagram =
        isAboutDiagram && (activeTrack?.diagram.isNotEmpty ?? false)
        ? [
            BlackboardDiagramElement(
              id: 'hl_${now % 10000}',
              type: 'circle',
              points: const [BlackboardDiagramPoint(50, 48)],
              radius: 14,
              label: '重点聚焦区',
              color: ChalkColor.pink,
              dashed: true,
              appearAtStepIndex: 0,
              highlightOnStepIds: [targetStepId],
            ),
          ]
        : const <BlackboardDiagramElement>[];

    final (String sideReply, String noteLine1, String noteLine2) = switch (subj) {
      'eng' => (
        '你针对「$stepTitle」的提问非常关键！这一步核心是抓住句子主干与英语搭配规律：'
        '${stepLinePreview.isNotEmpty ? "先看「${_truncate(stepLinePreview, 32)}」，" : ""}'
        '我把词法/语序拆开批注在了下面，结合原句读一读就明白了！',
        '针对「$stepTitle」：先分清句子主干（主语 + 谓语）与时间/地点修饰成分',
        '重点复核动词时态、单复数一致以及固定介词搭配',
      ),
      _ when _isHumanitiesSubject(subj) => (
        '你抓住了「$stepTitle」的关键！这步重在紧扣题干设问回到原文印证：'
        '${stepLinePreview.isNotEmpty ? "围绕「${_truncate(stepLinePreview, 32)}」，" : ""}'
        '下面的批注已经梳理出了答题角度，按要点组织语言就清晰了～',
        '针对「$stepTitle」：把设问限定词和原文/材料关键句一一对应',
        '答题时用「核心观点 + 原文依据」分条陈述更易拿全分',
      ),
      'chem' || 'bio' => (
        '你问的「$stepTitle」正是机理卡点！'
        '${stepLinePreview.isNotEmpty ? "顺着「${_truncate(stepLinePreview, 32)}」，" : ""}'
        '看清反应/生理条件和前后变化规律就能豁然开朗～',
        '针对「$stepTitle」：明确关键实验条件及物质/生理状态的因果变化',
        '复核守恒关系、现象描述及专业名词书写规范',
      ),
      _ => (
        '你圈选的「$stepTitle」非常精准！这一步的核心是把题干语言转化成数学/物理关系：'
        '${stepLinePreview.isNotEmpty ? "先抓住「${_truncate(stepLinePreview, 32)}」，" : ""}'
        '我在下面补上了拆解批注，${addedDiagram.isNotEmpty ? "并在左侧示意图圈出了重点位置，" : ""}看看是不是清楚多了？',
        '针对「$stepTitle」：先把已知量代入核心关系式，明确各符号含义',
        '遇到正负号或系数变化，先单独列一行草稿核对再化简',
      ),
    };

    final note = BlackboardSideNote(
      id: 'sn_${_uuid.v4().substring(0, 8)}',
      targetStepId: targetStepId,
      studentQuestion: req.userQuestion,
      spokenReply: sideReply,
      emotion: 'thinking',
      chalkLines: [
        BlackboardLineItem(
          id: 'nl_1',
          tag: '',
          text: noteLine1,
          color: ChalkColor.white,
          annotation: ChalkAnnotationKind.arrow,
        ),
        BlackboardLineItem(
          id: 'nl_2',
          tag: '',
          text: noteLine2,
          color: ChalkColor.yellow,
        ),
      ],
      addedDiagramElements: addedDiagram,
      createdAtMs: now,
    );

    return BlackboardAskResult(
      emotion: MascotEmotion.thinking,
      spokenReply: note.spokenReply,
      sideNote: note,
      usedOfflineFallback: true,
      toolTrace: [
        TutorToolTraceStep(
          toolName: 'blackboard_side_note',
          summary: 'step=$targetStepId',
          outputSnippet: '已原位插入粉笔旁批',
        ),
      ],
    );
  }

  BlackboardSolutionTrack _buildAlternateTrack(
    Question q,
    String subj,
    BlackboardDiagramSpec baseDiagram,
    String ansSummary,
    String kps,
  ) {
    if (subj == 'eng') {
      return BlackboardSolutionTrack(
        id: 'track_2',
        label: '拓展：词块归类与排除法',
        diagram: const BlackboardDiagramSpec(),
        revealedCount: 1,
        takeaway: '先排除词性或时态明显冲突的选项/语序，准确率立刻提升。',
        steps: [
          const BlackboardStep(
            id: 'alt_step_1',
            stepNumber: 1,
            title: '用词性与句意排除干扰',
            spokenText: '除了正面按语法推导，我们还可以从空处所需词性或句首/句尾语序特征入手快速排除干扰项！',
            emotion: 'wink',
            lines: [
              BlackboardLineItem(
                id: 'alt_l1',
                tag: '',
                text: '判断当前位置需要名词、动词、形容词还是副词，划掉词性或单复数不符的表达',
                color: ChalkColor.white,
                annotation: ChalkAnnotationKind.underline,
              ),
            ],
          ),
          BlackboardStep(
            id: 'alt_step_2',
            stepNumber: 2,
            title: '整句代入朗读互验',
            spokenText: '把保留的答案代回原句读一遍，语义、搭配、时态全部契合就稳了！',
            emotion: 'celebrate',
            lines: [
              BlackboardLineItem(
                id: 'alt_l2',
                tag: '',
                text: '互验结论：$ansSummary',
                color: ChalkColor.green,
                annotation: ChalkAnnotationKind.box,
              ),
            ],
          ),
        ],
      );
    }

    if (_isHumanitiesSubject(subj) || subj == 'chem' || subj == 'bio') {
      return BlackboardSolutionTrack(
        id: 'track_2',
        label: '拓展：选项排查与要点核对',
        diagram: const BlackboardDiagramSpec(),
        revealedCount: 1,
        takeaway: '正推核心知识 + 反查设问关键词，双向验证更保险。',
        steps: [
          const BlackboardStep(
            id: 'alt_step_1',
            stepNumber: 1,
            title: '从设问与材料矛盾点切入排查',
            spokenText: '换个角度看这道题：先排查是否出现「偷换概念、绝对化用词或因果倒置」的典型陷阱！',
            emotion: 'wink',
            lines: [
              BlackboardLineItem(
                id: 'alt_l1',
                tag: '',
                text: '逐句对照原文与教材核心原理，标记绝对词（一定、所有、完全）或范围偏差',
                color: ChalkColor.white,
                annotation: ChalkAnnotationKind.underline,
              ),
            ],
          ),
          BlackboardStep(
            id: 'alt_step_2',
            stepNumber: 2,
            title: '交叉确认答案要点',
            spokenText: '两条分析路线结论一致，答案就可以放心落笔啦！',
            emotion: 'celebrate',
            lines: [
              BlackboardLineItem(
                id: 'alt_l2',
                tag: '',
                text: '交叉确认：$ansSummary',
                color: ChalkColor.green,
                annotation: ChalkAnnotationKind.box,
              ),
            ],
          ),
        ],
      );
    }

    final isChoice = q.kind == QuestionKind.choice;
    final title = isChoice ? '解法二：特值代入与排除法' : '解法二：逆推检验 / 数形结合';
    final diag = baseDiagram.isNotEmpty
        ? baseDiagram
        : const BlackboardDiagramSpec();

    return BlackboardSolutionTrack(
      id: 'track_2',
      label: title,
      diagram: diag,
      revealedCount: 1,
      takeaway: isChoice ? '选填小题巧用特殊值与排除法可节省一半时间。' : '用第二视角互验，能大幅提高大题满分的稳定性。',
      steps: [
        BlackboardStep(
          id: 'alt_step_1',
          stepNumber: 1,
          title: isChoice ? '先看选项特征，排除明显矛盾项' : '从图形直观 / 边界特例切入',
          spokenText: isChoice
              ? '除了常规步骤，做选择题时还可以先观察选项差异，利用正负号或特值快速缩小范围！'
              : '换个视角再看一遍「$kps」：我们可以把代数关系和图形变化或极值情况对照起来看。',
          emotion: 'wink',
          lines: [
            BlackboardLineItem(
              id: 'alt_l1',
              tag: '',
              text: isChoice
                  ? '将选项中的代表数值反代回原题干条件，验证是否同时满足所有限制'
                  : '先定性判断结果的大致范围/正负号，再定量验算',
              color: ChalkColor.white,
              annotation: ChalkAnnotationKind.underline,
            ),
          ],
        ),
        BlackboardStep(
          id: 'alt_step_2',
          stepNumber: 2,
          title: '交叉核对得出结论',
          spokenText: '两条路线最终指向同一个结论，这就说明我们的解答稳稳的啦！',
          emotion: 'celebrate',
          lines: [
            BlackboardLineItem(
              id: 'alt_l2',
              tag: '',
              text: '交叉验证结果：$ansSummary',
              color: ChalkColor.green,
              annotation: ChalkAnnotationKind.box,
            ),
          ],
        ),
      ],
    );
  }

  BlackboardCheckpoint _buildCheckpointForQuestion(
    Question q,
    String subj, {
    required bool isL1,
  }) {
    if (subj == 'eng') {
      if (q.isSequence) {
        return BlackboardCheckpoint(
          prompt: isL1 ? '小提问：英语连词成句时，第一步先确定什么？' : '小提问：排好单词顺序后，最容易漏检的是哪一项？',
          options: isL1
              ? const ['先认清句型（陈述/疑问）并找出主语和谓语动词', '按单词字母表顺序拼在一起', '只凭中文词序一个个对译']
              : const ['句首首字母大写、标点及时间状语通常放在句尾', '不需要考虑助动词和人称配合', '单词间不用核对固定搭配'],
          correctIndex: 0,
          encouragement: '说得太对了！抓牢英语「主谓骨架 + 语序规则」，连词成句轻松拿满分～',
        );
      }
      return BlackboardCheckpoint(
        prompt: isL1 ? '小提问：做英语语法或选择填空题时，优先看哪里找依据？' : '小提问：选出答案或填好词形后，最后还要核对什么？',
        options: isL1
            ? const ['句子主语单复数、时间标志词以及前后固定搭配', '只看选项哪个单词最长', '不看上下文直接选最熟悉的词']
            : const ['时态语态是否一致、拼写及固定搭配是否地道', '只要中文大意差不多就行', '不用回读整个句子'],
        correctIndex: 0,
        encouragement: '完全抓到英语题的精髓啦！语境与语法搭配双线核对最稳妥～',
      );
    }
    if (_isHumanitiesSubject(subj)) {
      return BlackboardCheckpoint(
        prompt: isL1 ? '小提问：面对阅读理解或材料解析题，第一步应该做什么？' : '小提问：落笔组织答案时，怎么才能少丢踩分点？',
        options: isL1
            ? const ['精准圈画设问限定词，并回到原文定位关键句段', '不看材料直接背一段通用套话', '只凭第一印象猜一个结论']
            : const ['按「核心结论 + 结合材料依据」分条规范作答', '想到什么写什么不划分要点', '全抄整段原文不加提炼'],
        correctIndex: 0,
        encouragement: '思路特别正！紧扣设问和材料依据，踩分点就能稳稳拿到～',
      );
    }
    if (subj == 'chem' || subj == 'bio') {
      return BlackboardCheckpoint(
        prompt: subj == 'chem'
            ? '小提问：分析化学反应或物质转化题时，第一步先看清什么？'
            : '小提问：分析生物实验或生理过程题时，第一步先确定什么？',
        options: subj == 'chem'
            ? const ['反应物性质、反应条件与元素/质量守恒', '直接背一个不相关的方程式', '忽略反应条件与气体沉淀符号']
            : const ['实验对照变量与对应细胞结构/生理功能', '只记选项关键词不看过程', '忽略实验前提与对照组'],
        correctIndex: 0,
        encouragement: '没错！先抓牢条件与机理逻辑，选项判断自然清晰～',
      );
    }
    if (subj == 'phy') {
      return const BlackboardCheckpoint(
        prompt: '小提问：进行力学或电学分析时，第一步应该先做什么？',
        options: ['明确研究对象并画出受力/等效电路图', '直接把所有数字乘起来', '随便套一个最长的公式'],
        correctIndex: 0,
        encouragement: '完全正确！先选研究对象再画图，方向就不会乱～',
      );
    }
    if (q.plainText.contains('三角形') ||
        q.plainText.contains('直角') ||
        q.plainText.contains('几何')) {
      return const BlackboardCheckpoint(
        prompt: '小提问：看到几何里的直角或等腰条件，优先考虑哪条辅助线/定理？',
        options: ['利用勾股定理或作斜边高/中线构造直角三角形', '把图形随便拉长看面积', '只看选项猜数字'],
        correctIndex: 0,
        encouragement: '太棒了！作高线或利用勾股定理正是几何高频突破口！',
      );
    }
    if (q.plainText.contains('函数') ||
        q.plainText.contains('y =') ||
        q.plainText.contains('y=')) {
      return const BlackboardCheckpoint(
        prompt: '小提问：已知图像经过某个点 (x₀, y₀)，下一步最直接的操作是？',
        options: ['把点的横纵坐标分别代入解析式建立方程', '先求图像与 y 轴的夹角', '直接忽略这个已知点'],
        correctIndex: 0,
        encouragement: '答对了！「点在图像上 ↔ 坐标满足解析式」是函数通用金钥匙！',
      );
    }
    return BlackboardCheckpoint(
      prompt: isL1 ? '小提问：读完题干后，你认为第一步破题的关键是什么？' : '小提问：列出核心关系式后，化简时最需要注意什么？',
      options: isL1
          ? const ['把已知条件转化为核心公式中的等量关系', '跳过条件直接写结论', '只看最后问号不管前提']
          : const ['移项变号、括号展开符号以及定义域检验', '只算第一项忽略常数', '不检查直接跳步'],
      correctIndex: 0,
      encouragement: '思路非常清晰！继续看诺诺写下一步板书～',
    );
  }

  BlackboardDiagramSpec _inferDiagramForQuestion(
    Question q,
    String effectiveSubject,
  ) {
    // Only math & physics use chalkboard geometry / function / force diagrams.
    if (effectiveSubject != 'math' && effectiveSubject != 'phy') {
      return const BlackboardDiagramSpec();
    }
    final text = q.plainText;

    // 1. Physics force / inclined plane / motion
    if (effectiveSubject == 'phy' ||
        text.contains('受力') ||
        text.contains('斜面') ||
        text.contains('摩擦') ||
        text.contains('重力')) {
      return const BlackboardDiagramSpec(
        kind: BlackboardDiagramKind.physicsForce,
        title: '物理受力分析示意图',
        elements: [
          BlackboardDiagramElement(
            id: 'phy_ground',
            type: 'segment',
            points: [
              BlackboardDiagramPoint(12, 82),
              BlackboardDiagramPoint(88, 82),
            ],
            color: ChalkColor.white,
            appearAtStepIndex: 0,
          ),
          BlackboardDiagramElement(
            id: 'phy_slope',
            type: 'polygon',
            points: [
              BlackboardDiagramPoint(16, 82),
              BlackboardDiagramPoint(78, 82),
              BlackboardDiagramPoint(78, 40),
            ],
            label: '斜面/支持面',
            color: ChalkColor.white,
            appearAtStepIndex: 0,
          ),
          BlackboardDiagramElement(
            id: 'phy_block',
            type: 'box',
            points: [
              BlackboardDiagramPoint(46, 52),
              BlackboardDiagramPoint(58, 62),
            ],
            label: '研究对象 m',
            color: ChalkColor.blue,
            appearAtStepIndex: 0,
          ),
          BlackboardDiagramElement(
            id: 'phy_gravity',
            type: 'arrow',
            points: [
              BlackboardDiagramPoint(52, 57),
              BlackboardDiagramPoint(52, 82),
            ],
            label: 'G = mg',
            color: ChalkColor.yellow,
            appearAtStepIndex: 1,
            highlightOnStepIds: ['step_2'],
          ),
          BlackboardDiagramElement(
            id: 'phy_normal',
            type: 'arrow',
            points: [
              BlackboardDiagramPoint(52, 57),
              BlackboardDiagramPoint(38, 37),
            ],
            label: 'N',
            color: ChalkColor.green,
            appearAtStepIndex: 1,
            highlightOnStepIds: ['step_2'],
          ),
          BlackboardDiagramElement(
            id: 'phy_friction',
            type: 'arrow',
            points: [
              BlackboardDiagramPoint(52, 57),
              BlackboardDiagramPoint(70, 44),
            ],
            label: 'f',
            color: ChalkColor.pink,
            dashed: true,
            appearAtStepIndex: 2,
            highlightOnStepIds: ['step_3'],
          ),
        ],
      );
    }

    // 2. Geometry
    if (text.contains('三角形') ||
        text.contains('直角') ||
        text.contains('勾股') ||
        text.contains('斜边') ||
        text.contains('等腰') ||
        text.contains('圆') ||
        text.contains('△') ||
        text.contains('∠')) {
      final isRight = text.contains('直角') || text.contains('勾股');
      return BlackboardDiagramSpec(
        kind: BlackboardDiagramKind.geometry,
        title: isRight ? '直角三角形几何示意图' : '几何图形与辅助线示意图',
        elements: [
          BlackboardDiagramElement(
            id: 'geo_tri',
            type: 'polygon',
            points: isRight
                ? const [
                    BlackboardDiagramPoint(22, 78, label: 'C'),
                    BlackboardDiagramPoint(78, 78, label: 'B'),
                    BlackboardDiagramPoint(22, 24, label: 'A'),
                  ]
                : const [
                    BlackboardDiagramPoint(18, 78, label: 'B'),
                    BlackboardDiagramPoint(82, 78, label: 'C'),
                    BlackboardDiagramPoint(48, 22, label: 'A'),
                  ],
            color: ChalkColor.white,
            appearAtStepIndex: 0,
            highlightOnStepIds: ['step_1'],
          ),
          if (isRight)
            const BlackboardDiagramElement(
              id: 'geo_right_angle',
              type: 'angle',
              points: [
                BlackboardDiagramPoint(22, 78),
                BlackboardDiagramPoint(30, 78),
                BlackboardDiagramPoint(22, 70),
              ],
              label: '90°',
              color: ChalkColor.blue,
              appearAtStepIndex: 0,
            ),
          BlackboardDiagramElement(
            id: 'geo_aux',
            type: 'segment',
            points: isRight
                ? const [
                    BlackboardDiagramPoint(22, 78),
                    BlackboardDiagramPoint(48, 52, label: 'D'),
                  ]
                : const [
                    BlackboardDiagramPoint(48, 22),
                    BlackboardDiagramPoint(48, 78, label: 'H'),
                  ],
            label: isRight ? '辅助高 CD' : '辅助高 AH',
            color: ChalkColor.yellow,
            dashed: true,
            appearAtStepIndex: 1,
            highlightOnStepIds: ['step_2'],
          ),
          if (!isRight)
            const BlackboardDiagramElement(
              id: 'geo_circle',
              type: 'circle',
              points: [BlackboardDiagramPoint(48, 55)],
              radius: 20,
              color: ChalkColor.blue,
              dashed: true,
              appearAtStepIndex: 2,
              highlightOnStepIds: ['step_3'],
            ),
        ],
      );
    }

    // 3. Function / Quadratic / Linear coordinate plot
    if (text.contains('函数') ||
        text.contains('抛物线') ||
        text.contains('交点') ||
        text.contains('坐标') ||
        text.contains('y =') ||
        text.contains('y=') ||
        text.contains('x²') ||
        text.contains('x^2')) {
      final isParabola =
          text.contains('二次') ||
          text.contains('抛物线') ||
          text.contains('x²') ||
          text.contains('x^2');
      return BlackboardDiagramSpec(
        kind: BlackboardDiagramKind.functionPlot,
        title: isParabola ? '函数图像与零点示意图' : '平面直角坐标系函数图像',
        elements: [
          const BlackboardDiagramElement(
            id: 'fn_axes',
            type: 'axes',
            points: [
              BlackboardDiagramPoint(50, 56, label: 'O'),
            ],
            color: ChalkColor.white,
            appearAtStepIndex: 0,
          ),
          BlackboardDiagramElement(
            id: 'fn_curve',
            type: 'curve',
            points: isParabola
                ? const [
                    BlackboardDiagramPoint(24, 22),
                    BlackboardDiagramPoint(34, 52),
                    BlackboardDiagramPoint(44, 72),
                    BlackboardDiagramPoint(52, 76),
                    BlackboardDiagramPoint(60, 72),
                    BlackboardDiagramPoint(70, 52),
                    BlackboardDiagramPoint(80, 22),
                  ]
                : const [
                    BlackboardDiagramPoint(24, 76),
                    BlackboardDiagramPoint(62, 34),
                    BlackboardDiagramPoint(80, 14),
                  ],
            label: isParabola ? 'y = f(x)' : 'y = kx + b',
            color: ChalkColor.blue,
            appearAtStepIndex: 0,
            highlightOnStepIds: ['step_1', 'step_2'],
          ),
          BlackboardDiagramElement(
            id: 'fn_key_pt',
            type: 'point',
            points: isParabola
                ? const [
                    BlackboardDiagramPoint(37, 56, label: 'x₁'),
                    BlackboardDiagramPoint(67, 56, label: 'x₂'),
                  ]
                : const [
                    BlackboardDiagramPoint(62, 34, label: 'P(x₀, y₀)'),
                  ],
            color: ChalkColor.yellow,
            appearAtStepIndex: 1,
            highlightOnStepIds: ['step_2', 'step_3'],
          ),
          const BlackboardDiagramElement(
            id: 'fn_proj',
            type: 'segment',
            points: [
              BlackboardDiagramPoint(62, 34),
              BlackboardDiagramPoint(62, 56),
            ],
            label: '坐标投影',
            color: ChalkColor.green,
            dashed: true,
            appearAtStepIndex: 2,
            highlightOnStepIds: ['step_3'],
          ),
        ],
      );
    }

    return const BlackboardDiagramSpec();
  }

  bool _isHumanitiesSubject(String subject) =>
      subject == 'chn' ||
      subject == 'hist' ||
      subject == 'geo' ||
      subject == 'pol';

  String _resolveEffectiveSubject(Question q) {
    final searchable = SubjectDetector.searchableTextOfQuestion(q);
    final resolved = SubjectDetector.resolveSubjectForText(
      searchable,
      preferredSubject: q.meta.subject,
      allowOverrideDefault: true,
    );
    final det = SubjectDetector.detect(searchable);
    final mathScore = det.scores['math'] ?? 0;

    if ((resolved == 'math' || resolved == 'other') && mathScore == 0) {
      if (det.subject != 'math' &&
          det.subject != 'other' &&
          (det.scores[det.subject] ?? 0) >= 3) {
        return det.subject;
      }
      if ((det.scores['phy'] ?? 0) == 0 && (det.scores['chem'] ?? 0) == 0) {
        final withoutLatex = searchable.replaceAll(RegExp(r'\\[a-zA-Z]+'), ' ');
        final engWords = RegExp(r'\b[A-Za-z]{2,}\b')
            .allMatches(withoutLatex)
            .length;
        final hasMathSymbols = RegExp(
          r'([∠△⊙⊥∥√±×÷≤≥≠≈]|x²|x\^2|\b\d+\s*[\+\-\*/=]\s*\d+)',
        ).hasMatch(searchable);
        if (engWords >= 3 && !hasMathSymbols) {
          return 'eng';
        }
      }
    }
    return resolved;
  }

  String _pitfallForSubject(String subject, String kps) => switch (subject) {
    'math' => '做「$kps」时，务必复查移项变号、根号/分母取值范围，以及题目问的是单解还是多解！',
    'phy' => '物理题注意国际单位制统一（cm→m, km/h→m/s），画受力图时千万别漏画摩擦力或支持力！',
    'chem' => '化学方程式记得检查配平系数、反应条件与气体/沉淀符号（↑/↓）！',
    'bio' => '生物题注意对照实验变量设定与专有名词准确书写，勿把因果关系写反！',
    'eng' => '英语做题注意回到原句核对时态语态、主谓单复数一致、介词固定搭配与大小写！',
    'chn' => '语文表达要紧扣原文关键词，答题按「要点+分析」分条陈述避免漏点！',
    'hist' => '历史解析注意时间背景、史实因果与材料限定角度，切忌脱离材料泛泛而谈！',
    'geo' => '地理读图题注意经纬度/等高线与气候成因的精准对应，因果链表述完整！',
    'pol' => '道德与法治答题要将材料信息与教材核心观点精准挂钩，分条亮明主旨！',
    _ => '完成「$kps」后记得回读核对设问要求与作答规范。',
  };

  String _formatGradingSummary(Question q) {
    final g = q.grading;
    final answerSets = g['answerSets'];
    if (answerSets is List && answerSets.isNotEmpty) {
      final first = answerSets.first;
      if (first is Map) {
        final expected = first['expected'];
        if (expected is Map) {
          if (expected['selectedIds'] is List) {
            final ids = (expected['selectedIds'] as List)
                .map((e) => e.toString())
                .toList();
            final optLookup = QuestionBlackboardFormatter.optionTextById(q);
            if (optLookup.isNotEmpty && ids.length == 1) {
              final optTxt = optLookup[ids.first];
              if (optTxt != null && optTxt.isNotEmpty) {
                return '正确选项 ${ids.first}（$optTxt）';
              }
            }
            return '正确选项 ${ids.join(', ')}';
          }
          if (expected['entries'] is List) {
            final bankLookup = QuestionBlackboardFormatter.bankTextById(q);
            final entries = (expected['entries'] as List)
                .whereType<Map<Object?, Object?>>()
                .map((e) {
                  final vals = e['acceptedValues'] as List?;
                  final firstVal = vals?.firstOrNull;
                  if (firstVal is Map && firstVal['itemIds'] is List) {
                    final itemIds = (firstVal['itemIds'] as List)
                        .map((id) => id.toString())
                        .toList();
                    final tokens = itemIds
                        .map((id) => bankLookup[id] ?? id)
                        .where((t) => t.trim().isNotEmpty)
                        .toList();
                    if (tokens.isNotEmpty) {
                      return QuestionBlackboardFormatter.joinOrderedTokens(
                        tokens,
                      );
                    }
                  }
                  final display = firstVal is Map
                      ? (firstVal['value'] ?? firstVal['text'] ?? '')
                      : (firstVal ?? '');
                  return q.isSequence ? '$display' : '${e['slotId']}: $display';
                })
                .where((s) => s.trim().isNotEmpty)
                .join('；');
            if (entries.isNotEmpty) return entries;
          }
          if (expected['pairs'] is List) {
            final leftMap = QuestionBlackboardFormatter.itemMapFromBody(
              q.body['left'],
            );
            final rightMap = QuestionBlackboardFormatter.itemMapFromBody(
              q.body['right'],
            );
            final pairs = (expected['pairs'] as List)
                .whereType<Map<Object?, Object?>>()
                .map((p) {
                  final l = leftMap['${p['fromId']}'] ?? '${p['fromId']}';
                  final r = rightMap['${p['toId']}'] ?? '${p['toId']}';
                  return '$l → $r';
                })
                .join('；');
            if (pairs.isNotEmpty) return pairs;
          }
          if (expected['assignments'] is List) {
            final itemMap = QuestionBlackboardFormatter.itemMapFromBody(
              q.body['items'],
            );
            final catMap = QuestionBlackboardFormatter.itemMapFromBody(
              q.body['categories'],
            );
            final list = (expected['assignments'] as List)
                .whereType<Map<Object?, Object?>>()
                .map((a) {
                  final it = itemMap['${a['itemId']}'] ?? '${a['itemId']}';
                  final cat =
                      catMap['${a['categoryId']}'] ?? '${a['categoryId']}';
                  return '$it → $cat';
                })
                .join('；');
            if (list.isNotEmpty) return list;
          }
        }
      }
    }
    final fin = g['finalAnswer'];
    if (fin is Map && fin['acceptedValues'] is List) {
      final first = (fin['acceptedValues'] as List).firstOrNull;
      if (first is Map) {
        return '${first['value'] ?? first['text'] ?? ''}';
      }
    } else if (fin != null) {
      return '$fin';
    }
    if (g['sampleAnswer'] != null) {
      return '${g['sampleAnswer']}';
    }
    return '请核对各步参考答案';
  }

  String _extractFirstSentence(String text) {
    final cleaned = text.trim();
    if (cleaned.isEmpty) return '';
    final idx = cleaned.indexOf(RegExp(r'[。；\n]'));
    if (idx > 4) return cleaned.substring(0, idx + 1);
    return _truncate(cleaned, 48);
  }

  String _compactArgs(String raw) {
    final s = raw.replaceAll('\n', ' ').trim();
    return s.length > 48 ? '${s.substring(0, 48)}…' : s;
  }

  String _truncate(String s, int max) =>
      s.length <= max ? s : '${s.substring(0, max)}…';
}

/// Parses unclosed/incomplete streaming LLM JSON into incremental
/// [BlackboardLessonRecord] snapshots so chalk lines appear live while the
/// model is still streaming.
abstract final class IncrementalBlackboardParser {
  static final RegExp _completeThink = RegExp(
    r'<think>[\s\S]*?</think>',
    caseSensitive: false,
  );
  static final RegExp _openThink = RegExp(
    r'<think>[\s\S]*$',
    caseSensitive: false,
  );
  static final RegExp _leadingFence = RegExp(
    r'^[\s\S]*?```(?:json)?\s*\r?\n?',
    caseSensitive: false,
  );

  /// Compact signature used to detect meaningful streaming progress across ticks.
  static String contentSignature(BlackboardLessonRecord record) {
    final track = record.activeTrack;
    if (track == null) return '0|0';
    final chars = track.steps.fold<int>(
      0,
      (sum, s) =>
          sum +
          s.title.length +
          s.spokenText.length +
          s.lines.fold<int>(
            0,
            (ls, l) => ls + l.text.length + (l.latex?.length ?? 0),
          ),
    );
    return '${track.steps.length}|$chars';
  }

  /// Attempts to extract a partial [BlackboardLessonRecord] from incomplete
  /// streamed JSON output. Returns `null` if no usable step content has arrived.
  static BlackboardLessonRecord? tryParsePartial(
    String rawStreamText, {
    required String lessonId,
    required String questionId,
    required String questionTitle,
    required int hintLevel,
  }) {
    var cleaned = rawStreamText.replaceAll(_completeThink, '');
    // Still inside an unclosed <think> block: wait until JSON begins
    if (_openThink.hasMatch(cleaned)) {
      cleaned = cleaned.replaceAll(_openThink, '');
    }
    cleaned = cleaned.trimLeft();
    if (cleaned.contains('```')) {
      cleaned = cleaned.replaceFirst(_leadingFence, '');
    }
    final objStart = cleaned.indexOf('{');
    if (objStart < 0) return null;
    cleaned = cleaned.substring(objStart);

    final closedJson = _closePartialJson(cleaned);
    if (closedJson == null) return null;

    Object? decoded;
    try {
      decoded = jsonDecode(closedJson);
    } catch (_) {
      return null;
    }
    if (decoded is! Map) return null;

    final rawTracks = decoded['tracks'];
    if (rawTracks is! List || rawTracks.isEmpty) return null;

    final parsedTracks = <BlackboardSolutionTrack>[];
    for (var ti = 0; ti < rawTracks.length; ti++) {
      final rawTrack = rawTracks[ti];
      if (rawTrack is! Map) continue;
      final trackMap = rawTrack.map((k, v) => MapEntry(k.toString(), v));
      final rawId = trackMap['id']?.toString().trim() ?? '';
      if (rawId.isEmpty) {
        trackMap['id'] = 'track_${ti + 1}';
      }
      final track = BlackboardSolutionTrack.fromJson(trackMap);
      final validSteps = track.steps
          .where(
            (s) =>
                s.title.trim().isNotEmpty ||
                s.spokenText.trim().isNotEmpty ||
                s.lines.any(
                  (l) =>
                      l.text.trim().isNotEmpty ||
                      (l.latex?.trim().isNotEmpty ?? false),
                ),
          )
          .toList(growable: false);
      if (validSteps.isEmpty) continue;
      parsedTracks.add(
        track.copyWith(
          label: track.label.trim().isEmpty ? '正在板书' : track.label,
          steps: validSteps,
          revealedCount: 1,
        ),
      );
    }

    if (parsedTracks.isEmpty) return null;

    return BlackboardLessonRecord(
      id: lessonId,
      questionId: questionId,
      questionTitle: questionTitle,
      hintLevel: hintLevel,
      tracks: parsedTracks,
      activeTrackIndex: 0,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// Auto-closes an arbitrary truncated JSON prefix so `jsonDecode` can parse
  /// partially streamed keys, arrays, objects, and string values cleanly.
  static String? _closePartialJson(String prefix) {
    final stack = <String>[];
    var inString = false;
    var escaped = false;
    var lastStringStart = -1;

    for (var i = 0; i < prefix.length; i++) {
      final ch = prefix[i];
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (ch == r'\') {
          escaped = true;
        } else if (ch == '"') {
          inString = false;
        }
        continue;
      }
      if (ch == '"') {
        inString = true;
        lastStringStart = i;
      } else if (ch == '{') {
        stack.add('}');
      } else if (ch == '[') {
        stack.add(']');
      } else if ((ch == '}' || ch == ']') && stack.isNotEmpty) {
        stack.removeLast();
      }
    }

    var work = prefix;
    if (inString && lastStringStart >= 0) {
      // Determine whether this unclosed string is a value or an object key
      var j = lastStringStart - 1;
      while (j >= 0 && _isWs(work.codeUnitAt(j))) {
        j--;
      }
      final prevChar = j >= 0 ? work[j] : '';
      final isValueString =
          prevChar == ':' ||
          prevChar == '[' ||
          (prevChar == ',' && stack.isNotEmpty && stack.last == ']');
      if (isValueString) {
        // Trim dangling incomplete escape sequence (`\` or `\u12`) before closing
        work = work.replaceFirst(RegExp(r'(?:\\u[0-9a-fA-F]{0,3}|\\)$'), '');
        work = '$work"';
      } else {
        // Incomplete key inside an object -> drop the partial key cleanly
        work = work.substring(0, lastStringStart);
      }
    }

    work = _trimIncompleteTailOutsideString(work);
    if (work.isEmpty || stack.isEmpty && !work.startsWith('{')) {
      return null;
    }

    // Re-evaluate closing braces cleanly against trimmed work
    final closeStack = <String>[];
    var sInStr = false;
    var sEsc = false;
    for (var i = 0; i < work.length; i++) {
      final ch = work[i];
      if (sInStr) {
        if (sEsc) {
          sEsc = false;
        } else if (ch == r'\') {
          sEsc = true;
        } else if (ch == '"') {
          sInStr = false;
        }
        continue;
      }
      if (ch == '"') {
        sInStr = true;
      } else if (ch == '{') {
        closeStack.add('}');
      } else if (ch == '[') {
        closeStack.add(']');
      } else if ((ch == '}' || ch == ']') && closeStack.isNotEmpty) {
        closeStack.removeLast();
      }
    }
    if (sInStr) return null;

    final out = StringBuffer(work);
    for (var i = closeStack.length - 1; i >= 0; i--) {
      out.write(closeStack[i]);
    }
    return out.toString();
  }

  static String _trimIncompleteTailOutsideString(String input) {
    var work = input.trimRight();
    // Strip partial boolean / null / numeric tail outside strings
    final bareMatch = RegExp(r'([A-Za-z_]+|-|\d+\.)$').firstMatch(work);
    if (bareMatch != null) {
      final tok = bareMatch.group(1)!;
      if (tok != 'true' && tok != 'false' && tok != 'null') {
        work = work.substring(0, bareMatch.start).trimRight();
      }
    }

    while (work.isNotEmpty) {
      work = work.trimRight();
      if (work.endsWith(',')) {
        work = work.substring(0, work.length - 1).trimRight();
        continue;
      }
      if (work.endsWith(':')) {
        // Drop incomplete `"key":` entry
        final keyDrop = work.replaceFirst(RegExp(r'"(?:[^"\\]|\\.)*"\s*:$'), '');
        if (keyDrop != work) {
          work = keyDrop.trimRight();
          continue;
        }
      }
      break;
    }
    return work;
  }

  static bool _isWs(int c) => c == 32 || c == 10 || c == 13 || c == 9;
}

/// Incremental line-protocol parser for `P-17` single-step BBSTREAM output.
///
/// Extracts streamed fields token-by-token without requiring closing JSON
/// braces, falling back gracefully to single-step JSON extraction or plain
/// bulleted prose if an upstream model ignores the `[[TAG]]` syntax.
abstract final class BlackboardStepStreamParser {
  static final RegExp _completeThink = RegExp(
    r'<think>[\s\S]*?</think>',
    caseSensitive: false,
  );
  static final RegExp _openThink = RegExp(
    r'<think>[\s\S]*$',
    caseSensitive: false,
  );
  static final RegExp _leadingFence = RegExp(
    r'^\s*```(?:json|text|markdown)?\s*\r?\n?',
    caseSensitive: false,
  );
  static final RegExp _trailingFence = RegExp(r'\r?\n?```\s*$');
  static final RegExp _lineTag = RegExp(
    r'^\[\[LINE:([a-zA-Z]+):([a-zA-Z]+)\]\]\s*(.*)$',
  );
  static final RegExp _simpleTag = RegExp(
    r'^\[\[([A-Z_]+)\]\]\s*(.*)$',
  );

  static ParsedBlackboardStep? parse(
    String rawText, {
    required int stepNumber,
    required int maxStepsForLevel,
    bool isMathOrPhysics = true,
    bool isFinal = false,
  }) {
    var cleaned = rawText.replaceAll(_completeThink, '');
    if (_openThink.hasMatch(cleaned)) {
      cleaned = cleaned.replaceAll(_openThink, '');
    }
    cleaned = cleaned.trimLeft();
    if (cleaned.startsWith('```')) {
      cleaned = cleaned.replaceFirst(_leadingFence, '');
    }
    if (isFinal) {
      cleaned = cleaned.replaceFirst(_trailingFence, '');
    }

    final trimmedLeft = cleaned.trimLeft();
    if (trimmedLeft.isEmpty) return null;

    // Fallback: model replied with JSON tracks structure instead of BBSTREAM
    if (trimmedLeft.startsWith('{')) {
      final partial = IncrementalBlackboardParser.tryParsePartial(
        trimmedLeft,
        lessonId: 'tmp',
        questionId: 'tmp',
        questionTitle: '',
        hintLevel: 1,
      );
      final track = partial?.activeTrack;
      if (track == null || track.steps.isEmpty) return null;
      final idx = (stepNumber - 1) < track.steps.length ? (stepNumber - 1) : 0;
      final matched = track.steps[idx];
      final step = BlackboardStep(
        id: 'step_$stepNumber',
        stepNumber: stepNumber,
        title: matched.title,
        spokenText: matched.spokenText,
        emotion: matched.emotion,
        lines: matched.lines,
        checkpoint: matched.checkpoint,
      );
      final hasMore =
          stepNumber < maxStepsForLevel &&
          (track.steps.length > stepNumber || !isFinal);
      return ParsedBlackboardStep(
        step: step,
        hasMoreSteps: hasMore,
        plannedTotalSteps: track.steps.length > 1
            ? track.steps.length.clamp(stepNumber, maxStepsForLevel)
            : maxStepsForLevel,
        diagram: (isMathOrPhysics && stepNumber == 1 && track.diagram.isNotEmpty)
            ? track.diagram
            : null,
        takeaway: hasMore ? '' : track.takeaway,
      );
    }

    final endsWithNewline =
        cleaned.endsWith('\n') || cleaned.endsWith('\r');
    final rawLines = cleaned.split(RegExp(r'\r?\n'));

    var title = '';
    var spokenText = '';
    var emotion = 'happy';
    int? plannedTotal;
    bool? explicitMore;
    var takeaway = '';
    BlackboardCheckpoint? checkpoint;
    BlackboardDiagramSpec? diagram;
    final addedDiagram = <BlackboardDiagramElement>[];
    final lines = <BlackboardLineItem>[];
    var hasAnyTag = false;
    String? activeSection; // 'SPOKEN' | 'LINE' | 'TAKEAWAY' | 'TITLE'

    for (var i = 0; i < rawLines.length; i++) {
      final isLastLine = i == rawLines.length - 1;
      final isIncompleteLast = isLastLine && !endsWithNewline && !isFinal;
      final rawLine = rawLines[i];
      final trimmed = rawLine.trim();
      if (trimmed.isEmpty) continue;

      // Avoid flashing half-typed opening `[[TAG` markup while streaming
      if (isIncompleteLast &&
          trimmed.startsWith('[[') &&
          !trimmed.contains(']]')) {
        continue;
      }

      final lineMatch = _lineTag.firstMatch(trimmed);
      if (lineMatch != null) {
        hasAnyTag = true;
        final color = ChalkColor.fromCode(lineMatch.group(1));
        final ann = ChalkAnnotationKind.fromCode(lineMatch.group(2));
        final text = lineMatch.group(3)?.trimLeft() ?? '';
        lines.add(
          BlackboardLineItem(
            id: 'l_${stepNumber}_${lines.length + 1}',
            tag: '',
            text: text,
            color: color,
            annotation: ann,
          ),
        );
        activeSection = 'LINE';
        continue;
      }

      final tagMatch = _simpleTag.firstMatch(trimmed);
      if (tagMatch != null) {
        hasAnyTag = true;
        final tag = tagMatch.group(1)!.toUpperCase();
        final val = tagMatch.group(2)?.trim() ?? '';
        activeSection = null;

        switch (tag) {
          case 'TOTAL':
            final parsedNum = int.tryParse(
              RegExp(r'\d+').firstMatch(val)?.group(0) ?? '',
            );
            if (parsedNum != null) {
              plannedTotal = parsedNum.clamp(
                math.max(stepNumber, 2),
                maxStepsForLevel,
              );
            }
          case 'TITLE':
            title = val;
            activeSection = 'TITLE';
          case 'EMO':
            if (val.isNotEmpty) {
              emotion = MascotEmotion.fromCode(
                val.split(RegExp(r'[\s|,]+')).first,
              ).code;
            }
          case 'SPOKEN':
            spokenText = val;
            activeSection = 'SPOKEN';
          case 'FORMULA':
            if (val.isNotEmpty && isMathOrPhysics && lines.isNotEmpty) {
              final last = lines.last;
              lines[lines.length - 1] = last.copyWith(latex: val);
            }
          case 'CHECKPOINT':
            if (!isIncompleteLast && val.isNotEmpty) {
              final parsedCp = _parseCheckpoint(val);
              if (parsedCp != null) checkpoint = parsedCp;
            }
          case 'TRY_PROMPT':
            if (!isIncompleteLast && val.isNotEmpty) {
              final parts = val
                  .split('|')
                  .map((e) => e.trim())
                  .where((e) => e.isNotEmpty)
                  .toList(growable: false);
              if (parts.isNotEmpty) {
                checkpoint = BlackboardCheckpoint(
                  prompt: parts.first,
                  options: const [],
                  correctIndex: 0,
                  expectedHint: parts.length > 1 ? parts[1] : null,
                );
              }
            }
          case 'DIAGRAM':
            if (isMathOrPhysics && stepNumber == 1 && val.isNotEmpty) {
              try {
                final dec = jsonDecode(AiTextPostProcessor.extractJsonText(val));
                if (dec is Map) {
                  final spec = BlackboardDiagramSpec.fromJson(
                    dec.map((k, v) => MapEntry(k.toString(), v)),
                  );
                  if (spec.kind != BlackboardDiagramKind.none &&
                      spec.elements.isNotEmpty) {
                    diagram = spec;
                  }
                }
              } catch (_) {}
            }
          case 'DIAGRAM_ADD':
            if (isMathOrPhysics && val.isNotEmpty) {
              try {
                final dec = jsonDecode(AiTextPostProcessor.extractJsonText(val));
                if (dec is List) {
                  for (final item in dec.whereType<Map<Object?, Object?>>()) {
                    addedDiagram.add(
                      BlackboardDiagramElement.fromJson(
                        item.map((k, v) => MapEntry(k.toString(), v)),
                      ),
                    );
                  }
                }
              } catch (_) {}
            }
          case 'MORE':
            final lower = val.toLowerCase();
            if (lower.startsWith('false') || lower == '0' || lower == '否') {
              explicitMore = false;
            } else if (lower.startsWith('true') || lower == '1') {
              explicitMore = true;
            }
          case 'TAKEAWAY':
            takeaway = val;
            activeSection = 'TAKEAWAY';
        }
        continue;
      }

      // Handle continuation lines or untagged fallback prose
      if (hasAnyTag) {
        if (activeSection == 'SPOKEN') {
          spokenText = spokenText.isEmpty ? trimmed : '$spokenText $trimmed';
        } else if (activeSection == 'LINE' && lines.isNotEmpty) {
          final last = lines.last;
          lines[lines.length - 1] = last.copyWith(
            text: last.text.isEmpty ? trimmed : '${last.text}\n$trimmed',
          );
        } else if (activeSection == 'TAKEAWAY') {
          takeaway = takeaway.isEmpty ? trimmed : '$takeaway $trimmed';
        }
      }
    }

    // Plain-text fallback when model omitted [[TAG]] wrappers completely
    if (!hasAnyTag) {
      if (!isFinal && trimmedLeft.length < 24) return null;
      final plainLines = cleaned
          .split(RegExp(r'\r?\n'))
          .map((l) => l.trim().replaceFirst(RegExp(r'^[-*•]\s*'), ''))
          .where((l) => l.isNotEmpty && l != '```')
          .toList(growable: false);
      if (plainLines.isEmpty) return null;
      if (plainLines.length >= 2 &&
          plainLines.first.length <= 22 &&
          !plainLines.first.contains('。')) {
        title = plainLines.first.replaceFirst(RegExp(r'^\d+[.、]\s*'), '');
        for (final bodyLine in plainLines.skip(1).take(5)) {
          lines.add(
            BlackboardLineItem(
              id: 'l_${stepNumber}_${lines.length + 1}',
              tag: '',
              text: bodyLine,
              color: ChalkColor.white,
            ),
          );
        }
      } else {
        title = '第 $stepNumber 步讲解';
        for (final bodyLine in plainLines.take(5)) {
          lines.add(
            BlackboardLineItem(
              id: 'l_${stepNumber}_${lines.length + 1}',
              tag: '',
              text: bodyLine,
              color: ChalkColor.white,
            ),
          );
        }
      }
      if (spokenText.isEmpty && lines.isNotEmpty) {
        spokenText = lines.first.text;
      }
    }

    final hasContent =
        title.isNotEmpty ||
        spokenText.isNotEmpty ||
        lines.any((l) => l.text.trim().isNotEmpty || (l.latex?.isNotEmpty ?? false));
    if (!hasContent) return null;

    if (checkpoint != null &&
        _isSelfSpoiledCheckpoint(checkpoint, lines, spokenText)) {
      checkpoint = null;
    }

    final clampedHasMore = stepNumber < maxStepsForLevel
        ? (explicitMore ??
              (plannedTotal != null ? stepNumber < plannedTotal : true))
        : false;
    final resolvedTotal = explicitMore == false
        ? stepNumber
        : (plannedTotal ??
              (clampedHasMore ? maxStepsForLevel : stepNumber));

    return ParsedBlackboardStep(
      step: BlackboardStep(
        id: 'step_$stepNumber',
        stepNumber: stepNumber,
        title: title.isEmpty ? '第 $stepNumber 步分析' : title,
        spokenText: spokenText.isNotEmpty
            ? spokenText
            : '我们来看第 $stepNumber 步的核心分析～',
        emotion: emotion,
        lines: lines
            .where(
              (l) =>
                  l.text.trim().isNotEmpty ||
                  (l.latex?.trim().isNotEmpty ?? false),
            )
            .toList(growable: false),
        checkpoint: checkpoint,
      ),
      hasMoreSteps: clampedHasMore,
      plannedTotalSteps: resolvedTotal,
      diagram: diagram,
      addedDiagramElements: addedDiagram,
      takeaway: clampedHasMore ? '' : takeaway,
    );
  }

  static BlackboardCheckpoint? _parseCheckpoint(String raw) {
    final parts = raw.split('|').map((e) => e.trim()).toList(growable: false);
    if (parts.length < 4) return null;
    final prompt = parts.first;
    if (prompt.isEmpty) return null;

    var idxPos = -1;
    var correctIdx = 0;
    for (var i = parts.length - 1; i >= 1; i--) {
      final candidate = int.tryParse(parts[i]);
      if (candidate != null) {
        idxPos = i;
        correctIdx = candidate;
        break;
      }
    }

    final List<String> options;
    var encouragement = '思路太棒了，这一步轻松拿下！';
    if (idxPos >= 2) {
      options = parts
          .sublist(1, idxPos)
          .where((s) => s.isNotEmpty)
          .toList(growable: false);
      if (idxPos + 1 < parts.length && parts[idxPos + 1].isNotEmpty) {
        encouragement = parts[idxPos + 1];
      }
    } else {
      options = parts
          .sublist(1)
          .where((s) => s.isNotEmpty)
          .take(3)
          .toList(growable: false);
    }
    if (options.length < 2) return null;
    return BlackboardCheckpoint(
      prompt: prompt,
      options: options,
      correctIndex: correctIdx.clamp(0, options.length - 1),
      encouragement: encouragement,
    );
  }

  /// Drops an interactive checkpoint/try-prompt when the same step's chalk lines
  /// or spoken text already explicitly revealed its target answer.
  static bool _isSelfSpoiledCheckpoint(
    BlackboardCheckpoint cp,
    List<BlackboardLineItem> lines,
    String spokenText,
  ) {
    final linesText = lines
        .map((l) => '${l.text} ${l.latex ?? ""}')
        .join('\n')
        .trim();
    final combinedBody = '$linesText\n$spokenText';
    final combinedLower = combinedBody.toLowerCase();
    final promptLower = cp.prompt.toLowerCase();

    if (cp.isOpenEnded) {
      final rawHint = (cp.expectedHint ?? '').trim();
      if (rawHint.isEmpty) return false;
      final candidates = rawHint
          .split(RegExp(r'[/|、,，;；]|或'))
          .map((e) => e.trim())
          .where(
            (e) =>
                e.length >= 2 &&
                e.length <= 24 &&
                !promptLower.contains(e.toLowerCase()),
          )
          .toList(growable: false);
      if (candidates.isEmpty) return false;
      for (final candidate in candidates) {
        if (_containsAnswerVerbatim(combinedBody, combinedLower, candidate)) {
          return true;
        }
      }
      return false;
    }

    if (cp.correctIndex < 0 || cp.correctIndex >= cp.options.length) {
      return false;
    }
    final correctOpt = cp.options[cp.correctIndex].trim();
    if (correctOpt.length < 4 || promptLower.contains(correctOpt.toLowerCase())) {
      return false;
    }
    return linesText.toLowerCase().contains(correctOpt.toLowerCase());
  }

  static bool _containsAnswerVerbatim(
    String rawBody,
    String lowerBody,
    String candidate,
  ) {
    final isAsciiWordLike = RegExp(
      r'^[A-Za-z0-9\s._\-+*/=]+$',
    ).hasMatch(candidate);
    if (isAsciiWordLike) {
      final escaped = RegExp.escape(candidate.trim());
      return RegExp(
        '(?<![A-Za-z0-9])$escaped(?![A-Za-z0-9])',
        caseSensitive: false,
      ).hasMatch(rawBody);
    }
    return lowerBody.contains(candidate.toLowerCase());
  }
}

/// Shared question body/prompt extractor for the AI blackboard tutor and UI
/// overlays so choice options, sequence word banks, and match/classify pairs
/// are never omitted.
abstract final class QuestionBlackboardFormatter {
  static List<ContentBlock> cleanedPromptBlocks(Question q) {
    if (!q.isSequence) return q.prompt;
    return q.prompt
        .where((b) => b is! SlotBlock)
        .toList(growable: false);
  }

  static String cleanStemText(Question q) {
    final blocks = cleanedPromptBlocks(q);
    final raw = ContentTextUtils.extractPlainText(blocks).trim();
    if (!q.isSequence) return raw.isEmpty ? q.plainText : raw;
    return raw.replaceAll(RegExp(r'\s*_{2,}\s*$'), '').trim();
  }

  static String _extractEntryText(Map<Object?, Object?> raw) {
    for (final blockKey in const ['content', 'prompt']) {
      final blockList = raw[blockKey];
      if (blockList is List) {
        final blocks = blockList
            .whereType<Map<Object?, Object?>>()
            .map(
              (m) => ContentBlock.fromJson(
                m.map((k, v) => MapEntry(k.toString(), v)),
              ),
            )
            .toList(growable: false);
        final txt = ContentTextUtils.extractPlainText(blocks).trim();
        if (txt.isNotEmpty) return txt;
      }
    }
    final plain =
        raw['prompt'] ??
        raw['title'] ??
        raw['text'] ??
        raw['label'] ??
        raw['value'] ??
        raw['pinyin'];
    return plain == null || plain is List ? '' : '$plain'.trim();
  }

  static Map<String, String> itemMapFromBody(Object? rawList) {
    if (rawList is! List) return const {};
    final map = <String, String>{};
    for (final entry in rawList) {
      if (entry is! Map) continue;
      final id = entry['id']?.toString() ?? '';
      final txt = _extractEntryText(entry);
      if (id.isNotEmpty && txt.isNotEmpty) {
        map[id] = txt;
      }
    }
    return map;
  }

  static List<({String id, String text})> extractOptionItems(Question q) {
    final rawOpts = q.body['options'];
    if (rawOpts is! List) return const [];
    final out = <({String id, String text})>[];
    for (var i = 0; i < rawOpts.length; i++) {
      final item = rawOpts[i];
      if (item is String && item.trim().isNotEmpty) {
        out.add((id: String.fromCharCode(65 + i), text: item.trim()));
        continue;
      }
      if (item is! Map) continue;
      final id = (item['id']?.toString().trim().isNotEmpty ?? false)
          ? item['id'].toString().trim()
          : String.fromCharCode(65 + i);
      final text = _extractEntryText(item);
      if (text.isNotEmpty) {
        out.add((id: id, text: text));
      }
    }
    return out;
  }

  static Map<String, String> optionTextById(Question q) {
    return {for (final opt in extractOptionItems(q)) opt.id: opt.text};
  }

  static List<({String id, String text})> extractWordBankItems(Question q) {
    final rawBank = q.body['bank'];
    if (rawBank is! List) return const [];
    final out = <({String id, String text})>[];
    for (var i = 0; i < rawBank.length; i++) {
      final item = rawBank[i];
      if (item is String && item.trim().isNotEmpty) {
        out.add((id: 'w_$i', text: item.trim()));
        continue;
      }
      if (item is! Map) continue;
      final id = item['id']?.toString() ?? 'w_$i';
      final text = _extractEntryText(item);
      if (text.isNotEmpty) {
        out.add((id: id, text: text));
      }
    }
    return out;
  }

  static Map<String, String> bankTextById(Question q) {
    return {for (final b in extractWordBankItems(q)) b.id: b.text};
  }

  static List<String> extractWordBank(Question q) {
    return extractWordBankItems(q).map((e) => e.text).toList(growable: false);
  }

  static List<String> extractMatchSummary(Question q) {
    final left = q.body['left'];
    final right = q.body['right'];
    final out = <String>[];
    if (left is List && left.isNotEmpty) {
      final items = left
          .whereType<Map<Object?, Object?>>()
          .map(_extractEntryText)
          .where((s) => s.isNotEmpty)
          .join('、');
      if (items.isNotEmpty) out.add('左栏：$items');
    }
    if (right is List && right.isNotEmpty) {
      final items = right
          .whereType<Map<Object?, Object?>>()
          .map(_extractEntryText)
          .where((s) => s.isNotEmpty)
          .join('、');
      if (items.isNotEmpty) out.add('右栏：$items');
    }
    return out;
  }

  static List<String> extractClassifySummary(Question q) {
    final cats = q.body['categories'];
    final items = q.body['items'];
    final out = <String>[];
    if (cats is List && cats.isNotEmpty) {
      final list = cats
          .whereType<Map<Object?, Object?>>()
          .map(_extractEntryText)
          .where((s) => s.isNotEmpty)
          .join('、');
      if (list.isNotEmpty) out.add('分类：$list');
    }
    if (items is List && items.isNotEmpty) {
      final list = items
          .whereType<Map<Object?, Object?>>()
          .map(_extractEntryText)
          .where((s) => s.isNotEmpty)
          .join('、');
      if (list.isNotEmpty) out.add('待分项：$list');
    }
    return out;
  }

  static List<String> _extractListBodySummary(
    Question q,
    String key, {
    required String itemPrefix,
    bool inlineList = false,
  }) {
    final rawList = q.body[key];
    if (rawList is! List || rawList.isEmpty) return const [];
    final entries = <String>[];
    for (final entry in rawList) {
      if (entry is String && entry.trim().isNotEmpty) {
        entries.add(entry.trim());
      } else if (entry is Map) {
        final txt = _extractEntryText(entry);
        if (txt.isNotEmpty) entries.add(txt);
      }
    }
    if (entries.isEmpty) return const [];
    if (inlineList) {
      return ['$itemPrefix：${entries.join('、')}'];
    }
    return [
      for (var i = 0; i < entries.length; i++)
        '$itemPrefix${entries.length > 1 ? " ${i + 1}" : ""}：${entries[i]}',
    ];
  }

  static String? compactBodySummary(Question q) {
    final bank = extractWordBank(q);
    if (bank.isNotEmpty) {
      return '待排词块：${bank.join(' / ')}';
    }
    final opts = extractOptionItems(q);
    if (opts.isNotEmpty) {
      final joined = opts.map((o) => '${o.id}. ${o.text}').join('  ');
      return '选项：$joined';
    }
    final match = extractMatchSummary(q);
    if (match.isNotEmpty) return match.join('｜');
    final classify = extractClassifySummary(q);
    if (classify.isNotEmpty) return classify.join('｜');
    final parts = _extractListBodySummary(q, 'parts', itemPrefix: '分问');
    if (parts.isNotEmpty) return parts.join('｜');
    final targets = _extractListBodySummary(
      q,
      'targets',
      itemPrefix: '标注项',
      inlineList: true,
    );
    if (targets.isNotEmpty) return targets.first;
    final cells = _extractListBodySummary(
      q,
      'cells',
      itemPrefix: '书写项',
      inlineList: true,
    );
    if (cells.isNotEmpty) return cells.first;
    final sub = q.body['questions'];
    if (sub is List && sub.isNotEmpty) {
      return '含 ${sub.length} 道小题';
    }
    return null;
  }

  /// Short count indicator shown on compact collapsed stem strips.
  static String? countTagLabel(Question q) {
    final bank = extractWordBank(q);
    if (bank.isNotEmpty) return '${bank.length}个词块';
    final opts = extractOptionItems(q);
    if (opts.isNotEmpty) return '${opts.length}个选项';
    final sub = q.body['questions'];
    if (sub is List && sub.isNotEmpty) return '${sub.length}道小题';
    return null;
  }

  static String formatFullPromptForTutor(Question q, {int depth = 0}) {
    final buf = StringBuffer(cleanStemText(q));
    final desc = ContentTextUtils.extractPlainText(
      q.header.description,
    ).trim();
    if (desc.isNotEmpty && !buf.toString().contains(desc)) {
      buf
        ..writeln()
        ..writeln('题目说明：$desc');
    }
    final opts = extractOptionItems(q);
    if (opts.isNotEmpty) {
      buf.writeln();
      for (final opt in opts) {
        buf.writeln('${opt.id}. ${opt.text}');
      }
    }
    final bank = extractWordBank(q);
    if (bank.isNotEmpty) {
      buf
        ..writeln()
        ..writeln('待排列词块：${bank.join(' / ')}');
    }
    final match = extractMatchSummary(q);
    if (match.isNotEmpty) {
      buf
        ..writeln()
        ..writeln(match.join('\n'));
    }
    final classify = extractClassifySummary(q);
    if (classify.isNotEmpty) {
      buf
        ..writeln()
        ..writeln(classify.join('\n'));
    }
    final parts = _extractListBodySummary(q, 'parts', itemPrefix: '作答分问');
    if (parts.isNotEmpty) {
      buf
        ..writeln()
        ..writeln(parts.join('\n'));
    }
    final solveSteps = _extractListBodySummary(q, 'steps', itemPrefix: '步骤提示');
    if (solveSteps.isNotEmpty) {
      buf
        ..writeln()
        ..writeln(solveSteps.join('\n'));
    }
    final targets = _extractListBodySummary(
      q,
      'targets',
      itemPrefix: '待标注项',
      inlineList: true,
    );
    if (targets.isNotEmpty) {
      buf
        ..writeln()
        ..writeln(targets.first);
    }
    final cells = _extractListBodySummary(
      q,
      'cells',
      itemPrefix: '待书写内容',
      inlineList: true,
    );
    if (cells.isNotEmpty) {
      buf
        ..writeln()
        ..writeln(cells.first);
    }
    if (depth < 2 && q.body['questions'] is List) {
      final rawSubs = q.body['questions']! as List;
      for (var i = 0; i < rawSubs.length; i++) {
        final rawChild = rawSubs[i];
        if (rawChild is! Map) continue;
        try {
          final child = Question.fromJson(
            rawChild.map((k, v) => MapEntry(k.toString(), v)),
            fallbackId: '${q.id}_sub_$i',
          );
          final childPrompt = formatFullPromptForTutor(
            child,
            depth: depth + 1,
          );
          if (childPrompt.isNotEmpty) {
            buf
              ..writeln()
              ..writeln('【小题 ${i + 1}（${child.displayKindLabel}）】')
              ..writeln(childPrompt);
          }
        } catch (_) {}
      }
    }
    return buf.toString().trim();
  }

  static String joinOrderedTokens(List<String> tokens) {
    final buf = StringBuffer();
    for (final raw in tokens) {
      final tok = raw.trim();
      if (tok.isEmpty) continue;
      if (buf.isEmpty) {
        buf.write(tok);
        continue;
      }
      final isPunct = RegExp(r'^[.,!?;:。，！？；：]+$').hasMatch(tok);
      final isAsciiStart = RegExp(r'^[A-Za-z0-9]').hasMatch(tok);
      if (isPunct) {
        buf.write(tok);
      } else if (isAsciiStart || RegExp(r'[A-Za-z0-9]$').hasMatch(buf.toString())) {
        buf.write(' $tok');
      } else {
        buf.write(tok);
      }
    }
    return buf.toString();
  }
}
