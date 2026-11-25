import 'dart:async';

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:dio/dio.dart';
import 'package:inou_domain/inou_domain.dart';
import 'package:meta/meta.dart';

import 'ai_endpoint_config.dart';

/// Configuration controlling automatic retries for failed AI model calls.
@immutable
class AiRetryConfig {
  const AiRetryConfig({
    this.maxRetries = 2,
    this.baseDelay = const Duration(milliseconds: 400),
  });

  final int maxRetries;
  final Duration baseDelay;

  static const AiRetryConfig standard = AiRetryConfig();
  static const AiRetryConfig none = AiRetryConfig(
    maxRetries: 0,
    baseDelay: Duration.zero,
  );
}

/// Event broadcast when an AI invocation enters auto-retry, recovers, or
/// exhausts all configured retries.
@immutable
class AiRetryEvent {
  const AiRetryEvent({
    required this.scene,
    required this.attempt,
    required this.maxRetries,
    required this.statusMessage,
    this.exhausted = false,
    this.recovered = false,
  });

  final String scene;
  final int attempt;
  final int maxRetries;
  final String statusMessage;
  final bool exhausted;
  final bool recovered;
}

/// Standardized Chinese user-facing messages that avoid leaking raw exceptions,
/// HTTP trace payloads, or stack traces into UI widgets.
abstract final class AiUserErrorMessages {
  static String retrying({required int attempt, required int maxRetries}) =>
      'AI 回答出错，正在自动重试（第 $attempt/$maxRetries 次）…';

  static String retriesExhausted({int maxRetries = 2}) =>
      'AI 已自动重试 $maxRetries 次仍未成功，请稍后再试或检查「设置 → AI 接口」配置。';

  static String fallbackNotice({int maxRetries = 2}) =>
      'AI 回答出错，已自动重试 $maxRetries 次仍未成功，已为您切换本地兜底提示，请稍后再试或检查「设置 → AI 接口」配置。';

  static String judgeFallbackNotice({int maxRetries = 2}) =>
      'AI 批改已自动重试 $maxRetries 次仍未成功，已切换本地兜底模式';

  static String solveRetryHint({int maxRetries = 2}) =>
      'AI 独立求解已自动重试 $maxRetries 次仍未成功，已保留识别题干，可稍后点击「重新求解」再试。';

  static String blackboardFallbackSpoken({int maxRetries = 2}) =>
      'AI 板书已自动重试 $maxRetries 次仍未成功，先为你展示本地兜底讲解，稍后可点击重新生成～';

  static String captureFailedFallback({int maxRetries = 2}) =>
      'AI 识题已自动重试 $maxRetries 次仍未成功，请稍后再试或检查网络与「设置 → AI 接口」配置。';

  static String photoSearchFailedFallback({int maxRetries = 2}) =>
      '拍照搜题已自动重试 $maxRetries 次仍未成功，请稍后再试或检查网络与「设置 → AI 接口」配置。';

  static String reportFailedFallback({int maxRetries = 2}) =>
      'AI 诊断报告已自动重试 $maxRetries 次仍未成功，已为您展示本地统计兜底报告，请稍后再试。';

  static String drillFailedFallback({int maxRetries = 2}) =>
      'AI 出题已自动重试 $maxRetries 次仍未成功，请稍后再试或检查「设置 → AI 接口」配置。';

  static String networkFailedFallback() =>
      '网络请求失败，请检查网络连接或「设置 → AI 接口」配置。';

  /// Maps a network/HTTP error to a concise user-friendly Chinese hint without
  /// leaking raw URLs, headers, stack frames, or gateway error JSON.
  static String formatFriendlyNetworkError(Object error) {
    if (error is DioException) {
      final status = error.response?.statusCode;
      if (status == 401 || status == 403) {
        return '接口鉴权失败（HTTP $status），请检查 API Key 是否正确';
      }
      if (status == 404) {
        return '接口地址不可用（HTTP 404），请检查网关地址与模型名称';
      }
      if (status == 429) {
        return '请求过于频繁（HTTP 429），请稍后再试';
      }
      if (status != null && status >= 500) {
        return 'AI 服务端暂时异常（HTTP $status），请稍后重试';
      }
      return switch (error.type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.sendTimeout ||
        DioExceptionType.receiveTimeout => '请求超时，请检查网络连接或网关响应速度',
        DioExceptionType.connectionError => '无法连接至接口服务，请检查网络或网关地址',
        DioExceptionType.cancel => '请求已取消',
        _ => networkFailedFallback(),
      };
    }
    return networkFailedFallback();
  }
}

/// Global broadcast bus for UI surfaces (banners, Copilot drawer, progress) to
/// reflect live AI auto-retry states.
class AiRetryEventBus {
  AiRetryEventBus._();

  static final AiRetryEventBus instance = AiRetryEventBus._();

  final StreamController<AiRetryEvent> _controller =
      StreamController<AiRetryEvent>.broadcast();

  Stream<AiRetryEvent> get stream => _controller.stream;

  void emit(AiRetryEvent event) {
    if (!_controller.isClosed) {
      _controller.add(event);
    }
  }

  static void emitRetry({
    required String scene,
    required int attempt,
    required int maxRetries,
    void Function(AiRetryEvent)? onRetry,
  }) {
    final ev = AiRetryEvent(
      scene: scene,
      attempt: attempt,
      maxRetries: maxRetries,
      statusMessage: AiUserErrorMessages.retrying(
        attempt: attempt,
        maxRetries: maxRetries,
      ),
    );
    instance.emit(ev);
    onRetry?.call(ev);
  }

  static void emitExhausted({
    required String scene,
    required int maxRetries,
    String? customMessage,
    void Function(AiRetryEvent)? onRetry,
  }) {
    final ev = AiRetryEvent(
      scene: scene,
      attempt: maxRetries,
      maxRetries: maxRetries,
      exhausted: true,
      statusMessage:
          customMessage ??
          AiUserErrorMessages.retriesExhausted(maxRetries: maxRetries),
    );
    instance.emit(ev);
    onRetry?.call(ev);
  }

  static void emitRecovered({
    required String scene,
    required int maxRetries,
    void Function(AiRetryEvent)? onRetry,
  }) {
    final ev = AiRetryEvent(
      scene: scene,
      attempt: 0,
      maxRetries: maxRetries,
      recovered: true,
      statusMessage: '',
    );
    instance.emit(ev);
    onRetry?.call(ev);
  }
}

/// Shared execution runner with bounded backoff retries, cancellation support,
/// and diagnostics logging.
abstract final class AiRetryRunner {
  static bool isCancelled(Object error, CancelToken? cancelToken) {
    if (cancelToken?.isCancelled ?? false) return true;
    return error is DioException && error.type == DioExceptionType.cancel;
  }

  static bool shouldRetry(Object error, {CancelToken? cancelToken}) {
    if (isCancelled(error, cancelToken)) return false;
    if (AiEndpointConfig.isModelUnavailableError(error)) return false;
    return true;
  }

  static Future<void> backoff({
    required int failedAttemptIndex,
    required AiRetryConfig config,
    CancelToken? cancelToken,
  }) async {
    if (config.baseDelay <= Duration.zero) return;
    final delay = Duration(
      milliseconds: config.baseDelay.inMilliseconds * (failedAttemptIndex + 1),
    );
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
    if (cancelToken?.isCancelled ?? false) {
      throw DioException.requestCancelled(
        requestOptions: RequestOptions(),
        reason: 'cancelled',
      );
    }
  }

  static Future<T> run<T>({
    required String scene,
    required Future<T> Function(int attemptIndex) action,
    AiRetryConfig config = AiRetryConfig.standard,
    CancelToken? cancelToken,
    void Function(AiRetryEvent)? onRetry,
    bool Function(T result)? retryIfResult,
    String? exhaustedMessage,
    String loggerTag = 'ai.retry',
  }) async {
    for (var attempt = 0; attempt <= config.maxRetries; attempt++) {
      if (cancelToken?.isCancelled ?? false) {
        throw DioException.requestCancelled(
          requestOptions: RequestOptions(),
          reason: 'cancelled',
        );
      }
      try {
        final result = await action(attempt);
        final needsResultRetry = retryIfResult?.call(result) ?? false;
        if (!needsResultRetry) {
          if (attempt > 0) {
            AiRetryEventBus.emitRecovered(
              scene: scene,
              maxRetries: config.maxRetries,
              onRetry: onRetry,
            );
          }
          return result;
        }
        if (attempt >= config.maxRetries) {
          if (config.maxRetries > 0) {
            InouDiagnosticsLogger.instance.warn(
              loggerTag,
              'AI call returned invalid/empty result after ${config.maxRetries} retries (scene=$scene)',
            );
            AiRetryEventBus.emitExhausted(
              scene: scene,
              maxRetries: config.maxRetries,
              customMessage: exhaustedMessage,
              onRetry: onRetry,
            );
          }
          return result;
        }
        final nextRetry = attempt + 1;
        InouDiagnosticsLogger.instance.warn(
          loggerTag,
          'AI result invalid/empty, scheduling retry $nextRetry/${config.maxRetries} (scene=$scene)',
        );
        AiRetryEventBus.emitRetry(
          scene: scene,
          attempt: nextRetry,
          maxRetries: config.maxRetries,
          onRetry: onRetry,
        );
        await backoff(
          failedAttemptIndex: attempt,
          config: config,
          cancelToken: cancelToken,
        );
      } catch (e, st) {
        final canRetry =
            attempt < config.maxRetries &&
            shouldRetry(e, cancelToken: cancelToken);
        if (!canRetry) {
          if (config.maxRetries > 0 && shouldRetry(e, cancelToken: cancelToken)) {
            InouDiagnosticsLogger.instance.error(
              loggerTag,
              'AI call exhausted all ${config.maxRetries} retries (scene=$scene)',
              error: e,
              stackTrace: st,
            );
            AiRetryEventBus.emitExhausted(
              scene: scene,
              maxRetries: config.maxRetries,
              customMessage: exhaustedMessage,
              onRetry: onRetry,
            );
          }
          rethrow;
        }
        final nextRetry = attempt + 1;
        InouDiagnosticsLogger.instance.warn(
          loggerTag,
          'AI attempt failed, retrying $nextRetry/${config.maxRetries} (scene=$scene)',
          error: e,
          stackTrace: st,
        );
        AiRetryEventBus.emitRetry(
          scene: scene,
          attempt: nextRetry,
          maxRetries: config.maxRetries,
          onRetry: onRetry,
        );
        await backoff(
          failedAttemptIndex: attempt,
          config: config,
          cancelToken: cancelToken,
        );
      }
    }
    throw StateError('Unreachable retry loop end');
  }
}

/// Decorator around [LLMClient] that automatically retries transient errors
/// and logs raw exceptions to [InouDiagnosticsLogger].
class RetryingLlmClient implements LLMClient {
  const RetryingLlmClient(
    this.inner, {
    this.scene = 'ai',
    this.config = AiRetryConfig.standard,
    this.onRetry,
  });

  final LLMClient inner;
  final String scene;
  final AiRetryConfig config;
  final void Function(AiRetryEvent)? onRetry;

  /// Wraps [client] without double-wrapping existing [RetryingLlmClient]
  /// decorators unless custom callbacks/config are requested.
  static LLMClient wrap(
    LLMClient client, {
    String scene = 'ai',
    AiRetryConfig config = AiRetryConfig.standard,
    void Function(AiRetryEvent)? onRetry,
  }) {
    if (config.maxRetries <= 0) {
      return unwrap(client);
    }
    if (client is RetryingLlmClient) {
      if (client.config.maxRetries == config.maxRetries &&
          client.config.baseDelay == config.baseDelay &&
          onRetry == null) {
        return client;
      }
      return RetryingLlmClient(
        unwrap(client),
        scene: scene,
        config: config,
        onRetry: onRetry ?? client.onRetry,
      );
    }
    return RetryingLlmClient(
      client,
      scene: scene,
      config: config,
      onRetry: onRetry,
    );
  }

  /// Extracts the underlying raw [LLMClient] when callers run outer retry loops.
  static LLMClient unwrap(LLMClient client) {
    var cur = client;
    while (cur is RetryingLlmClient) {
      cur = cur.inner;
    }
    return cur;
  }

  @override
  Future<ModelMessage> generate(
    List<LLMMessage> messages, {
    List<Tool>? tools,
    ToolChoice? toolChoice,
    required ModelConfig modelConfig,
    bool? jsonOutput,
    CancelToken? cancelToken,
  }) {
    final rawClient = unwrap(inner);
    if (config.maxRetries <= 0) {
      return rawClient.generate(
        messages,
        tools: tools,
        toolChoice: toolChoice,
        modelConfig: modelConfig,
        jsonOutput: jsonOutput,
        cancelToken: cancelToken,
      );
    }
    return AiRetryRunner.run(
      scene: scene,
      config: config,
      cancelToken: cancelToken,
      onRetry: onRetry,
      action: (_) => rawClient.generate(
        messages,
        tools: tools,
        toolChoice: toolChoice,
        modelConfig: modelConfig,
        jsonOutput: jsonOutput,
        cancelToken: cancelToken,
      ),
    );
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
    final rawClient = unwrap(inner);
    if (config.maxRetries <= 0) {
      return rawClient.stream(
        messages,
        tools: tools,
        toolChoice: toolChoice,
        modelConfig: modelConfig,
        jsonOutput: jsonOutput,
        cancelToken: cancelToken,
      );
    }
    return _streamWithRetry(
      rawClient,
      messages,
      tools: tools,
      toolChoice: toolChoice,
      modelConfig: modelConfig,
      jsonOutput: jsonOutput,
      cancelToken: cancelToken,
    );
  }

  Stream<StreamingMessage> _streamWithRetry(
    LLMClient rawClient,
    List<LLMMessage> messages, {
    List<Tool>? tools,
    ToolChoice? toolChoice,
    required ModelConfig modelConfig,
    bool? jsonOutput,
    CancelToken? cancelToken,
  }) async* {
    for (var attempt = 0; attempt <= config.maxRetries; attempt++) {
      if (cancelToken?.isCancelled ?? false) return;
      var emittedChunk = false;
      try {
        final s = await rawClient.stream(
          messages,
          tools: tools,
          toolChoice: toolChoice,
          modelConfig: modelConfig,
          jsonOutput: jsonOutput,
          cancelToken: cancelToken,
        );
        await for (final chunk in s) {
          if ((chunk.modelMessage?.textOutput ?? '').isNotEmpty ||
              (chunk.modelMessage?.functionCalls.isNotEmpty ?? false)) {
            emittedChunk = true;
          }
          yield chunk;
        }
        if (attempt > 0) {
          AiRetryEventBus.emitRecovered(
            scene: scene,
            maxRetries: config.maxRetries,
            onRetry: onRetry,
          );
        }
        return;
      } catch (e, st) {
        final canRetry =
            !emittedChunk &&
            attempt < config.maxRetries &&
            AiRetryRunner.shouldRetry(e, cancelToken: cancelToken);
        if (!canRetry) {
          if (AiRetryRunner.shouldRetry(e, cancelToken: cancelToken)) {
            InouDiagnosticsLogger.instance.error(
              'ai.retry',
              'AI stream exhausted retries (scene=$scene)',
              error: e,
              stackTrace: st,
            );
            AiRetryEventBus.emitExhausted(
              scene: scene,
              maxRetries: config.maxRetries,
              onRetry: onRetry,
            );
          }
          rethrow;
        }
        final nextRetry = attempt + 1;
        InouDiagnosticsLogger.instance.warn(
          'ai.retry',
          'AI stream attempt failed, retrying $nextRetry/${config.maxRetries} (scene=$scene)',
          error: e,
          stackTrace: st,
        );
        AiRetryEventBus.emitRetry(
          scene: scene,
          attempt: nextRetry,
          maxRetries: config.maxRetries,
          onRetry: onRetry,
        );
        await AiRetryRunner.backoff(
          failedAttemptIndex: attempt,
          config: config,
          cancelToken: cancelToken,
        );
      }
    }
  }
}

/// Runs [worker] across [items] using at most [maxConcurrency] simultaneous
/// operations while preserving item ordering and honoring [cancelToken].
Future<List<R>> runBoundedPool<T, R>(
  List<T> items, {
  required Future<R> Function(int index, T item) worker,
  int maxConcurrency = 3,
  CancelToken? cancelToken,
}) async {
  if (items.isEmpty) return <R>[];
  final limit = maxConcurrency < 1
      ? 1
      : (maxConcurrency > items.length ? items.length : maxConcurrency);
  final results = List<R?>.filled(items.length, null);
  var nextIndex = 0;

  Future<void> runWorker() async {
    while (true) {
      if (cancelToken?.isCancelled ?? false) return;
      final current = nextIndex;
      if (current >= items.length) return;
      nextIndex++;
      results[current] = await worker(current, items[current]);
    }
  }

  await Future.wait(
    List<Future<void>>.generate(limit, (_) => runWorker(), growable: false),
  );
  if (cancelToken?.isCancelled ?? false) {
    throw DioException.requestCancelled(
      requestOptions: RequestOptions(),
      reason: 'cancelled',
    );
  }
  return List<R>.generate(items.length, (i) => results[i] as R, growable: false);
}
