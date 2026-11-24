import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inou_domain/inou_domain.dart';
import 'package:inou_ui_kit/inou_ui_kit.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/platform/display_cutout_helper.dart';
import '../../../core/platform/platform_media_service.dart';
import '../../../core/state/app_store.dart';

Map<String, String> _collectDiagnosticMetadata(
  BuildContext context,
  WidgetRef ref,
) {
  final state = ref.read(appStoreProvider);
  final ep = state.activeEndpoint;
  return {
    '端点名称': ep.name,
    '接口协议': ep.protocol.name,
    'BaseURL': ep.baseUrl.trim().isEmpty ? '(默认)' : ep.baseUrl.trim(),
    '模型(Fast/Balanced/Strong)': ep.tierModels.values.join(' / '),
    '屏幕安全区': DisplayCutoutInsets.describeMetrics(context),
  };
}

/// Copies the full redacted diagnostic report to the system clipboard and shows
/// confirmation feedback.
Future<void> copyDiagnosticsLogsToClipboard(
  BuildContext context,
  WidgetRef ref, {
  bool errorsOnly = false,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final fullText = InouDiagnosticsLogger.instance.formatExportText(
    metadata: _collectDiagnosticMetadata(context, ref),
    errorsOnly: errorsOnly,
  );
  await Clipboard.setData(ClipboardData(text: fullText));
  if (!context.mounted) return;
  messenger?.showSnackBar(
    const SnackBar(content: Text('已复制完整诊断日志（密钥已自动脱敏）')),
  );
}

/// Builds the full redacted diagnostic report and exports or shares it as a
/// `.txt` file via [PlatformMediaService].
Future<bool> exportDiagnosticsLogFile(
  BuildContext context,
  WidgetRef ref, {
  required bool shareSheet,
  bool errorsOnly = false,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final media = ref.read(platformMediaServiceProvider);
  final report = InouDiagnosticsLogger.instance.formatExportText(
    metadata: _collectDiagnosticMetadata(context, ref),
    errorsOnly: errorsOnly,
  );
  final now = DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  final filename =
      'inou_logs_${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}${two(now.second)}.txt';
  final bytes = Uint8List.fromList(utf8.encode(report));

  final ok = shareSheet
      ? await media.shareFile(
          filename: filename,
          mimeType: 'text/plain',
          bytes: bytes,
        )
      : await media.saveFile(
          filename: filename,
          mimeType: 'text/plain',
          bytes: bytes,
        );
  if (!context.mounted) return ok;
  messenger?.showSnackBar(
    SnackBar(
      content: Text(
        ok
            ? (shareSheet ? '已调起系统分享诊断日志：$filename' : '已保存诊断日志：$filename')
            : '已取消保存日志（可通过「复制全部」直接拷贝完整报错）',
      ),
    ),
  );
  return ok;
}

/// Opens a full-screen-adaptive dialog showing untruncated [InouDiagnosticsLogger]
/// entries with selectable stack traces and one-tap file export / copy.
Future<void> showDiagnosticsLogDialog(
  BuildContext context, {
  bool initialErrorsOnly = false,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _DiagnosticsLogDialog(initialErrorsOnly: initialErrorsOnly),
  );
}

class _DiagnosticsLogDialog extends ConsumerStatefulWidget {
  const _DiagnosticsLogDialog({this.initialErrorsOnly = false});

  final bool initialErrorsOnly;

  @override
  ConsumerState<_DiagnosticsLogDialog> createState() =>
      _DiagnosticsLogDialogState();
}

class _DiagnosticsLogDialogState extends ConsumerState<_DiagnosticsLogDialog> {
  late bool _errorsOnly;

  @override
  void initState() {
    super.initState();
    _errorsOnly = widget.initialErrorsOnly;
    InouDiagnosticsLogger.instance.addListener(_onLogChanged);
  }

  @override
  void dispose() {
    InouDiagnosticsLogger.instance.removeListener(_onLogChanged);
    super.dispose();
  }

  void _onLogChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final t = context.inou;
    final logger = InouDiagnosticsLogger.instance;
    final entries = _errorsOnly
        ? logger.entries
              .where((e) => e.level == InouLogLevel.error)
              .toList(growable: false)
        : logger.entries;
    final reversed = entries.reversed.toList(growable: false);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 780, maxHeight: 620),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 12, 10),
              child: Row(
                children: [
                  Icon(Icons.bug_report_outlined, size: 20, color: t.accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '运行诊断日志',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: t.textPrimary,
                      ),
                    ),
                  ),
                  InouBadge(
                    label: '错误 ${logger.errorCount} 条',
                    tone: logger.errorCount > 0
                        ? InouBadgeTone.danger
                        : InouBadgeTone.neutral,
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, size: 19),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ChoiceChip(
                    label: Text('全部 (${logger.entries.length})'),
                    selected: !_errorsOnly,
                    onSelected: (_) => setState(() => _errorsOnly = false),
                  ),
                  ChoiceChip(
                    label: Text('仅错误 (${logger.errorCount})'),
                    selected: _errorsOnly,
                    onSelected: (_) => setState(() => _errorsOnly = true),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            const Divider(height: 1),
            Expanded(
              child: reversed.isEmpty
                  ? Center(
                      child: Text(
                        _errorsOnly ? '暂无错误日志' : '暂无日志记录',
                        style: TextStyle(fontSize: 13, color: t.textSecondary),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(14),
                      itemCount: reversed.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final entry = reversed[index];
                        final isErr = entry.level == InouLogLevel.error;
                        final isWarn = entry.level == InouLogLevel.warn;
                        final accentCol = isErr
                            ? t.danger
                            : (isWarn ? Colors.amber.shade700 : t.accent);
                        return Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: isErr
                                ? t.danger.withValues(alpha: 0.06)
                                : t.surfaceMuted,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isErr
                                  ? t.danger.withValues(alpha: 0.35)
                                  : t.borderHairline,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 1.5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: accentCol.withValues(alpha: 0.14),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      entry.level.tag,
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w700,
                                        color: accentCol,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      '${entry.tag} · ${entry.timestamp.toLocal().toIso8601String()}',
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: t.textSecondary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              SelectableText(
                                entry.message,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: t.textPrimary,
                                  height: 1.4,
                                ),
                              ),
                              if (entry.detail != null &&
                                  entry.detail!.trim().isNotEmpty) ...[
                                const SizedBox(height: 4),
                                SelectableText(
                                  entry.detail!,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontFamily: 'monospace',
                                    color: t.textSecondary,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                              if (entry.stackTrace != null &&
                                  entry.stackTrace!.trim().isNotEmpty) ...[
                                const SizedBox(height: 4),
                                SelectableText(
                                  entry.stackTrace!,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontFamily: 'monospace',
                                    color: t.textMuted,
                                    height: 1.35,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.spaceBetween,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: () => exportDiagnosticsLogFile(
                          context,
                          ref,
                          shareSheet: false,
                          errorsOnly: _errorsOnly,
                        ),
                        icon: const Icon(Icons.save_alt, size: 16),
                        label: const Text('保存日志文件'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => exportDiagnosticsLogFile(
                          context,
                          ref,
                          shareSheet: true,
                          errorsOnly: _errorsOnly,
                        ),
                        icon: const Icon(Icons.share_outlined, size: 16),
                        label: const Text('分享日志'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => copyDiagnosticsLogsToClipboard(
                          context,
                          ref,
                          errorsOnly: _errorsOnly,
                        ),
                        icon: const Icon(Icons.copy, size: 16),
                        label: const Text('复制全部'),
                      ),
                    ],
                  ),
                  TextButton.icon(
                    onPressed: logger.entries.isEmpty ? null : logger.clear,
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: const Text('清空日志'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}