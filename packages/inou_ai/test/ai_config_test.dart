import 'package:inou_ai/inou_ai.dart';
import 'package:test/test.dart';

void main() {
  group('AiEndpointConfig', () {
    test(
      'falls back to available tier model when specific tier is missing',
      () {
        const cfg = AiEndpointConfig(
          id: 'custom_1',
          name: 'My Proxy',
          protocol: AiProtocol.openAiCompatible,
          baseUrl: 'https://example.com/v1',
          tierModels: {AiTier.balanced: 'qwen-vl-max'},
        );

        expect(cfg.resolveModel(AiTier.fast), 'qwen-vl-max');
        expect(cfg.resolveModel(AiTier.balanced), 'qwen-vl-max');
        expect(cfg.resolveModel(AiTier.strong), 'qwen-vl-max');
      },
    );

    test('default presets include both Gemini and OpenAI-compatible', () {
      final presets = AiEndpointPresets.defaults();
      expect(presets.any((p) => p.protocol == AiProtocol.gemini), isTrue);
      expect(
        presets.any((p) => p.protocol == AiProtocol.openAiCompatible),
        isTrue,
      );
    });
  });

  group('OpenAiUrlNormalizer', () {
    test('normalizes trailing slashes and chat/completions suffix', () {
      expect(
        OpenAiUrlNormalizer.chatCompletionsUri('https://api.openai.com/v1/')
            .toString(),
        'https://api.openai.com/v1/chat/completions',
      );
      expect(
        OpenAiUrlNormalizer.chatCompletionsUri(
          'https://gateway.example/v1/chat/completions',
        ).toString(),
        'https://gateway.example/v1/chat/completions',
      );
      expect(
        OpenAiUrlNormalizer.modelsUri(
          'https://gateway.example/v1/chat/completions',
        ).toString(),
        'https://gateway.example/v1/models',
      );
    });
  });

  group('AiTextPostProcessor', () {
    test('strips reasoning think tags and markdown json fences', () {
      const raw =
          '<think>step 1...\nstep 2...</think>\n```json\n{"ok": true}\n```';
      expect(AiTextPostProcessor.extractJsonText(raw), '{"ok": true}');
    });
  });
}
