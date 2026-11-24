import 'dart:async';
import 'dart:convert';

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:inou_ai/inou_ai.dart';
import 'package:test/test.dart';

class _ScriptedLlmClient extends LLMClient {
  _ScriptedLlmClient(this._script);

  final FutureOr<ModelMessage> Function(
    int callIndex,
    List<LLMMessage> messages,
    List<Tool>? tools,
  )
  _script;

  int callCount = 0;
  final List<List<String>> observedToolNamesPerCall = [];

  @override
  Future<ModelMessage> generate(
    List<LLMMessage> messages, {
    List<Tool>? tools,
    ToolChoice? toolChoice,
    required ModelConfig modelConfig,
    bool? jsonOutput,
    CancelToken? cancelToken,
  }) async {
    final idx = callCount++;
    observedToolNamesPerCall.add(
      (tools ?? const <Tool>[]).map((t) => t.name).toList(),
    );
    return _script(idx, messages, tools);
  }

  @override
  Future<Stream<StreamingMessage>> stream(
    List<LLMMessage> messages, {
    List<Tool>? tools,
    ToolChoice? toolChoice,
    required ModelConfig modelConfig,
    bool? jsonOutput,
    CancelToken? cancelToken,
  }) async {
    final msg = await generate(
      messages,
      tools: tools,
      toolChoice: toolChoice,
      modelConfig: modelConfig,
      jsonOutput: jsonOutput,
      cancelToken: cancelToken,
    );
    return Stream<StreamingMessage>.value(StreamingMessage(modelMessage: msg));
  }
}

void main() {
  group('InouTutorAgent & AntiSpoilerHook', () {
    test('runs multi-step tool loop and records usage', () async {
      final client = _ScriptedLlmClient((idx, messages, tools) {
        if (idx == 0) {
          return ModelMessage(
            model: 'fake-model',
            stopReason: 'tool_calls',
            textOutput: '',
            functionCalls: [
              FunctionCall(
                id: 'call_1',
                name: InouToolNames.readQuestionPublic,
                arguments: jsonEncode({'questionId': 'q_01'}),
              ),
            ],
            usage: ModelUsage(
              promptTokens: 100,
              completionTokens: 20,
              totalTokens: 120,
              model: 'fake-model',
            ),
          );
        }
        return ModelMessage(
          model: 'fake-model',
          stopReason: 'stop',
          textOutput: '[[emo=happy]]\n这道题考查因式分解法，先把常数项 6 拆成 (-2)×(-3) 试试看！',
          usage: ModelUsage(
            promptTokens: 150,
            completionTokens: 40,
            totalTokens: 190,
            model: 'fake-model',
          ),
        );
      });

      final usageHook = InouUsageHook();
      final readPublicTool = Tool(
        name: InouToolNames.readQuestionPublic,
        description: 'Reads question stem without answer.',
        parameters: {
          'type': 'object',
          'properties': {
            'questionId': {'type': 'string'},
          },
          'required': ['questionId'],
        },
        executable: (String questionId) => '题目 $questionId: x^2 - 5x + 6 = 0',
        namedParameters: const ['questionId'],
      );

      final agent = const InouTutorAgentBuilder().build(
        client: client,
        modelConfig: ModelConfig(model: 'fake-model'),
        state: AgentState.empty(),
        systemPrompts: const ['你是诺诺老师。'],
        tools: [readPublicTool],
        extraHooks: [usageHook],
      );

      final messages = await agent.run([UserMessage.text('帮我看看这道题')]);
      expect(client.callCount, 2);
      expect(usageHook.recordedUsages, hasLength(2));
      expect((messages.last as ModelMessage).textOutput, contains('因式分解法'));
    });

    test('AntiSpoilerHook hides and blocks read_question_answer at L1/L2, allows at L3', () async {
      var answerToolInvoked = 0;
      var currentLevel = HintLevel.l1Concept;

      final answerTool = Tool(
        name: InouToolNames.readQuestionAnswer,
        description: 'Reads private answer and explanation.',
        parameters: const {'type': 'object', 'properties': <String, Object?>{}},
        executable: () {
          answerToolInvoked++;
          return '答案：A (x1=2, x2=3)';
        },
      );

      // Even if the model ignores available tools and still emits a call to
      // `read_question_answer`, AntiSpoilerHook.beforeToolCall must deny it.
      final rogueClient = _ScriptedLlmClient((idx, messages, tools) {
        if (idx == 0) {
          return ModelMessage(
            model: 'fake-model',
            stopReason: 'tool_calls',
            textOutput: '',
            functionCalls: [
              FunctionCall(
                id: 'call_secret',
                name: InouToolNames.readQuestionAnswer,
                arguments: '{}',
              ),
            ],
          );
        }
        return ModelMessage(
          model: 'fake-model',
          stopReason: 'stop',
          textOutput: '[[emo=encourage]]\n先想想十字相乘哦！',
        );
      });

      final restrictedAgent = const InouTutorAgentBuilder().build(
        client: rogueClient,
        modelConfig: ModelConfig(model: 'fake-model'),
        state: AgentState.empty(),
        systemPrompts: const ['你是诺诺老师。'],
        tools: [answerTool],
        hintLevelProvider: () => currentLevel,
      );

      await restrictedAgent.run([UserMessage.text('给我思路提示')]);
      expect(
        rogueClient.observedToolNamesPerCall.first,
        isNot(contains(InouToolNames.readQuestionAnswer)),
      );
      expect(answerToolInvoked, 0);

      // Now switch to L3 full solution: answer tool should be visible & invoked.
      currentLevel = HintLevel.l3FullSolution;
      final fullClient = _ScriptedLlmClient((idx, messages, tools) {
        if (idx == 0) {
          return ModelMessage(
            model: 'fake-model',
            stopReason: 'tool_calls',
            textOutput: '',
            functionCalls: [
              FunctionCall(
                id: 'call_full',
                name: InouToolNames.readQuestionAnswer,
                arguments: '{}',
              ),
            ],
          );
        }
        return ModelMessage(
          model: 'fake-model',
          stopReason: 'stop',
          textOutput: '[[emo=happy]]\n完整答案是 A。',
        );
      });

      final fullAgent = const InouTutorAgentBuilder().build(
        client: fullClient,
        modelConfig: ModelConfig(model: 'fake-model'),
        state: AgentState.empty(),
        systemPrompts: const ['你是诺诺老师。'],
        tools: [answerTool],
        hintLevelProvider: () => currentLevel,
      );

      await fullAgent.run([UserMessage.text('告诉我完整答案')]);
      expect(
        fullClient.observedToolNamesPerCall.first,
        contains(InouToolNames.readQuestionAnswer),
      );
      expect(answerToolInvoked, 1);
    });
  });

  group('InouLlmClientFactory adapters', () {
    test('rewrites Gemini origin when custom proxy baseUrl is configured', () {
      const originUrl =
          'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent';
      expect(
        InouLlmClientFactory.rewriteGeminiUrl(
          originUrl,
          customBaseUrl: 'https://my-proxy.example.com/gemini/',
        ),
        'https://my-proxy.example.com/gemini/v1beta/models/gemini-2.5-flash:generateContent',
      );
    });

    test('adapts OpenAI-compatible payload quirks per endpoint config', () {
      const cfg = AiEndpointConfig(
        id: 'zhipu_test',
        name: 'Zhipu',
        protocol: AiProtocol.openAiCompatible,
        baseUrl: 'https://open.bigmodel.cn/api/paas/v4/chat/completions',
        tierModels: {AiTier.balanced: 'glm-4v-plus'},
        jsonModeStrategy: JsonModeStrategy.promptOnly,
        sendImageDetail: false,
        supportsStreamUsage: false,
      );

      expect(
        OpenAiUrlNormalizer.apiBaseUrl(cfg.baseUrl),
        'https://open.bigmodel.cn/api/paas/v4',
      );

      final payload = <String, Object?>{
        'model': 'glm-4v-plus',
        'stream': true,
        'stream_options': <String, Object?>{'include_usage': true},
        'response_format': <String, Object?>{'type': 'json_object'},
        'messages': <Object?>[
          <String, Object?>{
            'role': 'user',
            'content': <Object?>[
              <String, Object?>{'type': 'text', 'text': 'hi'},
              <String, Object?>{
                'type': 'image_url',
                'image_url': <String, Object?>{
                  'url': 'data:image/jpeg;base64,AAA',
                  'detail': 'high',
                },
              },
            ],
          },
        ],
      };

      InouLlmClientFactory.adaptOpenAiPayload(payload, cfg);
      expect(payload.containsKey('stream_options'), isFalse);
      expect(payload.containsKey('response_format'), isFalse);
      final msgs = payload['messages'] as List<Object?>;
      final firstMsg = msgs.first as Map<String, Object?>;
      final content = firstMsg['content'] as List<Object?>;
      final imgPart = content[1] as Map<String, Object?>;
      final imgUrl = imgPart['image_url'] as Map<String, Object?>;
      expect(imgUrl.containsKey('detail'), isFalse);

      const factory = InouLlmClientFactory();
      expect(
        factory.createClient(cfg, apiKey: 'test-key'),
        isA<OpenAIClient>(),
      );
      expect(
        factory.createClient(
          AiEndpointPresets.defaults().first,
          apiKey: 'test-key',
        ),
        isA<GeminiClient>(),
      );
    });
  });
}
