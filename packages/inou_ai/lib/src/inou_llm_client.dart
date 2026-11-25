import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:dio/dio.dart';

import 'ai_endpoint_config.dart';
import 'ai_retry_policy.dart';
import 'dio_http_adapter_stub.dart'
    if (dart.library.io) 'dio_http_adapter_io.dart';
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
    Duration timeout = const Duration(seconds: 90),
    Duration connectTimeout = const Duration(seconds: 20),
    String? proxyUrl,
    AiRetryConfig retryConfig = AiRetryConfig.standard,
    String scene = 'ai',
    void Function(AiRetryEvent)? onRetry,
  }) {
    final client = switch (config.protocol) {
      AiProtocol.gemini => GeminiClient(
        apiKey: apiKey,
        timeout: timeout,
        connectTimeout: connectTimeout,
        proxyUrl: proxyUrl,
        maxRetries: 0,
        client: createGeminiDio(config),
      ),
      AiProtocol.openAiCompatible => OpenAIClient(
        apiKey: apiKey,
        baseUrl: OpenAiUrlNormalizer.apiBaseUrl(config.baseUrl),
        timeout: timeout,
        connectTimeout: connectTimeout,
        proxyUrl: proxyUrl,
        maxRetries: 0,
        client: createOpenAiDio(config),
      ),
    };
    if (retryConfig.maxRetries <= 0) {
      return client;
    }
    return RetryingLlmClient.wrap(
      client,
      scene: scene,
      config: retryConfig,
      onRetry: onRetry,
    );
  }

  /// Creates a [Dio] instance that rewrites the default Gemini host when
  /// [config.baseUrl] points to a custom proxy/gateway and injects headers.
  static Dio createGeminiDio(AiEndpointConfig config) {
    final disableReuse = config.disableSocketReuse;
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 20),
        sendTimeout: const Duration(seconds: 45),
        receiveTimeout: const Duration(seconds: 90),
        persistentConnection: !disableReuse,
        headers: {if (disableReuse) 'Connection': 'close'},
      ),
    );
    configureDioHttpClient(dio, disableKeepAlive: disableReuse);
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
          if (disableReuse) {
            options.persistentConnection = false;
            options.headers['Connection'] = 'close';
          }
          if (options.path.contains('alt=sse')) {
            options.headers.putIfAbsent('Accept', () => 'text/event-stream');
            options.headers.putIfAbsent('Cache-Control', () => 'no-cache');
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
    final disableReuse = config.disableSocketReuse;
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 20),
        sendTimeout: const Duration(seconds: 45),
        receiveTimeout: const Duration(seconds: 90),
        persistentConnection: !disableReuse,
        headers: {if (disableReuse) 'Connection': 'close'},
      ),
    );
    configureDioHttpClient(dio, disableKeepAlive: disableReuse);
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (disableReuse) {
            options.persistentConnection = false;
            options.headers['Connection'] = 'close';
          }
          if (config.extraHeaders.isNotEmpty) {
            options.headers.addAll(config.extraHeaders);
          }
          final data = options.data;
          if (data is Map<String, Object?>) {
            adaptOpenAiPayload(data, config);
            if (data['stream'] == true) {
              options.headers.putIfAbsent('Accept', () => 'text/event-stream');
              options.headers.putIfAbsent('Cache-Control', () => 'no-cache');
            }
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
