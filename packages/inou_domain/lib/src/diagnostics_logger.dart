import 'dart:collection';

import 'package:meta/meta.dart';

/// Callback signature invoked when [InouDiagnosticsLogger] appends or clears logs.
typedef DiagnosticsLogListener = void Function();

/// Severity levels for structured in-app diagnostic logs.
enum InouLogLevel {
  debug('DEBUG'),
  info('INFO'),
  warn('WARN'),
  error('ERROR');

  const InouLogLevel(this.tag);

  final String tag;
}

/// Immutable diagnostic log entry stored inside [InouDiagnosticsLogger].
@immutable
class InouLogEntry {
  const InouLogEntry({
    required this.timestamp,
    required this.level,
    required this.tag,
    required this.message,
    this.detail,
    this.stackTrace,
  });

  final DateTime timestamp;
  final InouLogLevel level;
  final String tag;
  final String message;
  final String? detail;
  final String? stackTrace;

  String formatBlock() {
    final buf = StringBuffer()
      ..writeln(
        '[${timestamp.toIso8601String()}] [${level.tag}] [$tag] $message',
      );
    if (detail != null && detail!.trim().isNotEmpty) {
      buf.writeln('  detail: ${detail!.trim()}');
    }
    if (stackTrace != null && stackTrace!.trim().isNotEmpty) {
      buf.writeln('  stackTrace:');
      for (final line in stackTrace!.trimRight().split('\n')) {
        buf.writeln('    $line');
      }
    }
    return buf.toString().trimRight();
  }
}

/// Thread-safe in-memory ring-buffer logger with automatic secret redaction
/// so full error messages and stack traces can be inspected and exported
/// without leaking API keys or authorization tokens.
class InouDiagnosticsLogger {
  InouDiagnosticsLogger({this.maxEntries = 500});

  static final InouDiagnosticsLogger instance = InouDiagnosticsLogger();

  static final RegExp _bearerPattern = RegExp(
    r'Bearer\s+[A-Za-z0-9._\-]+',
    caseSensitive: false,
  );
  static final RegExp _prefixedKeyPattern = RegExp(
    r'\b(?:sk|rk|pk)-[A-Za-z0-9_\-]{12,}',
  );
  static final RegExp _googleKeyPattern = RegExp(r'\bAIza[A-Za-z0-9_\-]{16,}');
  static final RegExp _kvSecretPattern = RegExp(
    r'''((?:api[_-]?key|x-goog-api-key|authorization|token|key)\s*[:=]\s*(?:Bearer\s+)?["']?)[^\s&"',;}]+''',
    caseSensitive: false,
  );

  final int maxEntries;
  final ListQueue<InouLogEntry> _entries = ListQueue<InouLogEntry>();
  final Set<DiagnosticsLogListener> _listeners = <DiagnosticsLogListener>{};

  List<InouLogEntry> get entries => List<InouLogEntry>.unmodifiable(_entries);

  int get errorCount =>
      _entries.where((e) => e.level == InouLogLevel.error).length;

  InouLogEntry? get latestError {
    for (final entry in _entries.toList().reversed) {
      if (entry.level == InouLogLevel.error) return entry;
    }
    return null;
  }

  void addListener(DiagnosticsLogListener listener) {
    _listeners.add(listener);
  }

  void removeListener(DiagnosticsLogListener listener) {
    _listeners.remove(listener);
  }

  void clear() {
    _entries.clear();
    _notifyListeners();
  }

  void debug(
    String tag,
    String message, {
    Object? error,
    StackTrace? stackTrace,
    String? detail,
  }) => _record(
    InouLogLevel.debug,
    tag,
    message,
    error: error,
    stackTrace: stackTrace,
    detail: detail,
  );

  void info(
    String tag,
    String message, {
    Object? error,
    StackTrace? stackTrace,
    String? detail,
  }) => _record(
    InouLogLevel.info,
    tag,
    message,
    error: error,
    stackTrace: stackTrace,
    detail: detail,
  );

  void warn(
    String tag,
    String message, {
    Object? error,
    StackTrace? stackTrace,
    String? detail,
  }) => _record(
    InouLogLevel.warn,
    tag,
    message,
    error: error,
    stackTrace: stackTrace,
    detail: detail,
  );

  void error(
    String tag,
    String message, {
    Object? error,
    StackTrace? stackTrace,
    String? detail,
  }) => _record(
    InouLogLevel.error,
    tag,
    message,
    error: error,
    stackTrace: stackTrace,
    detail: detail,
  );

  void _record(
    InouLogLevel level,
    String tag,
    String message, {
    Object? error,
    StackTrace? stackTrace,
    String? detail,
  }) {
    final mergedDetailBuf = StringBuffer();
    if (detail != null && detail.trim().isNotEmpty) {
      mergedDetailBuf.write(detail.trim());
    }
    if (error != null) {
      final errStr = error.toString().trim();
      if (errStr.isNotEmpty && !message.contains(errStr)) {
        if (mergedDetailBuf.isNotEmpty) mergedDetailBuf.write(' | ');
        mergedDetailBuf.write(errStr);
      }
    }
    final sanitizedMsg = redactSecrets(message);
    final sanitizedDetail = mergedDetailBuf.isEmpty
        ? null
        : redactSecrets(mergedDetailBuf.toString());
    final sanitizedStack = stackTrace == null
        ? null
        : redactSecrets(stackTrace.toString());

    while (_entries.length >= maxEntries && _entries.isNotEmpty) {
      _entries.removeFirst();
    }
    _entries.addLast(
      InouLogEntry(
        timestamp: DateTime.now(),
        level: level,
        tag: tag,
        message: sanitizedMsg,
        detail: sanitizedDetail,
        stackTrace: sanitizedStack,
      ),
    );
    _notifyListeners();
  }

  void _notifyListeners() {
    for (final listener in List<DiagnosticsLogListener>.of(_listeners)) {
      listener();
    }
  }

  /// Strips API keys, Bearer headers, and secret tokens from diagnostic strings.
  static String redactSecrets(String raw) {
    var out = raw.replaceAll(_bearerPattern, 'Bearer ***REDACTED***');
    out = out.replaceAll(_prefixedKeyPattern, '***REDACTED_KEY***');
    out = out.replaceAll(_googleKeyPattern, '***REDACTED_KEY***');
    out = out.replaceAllMapped(
      _kvSecretPattern,
      (m) => '${m.group(1)}***REDACTED***',
    );
    return out;
  }

  /// Formats buffered log entries into an untruncated plain-text report.
  String formatExportText({
    Map<String, String> metadata = const {},
    bool errorsOnly = false,
  }) {
    final targetEntries = errorsOnly
        ? _entries
              .where((e) => e.level == InouLogLevel.error)
              .toList(growable: false)
        : _entries.toList(growable: false);

    final buf = StringBuffer()
      ..writeln('=== InoU 运行诊断日志报告 ===')
      ..writeln('导出时间: ${DateTime.now().toIso8601String()}')
      ..writeln(
        '记录范围: ${errorsOnly ? '仅错误' : '全部'}（共 ${targetEntries.length} 条，总错误数 $errorCount）',
      );
    for (final entry in metadata.entries) {
      buf.writeln('${entry.key}: ${redactSecrets(entry.value)}');
    }
    buf.writeln('================================');

    if (targetEntries.isEmpty) {
      buf.writeln('（暂无符合条件的日志记录）');
    } else {
      for (final entry in targetEntries) {
        buf
          ..writeln()
          ..writeln(entry.formatBlock());
      }
    }
    return buf.toString();
  }
}