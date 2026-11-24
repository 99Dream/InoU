import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:dio/dio.dart';

import 'ai_endpoint_config.dart';
import 'openai_compat_utils.dart';

/// Builds [LLMClient] instances backed by `dart_agent_core` while preserving
/// custom Gemini proxy URLs and OpenAI-compatible dialect flags.
class InouLlmClientFactory {
  const InouLlmClientFactory();

  static const String defaultGeminiOrigin =
      'https://generativelanguage.googleapis.com';

  LLMClient createClient(
    AiEndpointConfig config, {
    required String apiKey,
    Duration timeout = const Duration(seconds: 300),
    Duration connectTimeout = const Duration(seconds: 60),
    String? proxyUrl,
  }) {
    return switch (config.protocol) {
      AiProtocol.gemini => GeminiClient(
        apiKey: apiKey,
        timeout: timeout,
        connectTimeout: connectTimeout,
        proxyUrl: proxyUrl,
        client: createGeminiDio(config),
      ),
      AiProtocol.openAiCompatible => OpenAIClient(
        apiKey: apiKey,
        baseUrl: OpenAiUrlNormalizer.apiBaseUrl(config.baseUrl),
        timeout: timeout,
        connectTimeout: connectTimeout,
        proxyUrl: proxyUrl,
        client: createOpenAiDio(config),
      ),
    };
  }

  /// Creates a [Dio] instance that rewrites the default Gemini host when
  /// [config.baseUrl] points to a custom proxy/gateway and injects headers.
  static Dio createGeminiDio(AiEndpointConfig config) {
    final dio = Dio();
    final targetBase = config.baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (targetBase.isNotEmpty && targetBase != defaultGeminiOrigin) {
            options.path = rewriteGeminiUrl(
              options.path,
              customBaseUrl: targetBase,
            );
          }
          if (config.extraHeaders.isNotEmpty) {
            options.headers.addAll(config.extraHeaders);
          }
          handler.next(options);
        },
      ),
    );
    return dio;
  }

  /// Creates a [Dio] instance that adapts OpenAI-compatible payload quirks
  /// (`stream_options`, `response_format`, `image_url.detail`) per endpoint.
  static Dio createOpenAiDio(AiEndpointConfig config) {
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (config.extraHeaders.isNotEmpty) {
            options.headers.addAll(config.extraHeaders);
          }
          final data = options.data;
          if (data is Map<String, Object?>) {
            adaptOpenAiPayload(data, config);
          }
          handler.next(options);
        },
      ),
    );
    return dio;
  }

  static String rewriteGeminiUrl(
    String rawUrl, {
    required String customBaseUrl,
  }) {
    final normalizedBase = customBaseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (rawUrl.startsWith(defaultGeminiOrigin)) {
      return '$normalizedBase${rawUrl.substring(defaultGeminiOrigin.length)}';
    }
    return rawUrl;
  }

  static void adaptOpenAiPayload(
    Map<String, Object?> body,
    AiEndpointConfig config,
  ) {
    if (!config.supportsStreamUsage) {
      body.remove('stream_options');
    }
    if (config.jsonModeStrategy == JsonModeStrategy.promptOnly) {
      body.remove('response_format');
    }
    if (!config.sendImageDetail) {
      final messages = body['messages'];
      if (messages is List) {
        for (final msg in messages) {
          if (msg is Map<String, Object?>) {
            final content = msg['content'];
            if (content is List) {
              for (final part in content) {
                if (part is Map<String, Object?> &&
                    part['type'] == 'image_url') {
                  final img = part['image_url'];
                  if (img is Map<String, Object?>) {
                    img.remove('detail');
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
