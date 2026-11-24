import 'package:meta/meta.dart';

/// Supported AI wire protocols.
enum AiProtocol {
  gemini('gemini', 'Google Gemini 原生'),
  openAiCompatible('openai_compatible', 'OpenAI 兼容格式');

  const AiProtocol(this.code, this.label);

  final String code;
  final String label;

  static AiProtocol fromCode(String code) {
    return AiProtocol.values.firstWhere(
      (p) => p.code == code,
      orElse: () => AiProtocol.openAiCompatible,
    );
  }
}

/// Model capability tiers mapped per endpoint configuration.
enum AiTier { fast, balanced, strong }

/// High-level AI task identifiers across InoU pipelines.
enum AiTask {
  layoutAnalysis,
  questionStructuring,
  answerMatching,
  solve,
  selfCheck,
  judgeHandwriting,
  tutorChat,
  report,
  generateQuestions,
  tempAsk,
}

/// Structured-output negotiation mode, especially for OpenAI-compatible services.
enum JsonModeStrategy {
  auto('auto'),
  jsonSchema('json_schema'),
  jsonObject('json_object'),
  promptOnly('prompt_only');

  const JsonModeStrategy(this.code);
  final String code;

  static JsonModeStrategy fromCode(String code) {
    return JsonModeStrategy.values.firstWhere(
      (j) => j.code == code,
      orElse: () => JsonModeStrategy.auto,
    );
  }
}

/// Expected normalized bounding box coordinate order returned by vision models.
enum BboxOrder {
  yxyx1000('yxyx1000'),
  xyxy1000('xyxy1000');

  const BboxOrder(this.code);
  final String code;

  static BboxOrder fromCode(String code) {
    return BboxOrder.values.firstWhere(
      (b) => b.code == code,
      orElse: () => BboxOrder.yxyx1000,
    );
  }
}

/// Non-secret configuration for an AI endpoint profile.
/// The matching API key is stored separately in secure storage keyed by [id].
@immutable
class AiEndpointConfig {
  const AiEndpointConfig({
    required this.id,
    required this.name,
    required this.protocol,
    required this.baseUrl,
    required this.tierModels,
    this.jsonModeStrategy = JsonModeStrategy.auto,
    this.bboxOrder = BboxOrder.yxyx1000,
    this.sendImageDetail = true,
    this.supportsThinking = false,
    this.supportsStreamUsage = true,
    this.extraHeaders = const {},
  });

  factory AiEndpointConfig.fromJson(Map<String, Object?> json) {
    final rawTiers = json['tierModels'] as Map<String, Object?>? ?? const {};
    final tiers = <AiTier, String>{};
    for (final tier in AiTier.values) {
      final val = rawTiers[tier.name];
      if (val is String && val.trim().isNotEmpty) {
        tiers[tier] = val.trim();
      }
    }
    return AiEndpointConfig(
      id: json['id'] as String? ?? 'custom_endpoint',
      name: json['name'] as String? ?? '自定义端点',
      protocol: AiProtocol.fromCode(
        json['protocol'] as String? ?? 'openai_compatible',
      ),
      baseUrl: json['baseUrl'] as String? ?? '',
      tierModels: tiers,
      jsonModeStrategy: JsonModeStrategy.fromCode(
        json['jsonModeStrategy'] as String? ?? 'auto',
      ),
      bboxOrder: BboxOrder.fromCode(json['bboxOrder'] as String? ?? 'yxyx1000'),
      sendImageDetail: (json['sendImageDetail'] as bool?) ?? true,
      supportsThinking: (json['supportsThinking'] as bool?) ?? false,
      supportsStreamUsage: (json['supportsStreamUsage'] as bool?) ?? true,
      extraHeaders: (json['extraHeaders'] as Map<String, Object?>? ?? const {})
          .map((k, v) => MapEntry(k, v.toString())),
    );
  }

  final String id;
  final String name;
  final AiProtocol protocol;
  final String baseUrl;
  final Map<AiTier, String> tierModels;
  final JsonModeStrategy jsonModeStrategy;
  final BboxOrder bboxOrder;
  final bool sendImageDetail;
  final bool supportsThinking;
  final bool supportsStreamUsage;
  final Map<String, String> extraHeaders;

  /// Resolves a model for [tier], falling back to balanced/fast/strong if
  /// the user configured a single primary multimodal model.
  String resolveModel(AiTier tier) {
    final direct = tierModels[tier];
    if (direct != null && direct.trim().isNotEmpty) return direct.trim();
    for (final fallback in [AiTier.balanced, AiTier.strong, AiTier.fast]) {
      final candidate = tierModels[fallback];
      if (candidate != null && candidate.trim().isNotEmpty) {
        return candidate.trim();
      }
    }
    throw StateError('No model configured for endpoint "$name" ($id).');
  }

  /// Ordered, deduplicated list of configured models starting with [tier],
  /// used to fall back automatically when an auxiliary tier preset (e.g., an
  /// unconfigured `strong` model) rejects requests with `model_not_found`.
  List<String> resolveModelCandidates(AiTier tier) {
    final out = <String>[];
    for (final t in [tier, AiTier.balanced, AiTier.fast, AiTier.strong]) {
      final m = tierModels[t]?.trim();
      if (m != null && m.isNotEmpty && !out.contains(m)) {
        out.add(m);
      }
    }
    if (out.isEmpty) {
      throw StateError('No model configured for endpoint "$name" ($id).');
    }
    return out;
  }

  /// Detects upstream relay/API errors indicating the requested model name is
  /// absent on the provider channel so callers can retry with another tier.
  static bool isModelUnavailableError(Object error) {
    final msg = error.toString().toLowerCase();
    return msg.contains('model_not_found') ||
        msg.contains('no available channel') ||
        msg.contains('does not exist') ||
        msg.contains('unknown model') ||
        msg.contains('model is not supported') ||
        msg.contains('unsupported model');
  }

  AiEndpointConfig copyWith({
    String? id,
    String? name,
    AiProtocol? protocol,
    String? baseUrl,
    Map<AiTier, String>? tierModels,
    JsonModeStrategy? jsonModeStrategy,
    BboxOrder? bboxOrder,
    bool? sendImageDetail,
    bool? supportsThinking,
    bool? supportsStreamUsage,
    Map<String, String>? extraHeaders,
  }) {
    return AiEndpointConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      protocol: protocol ?? this.protocol,
      baseUrl: baseUrl ?? this.baseUrl,
      tierModels: tierModels ?? this.tierModels,
      jsonModeStrategy: jsonModeStrategy ?? this.jsonModeStrategy,
      bboxOrder: bboxOrder ?? this.bboxOrder,
      sendImageDetail: sendImageDetail ?? this.sendImageDetail,
      supportsThinking: supportsThinking ?? this.supportsThinking,
      supportsStreamUsage: supportsStreamUsage ?? this.supportsStreamUsage,
      extraHeaders: extraHeaders ?? this.extraHeaders,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'protocol': protocol.code,
    'baseUrl': baseUrl,
    'tierModels': tierModels.map((k, v) => MapEntry(k.name, v)),
    'jsonModeStrategy': jsonModeStrategy.code,
    'bboxOrder': bboxOrder.code,
    'sendImageDetail': sendImageDetail,
    'supportsThinking': supportsThinking,
    'supportsStreamUsage': supportsStreamUsage,
    if (extraHeaders.isNotEmpty) 'extraHeaders': extraHeaders,
  };
}

/// Built-in non-secret endpoint presets for onboarding & settings.
abstract final class AiEndpointPresets {
  static List<AiEndpointConfig> defaults() => const [
    AiEndpointConfig(
      id: 'preset_gemini',
      name: 'Google Gemini（原生）',
      protocol: AiProtocol.gemini,
      baseUrl: 'https://generativelanguage.googleapis.com',
      tierModels: {
        AiTier.fast: 'gemini-2.5-flash',
        AiTier.balanced: 'gemini-2.5-flash',
        AiTier.strong: 'gemini-2.5-pro',
      },
      supportsThinking: true,
    ),
    AiEndpointConfig(
      id: 'preset_dashscope',
      name: '阿里云百炼 DashScope',
      protocol: AiProtocol.openAiCompatible,
      baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
      tierModels: {
        AiTier.fast: 'qwen-vl-plus',
        AiTier.balanced: 'qwen-vl-max-latest',
        AiTier.strong: 'qwen-max',
      },
      jsonModeStrategy: JsonModeStrategy.jsonObject,
      bboxOrder: BboxOrder.xyxy1000,
    ),
    AiEndpointConfig(
      id: 'preset_zhipu',
      name: '智谱 BigModel',
      protocol: AiProtocol.openAiCompatible,
      baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
      tierModels: {
        AiTier.fast: 'glm-4v-flash',
        AiTier.balanced: 'glm-4v-plus',
        AiTier.strong: 'glm-4-long',
      },
      jsonModeStrategy: JsonModeStrategy.jsonObject,
      bboxOrder: BboxOrder.xyxy1000,
      sendImageDetail: false,
    ),
    AiEndpointConfig(
      id: 'preset_doubao',
      name: '火山引擎豆包',
      protocol: AiProtocol.openAiCompatible,
      baseUrl: 'https://ark.cn-beijing.volces.com/api/v3',
      tierModels: {
        AiTier.fast: 'doubao-1.5-lite',
        AiTier.balanced: 'doubao-1.5-vision-pro',
        AiTier.strong: 'doubao-1.5-thinking-pro',
      },
      jsonModeStrategy: JsonModeStrategy.promptOnly,
      bboxOrder: BboxOrder.xyxy1000,
    ),
    AiEndpointConfig(
      id: 'preset_openai',
      name: 'OpenAI 官方',
      protocol: AiProtocol.openAiCompatible,
      baseUrl: 'https://api.openai.com/v1',
      tierModels: {
        AiTier.fast: 'gpt-4o-mini',
        AiTier.balanced: 'gpt-4o',
        AiTier.strong: 'gpt-4o',
      },
      jsonModeStrategy: JsonModeStrategy.jsonSchema,
    ),
    AiEndpointConfig(
      id: 'preset_deepseek',
      name: 'DeepSeek',
      protocol: AiProtocol.openAiCompatible,
      baseUrl: 'https://api.deepseek.com/v1',
      tierModels: {
        AiTier.fast: 'deepseek-chat',
        AiTier.balanced: 'deepseek-chat',
        AiTier.strong: 'deepseek-reasoner',
      },
      jsonModeStrategy: JsonModeStrategy.jsonObject,
    ),
    AiEndpointConfig(
      id: 'preset_ollama',
      name: 'Ollama 本地服务',
      protocol: AiProtocol.openAiCompatible,
      baseUrl: 'http://127.0.0.1:11434/v1',
      tierModels: {
        AiTier.fast: 'qwen2.5vl:7b',
        AiTier.balanced: 'qwen2.5vl:7b',
        AiTier.strong: 'qwen2.5:14b',
      },
      jsonModeStrategy: JsonModeStrategy.promptOnly,
      bboxOrder: BboxOrder.xyxy1000,
    ),
  ];
}
