import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:dio/dio.dart';
import 'package:inou_domain/inou_domain.dart';
import 'package:meta/meta.dart';

import 'ai_endpoint_config.dart';
import 'ai_provider.dart';
import 'ai_retry_policy.dart';
import 'blackboard_stream_transport.dart';
import 'inou_llm_client.dart';
import 'openai_compat_utils.dart';
import 'prompt_library.dart';

/// Pure-Dart mathematical expression & root verifier used by the Tutor/Coach
/// `run_math_verify` tool so arithmetic and algebraic steps never rely solely
/// on LLM mental calculation.
abstract final class MathVerifyEngine {
  /// 1x1 transparent PNG used for lightweight endpoint vision checks.
  static final Uint8List tinyTestPngBytes = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
  );

  static String _preprocess(String raw) {
    var s = ContentTextUtils.normalizeText(
      raw,
      fullWidthToHalf: true,
      caseSensitive: false,
      ignorePunct: false,
    );
    s = s
        .replaceAll('×', '*')
        .replaceAll('·', '*')
        .replaceAll('÷', '/')
        .replaceAll('−', '-')
        .replaceAll('—', '-')
        .replaceAll('²', '^2')
        .replaceAll('³', '^3')
        .replaceAll('√', 'sqrt')
        .replaceAll(r'\times', '*')
        .replaceAll(r'\div', '/')
        .replaceAll(r'\cdot', '*')
        .replaceAll(r'\sqrt', 'sqrt')
        .replaceAll('{', '(')
        .replaceAll('}', ')')
        .replaceAll(r'$', '')
        .replaceAll(' ', '');
    // Support simple `\frac{a}{b}` after `{}` normalization -> `frac(a)(b)`
    s = s.replaceAllMapped(
      RegExp(r'\\?frac\(([^()]+)\)\(([^()]+)\)'),
      (m) => '((${m.group(1)})/(${m.group(2)}))',
    );
    return s;
  }

  /// Evaluates a numeric arithmetic expression (supports `+ - * / ^ () sqrt abs pi`).
  /// Returns `null` if the expression is malformed or non-numeric.
  static double? evaluateExpression(String expression) {
    final cleaned = _preprocess(expression);
    if (cleaned.isEmpty) return null;
    try {
      final tokens = _tokenize(cleaned);
      if (tokens.isEmpty) return null;
      final parser = _ExprParser(tokens);
      final value = parser.parseExpression();
      if (!parser.isAtEnd || value.isNaN || value.isInfinite) {
        return null;
      }
      return value;
    } catch (_) {
      return null;
    }
  }

  /// Compares two expressions numerically (or checks `lhs = rhs` equality).
  static bool verifyNumericEquality(
    String expressionA,
    String expressionB, {
    double tolerance = 1e-6,
  }) {
    final a = evaluateExpression(expressionA);
    final b = evaluateExpression(expressionB);
    if (a != null && b != null) {
      return (a - b).abs() <= tolerance;
    }
    // Try multi-root comparison separated by comma/semicolon
    final listA = expressionA
        .split(RegExp(r'[,;，；]'))
        .map((e) => evaluateExpression(e.trim()))
        .whereType<double>()
        .toList();
    final listB = expressionB
        .split(RegExp(r'[,;，；]'))
        .map((e) => evaluateExpression(e.trim()))
        .whereType<double>()
        .toList();
    if (listA.isNotEmpty && listA.length == listB.length) {
      listA.sort();
      listB.sort();
      for (var i = 0; i < listA.length; i++) {
        if ((listA[i] - listB[i]).abs() > tolerance) return false;
      }
      return true;
    }
    return false;
  }

  /// Verifies roots of quadratic equation `a*x^2 + b*x + c = 0`.
  static Map<String, Object?> verifyQuadratic(
    double a,
    double b,
    double c,
    List<double> candidateRoots, {
    double tolerance = 1e-5,
  }) {
    final delta = b * b - 4 * a * c;
    final residuals = candidateRoots
        .map((x) => a * x * x + b * x + c)
        .toList(growable: false);
    final allRootsValid =
        residuals.isNotEmpty && residuals.every((r) => r.abs() <= tolerance);
    final expectedRoots = <double>[];
    if (a.abs() > 1e-12 && delta >= 0) {
      final sqrtD = math.sqrt(delta);
      final x1 = (-b - sqrtD) / (2 * a);
      final x2 = (-b + sqrtD) / (2 * a);
      expectedRoots.add(x1);
      if ((x1 - x2).abs() > tolerance) {
        expectedRoots.add(x2);
      }
      expectedRoots.sort();
    }
    return {
      'discriminant': delta,
      'expectedRoots': expectedRoots,
      'candidateRoots': candidateRoots,
      'residuals': residuals,
      'allCandidatesSatisfy': allRootsValid,
    };
  }

  /// Unified entrypoint for agent `run_math_verify` tool calls.
  static Map<String, Object?> verifyRun({
    String? expression,
    String? expected,
    double? a,
    double? b,
    double? c,
    List<double>? roots,
  }) {
    if (a != null && b != null && c != null) {
      final q = verifyQuadratic(a, b, c, roots ?? const []);
      return {'mode': 'quadratic', 'ok': true, ...q};
    }
    if (expression == null || expression.trim().isEmpty) {
      return {'ok': false, 'error': 'Missing expression or quadratic params.'};
    }

    // Support `lhs = rhs` equality check automatically
    if (expression.contains('=') && expected == null) {
      final parts = expression.split('=');
      if (parts.length == 2) {
        final lhs = evaluateExpression(parts[0]);
        final rhs = evaluateExpression(parts[1]);
        final equal = lhs != null && rhs != null && (lhs - rhs).abs() <= 1e-6;
        return {
          'mode': 'equation',
          'ok': lhs != null && rhs != null,
          'lhs': lhs,
          'rhs': rhs,
          'equal': equal,
        };
      }
    }

    final val = evaluateExpression(expression);
    if (val == null) {
      return {
        'mode': 'eval',
        'ok': false,
        'expression': expression,
        'error': 'Unable to parse numeric expression',
      };
    }
    final matchesExpected = expected != null
        ? verifyNumericEquality(expression, expected)
        : null;
    return {
      'mode': 'eval',
      'ok': true,
      'expression': expression,
      'value': val,
      'expected': ?expected,
      'matchesExpected': ?matchesExpected,
    };
  }

  static List<String> _tokenize(String input) {
    final tokens = <String>[];
    var i = 0;
    while (i < input.length) {
      final ch = input[i];
      if (_isDigitOrDot(ch)) {
        final start = i;
        while (i < input.length && _isDigitOrDot(input[i])) {
          i++;
        }
        tokens.add(input.substring(start, i));
        // Insert implicit multiply when followed by identifier or '('
        if (i < input.length && (input[i] == '(' || _isAlpha(input[i]))) {
          tokens.add('*');
        }
        continue;
      }
      if (_isAlpha(ch)) {
        final start = i;
        while (i < input.length && _isAlpha(input[i])) {
          i++;
        }
        tokens.add(input.substring(start, i));
        continue;
      }
      if ('+-*/^()'.contains(ch)) {
        tokens.add(ch);
        i++;
        if (ch == ')' &&
            i < input.length &&
            (input[i] == '(' ||
                _isDigitOrDot(input[i]) ||
                _isAlpha(input[i]))) {
          tokens.add('*');
        }
        continue;
      }
      throw FormatException('Unexpected token "$ch"');
    }
    return tokens;
  }

  static bool _isDigitOrDot(String ch) =>
      (ch.codeUnitAt(0) >= 48 && ch.codeUnitAt(0) <= 57) || ch == '.';

  static bool _isAlpha(String ch) {
    final code = ch.codeUnitAt(0);
    return (code >= 97 && code <= 122) || (code >= 65 && code <= 90);
  }
}

class _ExprParser {
  _ExprParser(this.tokens);

  final List<String> tokens;
  int _pos = 0;

  bool get isAtEnd => _pos >= tokens.length;

  String get _peek => tokens[_pos];

  String _consume() => tokens[_pos++];

  double parseExpression() {
    var value = _parseTerm();
    while (!isAtEnd && (_peek == '+' || _peek == '-')) {
      final op = _consume();
      final right = _parseTerm();
      value = op == '+' ? value + right : value - right;
    }
    return value;
  }

  double _parseTerm() {
    var value = _parseUnary();
    while (!isAtEnd && (_peek == '*' || _peek == '/')) {
      final op = _consume();
      final right = _parseUnary();
      if (op == '*') {
        value *= right;
      } else {
        if (right == 0) {
          throw const FormatException('Division by zero');
        }
        value /= right;
      }
    }
    return value;
  }

  double _parseUnary() {
    if (!isAtEnd && (_peek == '+' || _peek == '-')) {
      final op = _consume();
      final v = _parseUnary();
      return op == '-' ? -v : v;
    }
    return _parsePower();
  }

  double _parsePower() {
    final base = _parsePrimary();
    if (!isAtEnd && _peek == '^') {
      _consume();
      final exp = _parseUnary();
      return math.pow(base, exp).toDouble();
    }
    return base;
  }

  double _parsePrimary() {
    if (isAtEnd) throw const FormatException('Unexpected end');
    final tok = _consume();
    if (tok == '(') {
      final v = parseExpression();
      if (isAtEnd || _consume() != ')') {
        throw const FormatException('Missing closing paren');
      }
      return v;
    }
    if (tok == 'pi') return math.pi;
    if (tok == 'e') return math.e;
    if (tok == 'sqrt' || tok == 'abs') {
      if (isAtEnd || _consume() != '(') {
        throw FormatException('Expected ( after $tok');
      }
      final inner = parseExpression();
      if (isAtEnd || _consume() != ')') {
        throw const FormatException('Missing closing paren');
      }
      if (tok == 'sqrt') {
        if (inner < 0) throw const FormatException('sqrt negative');
        return math.sqrt(inner);
      }
      return inner.abs();
    }
    final numVal = double.tryParse(tok);
    if (numVal == null) {
      throw FormatException('Unknown identifier "$tok"');
    }
    return numVal;
  }
}

/// Detailed connection check output wrapping [ConnectionTestResult] with latency
/// and model telemetry for UI badges.
@immutable
class ConnectionCheckReport {
  const ConnectionCheckReport({
    required this.result,
    required this.latencyMs,
    required this.modelUsed,
    required this.protocol,
  });

  final ConnectionTestResult result;
  final int latencyMs;
  final String modelUsed;
  final AiProtocol protocol;
}

/// Discovered models returned from endpoint `/models` API.
@immutable
class ModelDiscoveryResult {
  const ModelDiscoveryResult({
    required this.ok,
    required this.models,
    this.errorMessage,
  });

  final bool ok;
  final List<String> models;
  final String? errorMessage;
}

/// Tests live Gemini & OpenAI-compatible endpoints (including vision check)
/// and discovers available model IDs.
class InouConnectionService {
  const InouConnectionService({
    this.clientFactory = const InouLlmClientFactory(),
  });

  final InouLlmClientFactory clientFactory;

  Future<ConnectionCheckReport> testConnection(
    AiEndpointConfig config, {
    required String apiKey,
    AiTier tier = AiTier.fast,
    bool verifyVision = false,
    LLMClient? overrideClient,
  }) async {
    final trimmedKey = apiKey.trim();
    if (trimmedKey.isEmpty && overrideClient == null) {
      return ConnectionCheckReport(
        result: const ConnectionTestResult(
          ok: false,
          textOk: false,
          message: '请先填写 API Key 再测试连接',
        ),
        latencyMs: 0,
        modelUsed: '',
        protocol: config.protocol,
      );
    }
    late final String model;
    try {
      model = config.resolveModel(tier);
    } catch (e) {
      return ConnectionCheckReport(
        result: const ConnectionTestResult(
          ok: false,
          textOk: false,
          message: '模型配置不完整，请在「设置 → AI 接口」补全模型名称',
        ),
        latencyMs: 0,
        modelUsed: '',
        protocol: config.protocol,
      );
    }

    final useSse = overrideClient == null && config.preferSse;
    final sw = Stopwatch()..start();
    try {
      bool textOk;
      bool? visionOk;
      if (useSse) {
        const transport = BlackboardStreamTransport(
          timeout: Duration(seconds: 25),
          connectTimeout: Duration(seconds: 15),
        );
        final textBuffer = await transport
            .streamText(
              endpoint: config,
              apiKey: trimmedKey,
              messages: [
                UserMessage([TextPart('请仅回复 OK')]),
              ],
              modelConfig: ModelConfig(
                model: model,
                temperature: 0,
                maxTokens: 24,
              ),
              retryConfig: AiRetryConfig.none,
              disableThinkingForSpeed: true,
            )
            .join();
        textOk = textBuffer.trim().isNotEmpty;
        if (verifyVision && textOk) {
          final visionModel = config.resolveModel(AiTier.balanced);
          final visionBuffer = await transport
              .streamText(
                endpoint: config,
                apiKey: trimmedKey,
                messages: [
                  UserMessage([
                    TextPart('简短描述这张图片的颜色或尺寸'),
                    ImagePart(
                      base64Encode(MathVerifyEngine.tinyTestPngBytes),
                      'image/png',
                      detail: config.sendImageDetail ? 'low' : null,
                    ),
                  ]),
                ],
                modelConfig: ModelConfig(
                  model: visionModel,
                  temperature: 0,
                  maxTokens: 48,
                ),
                retryConfig: AiRetryConfig.none,
                disableThinkingForSpeed: true,
              )
              .join();
          visionOk = visionBuffer.trim().isNotEmpty;
        }
      } else {
        final client =
            overrideClient ??
            clientFactory.createClient(
              config,
              apiKey: trimmedKey,
              timeout: const Duration(seconds: 25),
              connectTimeout: const Duration(seconds: 15),
              retryConfig: AiRetryConfig.none,
            );
        final textReply = await client.generate([
          UserMessage([TextPart('请仅回复 OK')]),
        ], modelConfig: ModelConfig(model: model, temperature: 0, maxTokens: 24));
        textOk = (textReply.textOutput ?? '').trim().isNotEmpty;
        if (verifyVision && textOk) {
          final visionModel = config.resolveModel(AiTier.balanced);
          final vReply = await client.generate(
            [
              UserMessage([
                TextPart('简短描述这张图片的颜色或尺寸'),
                ImagePart(
                  base64Encode(MathVerifyEngine.tinyTestPngBytes),
                  'image/png',
                  detail: config.sendImageDetail ? 'low' : null,
                ),
              ]),
            ],
            modelConfig: ModelConfig(
              model: visionModel,
              temperature: 0,
              maxTokens: 48,
            ),
          );
          visionOk = (vReply.textOutput ?? '').trim().isNotEmpty;
        }
      }
      sw.stop();
      final overallOk = textOk && (visionOk ?? true);
      return ConnectionCheckReport(
        result: ConnectionTestResult(
          ok: overallOk,
          textOk: textOk,
          visionOk: visionOk,
          message: overallOk
              ? '${useSse ? 'SSE 连接成功' : '连接成功'}（${sw.elapsedMilliseconds}ms）'
              : '文本或视觉链路返回空响应',
        ),
        latencyMs: sw.elapsedMilliseconds,
        modelUsed: model,
        protocol: config.protocol,
      );
    } catch (e, st) {
      sw.stop();
      InouDiagnosticsLogger.instance.error(
        'ai.gateway',
        'Endpoint connection test failed (${config.name} / $model)',
        error: e,
        stackTrace: st,
      );
      return ConnectionCheckReport(
        result: ConnectionTestResult(
          ok: false,
          textOk: false,
          visionOk: verifyVision ? false : null,
          message: _formatNetworkError(e),
        ),
        latencyMs: sw.elapsedMilliseconds,
        modelUsed: model,
        protocol: config.protocol,
      );
    }
  }

  Future<ModelDiscoveryResult> listModels(
    AiEndpointConfig config, {
    required String apiKey,
    Dio? dio,
  }) async {
    final trimmedKey = apiKey.trim();
    if (trimmedKey.isEmpty) {
      return const ModelDiscoveryResult(
        ok: false,
        models: [],
        errorMessage: '请先输入 API Key',
      );
    }
    final client =
        dio ??
        Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 12),
            receiveTimeout: const Duration(seconds: 15),
          ),
        );
    try {
      if (config.protocol == AiProtocol.openAiCompatible) {
        final uri = OpenAiUrlNormalizer.modelsUri(config.baseUrl);
        final resp = await client.getUri<Map<String, dynamic>>(
          uri,
          options: Options(
            headers: {
              'Authorization': 'Bearer $trimmedKey',
              ...config.extraHeaders,
            },
          ),
        );
        final rawList = resp.data?['data'] as List<dynamic>? ?? const [];
        final ids =
            rawList
                .whereType<Map<String, dynamic>>()
                .map((e) => e['id'] as String? ?? '')
                .where((id) => id.isNotEmpty)
                .toList()
              ..sort();
        return ModelDiscoveryResult(ok: true, models: ids);
      } else {
        final base = config.baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
        final effectiveBase = base.isEmpty
            ? InouLlmClientFactory.defaultGeminiOrigin
            : base;
        final uri = Uri.parse('$effectiveBase/v1beta/models')
            .replace(queryParameters: {'key': trimmedKey});
        final resp = await client.getUri<Map<String, dynamic>>(
          uri,
          options: Options(headers: config.extraHeaders),
        );
        final rawList = resp.data?['models'] as List<dynamic>? ?? const [];
        final ids =
            rawList
                .whereType<Map<String, dynamic>>()
                .map(
                  (e) =>
                      (e['name'] as String? ?? '').replaceFirst('models/', ''),
                )
                .where((id) => id.isNotEmpty)
                .toList()
              ..sort();
        return ModelDiscoveryResult(ok: true, models: ids);
      }
    } catch (e, st) {
      InouDiagnosticsLogger.instance.error(
        'ai.gateway',
        'listModels failed (${config.name})',
        error: e,
        stackTrace: st,
      );
      return ModelDiscoveryResult(
        ok: false,
        models: const [],
        errorMessage: _formatNetworkError(e),
      );
    }
  }

  String _formatNetworkError(Object error) =>
      AiUserErrorMessages.formatFriendlyNetworkError(error);
}

/// Output from [StructuredJsonCaller].
@immutable
class JsonCallResult {
  const JsonCallResult({
    required this.ok,
    required this.rawText,
    this.decoded,
    this.validationErrors = const [],
    this.repairAttempts = 0,
    this.errorMessage,
    this.technicalError,
    this.isConnectionError = false,
    this.usage,
  });

  final bool ok;
  final String rawText;
  final Object? decoded;
  final List<String> validationErrors;
  final int repairAttempts;
  final String? errorMessage;
  final String? technicalError;
  final bool isConnectionError;
  final ModelUsage? usage;

  Map<String, Object?>? get asMap => decoded is Map<String, Object?>
      ? decoded! as Map<String, Object?>
      : (decoded is Map
            ? (decoded! as Map).map((k, v) => MapEntry(k.toString(), v))
            : null);

  List<Object?>? get asList =>
      decoded is List ? List<Object?>.from(decoded! as List) : null;
}

/// Invokes an [LLMClient] requesting structured JSON output with automatic
/// `<think>`/Markdown fence stripping and bounded `P-03` schema self-repair.
class StructuredJsonCaller {
  const StructuredJsonCaller();

  Future<JsonCallResult> callJson({
    required LLMClient client,
    required AiEndpointConfig endpoint,
    AiTier tier = AiTier.balanced,
    required String systemPrompt,
    required String userPrompt,
    Uint8List? imageBytes,
    String imageMimeType = 'image/jpeg',
    String? imageDetail,
    double temperature = 0.2,
    int maxTokens = 4096,
    int maxRepairRetries = 2,
    List<String> Function(Object decoded)? validator,
    CancelToken? cancelToken,
    AiRetryConfig retryConfig = AiRetryConfig.standard,
    String scene = 'ai',
    void Function(AiRetryEvent)? onRetry,
    String? streamApiKey,
    bool disableThinkingForSpeed = true,
    void Function(int charsReceived)? onStreamProgress,
  }) async {
    if (cancelToken?.isCancelled ?? false) {
      return const JsonCallResult(
        ok: false,
        rawText: '',
        errorMessage: '任务已取消',
      );
    }
    final effectiveClient = RetryingLlmClient.wrap(
      client,
      scene: scene,
      config: retryConfig,
      onRetry: onRetry,
    );
    final candidates = endpoint.resolveModelCandidates(tier);
    final jsonOutput = endpoint.jsonModeStrategy != JsonModeStrategy.promptOnly;
    final parts = <UserContentPart>[
      TextPart(userPrompt),
      if (imageBytes != null)
        ImagePart(
          base64Encode(imageBytes),
          imageMimeType,
          detail: endpoint.sendImageDetail ? (imageDetail ?? 'auto') : null,
        ),
    ];

    final messages = <LLMMessage>[
      if (systemPrompt.trim().isNotEmpty) SystemMessage(systemPrompt),
      UserMessage(parts),
    ];

    for (var idx = 0; idx < candidates.length; idx++) {
      final model = candidates[idx];
      try {
        var attemptRes = await _generateText(
          effectiveClient: effectiveClient,
          endpoint: endpoint,
          messages: messages,
          model: model,
          temperature: temperature,
          maxTokens: maxTokens,
          jsonOutput: jsonOutput,
          streamApiKey: streamApiKey,
          scene: scene,
          retryConfig: retryConfig,
          disableThinkingForSpeed: disableThinkingForSpeed,
          cancelToken: cancelToken,
          onRetry: onRetry,
          onStreamProgress: onStreamProgress,
        );
        var raw = attemptRes.text;
        var repairCount = 0;

        while (true) {
          if (cancelToken?.isCancelled ?? false) {
            return const JsonCallResult(
              ok: false,
              rawText: '',
              errorMessage: '任务已取消',
            );
          }
          final cleaned = AiTextPostProcessor.extractJsonText(raw);
          Object? parsed;
          String? parseError;
          try {
            parsed = jsonDecode(cleaned);
          } catch (e) {
            parseError = e.toString();
          }

          final errors = <String>[
            if (parseError != null) 'JSON parse error: $parseError',
            if (parsed != null && validator != null) ...validator(parsed),
          ];

          if (errors.isEmpty && parsed != null) {
            if (repairCount > 0) {
              AiRetryEventBus.emitRecovered(
                scene: scene,
                maxRetries: maxRepairRetries,
                onRetry: onRetry,
              );
            }
            return JsonCallResult(
              ok: true,
              rawText: cleaned,
              decoded: parsed,
              repairAttempts: repairCount,
              usage: attemptRes.usage,
            );
          }

          if (repairCount >= maxRepairRetries) {
            final detail = errors.join('; ');
            InouDiagnosticsLogger.instance.error(
              'ai.gateway',
              'StructuredJsonCaller validation failed after $repairCount repairs',
              detail: detail,
            );
            if (maxRepairRetries > 0) {
              AiRetryEventBus.emitExhausted(
                scene: scene,
                maxRetries: maxRepairRetries,
                customMessage: AiUserErrorMessages.retriesExhausted(
                  maxRetries: maxRepairRetries,
                ),
                onRetry: onRetry,
              );
            }
            return JsonCallResult(
              ok: false,
              rawText: raw,
              decoded: parsed,
              validationErrors: errors,
              repairAttempts: repairCount,
              errorMessage: maxRepairRetries > 0
                  ? AiUserErrorMessages.retriesExhausted(
                      maxRetries: maxRepairRetries,
                    )
                  : AiUserErrorMessages.networkFailedFallback(),
              technicalError: detail,
              usage: attemptRes.usage,
            );
          }

          repairCount++;
          AiRetryEventBus.emitRetry(
            scene: scene,
            attempt: repairCount,
            maxRetries: maxRepairRetries,
            onRetry: onRetry,
          );
          final repairTemplate = PromptLibrary.get('P-03')
              .render({'errors': errors.join('\n- '), 'brokenJson': raw});
          attemptRes = await _generateText(
            effectiveClient: effectiveClient,
            endpoint: endpoint,
            messages: [
              if (repairTemplate.systemPrompt.isNotEmpty)
                SystemMessage(repairTemplate.systemPrompt),
              UserMessage([TextPart(repairTemplate.userPrompt)]),
            ],
            model: model,
            temperature: 0.1,
            maxTokens: maxTokens,
            jsonOutput: jsonOutput,
            streamApiKey: streamApiKey,
            scene: scene,
            retryConfig: retryConfig,
            disableThinkingForSpeed: true,
            cancelToken: cancelToken,
            onRetry: onRetry,
          );
          raw = attemptRes.text;
        }
      } catch (e, st) {
        if (idx + 1 < candidates.length &&
            AiEndpointConfig.isModelUnavailableError(e)) {
          continue;
        }
        InouDiagnosticsLogger.instance.error(
          'ai.gateway',
          'StructuredJsonCaller request failed (model=$model)',
          error: e,
          stackTrace: st,
        );
        final isCancelled = AiRetryRunner.isCancelled(e, cancelToken);
        final isConnErr = _looksLikeConnectionError(e);
        final userMsg = isCancelled
            ? '任务已取消'
            : AiEndpointConfig.isModelUnavailableError(e)
            ? '当前配置的模型暂不可用，请在「设置 → AI 接口」检查模型名称。'
            : (retryConfig.maxRetries > 0
                  ? AiUserErrorMessages.retriesExhausted(
                      maxRetries: retryConfig.maxRetries,
                    )
                  : AiUserErrorMessages.formatFriendlyNetworkError(e));
        return JsonCallResult(
          ok: false,
          rawText: '',
          errorMessage: userMsg,
          technicalError: e.toString(),
          isConnectionError: isConnErr,
        );
      }
    }
    return const JsonCallResult(
      ok: false,
      rawText: '',
      errorMessage: '未找到可用的配置模型',
    );
  }

  Future<({String text, ModelUsage? usage})> _generateText({
    required LLMClient effectiveClient,
    required AiEndpointConfig endpoint,
    required List<LLMMessage> messages,
    required String model,
    required double temperature,
    required int maxTokens,
    required bool jsonOutput,
    required String? streamApiKey,
    required String scene,
    required AiRetryConfig retryConfig,
    required bool disableThinkingForSpeed,
    CancelToken? cancelToken,
    void Function(AiRetryEvent)? onRetry,
    void Function(int charsReceived)? onStreamProgress,
  }) async {
    final trimmedKey = (streamApiKey ?? '').trim();
    final rawClient = RetryingLlmClient.unwrap(effectiveClient);
    final useSse =
        endpoint.preferSse &&
        trimmedKey.isNotEmpty &&
        (rawClient is OpenAIClient || rawClient is GeminiClient);
    if (!useSse) {
      final reply = await effectiveClient.generate(
        messages,
        modelConfig: ModelConfig(
          model: model,
          temperature: temperature,
          maxTokens: maxTokens,
        ),
        jsonOutput: jsonOutput,
        cancelToken: cancelToken,
      );
      return (text: reply.textOutput ?? '', usage: reply.usage);
    }

    const transport = BlackboardStreamTransport(
      timeout: Duration(seconds: 90),
      connectTimeout: Duration(seconds: 20),
    );
    final modelCfg = ModelConfig(
      model: model,
      temperature: temperature,
      maxTokens: maxTokens,
    );
    final streamed = await AiRetryRunner.run<String>(
      scene: scene,
      config: retryConfig,
      cancelToken: cancelToken,
      onRetry: onRetry,
      loggerTag: 'ai.gateway',
      action: (_) async {
        final buf = StringBuffer();
        var lastNotifyChars = 0;
        var lastNotifyMs = 0;
        final sw = Stopwatch()..start();
        await for (final delta in transport.streamText(
          endpoint: endpoint,
          apiKey: trimmedKey,
          messages: messages,
          modelConfig: modelCfg,
          cancelToken: cancelToken,
          disableThinkingForSpeed: disableThinkingForSpeed,
          jsonOutput: jsonOutput,
          retryConfig: AiRetryConfig.none,
        )) {
          if (cancelToken?.isCancelled ?? false) break;
          buf.write(delta);
          if (onStreamProgress != null) {
            final nowMs = sw.elapsedMilliseconds;
            if (buf.length - lastNotifyChars >= 80 ||
                nowMs - lastNotifyMs >= 250) {
              lastNotifyChars = buf.length;
              lastNotifyMs = nowMs;
              onStreamProgress(buf.length);
            }
          }
        }
        final total = buf.toString();
        if (onStreamProgress != null && total.isNotEmpty) {
          onStreamProgress(total.length);
        }
        return total;
      },
    );
    return (text: streamed, usage: null);
  }

  static bool _looksLikeConnectionError(Object error) {
    if (error is DioException) {
      final code = error.response?.statusCode;
      if (code == 401 || code == 403 || code == 404 || code == 429) {
        return true;
      }
      if (error.type == DioExceptionType.connectionError ||
          error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.receiveTimeout ||
          error.type == DioExceptionType.sendTimeout) {
        return true;
      }
      if (code != null && code >= 500) {
        return true;
      }
      final dioDetail =
          '${error.message ?? ''} ${error.error ?? ''}'.toLowerCase();
      if (_containsConnectionKeywords(dioDetail)) {
        return true;
      }
    }
    return _containsConnectionKeywords(error.toString().toLowerCase());
  }

  static bool _containsConnectionKeywords(String msg) {
    return msg.contains('401') ||
        msg.contains('403') ||
        msg.contains('429') ||
        msg.contains('500') ||
        msg.contains('502') ||
        msg.contains('503') ||
        msg.contains('504') ||
        msg.contains('status code') ||
        msg.contains('unauthorized') ||
        msg.contains('socketexception') ||
        msg.contains('httpexception') ||
        msg.contains('handshakeexception') ||
        msg.contains('failed host lookup') ||
        msg.contains('connection refused') ||
        msg.contains('connection reset') ||
        msg.contains('connection abort') ||
        msg.contains('software caused') ||
        msg.contains('connection closed') ||
        msg.contains('broken pipe') ||
        msg.contains('eof') ||
        msg.contains('timed out');
  }
}
