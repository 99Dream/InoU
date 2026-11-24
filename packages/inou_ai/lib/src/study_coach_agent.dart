import 'dart:async';
import 'dart:convert';

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:inou_domain/inou_domain.dart';
import 'package:meta/meta.dart';
import 'package:uuid/uuid.dart';

import 'ai_endpoint_config.dart';
import 'inou_llm_client.dart';
import 'llm_gateway.dart';
import 'prompt_library.dart';
import 'tutor_agent_service.dart';

/// Intercepts `submit_question_draft` calls before execution to enforce
/// `QuestionStructureValidator` + `QuestionSemanticValidator` + SimHash dedup.
class ValidationAndDedupHook extends AgentHook {
  ValidationAndDedupHook({
    required this.existingPlainStems,
    this.defaultSubject = 'math',
    this.defaultGrade = 'g9',
    this.maxAccepted = 8,
  });

  final List<String> existingPlainStems;
  final String defaultSubject;
  final String defaultGrade;
  final int maxAccepted;
  final List<Question> acceptedQuestions = <Question>[];
  int rejectedCount = 0;

  Question parseDraftQuestion(Map<String, Object?> qMap) {
    var q = Question.coerceFromAiMap(
      qMap,
      defaultSubject: defaultSubject,
      defaultGrade: defaultGrade,
      defaultAnswerSource: AnswerSource.aiVerified,
    );
    q = SequenceQuestionDetector.tryRescueAsSequence(q) ?? q;
    return q;
  }

  @override
  ToolCallHookResult beforeToolCall(ToolCallHookContext context) {
    if (context.call.name != 'submit_question_draft') {
      return ToolCallHookResult.proceed(context.call);
    }
    if (acceptedQuestions.length >= maxAccepted) {
      return ToolCallHookResult.deny(
        content: [TextPart('[QUOTA_REACHED] 已达到本次出题数量上限（$maxAccepted 题）。')],
      );
    }

    try {
      final decoded = jsonDecode(context.call.arguments);
      final map = decoded is Map<String, Object?>
          ? decoded
          : (decoded is Map
                ? decoded.map((k, v) => MapEntry(k.toString(), v))
                : <String, Object?>{});
      final rawQuestion = map['question'];
      final qMap = rawQuestion is Map<String, Object?>
          ? rawQuestion
          : (rawQuestion is Map
                ? rawQuestion.map((k, v) => MapEntry(k.toString(), v))
                : map);

      final q = parseDraftQuestion(qMap);
      final issues = validateQuestionEnvelope(q);
      if (issues.isNotEmpty) {
        rejectedCount++;
        final summary = issues
            .take(5)
            .map((e) => '${e.path}: ${e.message}')
            .join('; ');
        return ToolCallHookResult.deny(
          content: [TextPart('[VALIDATION_REJECTED] 题目 JSON 校验未通过：$summary')],
        );
      }

      final candidateStem = q.plainText;
      final pool = [
        ...existingPlainStems,
        ...acceptedQuestions.map((e) => e.plainText),
      ];
      for (final existing in pool) {
        if (ContentTextUtils.isLikelyDuplicate(candidateStem, existing)) {
          rejectedCount++;
          return ToolCallHookResult.deny(
            content: [
              TextPart('[DUPLICATE_REJECTED] 新题与已有题目高度相似，请更换情境或数值后重试。'),
            ],
          );
        }
      }
      return ToolCallHookResult.proceed(context.call);
    } catch (e) {
      rejectedCount++;
      return ToolCallHookResult.deny(
        content: [TextPart('[VALIDATION_REJECTED] 参数不是合法题目 JSON：$e')],
      );
    }
  }
}

/// Output of [StudyCoachAgentService.generateReport].
@immutable
class StudyCoachReportResult {
  const StudyCoachReportResult({
    required this.report,
    required this.usedOfflineFallback,
    required this.traceSteps,
    this.errorMessage,
  });

  final ReportRecord report;
  final bool usedOfflineFallback;
  final List<TutorToolTraceStep> traceSteps;
  final String? errorMessage;
}

/// Output of [StudyCoachAgentService.generateDrill].
@immutable
class DrillGenerationResult {
  const DrillGenerationResult({
    required this.questions,
    required this.usedOfflineFallback,
    required this.traceSteps,
    this.rejectedDraftCount = 0,
    this.errorMessage,
  });

  final List<Question> questions;
  final bool usedOfflineFallback;
  final List<TutorToolTraceStep> traceSteps;
  final int rejectedDraftCount;
  final String? errorMessage;
}

/// Orchestrates weakness diagnostic reports (`P-08`) and verified drill
/// generation (`P-09a`/`P-09b`) using `StatefulAgent` + `independent_solver`
/// [SubAgent] + [ValidationAndDedupHook].
class StudyCoachAgentService {
  const StudyCoachAgentService({
    this.clientFactory = const InouLlmClientFactory(),
  });

  final InouLlmClientFactory clientFactory;
  static const Uuid _uuid = Uuid();

  Future<StudyCoachReportResult> generateReport({
    required StudentProfile profile,
    required WeaknessSnapshot snapshot,
    required List<WrongItem> wrongItems,
    required List<Question> questions,
    String rangeDesc = '近 30 天',
    AiEndpointConfig? endpoint,
    String? apiKey,
    LLMClient? overrideClient,
  }) async {
    final canRunRemote =
        overrideClient != null ||
        (endpoint != null && (apiKey ?? '').trim().isNotEmpty);
    if (!canRunRemote) {
      return _offlineGenerateReport(
        profile: profile,
        snapshot: snapshot,
        wrongItems: wrongItems,
        rangeDesc: rangeDesc,
      );
    }

    final client =
        overrideClient ??
        clientFactory.createClient(endpoint!, apiKey: apiKey!.trim());
    final modelCandidates = endpoint != null
        ? endpoint.resolveModelCandidates(AiTier.strong)
        : const ['mock-model'];

    final questionById = {for (final q in questions) q.id: q};
    final rendered = PromptLibrary.get('P-08').render({
      'profileSummary':
          '${profile.name} · ${profile.stage.label} · ${profile.grade}',
      'rangeDesc': rangeDesc,
      'statsJson': jsonEncode({
        'subjectMastery': snapshot.subjectMasteryPercent,
        'rankedWeakLeaves': snapshot.rankedWeakLeaves
            .take(8)
            .map(
              (s) => {
                'kpId': s.kpId,
                'name': s.name,
                'subject': s.subject,
                'weakScore': s.weakScore,
                'unmasteredCount': s.unmasteredCount,
                'rawWrongCount': s.rawWrongCount,
              },
            )
            .toList(),
        'errorTags': snapshot.errorTagCounts.map((k, v) => MapEntry(k.code, v)),
      }),
      'sampleWrongsJson': jsonEncode(
        wrongItems.take(6).map((w) {
          final q = questionById[w.questionId];
          return {
            'questionId': w.questionId,
            'stem': q == null ? '' : q.plainText,
            'errorTags': w.errorTags.map((t) => t.code).toList(),
            'mastery': w.mastery.code,
          };
        }).toList(),
      ),
    });

    final traceSteps = <TutorToolTraceStep>[];
    ReportRecord? submitted;
    final controller = AgentController();
    final sub = controller.listen<AfterToolCallEvent>().listen((event) {
      final snippet = event.result.content
          .whereType<TextPart>()
          .map((e) => e.text)
          .join(' ')
          .trim();
      traceSteps.add(
        TutorToolTraceStep(
          toolName: event.result.name,
          summary: _compact(event.result.arguments, 48),
          isError: event.result.isError,
          outputSnippet: _compact(snippet, 120),
        ),
      );
    });

    try {
      List<LLMMessage> responses = const [];
      for (var idx = 0; idx < modelCandidates.length; idx++) {
        final model = modelCandidates[idx];
        final agent = StatefulAgent(
          name: 'study_coach_reporter',
          client: client,
          modelConfig: ModelConfig(
            model: model,
            temperature: 0.3,
            maxTokens: 3000,
          ),
          state: AgentState(sessionId: 'report_${_uuid.v4()}'),
          systemPrompts: [rendered.systemPrompt],
          controller: controller,
          maxTurns: 6,
          tools: [
            Tool(
              name: 'query_weakness_tree',
              description: '查看各学科掌握率与薄弱叶子知识点排行。',
              parameterMode: ToolParameterMode.object,
              parameters: const <String, Object?>{
                'type': 'object',
                'properties': <String, Object?>{},
              },
              executable: (Map<String, dynamic> args) => jsonEncode({
                'rankedWeakLeaves': snapshot.rankedWeakLeaves
                    .take(8)
                    .map(
                      (e) => {
                        'kpId': e.kpId,
                        'name': e.name,
                        'weakScore': e.weakScore,
                        'unmasteredCount': e.unmasteredCount,
                      },
                    )
                    .toList(),
                'subjectMasteryPercent': snapshot.subjectMasteryPercent,
              }),
            ),
            Tool(
              name: 'submit_report_json',
              description:
                  '提交结构化诊断报告（overallAdvice, weakPoints, plan, markdown）。',
              parameterMode: ToolParameterMode.object,
              parameters: const {
                'type': 'object',
                'required': ['overallAdvice'],
                'properties': {
                  'overallAdvice': {'type': 'string'},
                  'markdown': {'type': 'string'},
                  'weakPoints': {
                    'type': 'array',
                    'items': {'type': 'object'},
                  },
                  'plan': {
                    'type': 'array',
                    'items': {'type': 'object'},
                  },
                },
              },
              executable: (Map<String, dynamic> args) {
                submitted = ReportRecord.fromJson({
                  'id': 'rep_${_uuid.v4().substring(0, 8)}',
                  'createdAtMs': DateTime.now().millisecondsSinceEpoch,
                  'markdown':
                      args['markdown'] ??
                      (args['overallAdvice'] ?? '已完成阶段学习诊断报告。'),
                  'overallAdvice': args['overallAdvice'] ?? '',
                  'weakPoints': args['weakPoints'] ?? const [],
                  'plan': args['plan'] ?? const [],
                  'kpWeakRates': snapshot.toWeakRateMap(),
                  'toolTrace': traceSteps
                      .map((e) => e.toDisplayLine())
                      .toList(),
                });
                return jsonEncode({'ok': true, 'reportId': submitted!.id});
              },
            ),
          ],
        );
        try {
          responses = await agent.run([
            UserMessage([TextPart(rendered.userPrompt)]),
          ], useStream: false);
          break;
        } catch (e) {
          if (idx + 1 < modelCandidates.length &&
              AiEndpointConfig.isModelUnavailableError(e)) {
            continue;
          }
          rethrow;
        }
      }
      if (submitted != null) {
        return StudyCoachReportResult(
          report: submitted!,
          usedOfflineFallback: false,
          traceSteps: List.unmodifiable(traceSteps),
        );
      }
      final rawText = responses
          .whereType<ModelMessage>()
          .map((m) => m.textOutput ?? '')
          .join('\n')
          .trim();
      final offline = _offlineGenerateReport(
        profile: profile,
        snapshot: snapshot,
        wrongItems: wrongItems,
        rangeDesc: rangeDesc,
      );
      if (rawText.isEmpty) return offline;
      return StudyCoachReportResult(
        report: ReportRecord(
          id: 'rep_${_uuid.v4().substring(0, 8)}',
          createdAtMs: DateTime.now().millisecondsSinceEpoch,
          markdown: rawText,
          overallAdvice: offline.report.overallAdvice,
          weakPoints: offline.report.weakPoints,
          plan: offline.report.plan,
          kpWeakRates: snapshot.toWeakRateMap(),
          toolTrace: traceSteps.map((e) => e.toDisplayLine()).toList(),
        ),
        usedOfflineFallback: false,
        traceSteps: List.unmodifiable(traceSteps),
      );
    } catch (e, st) {
      InouDiagnosticsLogger.instance.error(
        'ai.coach',
        'AI diagnostic report generation failed',
        error: e,
        stackTrace: st,
      );
      final offline = _offlineGenerateReport(
        profile: profile,
        snapshot: snapshot,
        wrongItems: wrongItems,
        rangeDesc: rangeDesc,
      );
      return StudyCoachReportResult(
        report: offline.report,
        usedOfflineFallback: true,
        traceSteps: offline.traceSteps,
        errorMessage: 'AI 诊断报告请求失败：$e',
      );
    } finally {
      await sub.cancel();
    }
  }

  Future<DrillGenerationResult> generateDrill({
    required StudentProfile profile,
    required String subject,
    List<String> targetKpIds = const [],
    List<String> targetKpNames = const [],
    Question? sourceWrongQuestion,
    required List<Question> existingQuestions,
    int count = 3,
    AiEndpointConfig? endpoint,
    String? apiKey,
    LLMClient? overrideClient,
  }) async {
    final canRunRemote =
        overrideClient != null ||
        (endpoint != null && (apiKey ?? '').trim().isNotEmpty);
    if (!canRunRemote) {
      return _offlineGenerateDrill(
        profile: profile,
        subject: subject,
        targetKpIds: targetKpIds,
        targetKpNames: targetKpNames,
        sourceWrongQuestion: sourceWrongQuestion,
        existingQuestions: existingQuestions,
        count: count,
      );
    }

    final client =
        overrideClient ??
        clientFactory.createClient(endpoint!, apiKey: apiKey!.trim());
    final modelCandidates = endpoint != null
        ? endpoint.resolveModelCandidates(AiTier.strong)
        : const ['mock-model'];

    final existingStems = existingQuestions.map((q) => q.plainText).toList();
    final dedupHook = ValidationAndDedupHook(
      existingPlainStems: existingStems,
      defaultSubject: subject,
      defaultGrade: profile.grade,
      maxAccepted: count,
    );

    final traceSteps = <TutorToolTraceStep>[];
    final controller = AgentController();
    final sub = controller.listen<AfterToolCallEvent>().listen((event) {
      final snippet = event.result.content
          .whereType<TextPart>()
          .map((e) => e.text)
          .join(' ')
          .trim();
      final blocked =
          snippet.contains('VALIDATION_REJECTED') ||
          snippet.contains('DUPLICATE_REJECTED');
      traceSteps.add(
        TutorToolTraceStep(
          toolName: event.result.name,
          summary: _compact(event.result.arguments, 48),
          isBlocked: blocked,
          isError: event.result.isError && !blocked,
          outputSnippet: _compact(snippet, 120),
        ),
      );
    });

    final p04 = PromptLibrary.get('P-04');
    final templateId = sourceWrongQuestion != null ? 'P-09a' : 'P-09b';
    final rendered = PromptLibrary.get(templateId).render({
      'stage': profile.stage.label,
      'subject': SubjectCatalog.labelOf(subject),
      'count': '$count',
      if (sourceWrongQuestion != null)
        'sourceQuestionJson': jsonEncode(sourceWrongQuestion.toJson()),
      if (sourceWrongQuestion == null)
        'kpTargetsJson': jsonEncode({
          'kpIds': targetKpIds,
          'kpNames': targetKpNames,
        }),
      'existingSnippets': existingStems.take(10).join('\n'),
    });

    try {
      for (var idx = 0; idx < modelCandidates.length; idx++) {
        final strongModel = modelCandidates[idx];
        final balancedModel = (idx == 0 && endpoint != null)
            ? endpoint.resolveModel(AiTier.balanced)
            : strongModel;

        final solverSubAgent = SubAgent(
          name: 'independent_solver',
          description: '独立重解候选新题并校验唯一解与数值准确性，避免出出歧义题或错解。',
          agentFactory: (parent) => StatefulAgent(
            name: 'independent_solver',
            client: client,
            modelConfig: ModelConfig(
              model: balancedModel,
              temperature: 0.1,
              maxTokens: 1600,
            ),
            state: AgentState(sessionId: 'solver_${_uuid.v4()}'),
            isSubAgent: true,
            disableSubAgents: true,
            systemPrompts: [p04.systemTemplate],
            maxTurns: 4,
            tools: [
              Tool(
                name: 'run_math_verify',
                description: '本地精确数值计算与二次方程求根验算工具。',
                parameterMode: ToolParameterMode.object,
                parameters: const {
                  'type': 'object',
                  'properties': {
                    'expression': {'type': 'string'},
                    'expected': {'type': 'string'},
                    'a': {'type': 'number'},
                    'b': {'type': 'number'},
                    'c': {'type': 'number'},
                  },
                },
                executable: (Map<String, dynamic> args) => jsonEncode(
                  MathVerifyEngine.verifyRun(
                    expression: args['expression'] as String?,
                    expected: args['expected'] as String?,
                    a: (args['a'] as num?)?.toDouble(),
                    b: (args['b'] as num?)?.toDouble(),
                    c: (args['c'] as num?)?.toDouble(),
                  ),
                ),
              ),
            ],
          ),
        );

        final agent = StatefulAgent(
          name: 'study_coach_drill_generator',
          client: client,
          modelConfig: ModelConfig(
            model: strongModel,
            temperature: 0.4,
            maxTokens: 4000,
          ),
          state: AgentState(sessionId: 'drill_${_uuid.v4()}'),
          systemPrompts: [
            rendered.systemPrompt,
            '流程要求：先构造完整题目 JSON，再调用 independent_solver 核验答案正确性，最后调用 submit_question_draft 提交入库（共 $count 道，全部需通过 schema 校验且不与已有题重复）。',
          ],
          hooks: [dedupHook],
          subAgents: [solverSubAgent],
          controller: controller,
          maxTurns: 10,
          tools: [
            Tool(
              name: 'search_similar_questions',
              description: '检索题库中相近题干以避免重复出题。',
              parameterMode: ToolParameterMode.object,
              parameters: const {
                'type': 'object',
                'properties': {
                  'keyword': {'type': 'string'},
                },
              },
              executable: (Map<String, dynamic> args) {
                final kw = (args['keyword'] as String? ?? '').trim();
                final hits = existingStems
                    .where((s) => kw.isEmpty || s.contains(kw))
                    .take(5)
                    .toList();
                return jsonEncode({'count': hits.length, 'samples': hits});
              },
            ),
            Tool(
              name: 'submit_question_draft',
              description: '校验并提交一道生成的新题 JSON（schema=1, kind, header, prompt, body, presentation, grading, explanation, meta）。',
              parameterMode: ToolParameterMode.object,
              parameters: const {
                'type': 'object',
                'required': ['question'],
                'properties': {
                  'question': {'type': 'object'},
                },
              },
              executable: (Map<String, dynamic> args) {
                final rawQ = args['question'] ?? args;
                final map = (rawQ as Map).map(
                  (k, v) => MapEntry(k.toString(), v),
                );
                final q = dedupHook.parseDraftQuestion(map);
                dedupHook.acceptedQuestions.add(q);
                return jsonEncode({
                  'accepted': true,
                  'id': q.id,
                  'acceptedTotal': dedupHook.acceptedQuestions.length,
                });
              },
            ),
          ],
        );

        try {
          await agent.run([
            UserMessage([TextPart(rendered.userPrompt)]),
          ], useStream: false);
          break;
        } catch (e) {
          if (idx + 1 < modelCandidates.length &&
              AiEndpointConfig.isModelUnavailableError(e)) {
            continue;
          }
          rethrow;
        }
      }
      if (dedupHook.acceptedQuestions.isEmpty) {
        return DrillGenerationResult(
          questions: const [],
          usedOfflineFallback: false,
          traceSteps: List.unmodifiable(traceSteps),
          rejectedDraftCount: dedupHook.rejectedCount,
          errorMessage: 'AI 未能生成通过校验的题目，请调整模型或重试。',
        );
      }
      return DrillGenerationResult(
        questions: List.unmodifiable(dedupHook.acceptedQuestions),
        usedOfflineFallback: false,
        traceSteps: List.unmodifiable(traceSteps),
        rejectedDraftCount: dedupHook.rejectedCount,
      );
    } catch (e, st) {
      InouDiagnosticsLogger.instance.error(
        'ai.coach',
        'AI drill generation failed',
        error: e,
        stackTrace: st,
      );
      return DrillGenerationResult(
        questions: const [],
        usedOfflineFallback: false,
        traceSteps: List.unmodifiable(traceSteps),
        rejectedDraftCount: dedupHook.rejectedCount,
        errorMessage: 'AI 出题失败：$e',
      );
    } finally {
      await sub.cancel();
    }
  }

  StudyCoachReportResult _offlineGenerateReport({
    required StudentProfile profile,
    required WeaknessSnapshot snapshot,
    required List<WrongItem> wrongItems,
    required String rangeDesc,
  }) {
    final topLeaves = snapshot.rankedWeakLeaves.take(3).toList();
    final weakPoints = topLeaves
        .map(
          (stat) => WeaknessPointSummary(
            kpId: stat.kpId,
            kpName: stat.name,
            severity: stat.weakScore >= 0.65
                ? 'high'
                : (stat.weakScore >= 0.4 ? 'medium' : 'low'),
            reasons: [
              '近期加权薄弱指数 ${(stat.weakScore * 100).round()}%（未掌握 ${stat.unmasteredCount} 题，累计错题 ${stat.rawWrongCount} 道）',
            ],
            advice: [
              '围绕「${stat.name}」进行 L1/L2 分步梳理，先列核心关系式再代入数字，完成连续 3 次答对即可毕业。',
            ],
            suggestedCount: 4,
          ),
        )
        .toList(growable: false);

    final topErrorTag = snapshot.errorTagCounts.entries.isEmpty
        ? null
        : (snapshot.errorTagCounts.entries.toList()
                ..sort((a, b) => b.value.compareTo(a.value)))
              .first;

    if (wrongItems.isEmpty && snapshot.rankedWeakLeaves.isEmpty) {
      return StudyCoachReportResult(
        report: ReportRecord(
          id: 'rep_${_uuid.v4().substring(0, 8)}',
          createdAtMs: DateTime.now().millisecondsSinceEpoch,
          markdown:
              '### ${profile.name} · 本地学情统计\n\n当前暂无足够错题或作答记录，请先拍照录题或完成练习后再生成诊断。',
          overallAdvice: '${profile.name}当前暂无足够作答或错题样本，无法生成薄弱诊断；请先拍照录题或完成练习。',
          weakPoints: const [],
          plan: const [],
          kpWeakRates: const {},
          toolTrace: const [],
        ),
        usedOfflineFallback: true,
        traceSteps: const [],
      );
    }

    final focusKp = topLeaves.isNotEmpty ? topLeaves.first.name : '当前录入考点';
    final overallAdvice = snapshot.isSampleInsufficient
        ? '${profile.name}目前记录错题样本较少（${snapshot.totalWrongSamples} 题），当前最需关注「$focusKp」；配置 AI Key 后可获取针对性诊断建议。'
        : '${profile.name}在$rangeDesc的统计结果显示：最薄弱考点为「$focusKp」，主要错因集中在「${topErrorTag?.key.label ?? '待标注错因'}」。';

    final plan = [
      StudyPlanStep(day: 'Day 1', task: '重做错题本中「$focusKp」未掌握题目'),
      const StudyPlanStep(day: 'Day 2', task: '在设置中接入 AI 后，结合薄弱考点生成针对性巩固题'),
      const StudyPlanStep(day: 'Day 3', task: '完成限时回测检验连对掌握情况'),
    ];

    final trace = [
      TutorToolTraceStep(
        toolName: 'query_weakness_tree',
        summary: 'range=$rangeDesc',
        outputSnippet: '统计 ${snapshot.rankedWeakLeaves.length} 个叶子知识点衰减加权薄弱率',
      ),
      TutorToolTraceStep(
        toolName: 'fetch_wrong_samples',
        summary: 'samples=${wrongItems.length}',
        outputSnippet: '统计已标注错因标签 ${snapshot.errorTagCounts.length} 类',
      ),
    ];

    final mdBuffer = StringBuffer()
      ..writeln('### ${profile.name} · $rangeDesc学习统计简报')
      ..writeln()
      ..writeln('> $overallAdvice')
      ..writeln()
      ..writeln('#### 重点薄弱节点')
      ..writeln();
    for (final wp in weakPoints) {
      mdBuffer.writeln(
        '- **${wp.kpName}**（优先级：${wp.severity}）：${wp.reasons.first}',
      );
    }

    return StudyCoachReportResult(
      report: ReportRecord(
        id: 'rep_${_uuid.v4().substring(0, 8)}',
        createdAtMs: DateTime.now().millisecondsSinceEpoch,
        markdown: mdBuffer.toString().trim(),
        overallAdvice: overallAdvice,
        weakPoints: weakPoints,
        plan: plan,
        kpWeakRates: snapshot.toWeakRateMap(),
        toolTrace: trace.map((e) => e.toDisplayLine()).toList(growable: false),
      ),
      usedOfflineFallback: true,
      traceSteps: trace,
    );
  }

  DrillGenerationResult _offlineGenerateDrill({
    required StudentProfile profile,
    required String subject,
    List<String> targetKpIds = const [],
    List<String> targetKpNames = const [],
    Question? sourceWrongQuestion,
    required List<Question> existingQuestions,
    required int count,
  }) {
    return const DrillGenerationResult(
      questions: [],
      usedOfflineFallback: true,
      traceSteps: [],
      errorMessage: '个性化靶向出题与同源变式题需要连接实时 AI 模型，请先在「设置」中配置 API Key。',
    );
  }

  String _compact(String s, int max) {
    final cleaned = s.replaceAll('\n', ' ').trim();
    return cleaned.length <= max ? cleaned : '${cleaned.substring(0, max)}…';
  }
}
