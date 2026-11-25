import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:dio/dio.dart';
import 'package:inou_domain/inou_domain.dart';

import 'ai_endpoint_config.dart';
import 'ai_retry_policy.dart';
import 'inou_llm_client.dart';
import 'openai_compat_utils.dart';

/// Dedicated SSE / chunked text transport for step-by-step AI blackboard
/// streaming across Gemini native and OpenAI-compatible endpoints.
///
/// Key improvements over generic agent JSON streaming:
/// - Requests Gemini `?alt=sse` and parses `data:` lines reliably while also
///   supporting quote-aware `{...}` JSON array fallback so braces inside chalk
///   strings never break chunk boundaries.
/// - Disables or caps Gemini 2.5 thinking latency when [disableThinkingForSpeed]
///   is enabled, retrying once automatically if a relay rejects `thinkingConfig`.
/// - Strips `<think>...</think>` reasoning blocks incrementally on the wire.
class BlackboardStreamTransport {
  const BlackboardStreamTransport({
    this.timeout = const Duration(seconds: 90),
    this.connectTimeout = const Duration(seconds: 20),
  });

  final Duration timeout;
  final Duration connectTimeout;

  static final RegExp _openThinkReg = RegExp(r'<think>', caseSensitive: false);
  static final RegExp _closeThinkReg = RegExp(
    r'</think>',
    caseSensitive: false,
  );

  /// Streams raw text deltas for [messages] using [modelConfig].
  Stream<String> streamText({
    required AiEndpointConfig endpoint,
    required String? apiKey,
    required List<LLMMessage> messages,
    required ModelConfig modelConfig,
    LLMClient? overrideClient,
    CancelToken? cancelToken,
    bool disableThinkingForSpeed = true,
    bool? jsonOutput,
    AiRetryConfig retryConfig = AiRetryConfig.standard,
    String scene = 'blackboard',
    void Function(AiRetryEvent)? onRetry,
  }) {
    Stream<String> openRawStream() {
      if (overrideClient != null) {
        return _streamFromClient(
          RetryingLlmClient.unwrap(overrideClient),
          messages,
          modelConfig: modelConfig,
          cancelToken: cancelToken,
          jsonOutput: jsonOutput,
        );
      }
      if (endpoint.protocol == AiProtocol.gemini) {
        return _streamGeminiSse(
          endpoint: endpoint,
          apiKey: (apiKey ?? '').trim(),
          messages: messages,
          modelConfig: modelConfig,
          cancelToken: cancelToken,
          disableThinkingForSpeed: disableThinkingForSpeed,
          jsonOutput: jsonOutput,
        );
      }
      return _streamOpenAiSse(
        endpoint: endpoint,
        apiKey: (apiKey ?? '').trim(),
        messages: messages,
        modelConfig: modelConfig,
        cancelToken: cancelToken,
        jsonOutput: jsonOutput,
      );
    }

    if (retryConfig.maxRetries <= 0) {
      return stripThinkTags(openRawStream());
    }
    return _streamTextWithRetry(
      openRawStream: openRawStream,
      retryConfig: retryConfig,
      scene: scene,
      cancelToken: cancelToken,
      onRetry: onRetry,
    );
  }

  Stream<String> _streamTextWithRetry({
    required Stream<String> Function() openRawStream,
    required AiRetryConfig retryConfig,
    required String scene,
    CancelToken? cancelToken,
    void Function(AiRetryEvent)? onRetry,
  }) async* {
    for (var attempt = 0; attempt <= retryConfig.maxRetries; attempt++) {
      if (cancelToken?.isCancelled ?? false) return;
      var emittedChunk = false;
      try {
        await for (final delta in stripThinkTags(openRawStream())) {
          if (delta.isNotEmpty) {
            emittedChunk = true;
            yield delta;
          }
        }
        if (attempt > 0) {
          AiRetryEventBus.emitRecovered(
            scene: scene,
            maxRetries: retryConfig.maxRetries,
            onRetry: onRetry,
          );
        }
        return;
      } catch (e, st) {
        final canRetry =
            !emittedChunk &&
            attempt < retryConfig.maxRetries &&
            AiRetryRunner.shouldRetry(e, cancelToken: cancelToken);
        if (!canRetry) {
          if (AiRetryRunner.shouldRetry(e, cancelToken: cancelToken)) {
            InouDiagnosticsLogger.instance.error(
              'blackboard.stream',
              'Blackboard stream exhausted retries (scene=$scene)',
              error: e,
              stackTrace: st,
            );
            AiRetryEventBus.emitExhausted(
              scene: scene,
              maxRetries: retryConfig.maxRetries,
              onRetry: onRetry,
            );
          }
          rethrow;
        }
        final nextRetry = attempt + 1;
        InouDiagnosticsLogger.instance.warn(
          'blackboard.stream',
          'Blackboard stream attempt failed, retrying $nextRetry/${retryConfig.maxRetries} (scene=$scene)',
          error: e,
          stackTrace: st,
        );
        AiRetryEventBus.emitRetry(
          scene: scene,
          attempt: nextRetry,
          maxRetries: retryConfig.maxRetries,
          onRetry: onRetry,
        );
        await AiRetryRunner.backoff(
          failedAttemptIndex: attempt,
          config: retryConfig,
          cancelToken: cancelToken,
        );
      }
    }
  }

  Stream<String> _streamFromClient(
    LLMClient client,
    List<LLMMessage> messages, {
    required ModelConfig modelConfig,
    CancelToken? cancelToken,
    bool? jsonOutput,
  }) async* {
    final stream = await client.stream(
      messages,
      modelConfig: modelConfig,
      jsonOutput: jsonOutput,
      cancelToken: cancelToken,
    );
    await for (final msg in stream) {
      if (cancelToken?.isCancelled ?? false) break;
      final delta = msg.modelMessage?.textOutput;
      if (delta != null && delta.isNotEmpty) {
        yield delta;
      }
    }
  }

  Stream<String> _streamGeminiSse({
    required AiEndpointConfig endpoint,
    required String apiKey,
    required List<LLMMessage> messages,
    required ModelConfig modelConfig,
    CancelToken? cancelToken,
    required bool disableThinkingForSpeed,
    bool? jsonOutput,
  }) async* {
    final dio = InouLlmClientFactory.createGeminiDio(endpoint)
      ..options.connectTimeout = connectTimeout;
    final model = modelConfig.model;
    final url =
        '${InouLlmClientFactory.defaultGeminiOrigin}/v1beta/models/$model:streamGenerateContent?alt=sse';

    Future<Response<ResponseBody>> sendRequest({required bool includeThinking}) {
      final body = _buildGeminiBody(
        messages,
        endpoint: endpoint,
        modelConfig: modelConfig,
        disableThinkingForSpeed: includeThinking,
        jsonOutput: jsonOutput,
      );
      return dio.post<ResponseBody>(
        url,
        data: body,
        options: Options(
          responseType: ResponseType.stream,
          sendTimeout: const Duration(seconds: 45),
          receiveTimeout: const Duration(seconds: 60),
          persistentConnection: !endpoint.disableSocketReuse,
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'text/event-stream',
            'Cache-Control': 'no-cache',
            if (endpoint.disableSocketReuse) 'Connection': 'close',
            'x-goog-api-key': apiKey,
          },
          validateStatus: (_) => true,
        ),
        cancelToken: cancelToken,
      );
    }

    var response = await sendRequest(includeThinking: disableThinkingForSpeed);
    if (response.statusCode != 200) {
      final errBody = await _readStreamBody(response.data);
      final isThinkingRejected =
          response.statusCode == 400 &&
          disableThinkingForSpeed &&
          (errBody.contains('thinkingConfig') ||
              errBody.contains('thinkingBudget') ||
              errBody.contains('Unknown name'));
      if (isThinkingRejected) {
        response = await sendRequest(includeThinking: false);
        if (response.statusCode != 200) {
          final retryErr = await _readStreamBody(response.data);
          throw Exception(
            'Failed to stream from Gemini: ${response.statusCode} ${response.statusMessage} $retryErr',
          );
        }
      } else {
        throw Exception(
          'Failed to stream from Gemini: ${response.statusCode} ${response.statusMessage} $errBody',
        );
      }
    }

    final bodyStream = response.data;
    if (bodyStream == null) return;
    final lines = bodyStream.stream
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    yield* parseGeminiStreamChunks(lines);
  }

  Stream<String> _streamOpenAiSse({
    required AiEndpointConfig endpoint,
    required String apiKey,
    required List<LLMMessage> messages,
    required ModelConfig modelConfig,
    CancelToken? cancelToken,
    bool? jsonOutput,
  }) async* {
    final dio = InouLlmClientFactory.createOpenAiDio(endpoint)
      ..options.connectTimeout = connectTimeout;
    final url = OpenAiUrlNormalizer.chatCompletionsUri(
      endpoint.baseUrl,
    ).toString();

    Future<Response<ResponseBody>> sendOpenAiRequest(bool includeJsonOutput) {
      final body = _buildOpenAiBody(
        messages,
        modelConfig: modelConfig,
        jsonOutput: includeJsonOutput,
      );
      return dio.post<ResponseBody>(
        url,
        data: body,
        options: Options(
          responseType: ResponseType.stream,
          sendTimeout: const Duration(seconds: 45),
          receiveTimeout: const Duration(seconds: 60),
          persistentConnection: !endpoint.disableSocketReuse,
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'text/event-stream',
            'Cache-Control': 'no-cache',
            if (endpoint.disableSocketReuse) 'Connection': 'close',
            'Authorization': 'Bearer $apiKey',
          },
          validateStatus: (_) => true,
        ),
        cancelToken: cancelToken,
      );
    }

    final initialJsonOutput = jsonOutput == true;
    var response = await sendOpenAiRequest(initialJsonOutput);

    if (response.statusCode != 200) {
      final errBody = await _readStreamBody(response.data);
      final isJsonFormatRejected =
          response.statusCode == 400 &&
          initialJsonOutput &&
          (errBody.contains('response_format') ||
              errBody.contains('json_object') ||
              errBody.contains('json_schema'));
      if (isJsonFormatRejected) {
        response = await sendOpenAiRequest(false);
        if (response.statusCode != 200) {
          final retryErr = await _readStreamBody(response.data);
          throw Exception(
            'Failed to stream from OpenAI: ${response.statusCode} ${response.statusMessage} $retryErr',
          );
        }
      } else {
        throw Exception(
          'Failed to stream from OpenAI: ${response.statusCode} ${response.statusMessage} $errBody',
        );
      }
    }

    final contentType = (response.headers.value('content-type') ?? '')
        .toLowerCase();
    if (contentType.contains('application/json')) {
      final rawJson = await _readStreamBody(response.data);
      final extracted = _extractOpenAiNonStreamContent(rawJson);
      if (extracted.isNotEmpty) {
        yield extracted;
      }
      return;
    }

    final bodyStream = response.data;
    if (bodyStream == null) return;
    final lines = bodyStream.stream
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    yield* parseOpenAiSseChunks(lines);
  }

  static String _extractOpenAiNonStreamContent(String rawBody) {
    final trimmed = rawBody.trim();
    if (trimmed.isEmpty) return '';
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map) {
        final choices = decoded['choices'];
        if (choices is List && choices.isNotEmpty) {
          final first = choices.first;
          if (first is Map) {
            final msg = first['message'];
            if (msg is Map) {
              final content = msg['content'];
              if (content is String) return content;
              if (content is List) {
                return content
                    .whereType<Map<Object?, Object?>>()
                    .map((p) => p['text']?.toString() ?? '')
                    .join();
              }
            }
            final delta = first['delta'];
            if (delta is Map && delta['content'] is String) {
              return delta['content'] as String;
            }
          }
        }
      }
    } catch (_) {
      // Fallback below returns raw text when gateway didn't wrap in choices[].
    }
    return trimmed;
  }

  static Future<String> _readStreamBody(ResponseBody? body) async {
    if (body == null) return '';
    try {
      return await utf8.decodeStream(body.stream.cast<List<int>>());
    } catch (_) {
      return '';
    }
  }

  static Map<String, Object?> _buildGeminiBody(
    List<LLMMessage> messages, {
    required AiEndpointConfig endpoint,
    required ModelConfig modelConfig,
    required bool disableThinkingForSpeed,
    bool? jsonOutput,
  }) {
    final systemPrompts = <String>[];
    final contents = <Map<String, Object?>>[];

    for (final msg in messages) {
      if (msg is SystemMessage) {
        if (msg.content.trim().isNotEmpty) {
          systemPrompts.add(msg.content);
        }
      } else if (msg is UserMessage) {
        final parts = <Map<String, Object?>>[];
        for (final part in msg.contents) {
          if (part is TextPart) {
            parts.add({'text': part.text});
          } else if (part is ImagePart) {
            part.requireBase64('BlackboardStreamTransport');
            parts.add({
              'inlineData': {
                'mimeType': part.mimeType,
                'data': part.base64Data,
              },
            });
          }
        }
        contents.add({'role': 'user', 'parts': parts});
      } else if (msg is ModelMessage && (msg.textOutput?.isNotEmpty ?? false)) {
        contents.add({
          'role': 'model',
          'parts': [
            {'text': msg.textOutput!},
          ],
        });
      }
    }

    final generationConfig = <String, Object?>{
      if (modelConfig.temperature != null)
        'temperature': modelConfig.temperature,
      if (modelConfig.maxTokens != null)
        'maxOutputTokens': modelConfig.maxTokens,
      if (modelConfig.topP != null) 'topP': modelConfig.topP,
      if (modelConfig.topK != null) 'topK': modelConfig.topK,
      if (jsonOutput == true) 'responseMimeType': 'application/json',
    };

    if (disableThinkingForSpeed) {
      final lowerModel = modelConfig.model.toLowerCase();
      if (lowerModel.contains('2.5') && lowerModel.contains('flash')) {
        generationConfig['thinkingConfig'] = const {'thinkingBudget': 0};
      } else if (endpoint.supportsThinking && lowerModel.contains('2.5')) {
        generationConfig['thinkingConfig'] = const {'thinkingBudget': 256};
      }
    } else if (modelConfig.extra?['thinkingConfig'] != null) {
      generationConfig['thinkingConfig'] = modelConfig.extra!['thinkingConfig'];
    }

    return <String, Object?>{
      'contents': contents,
      'generationConfig': generationConfig,
      if (systemPrompts.isNotEmpty)
        'systemInstruction': {
          'parts': [
            {'text': systemPrompts.join('\n')},
          ],
        },
    };
  }

  static Map<String, Object?> _buildOpenAiBody(
    List<LLMMessage> messages, {
    required ModelConfig modelConfig,
    bool? jsonOutput,
  }) {
    final finalMessages = <Map<String, Object?>>[];
    for (final msg in messages) {
      if (msg is SystemMessage) {
        finalMessages.add({'role': 'system', 'content': msg.content});
      } else if (msg is UserMessage) {
        final content = <Map<String, Object?>>[];
        for (final part in msg.contents) {
          if (part is TextPart) {
            content.add({'type': 'text', 'text': part.text});
          } else if (part is ImagePart) {
            content.add({
              'type': 'image_url',
              'image_url': {
                'url': part.openAiImageUrl,
                if (part.detail != null) 'detail': part.detail,
              },
            });
          }
        }
        if (content.length == 1 && content.first['type'] == 'text') {
          finalMessages.add({
            'role': 'user',
            'content': content.first['text'],
          });
        } else {
          finalMessages.add({'role': 'user', 'content': content});
        }
      } else if (msg is ModelMessage && msg.textOutput != null) {
        finalMessages.add({'role': 'assistant', 'content': msg.textOutput});
      }
    }

    return <String, Object?>{
      'model': modelConfig.model,
      'messages': finalMessages,
      'stream': true,
      if (modelConfig.temperature != null)
        'temperature': modelConfig.temperature,
      if (modelConfig.maxTokens != null) 'max_tokens': modelConfig.maxTokens,
      if (modelConfig.topP != null) 'top_p': modelConfig.topP,
      if (jsonOutput == true) 'response_format': const {'type': 'json_object'},
    };
  }

  /// Parses Gemini SSE (`data: ...`) lines OR raw chunked JSON array responses
  /// using quote-aware brace tracking so `{` / `}` inside text never splits
  /// an object mid-payload.
  static Stream<String> parseGeminiStreamChunks(Stream<String> lines) async* {
    final jsonBuf = StringBuffer();
    var inObject = false;
    var braceDepth = 0;
    var inString = false;
    var escaped = false;
    final sseBuf = StringBuffer();

    await for (final line in lines) {
      final trimmed = line.trim();
      if (!inObject) {
        if (trimmed.isEmpty) {
          if (sseBuf.isNotEmpty) {
            final text = _decodeGeminiPayload(sseBuf.toString());
            sseBuf.clear();
            if (text.isNotEmpty) yield text;
          }
          continue;
        }
        if (trimmed.startsWith('data:')) {
          final payload = trimmed.substring(5).trim();
          if (payload == '[DONE]') {
            sseBuf.clear();
            continue;
          }
          final directText = _tryDecodeGeminiPayloadStrict(payload);
          if (directText != null) {
            sseBuf.clear();
            if (directText.isNotEmpty) yield directText;
          } else {
            sseBuf.write(payload);
            final bufferedText = _tryDecodeGeminiPayloadStrict(
              sseBuf.toString(),
            );
            if (bufferedText != null) {
              sseBuf.clear();
              if (bufferedText.isNotEmpty) yield bufferedText;
            }
          }
          continue;
        }
        if (trimmed.startsWith('event:') ||
            trimmed.startsWith(':') ||
            trimmed.startsWith('id:') ||
            trimmed.startsWith('retry:')) {
          continue;
        }
        if (trimmed == '[' || trimmed == ']' || trimmed == ',') {
          continue;
        }
      }

      // Raw JSON array / multi-line object fallback with quote awareness
      for (var i = 0; i < line.length; i++) {
        final ch = line[i];
        if (!inObject) {
          if (ch == '{') {
            inObject = true;
            braceDepth = 1;
            inString = false;
            escaped = false;
            jsonBuf.write(ch);
          }
          continue;
        }

        jsonBuf.write(ch);
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
        } else if (ch == '{') {
          braceDepth++;
        } else if (ch == '}') {
          braceDepth--;
          if (braceDepth == 0) {
            final rawObj = jsonBuf.toString();
            jsonBuf.clear();
            inObject = false;
            final text = _decodeGeminiPayload(rawObj);
            if (text.isNotEmpty) yield text;
          }
        }
      }
      if (inObject) {
        jsonBuf.write('\n');
      }
    }

    if (sseBuf.isNotEmpty) {
      final tail = _decodeGeminiPayload(sseBuf.toString());
      if (tail.isNotEmpty) yield tail;
    }
  }

  /// Parses OpenAI-compatible SSE lines (`data: {...}` or `data:{...}`),
  /// ignoring `[DONE]` and `delta.reasoning_content`.
  static Stream<String> parseOpenAiSseChunks(Stream<String> lines) async* {
    await for (final line in lines) {
      final trimmed = line.trim();
      if (!trimmed.startsWith('data:')) continue;
      final payload = trimmed.substring(5).trim();
      if (payload.isEmpty || payload == '[DONE]') continue;
      try {
        final decoded = jsonDecode(payload);
        if (decoded is! Map) continue;
        final choices = decoded['choices'];
        if (choices is! List || choices.isEmpty) continue;
        final first = choices.first;
        if (first is! Map) continue;
        final delta = first['delta'] ?? first['message'];
        if (delta is! Map) continue;
        final content = delta['content'];
        if (content is String && content.isNotEmpty) {
          yield content;
        } else if (content is List) {
          for (final item in content) {
            if (item is Map && item['text'] is String) {
              final t = item['text'] as String;
              if (t.isNotEmpty) yield t;
            }
          }
        }
      } catch (_) {
        // Ignore malformed or partial keepalive chunks cleanly
      }
    }
  }

  /// Incrementally removes `<think>...</think>` blocks across arbitrary chunk
  /// boundaries while streaming non-reasoning text immediately.
  static Stream<String> stripThinkTags(Stream<String> chunks) async* {
    var insideThink = false;
    var pending = '';

    await for (final chunk in chunks) {
      if (chunk.isEmpty) continue;
      pending += chunk;

      while (pending.isNotEmpty) {
        if (!insideThink) {
          final match = _openThinkReg.firstMatch(pending);
          if (match != null) {
            if (match.start > 0) {
              yield pending.substring(0, match.start);
            }
            pending = pending.substring(match.end);
            insideThink = true;
            continue;
          }
          final tailKeep = _matchingTagPrefixLen(pending, '<think>');
          final emitLen = pending.length - tailKeep;
          if (emitLen > 0) {
            yield pending.substring(0, emitLen);
            pending = pending.substring(emitLen);
          }
          break;
        } else {
          final closeMatch = _closeThinkReg.firstMatch(pending);
          if (closeMatch != null) {
            pending = pending.substring(closeMatch.end);
            insideThink = false;
            continue;
          }
          final tailKeep = _matchingTagPrefixLen(pending, '</think>');
          pending = tailKeep == 0
              ? ''
              : pending.substring(pending.length - tailKeep);
          break;
        }
      }
    }

    if (!insideThink && pending.isNotEmpty) {
      yield pending;
    }
  }

  static int _matchingTagPrefixLen(String text, String tag) {
    final maxCheck = math.min(text.length, tag.length - 1);
    for (var len = maxCheck; len >= 1; len--) {
      if (text.substring(text.length - len).toLowerCase() ==
          tag.substring(0, len)) {
        return len;
      }
    }
    return 0;
  }

  static String? _tryDecodeGeminiPayloadStrict(String payload) {
    try {
      final decoded = jsonDecode(payload);
      return _extractGeminiText(decoded);
    } catch (_) {
      return null;
    }
  }

  static String _decodeGeminiPayload(String payload) {
    return _tryDecodeGeminiPayloadStrict(payload) ?? '';
  }

  static String _extractGeminiText(Object? decoded) {
    if (decoded is! Map) return '';
    final candidates = decoded['candidates'];
    if (candidates is! List || candidates.isEmpty) return '';
    final first = candidates.first;
    if (first is! Map) return '';
    final content = first['content'];
    if (content is! Map) return '';
    final parts = content['parts'];
    if (parts is! List) return '';
    final out = StringBuffer();
    for (final part in parts) {
      if (part is! Map) continue;
      if (part['thought'] == true) continue;
      final text = part['text'];
      if (text is String) {
        out.write(text);
      }
    }
    return out.toString();
  }
}
