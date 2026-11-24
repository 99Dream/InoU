import 'dart:typed_data';

import 'package:meta/meta.dart';

import 'ai_endpoint_config.dart';

enum AiRole { system, user, assistant }

@immutable
class AiImageInput {
  const AiImageInput({
    required this.bytes,
    required this.mimeType,
    this.highDetail = true,
  });

  final Uint8List bytes;
  final String mimeType;
  final bool highDetail;
}

@immutable
class AiMessage {
  const AiMessage({
    required this.role,
    required this.text,
    this.images = const [],
  });

  final AiRole role;
  final String text;
  final List<AiImageInput> images;
}

class AiCancelToken {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() {
    _cancelled = true;
  }
}

@immutable
class AiRequest {
  const AiRequest({
    required this.task,
    required this.model,
    required this.messages,
    this.jsonMode = false,
    this.responseSchema,
    this.temperature,
    this.maxOutputTokens,
    this.thinkingBudget,
    this.cacheKey,
  });

  final AiTask task;
  final String model;
  final List<AiMessage> messages;
  final bool jsonMode;
  final Map<String, Object?>? responseSchema;
  final double? temperature;
  final int? maxOutputTokens;
  final int? thinkingBudget;
  final String? cacheKey;
}

@immutable
class AiUsage {
  const AiUsage({
    this.promptTokens,
    this.outputTokens,
    this.thoughtsTokens,
    this.estimated = false,
  });

  final int? promptTokens;
  final int? outputTokens;
  final int? thoughtsTokens;
  final bool estimated;
}

@immutable
class AiResponse {
  const AiResponse({
    required this.text,
    required this.model,
    required this.protocol,
    this.reasoningText,
    this.usage = const AiUsage(),
    this.finishReason,
  });

  final String text;
  final String? reasoningText;
  final String model;
  final AiProtocol protocol;
  final AiUsage usage;
  final String? finishReason;
}

@immutable
class AiChunk {
  const AiChunk({
    required this.deltaText,
    this.deltaReasoning,
    this.usage,
    this.isDone = false,
  });

  final String deltaText;
  final String? deltaReasoning;
  final AiUsage? usage;
  final bool isDone;
}

@immutable
class ProviderCapabilities {
  const ProviderCapabilities({
    required this.vision,
    required this.jsonSchema,
    required this.jsonObject,
    required this.streaming,
    this.contextCache = false,
    this.maxImageBytes = 20 * 1024 * 1024,
  });

  final bool vision;
  final bool jsonSchema;
  final bool jsonObject;
  final bool streaming;
  final bool contextCache;
  final int maxImageBytes;
}

@immutable
class ConnectionTestResult {
  const ConnectionTestResult({
    required this.ok,
    required this.textOk,
    this.visionOk,
    this.message,
  });

  final bool ok;
  final bool textOk;
  final bool? visionOk;
  final String? message;
}

abstract interface class AiProvider {
  ProviderCapabilities get capabilities;

  Future<AiResponse> generate(AiRequest req, {AiCancelToken? cancel});

  Stream<AiChunk> stream(AiRequest req, {AiCancelToken? cancel});

  Future<ConnectionTestResult> testConnection({bool verifyVision = false});

  Future<List<String>> listModels();
}
