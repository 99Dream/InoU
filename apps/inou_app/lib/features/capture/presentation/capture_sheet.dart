import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:inou_domain/inou_domain.dart';
import 'package:inou_ui_kit/inou_ui_kit.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/platform/platform_media_service.dart';
import '../../../core/state/app_store.dart';
import '../../settings/presentation/diagnostics_log_dialog.dart';
import '../../settings/presentation/settings_modal.dart';

/// Opens Camera / Gallery / Dual-Sheet / Text Capture adaptively:
/// full-height native bottom sheet on phones, crisp elevated modal on tablets.
Future<void> showCaptureModal(BuildContext context) {
  final compact = AdaptiveScope.of(context) == WindowClass.compact;
  if (compact) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const CaptureSheet(isSheet: true),
    );
  }
  return showDialog<void>(
    context: context,
    builder: (_) => const Dialog(
      insetPadding: EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      child: CaptureSheet(isSheet: false),
    ),
  );
}

enum _CaptureMode { menu, photoScan, singleWrong, dualSheet, textImport }

class CaptureSheet extends ConsumerStatefulWidget {
  const CaptureSheet({super.key, this.isSheet = false});

  final bool isSheet;

  @override
  ConsumerState<CaptureSheet> createState() => _CaptureSheetState();
}

class _CaptureSheetState extends ConsumerState<CaptureSheet> {
  String _subject = SubjectCatalog.autoCode;
  _CaptureMode _mode = _CaptureMode.menu;
  Uint8List? _examBytes;
  Uint8List? _answerBytes;
  String? _errorText;
  String? _importedFilename;
  String? _liveDetectedSubject;
  final TextEditingController _rawTextCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _rawTextCtrl.addListener(_onRawTextChanged);
  }

  void _onRawTextChanged() {
    final txt = _rawTextCtrl.text.trim();
    if (txt.length < 6) {
      if (_liveDetectedSubject != null) {
        setState(() => _liveDetectedSubject = null);
      }
      return;
    }
    final det = SubjectDetector.detect(txt);
    final next = det.confidence >= 0.35 ? det.subject : null;
    if (next != _liveDetectedSubject) {
      setState(() => _liveDetectedSubject = next);
    }
  }

  @override
  void dispose() {
    _rawTextCtrl
      ..removeListener(_onRawTextChanged)
      ..dispose();
    super.dispose();
  }

  Future<void> _captureFromCamera({required bool forAnswer}) async {
    setState(() => _errorText = null);
    try {
      final picked = await ref
          .read(platformMediaServiceProvider)
          .capturePhoto();
      if (!mounted || picked == null) return;
      setState(() {
        if (forAnswer) {
          _answerBytes = picked.bytes;
        } else {
          _examBytes = picked.bytes;
          if (_mode == _CaptureMode.menu) _mode = _CaptureMode.photoScan;
        }
      });
    } on PlatformException catch (e, st) {
      InouDiagnosticsLogger.instance.error(
        'app.capture',
        'Camera capture PlatformException (${e.code})',
        error: e.message ?? e,
        stackTrace: st,
      );
      if (!mounted) return;
      setState(() => _errorText = '未能打开相机，请检查相机权限后重试');
    } catch (e, st) {
      InouDiagnosticsLogger.instance.error(
        'app.capture',
        'Camera capture failed',
        error: e,
        stackTrace: st,
      );
      if (!mounted) return;
      setState(() => _errorText = '未能打开相机，请检查相机权限后重试');
    }
  }

  Future<void> _pickFromGallery({required bool forAnswer}) async {
    setState(() => _errorText = null);
    try {
      final picked = await ref
          .read(platformMediaServiceProvider)
          .pickGalleryImage();
      if (!mounted || picked == null) return;
      setState(() {
        if (forAnswer) {
          _answerBytes = picked.bytes;
        } else {
          _examBytes = picked.bytes;
          if (_mode == _CaptureMode.menu) _mode = _CaptureMode.photoScan;
        }
      });
    } on PlatformException catch (e, st) {
      InouDiagnosticsLogger.instance.error(
        'app.capture',
        'Gallery pick PlatformException (${e.code})',
        error: e.message ?? e,
        stackTrace: st,
      );
      if (!mounted) return;
      setState(() => _errorText = '未能打开相册，请检查相册权限后重试');
    } catch (e, st) {
      InouDiagnosticsLogger.instance.error(
        'app.capture',
        'Gallery pick failed',
        error: e,
        stackTrace: st,
      );
      if (!mounted) return;
      setState(() => _errorText = '未能打开相册，请检查相册权限后重试');
    }
  }

  Future<void> _rotateExam() async {
    if (_examBytes == null) return;
    final rotated = await ref
        .read(platformMediaServiceProvider)
        .rotateImage90(_examBytes!);
    if (!mounted) return;
    if (rotated != null) {
      setState(() => _examBytes = rotated);
    }
  }

  Future<void> _pickDocumentFile() async {
    setState(() => _errorText = null);
    try {
      final picked = await ref
          .read(platformMediaServiceProvider)
          .pickFile(mimeType: '*/*');
      if (!mounted || picked == null) return;
      final decoded = utf8.decode(picked.bytes, allowMalformed: true);
      setState(() {
        _importedFilename = picked.name;
        _rawTextCtrl.text = decoded;
        _mode = _CaptureMode.textImport;
      });
    } on PlatformException catch (e, st) {
      InouDiagnosticsLogger.instance.error(
        'app.capture',
        'Document pick PlatformException (${e.code})',
        error: e.message ?? e,
        stackTrace: st,
      );
      if (!mounted) return;
      setState(() => _errorText = '未能读取文件，请检查文件格式与访问权限后重试');
    } catch (e, st) {
      InouDiagnosticsLogger.instance.error(
        'app.capture',
        'Document pick failed',
        error: e,
        stackTrace: st,
      );
      if (!mounted) return;
      setState(() => _errorText = '未能读取文件，请检查文件格式与访问权限后重试');
    }
  }

  Future<void> _showSchemaCatalogDialog(BuildContext context) async {
    var selectedKind = QuestionKind.choice;
    final pickedSkeleton = await showDialog<String>(
      context: context,
      builder: (dlgCtx) {
        final dt = dlgCtx.inou;
        return StatefulBuilder(
          builder: (dlgCtx, setLocal) {
            final spec = QuestionSchemaCatalog.specFor(selectedKind);
            final skeleton = QuestionSchemaCatalog.formattedSkeletonJson(
              selectedKind,
            );
            return Dialog(
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 24,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 540,
                  maxHeight: 580,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 14, 10, 8),
                      child: Row(
                        children: [
                          Icon(
                            Icons.schema_outlined,
                            size: 18,
                            color: dt.accent,
                          ),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              '题库结构规范与空白骨架',
                              style: TextStyle(
                                fontSize: 15.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.of(dlgCtx).pop(),
                            icon: const Icon(Icons.close, size: 18),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 10, 18, 6),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (final s in QuestionSchemaCatalog.specs)
                              Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: ChoiceChip(
                                  label: Text(s.label),
                                  selected: s.kind == selectedKind,
                                  onSelected: (_) =>
                                      setLocal(() => selectedKind = s.kind),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(18, 6, 18, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              spec.description,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: dt.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            InouSurface(
                              subtle: true,
                              padding: const EdgeInsets.all(10),
                              child: Text(
                                spec.generationGuide,
                                style: TextStyle(
                                  fontSize: 12,
                                  height: 1.45,
                                  color: dt.textSecondary,
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              '标准 JSON 结构骨架（interaction: ${spec.defaultInteraction} · grading: ${spec.defaultGradingMode}）',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: dt.textMuted,
                              ),
                            ),
                            const SizedBox(height: 6),
                            InouSurface(
                              subtle: true,
                              padding: const EdgeInsets.all(10),
                              child: SelectableText(
                                skeleton,
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 11.5,
                                  height: 1.4,
                                  color: dt.textPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.of(dlgCtx).pop(),
                            child: const Text('关闭'),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.icon(
                            onPressed: () => Navigator.of(dlgCtx).pop(skeleton),
                            icon: const Icon(Icons.add, size: 16),
                            label: const Text('填入空白骨架'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    if (pickedSkeleton == null || !mounted) return;
    setState(() {
      _mode = _CaptureMode.textImport;
      _rawTextCtrl.text = pickedSkeleton;
      _errorText = null;
    });
  }

  Future<void> _startAiRecognition() async {
    if (_examBytes == null) return;
    final state = ref.read(appStoreProvider);
    final hasOverride = ref.read(overrideLlmClientProvider) != null;
    if (!state.hasLiveAiKey && !hasOverride) {
      setState(() {
        _errorText = '图片识题需先在「设置」中配置视觉 AI API Key；或改用「文本 / 文档导入」';
      });
      return;
    }
    setState(() => _errorText = null);
    final docTitle = _mode == _CaptureMode.singleWrong
        ? '单题快拍错题'
        : (_answerBytes != null ? '试卷 + 答案页导入' : '拍照试卷');
    ref
        .read(appStoreProvider.notifier)
        .enqueueBackgroundImageTask(
          examBytes: _examBytes!,
          answerBytes: _answerBytes,
          subject: _subject,
          lockSubject: _subject != SubjectCatalog.autoCode,
          docTitle: docTitle,
          autoFlagWrong: _mode == _CaptureMode.singleWrong,
        );
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    Navigator.of(context).pop();
    messenger?.showSnackBar(
      SnackBar(
        content: Text('已加入后台识题队列：「$docTitle」，可随时切换页面或取消'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _launchRawText() async {
    final txt = _rawTextCtrl.text.trim();
    if (txt.isEmpty) {
      setState(() => _errorText = '请先输入或导入题目文本 / JSON / JSONL');
      return;
    }
    setState(() => _errorText = null);
    final state = ref.read(appStoreProvider);
    final notifier = ref.read(appStoreProvider.notifier);
    final hasAi =
        state.hasLiveAiKey || ref.read(overrideLlmClientProvider) != null;
    final lockSubject = _subject != SubjectCatalog.autoCode;
    final structured = StructuredQuestionTextParser.tryParseJsonOrJsonl(
      txt,
      subject: _subject,
      grade: state.activeProfile.grade,
      lockSubject: lockSubject,
    );

    if (structured == null && hasAi && txt.length > 180) {
      final docTitle = (_importedFilename ?? '').trim().isNotEmpty
          ? _importedFilename!.trim()
          : '长文本 AI 拆题';
      notifier.enqueueBackgroundTextTask(
        rawText: txt,
        subject: _subject,
        lockSubject: lockSubject,
        docTitle: docTitle,
      );
      if (!mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      Navigator.of(context).pop();
      messenger?.showSnackBar(
        SnackBar(
          content: Text('已提交后台拆题：「$docTitle」'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final res = await notifier.importRawTextCapture(
      txt,
      subject: _subject,
      lockSubject: lockSubject,
    );
    if (!mounted) return;
    if (res.drafts.isNotEmpty) {
      Navigator.of(context).pop();
      context.go('/review');
    } else {
      setState(
        () => _errorText =
            '未能识别出有效题目，请按「1. 题干 / A. 选项 / 答案： / 解析：」或 JSON/JSONL 格式输入',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.inou;
    final state = ref.watch(appStoreProvider);
    final pad = widget.isSheet
        ? const EdgeInsets.fromLTRB(18, 0, 18, 22)
        : const EdgeInsets.all(22);

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: widget.isSheet ? double.infinity : 540,
      ),
      child: SingleChildScrollView(
        padding: pad,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '录题与识别',
                  style: TextStyle(
                    fontSize: 17.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                    color: t.textPrimary,
                  ),
                ),
                const Spacer(),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final code in const [
                    SubjectCatalog.autoCode,
                    'math',
                    'eng',
                    'chn',
                    'phy',
                    'chem',
                    'bio',
                    'hist',
                    'geo',
                    'pol',
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(SubjectCatalog.labelOf(code)),
                        selected: _subject == code,
                        onSelected: (_) => setState(() => _subject = code),
                      ),
                    ),
                ],
              ),
            ),
            if (state.backgroundTasks.isNotEmpty) ...[
              const SizedBox(height: 10),
              _SheetBackgroundTaskNotice(
                task: state.backgroundTasks.first,
                extraCount: state.backgroundTasks.length - 1,
                onOpenReview: () async {
                  final nav = Navigator.of(context);
                  final router = GoRouter.of(context);
                  await ref
                      .read(appStoreProvider.notifier)
                      .openBackgroundTaskForReview(
                        state.backgroundTasks.first.id,
                      );
                  if (!mounted) return;
                  nav.pop();
                  router.go('/review');
                },
                onCancel: () => ref
                    .read(appStoreProvider.notifier)
                    .cancelBackgroundTask(state.backgroundTasks.first.id),
                onRetry: () => ref
                    .read(appStoreProvider.notifier)
                    .retryBackgroundTask(state.backgroundTasks.first.id),
              ),
            ],
            const SizedBox(height: 14),
            if (_mode == _CaptureMode.textImport) ...[
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  OutlinedButton.icon(
                    onPressed: _pickDocumentFile,
                    icon: const Icon(Icons.upload_file_outlined, size: 15),
                    label: const Text('导入文档 (.json/.jsonl/.md)'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _showSchemaCatalogDialog(context),
                    icon: const Icon(Icons.schema_outlined, size: 15),
                    label: const Text('题型规范 / 空白骨架'),
                  ),
                ],
              ),
              if (_importedFilename != null ||
                  (_subject == SubjectCatalog.autoCode &&
                      _liveDetectedSubject != null)) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (_importedFilename != null)
                      InouBadge(
                        label: '已加载：$_importedFilename',
                        tone: InouBadgeTone.accent,
                      ),
                    if (_subject == SubjectCatalog.autoCode &&
                        _liveDetectedSubject != null)
                      InouBadge(
                        label:
                            '自动识别学科：${SubjectCatalog.labelOf(_liveDetectedSubject!)}',
                        tone: InouBadgeTone.success,
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              TextField(
                controller: _rawTextCtrl,
                maxLines: 6,
                decoration: const InputDecoration(
                  labelText: '题目文本 / Markdown / JSON / JSONL',
                  hintText: '例如：\n1. 已知直角三角形两条直角边分别为 3 和 4，则斜边长为 ____。\n答案：5\n解析：由勾股定理得 3² + 4² = 5²。',
                ),
              ),
              if (_errorText != null) ...[
                const SizedBox(height: 8),
                Text(
                  _errorText!,
                  style: TextStyle(fontSize: 12.5, color: t.danger),
                ),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  OutlinedButton(
                    onPressed: () => setState(() {
                      _mode = _CaptureMode.menu;
                      _errorText = null;
                      _importedFilename = null;
                    }),
                    child: const Text('返回'),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: _launchRawText,
                    icon: const Icon(Icons.auto_fix_high, size: 16),
                    label: const Text('解析并校对'),
                  ),
                ],
              ),
            ] else if (_mode != _CaptureMode.menu || _examBytes != null) ...[
              if (_examBytes == null)
                Row(
                  children: [
                    Expanded(
                      child: _CapturePrimaryButton(
                        icon: Icons.camera_alt_rounded,
                        title: '相机拍照',
                        subtitle: _mode == _CaptureMode.singleWrong
                            ? '拍单道错题自动标错'
                            : '拍摄整张试卷',
                        accent: true,
                        onTap: () => _captureFromCamera(forAnswer: false),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _CapturePrimaryButton(
                        icon: Icons.photo_library_outlined,
                        title: '相册选图',
                        subtitle: '从设备相册选取',
                        accent: false,
                        onTap: () => _pickFromGallery(forAnswer: false),
                      ),
                    ),
                  ],
                )
              else
                InouSurface(
                  subtle: true,
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 200),
                          child: Center(
                            child: Image.memory(
                              _examBytes!,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () =>
                                _captureFromCamera(forAnswer: false),
                            icon: const Icon(
                              Icons.camera_alt_outlined,
                              size: 15,
                            ),
                            label: const Text('重拍'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _rotateExam,
                            icon: const Icon(Icons.rotate_right, size: 15),
                            label: const Text('旋转 90°'),
                          ),
                          FilterChip(
                            selected: _mode == _CaptureMode.singleWrong,
                            label: const Text('全部标错入错题'),
                            onSelected: (on) => setState(
                              () => _mode = on
                                  ? _CaptureMode.singleWrong
                                  : _CaptureMode.photoScan,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 10),
              if (_mode == _CaptureMode.dualSheet || _answerBytes != null) ...[
                if (_answerBytes != null)
                  InouSurface(
                    subtle: true,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.memory(
                            _answerBytes!,
                            width: 40,
                            height: 40,
                            fit: BoxFit.cover,
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            '已附加参考答案页照片',
                            style: TextStyle(fontSize: 13),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () => setState(() => _answerBytes = null),
                        ),
                      ],
                    ),
                  )
                else
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => _captureFromCamera(forAnswer: true),
                        icon: const Icon(Icons.add_a_photo_outlined, size: 15),
                        label: const Text('拍摄答案页'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _pickFromGallery(forAnswer: true),
                        icon: const Icon(Icons.photo_outlined, size: 15),
                        label: const Text('相册选答案页'),
                      ),
                    ],
                  ),
              ] else if (_examBytes != null) ...[
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton.icon(
                      onPressed: () => _captureFromCamera(forAnswer: true),
                      icon: const Icon(Icons.add_a_photo_outlined, size: 15),
                      label: const Text('加拍答案页'),
                    ),
                    TextButton.icon(
                      onPressed: () => _pickFromGallery(forAnswer: true),
                      icon: const Icon(Icons.photo_outlined, size: 15),
                      label: const Text('选答案页'),
                    ),
                  ],
                ),
              ],
              if (_errorText != null) ...[
                const SizedBox(height: 8),
                InouSurface(
                  backgroundColor: t.dangerSoft,
                  borderColor: t.danger.withValues(alpha: 0.35),
                  padding: const EdgeInsets.all(10),
                  child: Row(
                    children: [
                      Expanded(
                        child: SelectableText(
                          _errorText!,
                          style: TextStyle(fontSize: 12.5, color: t.danger),
                        ),
                      ),
                      TextButton(
                        onPressed: () => showDiagnosticsLogDialog(
                          context,
                          initialErrorsOnly: true,
                        ),
                        child: const Text('查看日志'),
                      ),
                      if (!state.hasLiveAiKey)
                        TextButton(
                          onPressed: () => showSettingsModal(context),
                          child: const Text('去配置'),
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  OutlinedButton(
                    onPressed: () => setState(() {
                      _mode = _CaptureMode.menu;
                      _examBytes = null;
                      _answerBytes = null;
                      _errorText = null;
                    }),
                    child: const Text('切换方式'),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _examBytes == null
                          ? null
                          : _startAiRecognition,
                      icon: const Icon(Icons.auto_awesome, size: 16),
                      label: const Text('开始后台识题'),
                    ),
                  ),
                ],
              ),
            ] else ...[
              Row(
                children: [
                  Expanded(
                    child: _CapturePrimaryButton(
                      icon: Icons.camera_alt_rounded,
                      title: '相机拍照',
                      subtitle: '直拍试卷或错题',
                      accent: true,
                      onTap: () => _captureFromCamera(forAnswer: false),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _CapturePrimaryButton(
                      icon: Icons.photo_library_outlined,
                      title: '相册选图',
                      subtitle: '本地图片识题',
                      accent: false,
                      onTap: () => _pickFromGallery(forAnswer: false),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                '专项采集模式',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: t.textMuted,
                ),
              ),
              const SizedBox(height: 8),
              _CaptureModeRow(
                icon: Icons.saved_search_rounded,
                title: '拍照搜题（AI 自动求解）',
                subtitle: '拍摄无答案试卷或单题，AI 独立生成答案解析，按需加入题库/错题本',
                onTap: () {
                  final router = GoRouter.of(context);
                  Navigator.of(context).pop();
                  router.go('/photo-search');
                },
              ),
              const SizedBox(height: 8),
              _CaptureModeRow(
                icon: Icons.crop_free_rounded,
                title: '单题快拍录错',
                subtitle: '拍单道错题并自动标错存入错题本',
                onTap: () => setState(() => _mode = _CaptureMode.singleWrong),
              ),
              const SizedBox(height: 8),
              _CaptureModeRow(
                icon: Icons.fact_check_outlined,
                title: '试卷 + 答案双照',
                subtitle: '同时拍摄试题页与参考答案页对齐校验',
                onTap: () => setState(() => _mode = _CaptureMode.dualSheet),
              ),
              const SizedBox(height: 8),
              _CaptureModeRow(
                icon: Icons.text_snippet_outlined,
                title: '文本 / JSON / JSONL 导入',
                subtitle: '支持复制粘贴或导入 .json/.jsonl/.md 文档批量拆题',
                onTap: () => setState(() => _mode = _CaptureMode.textImport),
              ),
              const SizedBox(height: 8),
              _CaptureModeRow(
                icon: Icons.upload_file_outlined,
                title: '从本地文件导入题库',
                subtitle: '直接选取 .json / .jsonl / .md / .txt 文件解析',
                onTap: _pickDocumentFile,
              ),
              if (!state.hasLiveAiKey) ...[
                const SizedBox(height: 12),
                InouSurface(
                  backgroundColor: t.warningSoft,
                  borderColor: t.warning.withValues(alpha: 0.3),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, size: 16, color: t.warning),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          '图片识题需先配置视觉 AI 密钥；文本导入立即可用',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                      TextButton(
                        onPressed: () => showSettingsModal(context),
                        child: const Text('去配置'),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _CapturePrimaryButton extends StatelessWidget {
  const _CapturePrimaryButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.inou;
    return InouSurface(
      onTap: onTap,
      backgroundColor: accent ? t.accentSoft : t.surface,
      borderColor: accent ? t.accent : t.borderHairline,
      borderWidth: accent ? 1.5 : 0.9,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      child: Column(
        children: [
          Icon(icon, size: 24, color: accent ? t.accent : t.textPrimary),
          const SizedBox(height: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: t.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11.5, color: t.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _CaptureModeRow extends StatelessWidget {
  const _CaptureModeRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.inou;
    return InouSurface(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: t.accentSoft,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 17, color: t.accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: t.textPrimary,
                  ),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: t.textMuted),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, size: 18, color: t.textMuted),
        ],
      ),
    );
  }
}

class _SheetBackgroundTaskNotice extends StatelessWidget {
  const _SheetBackgroundTaskNotice({
    required this.task,
    required this.extraCount,
    required this.onOpenReview,
    required this.onCancel,
    required this.onRetry,
  });

  final CaptureBackgroundTask task;
  final int extraCount;
  final VoidCallback onOpenReview;
  final VoidCallback onCancel;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final t = context.inou;
    return InouSurface(
      subtle: true,
      borderColor: task.status == CaptureTaskStatus.failed
          ? t.danger.withValues(alpha: 0.45)
          : t.accent.withValues(alpha: 0.45),
      borderWidth: 1.2,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: Row(
        children: [
          if (task.status == CaptureTaskStatus.running)
            SizedBox(
              width: 15,
              height: 15,
              child: CircularProgressIndicator(strokeWidth: 2, color: t.accent),
            )
          else if (task.status == CaptureTaskStatus.completed)
            Icon(Icons.check_circle_rounded, size: 17, color: t.success)
          else
            Icon(Icons.error_outline_rounded, size: 17, color: t.danger),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  extraCount > 0
                      ? '${task.docTitle}（+$extraCount）'
                      : task.docTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: t.textPrimary,
                  ),
                ),
                Text(
                  task.errorMessage ?? task.stageLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: task.status == CaptureTaskStatus.failed
                        ? t.danger
                        : t.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          if (task.status == CaptureTaskStatus.running)
            TextButton(onPressed: onCancel, child: const Text('取消'))
          else if (task.status == CaptureTaskStatus.completed)
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 32),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
              ),
              onPressed: onOpenReview,
              child: const Text('去校对'),
            )
          else ...[
            TextButton(
              onPressed: () => showDiagnosticsLogDialog(
                context,
                initialErrorsOnly: true,
              ),
              child: const Text('查看日志'),
            ),
            TextButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ],
      ),
    );
  }
}
