/// Helpers shared by OpenAI-compatible & Gemini adapters.
abstract final class OpenAiUrlNormalizer {
  /// Returns the normalized base URL suitable for `OpenAIClient(baseUrl: ...)`
  /// (without trailing slashes and without `/chat/completions`).
  static String apiBaseUrl(String rawBaseUrl) {
    final trimmed = rawBaseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (trimmed.isEmpty) {
      throw ArgumentError('Base URL must not be empty.');
    }
    if (trimmed.endsWith('/chat/completions')) {
      return trimmed.substring(0, trimmed.length - '/chat/completions'.length);
    }
    return trimmed;
  }

  /// Builds the `/chat/completions` URL tolerating common user inputs.
  static Uri chatCompletionsUri(String rawBaseUrl) {
    return Uri.parse('${apiBaseUrl(rawBaseUrl)}/chat/completions');
  }

  static Uri modelsUri(String rawBaseUrl) {
    return Uri.parse('${apiBaseUrl(rawBaseUrl)}/models');
  }
}

/// Cleans reasoning blocks and Markdown fences before JSON parsing or
/// tutor emotion-tag extraction.
abstract final class AiTextPostProcessor {
  static final _thinkTagPattern = RegExp(
    r'<think>[\s\S]*?</think>',
    caseSensitive: false,
  );
  static final _fenceAnywherePattern = RegExp(
    r'```(?:json)?\s*\r?\n?([\s\S]*?)\r?\n?```',
    caseSensitive: false,
  );

  /// Strips `<think>...</think>` blocks and Markdown ```json fences (including
  /// when surrounded by explanatory prose), or slices outermost `{...}` / `[...]`.
  static String extractJsonText(String raw) {
    var cleaned = raw.replaceAll(_thinkTagPattern, '').trim();
    final fenceMatch = _fenceAnywherePattern.firstMatch(cleaned);
    if (fenceMatch != null) {
      cleaned = fenceMatch.group(1)!.trim();
    }
    if (cleaned.startsWith('{') || cleaned.startsWith('[')) {
      return cleaned;
    }
    final objStart = cleaned.indexOf('{');
    final objEnd = cleaned.lastIndexOf('}');
    final arrStart = cleaned.indexOf('[');
    final arrEnd = cleaned.lastIndexOf(']');
    if (objStart >= 0 &&
        objEnd > objStart &&
        (arrStart < 0 || objStart < arrStart)) {
      return cleaned.substring(objStart, objEnd + 1).trim();
    }
    if (arrStart >= 0 && arrEnd > arrStart) {
      return cleaned.substring(arrStart, arrEnd + 1).trim();
    }
    return cleaned;
  }
}
