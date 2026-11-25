import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:inou_ai/inou_ai.dart';
import 'package:inou_domain/inou_domain.dart';
import 'package:inou_ui_kit/inou_ui_kit.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/platform/platform_media_service.dart';
import '../../../core/state/app_store.dart';
import '../../library/presentation/question_editor_dialog.dart';
import '../../settings/presentation/diagnostics_log_dialog.dart';
import '../../settings/presentation/settings_modal.dart';

/// Photo Search & AI Independent Solve workspace for answer-free exam papers
/// and single questions, with one-click saving into Question Bank & WrongBook.
class PhotoSearchPage extends ConsumerStatefulWidget {
  const PhotoSearchPage({super.key});

  @override
  ConsumerState<PhotoSearchPage> createState() => _PhotoSearchPageState();
}

class _PhotoSearchPageState extends ConsumerState<PhotoSearchPage> {
  String _subject = SubjectCatalog.autoCode;
  Uint8List? _pendingImageBytes;
  String? _localErrorText;
  String? _selectedItemId;
  Uint8List? _measuredBytes;
  double _imageAspectRatio = 595 / 842;

  void _measureImageRatioIfNeeded(Uint8List? bytes) {
    if (bytes == null || identical(bytes, _measuredBytes)) return;
    _measuredBytes = bytes;
    ui.decodeImageFromList(bytes, (img) {
      if (!mounted || img.height <= 0) return;
      setState(() => _imageAspectRatio = img.width / img.height);
    });
  }

  Future<void> _captureFromCamera() async {
    setState(() => _localErrorText = null);
    try {
      final picked = await ref
          .read(platformMediaServiceProvider)
          .capturePhoto();
      if (!mounted || picked == null) return;
      setState(() => _pendingImageBytes = picked.bytes);
    } on PlatformException catch (e, st) {
      InouDiagnosticsLogger.instance.error(
        'app.photo_search',
        'Camera capture PlatformException (${e.code})',
        error: e.message ?? e,
        stackTrace: st,
      );
      if (!mounted) return;
      setState(() => _localErrorText = '未能打开相机，请检查相机权限后重试');
    } catch (e, st) {
      InouDiagnosticsLogger.instance.error(
        'app.photo_search',
        'Camera capture failed',
        error: e,
        stackTrace: st,
      );
      if (!mounted) return;
      setState(() => _localErrorText = '未能打开相机，请检查相机权限后重试');
    }
  }

  Future<void> _pickFromGallery() async {
    setState(() => _localErrorText = null);
    try {
      final picked = await ref
          .read(platformMediaServiceProvider)
          .pickGalleryImage();
      if (!mounted || picked == null) return;
      setState(() => _pendingImageBytes = picked.bytes);
    } on PlatformException catch (e, st) {
      InouDiagnosticsLogger.instance.error(
        'app.photo_search',
        'Gallery pick PlatformException (${e.code})',
        error: e.message ?? e,
        stackTrace: st,
      );
      if (!mounted) return;
      setState(() => _localErrorText = '未能打开相册，请检查相册权限后重试');
    } catch (e, st) {
      InouDiagnosticsLogger.instance.error(
        'app.photo_search',
        'Gallery pick failed',
        error: e,
        stackTrace: st,
      );
      if (!mounted) return;
      setState(() => _localErrorText = '未能打开相册，请检查相册权限后重试');
    }
  }

  Future<void> _rotatePending() async {
    final bytes = _pendingImageBytes;
    if (bytes == null) return;
    final rotated = await ref
        .read(platformMediaServiceProvider)
        .rotateImage90(bytes);
    if (!mounted || rotated == null) return;
    setState(() => _pendingImageBytes = rotated);
  }

  Future<void> _startSearch() async {
    final bytes = _pendingImageBytes;
    if (bytes == null) return;
    final state = ref.read(appStoreProvider);
    final hasOverride = ref.read(overrideLlmClientProvider) != null;
    if (!state.hasLiveAiKey && !hasOverride) {
      setState(() {
        _localErrorText = '拍照搜题需先在「设置」中配置支持视觉与推理的 AI API Key';
      });
      return;
    }
    setState(() => _localErrorText = null);
    final res = await ref
        .read(appStoreProvider.notifier)
        .runPhotoSearch(
          imageBytes: bytes,
          subject: _subject,
          lockSubject: _subject != SubjectCatalog.autoCode,
        );
    if (!mounted) return;
    if (res.ok && res.items.isNotEmpty) {
      setState(() {
        _pendingImageBytes = null;
        _selectedItemId = res.items.first.id;
      });
    }
  }

  static String _formatHistoryTime(int ms) {
    if (ms <= 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
  }

  Future<void> _showHistorySheet(
    BuildContext context,
    AppState state,
    AppStoreNotifier notifier,
  ) async {
    final history = state.activeWorkspace.photoSearchHistory;
    if (history.isEmpty) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetCtx) {
        final t = sheetCtx.inou;
        return ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetCtx).height * 0.72,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 10, 10),
                child: Row(
                  children: [
                    Icon(Icons.history_rounded, size: 19, color: t.accent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '搜题历史 (${history.length})',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: t.textPrimary,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(sheetCtx).pop(),
                      icon: const Icon(Icons.close, size: 20),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.all(14),
                  itemCount: history.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (ctx, index) {
                    final s = history[index];
                    final isActive = s.id == state.activePhotoSearchSessionId;
                    return InouSurface(
                      onTap: () async {
                        Navigator.of(sheetCtx).pop();
                        await notifier.selectPhotoSearchSession(s.id);
                        if (mounted && s.items.isNotEmpty) {
                          setState(() => _selectedItemId = s.items.first.id);
                        }
                      },
                      borderColor: isActive ? t.accent : t.borderHairline,
                      backgroundColor: isActive ? t.accentSoft : t.surface,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 11,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  s.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: t.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  [
                                    SubjectCatalog.labelOf(s.subject),
                                    '${s.items.length} 道题',
                                    if (_formatHistoryTime(s.createdAtMs).isNotEmpty)
                                      _formatHistoryTime(s.createdAtMs),
                                  ].join(' · '),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: t.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: '删除记录',
                            onPressed: () async {
                              await notifier.deletePhotoSearchSession(s.id);
                              if (sheetCtx.mounted) {
                                Navigator.of(sheetCtx).pop();
                              }
                            },
                            icon: Icon(
                              Icons.delete_outline,
                              size: 18,
                              color: t.danger,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.inou;
    final state = ref.watch(appStoreProvider);
    final notifier = ref.read(appStoreProvider.notifier);
    final ws = state.activeWorkspace;
    final activeSession = state.activePhotoSearchSession;
    final wide = AdaptiveScope.of(context) != WindowClass.compact;

    final previewBytes =
        state.photoSearchImageBytes ?? _pendingImageBytes;
    _measureImageRatioIfNeeded(previewBytes);

    if (activeSession != null &&
        activeSession.items.isNotEmpty &&
        (_selectedItemId == null ||
            !activeSession.items.any((it) => it.id == _selectedItemId))) {
      _selectedItemId = activeSession.items.first.id;
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: '返回首页',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/home'),
        ),
        title: const Text('拍照搜题'),
        actions: [
          if (activeSession != null && !state.photoSearchBusy)
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _pendingImageBytes = null;
                  _localErrorText = null;
                  _selectedItemId = null;
                });
                notifier.startNewPhotoSearch();
              },
              icon: const Icon(Icons.add_a_photo_outlined, size: 17),
              label: const Text('搜新题'),
            ),
          if (ws.photoSearchHistory.isNotEmpty && !state.photoSearchBusy)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton.icon(
                onPressed: () => _showHistorySheet(context, state, notifier),
                icon: const Icon(Icons.history_rounded, size: 18),
                label: Text('历史 (${ws.photoSearchHistory.length})'),
              ),
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: state.photoSearchBusy
            ? _buildSolvingView(t, state, notifier)
            : activeSession != null
            ? _buildResultsView(
                context,
                t,
                state,
                notifier,
                activeSession,
                wide: wide,
              )
            : _buildCaptureView(context, t, state, notifier, wide: wide),
      ),
    );
  }

  Widget _buildCaptureView(
    BuildContext context,
    InouTokens t,
    AppState state,
    AppStoreNotifier notifier, {
    required bool wide,
  }) {
    final ws = state.activeWorkspace;
    final errText = _localErrorText ?? state.photoSearchErrorMessage;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: ListView(
          padding: EdgeInsets.fromLTRB(wide ? 24 : 16, 10, wide ? 24 : 16, 28),
          children: [
            InouSurface(
              subtle: true,
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: t.accentSoft,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.saved_search_rounded,
                      color: t.accent,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '无答案试卷 / 单题 · AI 独立求解',
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            color: t.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '拍下没有答案的题目或整页试卷，AI 将自动识别题干、独立推导答案与分步解析，可按需加入题库或错题本。',
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.4,
                            color: t.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
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
            const SizedBox(height: 14),
            if (_pendingImageBytes == null)
              Row(
                children: [
                  Expanded(
                    child: _PhotoActionTile(
                      icon: Icons.camera_alt_rounded,
                      title: '相机拍照',
                      subtitle: '直拍单题或整页试卷',
                      accent: true,
                      onTap: _captureFromCamera,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _PhotoActionTile(
                      icon: Icons.photo_library_outlined,
                      title: '相册选图',
                      subtitle: '从本地相册选取题目图片',
                      accent: false,
                      onTap: _pickFromGallery,
                    ),
                  ),
                ],
              )
            else
              InouSurface(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 280),
                        child: Center(
                          child: Image.memory(
                            _pendingImageBytes!,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _captureFromCamera,
                          icon: const Icon(
                            Icons.camera_alt_outlined,
                            size: 16,
                          ),
                          label: const Text('重拍'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _pickFromGallery,
                          icon: const Icon(
                            Icons.photo_library_outlined,
                            size: 16,
                          ),
                          label: const Text('相册重选'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _rotatePending,
                          icon: const Icon(Icons.rotate_right, size: 16),
                          label: const Text('旋转 90°'),
                        ),
                        TextButton.icon(
                          onPressed: () => setState(() {
                            _pendingImageBytes = null;
                            _localErrorText = null;
                          }),
                          icon: const Icon(Icons.close, size: 16),
                          label: const Text('清除'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _startSearch,
                        icon: const Icon(Icons.auto_awesome, size: 18),
                        label: const Text('开始 AI 识题求解'),
                      ),
                    ),
                  ],
                ),
              ),
            if (errText != null && errText.isNotEmpty) ...[
              const SizedBox(height: 12),
              InouSurface(
                backgroundColor: t.dangerSoft,
                borderColor: t.danger.withValues(alpha: 0.35),
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: SelectableText(
                        errText,
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
            if (!state.hasLiveAiKey &&
                ref.read(overrideLlmClientProvider) == null) ...[
              const SizedBox(height: 12),
              InouSurface(
                backgroundColor: t.warningSoft,
                borderColor: t.warning.withValues(alpha: 0.3),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 16, color: t.warning),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        '拍照搜题需先在「设置」中配置支持视觉与推理的 AI API Key',
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
            if (ws.photoSearchHistory.isNotEmpty) ...[
              const SizedBox(height: 20),
              const InouSectionHeader(title: '最近搜题记录'),
              const SizedBox(height: 8),
              for (final s in ws.photoSearchHistory.take(5))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InouSurface(
                    onTap: () async {
                      await notifier.selectPhotoSearchSession(s.id);
                      if (mounted && s.items.isNotEmpty) {
                        setState(() => _selectedItemId = s.items.first.id);
                      }
                    },
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 11,
                    ),
                    child: Row(
                      children: [
                        InouBadge(
                          label: SubjectCatalog.labelOf(s.subject),
                          tone: InouBadgeTone.accent,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                s.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                  color: t.textPrimary,
                                ),
                              ),
                              Text(
                                [
                                  '共 ${s.items.length} 道题',
                                  if (_PhotoSearchPageState._formatHistoryTime(
                                        s.createdAtMs,
                                      )
                                      .isNotEmpty)
                                    _PhotoSearchPageState._formatHistoryTime(
                                      s.createdAtMs,
                                    ),
                                ].join(' · '),
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: t.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.chevron_right,
                          size: 18,
                          color: t.textMuted,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSolvingView(
    InouTokens t,
    AppState state,
    AppStoreNotifier notifier,
  ) {
    final stageText = state.photoSearchStageLabel.isNotEmpty
        ? state.photoSearchStageLabel
        : PhotoSearchStage.layoutAndOcr.label;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: InouSurface(
            elevated: true,
            padding: const EdgeInsets.all(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (state.photoSearchImageBytes != null) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 170),
                      child: Image.memory(
                        state.photoSearchImageBytes!,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                CircularProgressIndicator(color: t.accent),
                const SizedBox(height: 16),
                Text(
                  stageText,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: t.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'AI 正在识别题干并独立推导答案与解析，请稍候…',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12.5, color: t.textSecondary),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: notifier.cancelPhotoSearch,
                  icon: const Icon(Icons.close, size: 16),
                  label: const Text('取消'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResultsView(
    BuildContext context,
    InouTokens t,
    AppState state,
    AppStoreNotifier notifier,
    PhotoSearchSession session, {
    required bool wide,
  }) {
    final ws = state.activeWorkspace;
    final unsavedLibraryCount = session.items
        .where(
          (it) =>
              it.savedQuestionId == null ||
              !ws.questions.any((q) => q.id == it.savedQuestionId),
        )
        .length;
    final unsavedWrongCount = session.items
        .where(
          (it) =>
              it.savedQuestionId == null ||
              !ws.wrongItems.any((w) => w.questionId == it.savedQuestionId),
        )
        .length;

    final imageBytes = state.photoSearchImageBytes;

    return Column(
      children: [
        Container(
          color: t.surface,
          padding: EdgeInsets.fromLTRB(wide ? 20 : 14, 10, wide ? 20 : 14, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                alignment: WrapAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      InouBadge(
                        label: SubjectCatalog.labelOf(session.subject),
                        tone: InouBadgeTone.accent,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          session.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: t.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '共 ${session.items.length} 题 · AI 独立求解',
                        style: TextStyle(fontSize: 12, color: t.textMuted),
                      ),
                    ],
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      OutlinedButton.icon(
                        onPressed: unsavedLibraryCount == 0
                            ? null
                            : () async {
                                final res = await notifier
                                    .saveAllPhotoSearchItems(
                                      session.id,
                                      alsoAddToWrongBook: false,
                                    );
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      res.addedLibrary > 0
                                          ? '已将 ${res.addedLibrary} 道题加入题库'
                                          : '题目均已在题库中',
                                    ),
                                    action: SnackBarAction(
                                      label: '去题库',
                                      onPressed: () => context.go('/library'),
                                    ),
                                  ),
                                );
                              },
                        icon: Icon(
                          unsavedLibraryCount == 0
                              ? Icons.check_circle_outline
                              : Icons.library_add_outlined,
                          size: 16,
                        ),
                        label: Text(
                          unsavedLibraryCount == 0
                              ? '已全部入库'
                              : '全部加入题库 ($unsavedLibraryCount)',
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: unsavedWrongCount == 0
                            ? null
                            : () async {
                                final res = await notifier
                                    .saveAllPhotoSearchItems(
                                      session.id,
                                      alsoAddToWrongBook: true,
                                    );
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      '已同步加入题库（新增 ${res.addedLibrary} 题）与错题本（新增 ${res.addedWrong} 题）',
                                    ),
                                    action: SnackBarAction(
                                      label: '去错题本',
                                      onPressed: () => context.go('/wrongbook'),
                                    ),
                                  ),
                                );
                              },
                        icon: Icon(
                          unsavedWrongCount == 0
                              ? Icons.bookmark_added_outlined
                              : Icons.bookmark_add_outlined,
                          size: 16,
                        ),
                        label: Text(
                          unsavedWrongCount == 0 ? '已全部加入错题本' : '全部加入错题本',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if (session.traces.isNotEmpty) ...[
                const SizedBox(height: 8),
                InouThinkingDisclosure(traces: session.traces),
              ],
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: wide
              ? Row(
                  children: [
                    if (imageBytes != null) ...[
                      Expanded(
                        flex: 4,
                        child: _PhotoSearchImageViewport(
                          imageBytes: imageBytes,
                          aspectRatio: _imageAspectRatio,
                          items: session.items,
                          selectedId: _selectedItemId,
                          onSelect: (id) =>
                              setState(() => _selectedItemId = id),
                        ),
                      ),
                      const VerticalDivider(width: 1),
                    ],
                    Expanded(
                      flex: 7,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: session.items.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (ctx, i) {
                          final item = session.items[i];
                          return _PhotoSearchResultCard(
                            appState: state,
                            session: session,
                            item: item,
                            selected: item.id == _selectedItemId,
                            solving: state.photoSearchSolvingItemIds.contains(
                              item.id,
                            ),
                            onSelect: () =>
                                setState(() => _selectedItemId = item.id),
                            notifier: notifier,
                          );
                        },
                      ),
                    ),
                  ],
                )
              : ListView(
                  padding: const EdgeInsets.all(14),
                  children: [
                    if (imageBytes != null) ...[
                      SizedBox(
                        height: 200,
                        child: _PhotoSearchImageViewport(
                          imageBytes: imageBytes,
                          aspectRatio: _imageAspectRatio,
                          items: session.items,
                          selectedId: _selectedItemId,
                          onSelect: (id) =>
                              setState(() => _selectedItemId = id),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    for (final item in session.items)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _PhotoSearchResultCard(
                          appState: state,
                          session: session,
                          item: item,
                          selected: item.id == _selectedItemId,
                          solving: state.photoSearchSolvingItemIds.contains(
                            item.id,
                          ),
                          onSelect: () =>
                              setState(() => _selectedItemId = item.id),
                          notifier: notifier,
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _PhotoActionTile extends StatelessWidget {
  const _PhotoActionTile({
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
      child: Column(
        children: [
          Icon(icon, size: 26, color: accent ? t.accent : t.textPrimary),
          const SizedBox(height: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 14.5,
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

class _PhotoSearchImageViewport extends StatelessWidget {
  const _PhotoSearchImageViewport({
    required this.imageBytes,
    required this.aspectRatio,
    required this.items,
    required this.selectedId,
    required this.onSelect,
  });

  final Uint8List imageBytes;
  final double aspectRatio;
  final List<PhotoSearchItem> items;
  final String? selectedId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final t = context.inou;
    return Container(
      color: t.canvas,
      padding: const EdgeInsets.all(12),
      child: InteractiveViewer(
        minScale: 0.8,
        maxScale: 4.0,
        child: Center(
          child: AspectRatio(
            aspectRatio: aspectRatio.clamp(0.4, 2.2),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: t.borderHairline),
              ),
              clipBehavior: Clip.antiAlias,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final w = constraints.maxWidth;
                  final h = constraints.maxHeight;
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.memory(imageBytes, fit: BoxFit.fill),
                      for (var i = 0; i < items.length; i++)
                        _buildBboxOverlay(items[i], i, w, h, t),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBboxOverlay(
    PhotoSearchItem item,
    int index,
    double w,
    double h,
    InouTokens t,
  ) {
    final bbox =
        item.question.bbox ??
        NormalizedBbox(
          (80 + index * 200).clamp(40, 780),
          50,
          (250 + index * 200).clamp(160, 950),
          950,
        );
    final isSelected = item.id == selectedId;
    final boxColor = isSelected ? t.accent : const Color(0xFF64748B);

    return Positioned(
      left: w * (bbox.xmin / 1000),
      top: h * (bbox.ymin / 1000),
      width: w * ((bbox.xmax - bbox.xmin) / 1000).clamp(0.1, 1.0),
      height: h * ((bbox.ymax - bbox.ymin) / 1000).clamp(0.06, 1.0),
      child: GestureDetector(
        onTap: () => onSelect(item.id),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: boxColor.withValues(alpha: isSelected ? 0.16 : 0.05),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: boxColor, width: isSelected ? 2.2 : 1.1),
          ),
          child: Align(
            alignment: Alignment.topLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: boxColor,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '#${item.sortOrder}',
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PhotoSearchResultCard extends StatelessWidget {
  const _PhotoSearchResultCard({
    required this.appState,
    required this.session,
    required this.item,
    required this.selected,
    required this.solving,
    required this.onSelect,
    required this.notifier,
  });

  final AppState appState;
  final PhotoSearchSession session;
  final PhotoSearchItem item;
  final bool selected;
  final bool solving;
  final VoidCallback onSelect;
  final AppStoreNotifier notifier;

  @override
  Widget build(BuildContext context) {
    final t = context.inou;
    final ws = appState.activeWorkspace;
    final q = item.question;
    final isInLibrary =
        item.savedQuestionId != null &&
        ws.questions.any((eq) => eq.id == item.savedQuestionId);
    final isInWrongBook =
        item.savedQuestionId != null &&
        ws.wrongItems.any((w) => w.questionId == item.savedQuestionId);

    final trustTone = q.meta.answerSource == AnswerSource.aiVerified
        ? InouBadgeTone.accent
        : InouBadgeTone.warning;
    final trustLabel = q.meta.answerSource == AnswerSource.aiVerified
        ? 'AI 求解 · 已自检'
        : 'AI 求解 · 建议核对';
    final answerText = item.effectiveAnswerSummary;
    final targetQuestionId = isInLibrary ? item.savedQuestionId! : q.id;

    return InouSurface(
      onTap: onSelect,
      borderColor: selected ? t.accent : t.borderHairline,
      borderWidth: selected ? 1.6 : 0.9,
      padding: const EdgeInsets.all(15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    InouBadge(
                      label: '第 ${item.sortOrder} 题 · ${q.displayKindLabel}',
                      tone: InouBadgeTone.accent,
                    ),
                    PopupMenuButton<String>(
                      tooltip: '切换学科分类',
                      initialValue: q.meta.subject,
                      onSelected: (nextSub) => notifier.updatePhotoSearchItem(
                        session.id,
                        item.copyWith(
                          question: q.copyWith(
                            meta: q.meta.copyWith(subject: nextSub),
                          ),
                        ),
                      ),
                      itemBuilder: (_) => [
                        for (final entry in SubjectCatalog.labels.entries)
                          PopupMenuItem(
                            value: entry.key,
                            child: Row(
                              children: [
                                Text(entry.value),
                                if (entry.key == q.meta.subject) ...[
                                  const Spacer(),
                                  Icon(Icons.check, size: 16, color: t.accent),
                                ],
                              ],
                            ),
                          ),
                      ],
                      child: InouBadge(
                        label: SubjectCatalog.labelOf(q.meta.subject),
                        tone: InouBadgeTone.neutral,
                      ),
                    ),
                    InouBadge(label: trustLabel, tone: trustTone),
                    if (isInLibrary)
                      const InouBadge(
                        label: '已在题库',
                        tone: InouBadgeTone.success,
                      ),
                    if (isInWrongBook)
                      const InouBadge(
                        label: '已在错题本',
                        tone: InouBadgeTone.danger,
                      ),
                  ],
                ),
              ),
              if (solving)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: t.accent,
                    ),
                  ),
                )
              else
                IconButton(
                  tooltip: '重新求解',
                  visualDensity: VisualDensity.compact,
                  onPressed: () async {
                    final ok = await notifier.reSolvePhotoSearchItem(
                      session.id,
                      item.id,
                    );
                    if (!context.mounted || ok) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(AiUserErrorMessages.solveRetryHint()),
                      ),
                    );
                  },
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                ),
              IconButton(
                tooltip: '编辑题目或答案',
                visualDensity: VisualDensity.compact,
                onPressed: () async {
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                  final edited = await showQuestionEditorDialog(
                    context,
                    state: appState,
                    existing: q,
                    defaultSubject: q.meta.subject,
                  );
                  if (edited != null) {
                    final formatted = edited.formatReferenceAnswer();
                    await notifier.updatePhotoSearchItem(
                      session.id,
                      item.copyWith(
                        question: edited,
                        answerSummary: formatted.isNotEmpty
                            ? formatted
                            : item.answerSummary,
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.edit_outlined, size: 18),
              ),
            ],
          ),
          if (q.header.title.trim().isNotEmpty &&
              q.header.title.trim() != q.plainText.trim()) ...[
            const SizedBox(height: 8),
            Text(
              q.header.title,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: t.textPrimary,
              ),
            ),
          ],
          const SizedBox(height: 6),
          ContentBlockRenderer(blocks: q.prompt),
          _QuestionBodyPreview(question: q),
          const SizedBox(height: 12),
          InouSurface(
            backgroundColor: t.accentSoft,
            borderColor: t.accent.withValues(alpha: 0.35),
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.auto_awesome, size: 15, color: t.accent),
                    const SizedBox(width: 6),
                    Text(
                      'AI 参考答案',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: t.accent,
                      ),
                    ),
                    const Spacer(),
                    InouBadge(
                      label: '置信度 ${(item.confidence * 100).round()}%',
                      tone: item.confidence >= 0.75
                          ? InouBadgeTone.success
                          : InouBadgeTone.warning,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                if (solving)
                  Row(
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: t.accent,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'AI 正在独立求解并生成解析…',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: t.textSecondary,
                        ),
                      ),
                    ],
                  )
                else
                  SelectableText(
                    answerText.isNotEmpty ? answerText : '（详见下方解题步骤）',
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: t.textPrimary,
                      height: 1.4,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          InouSurface(
            subtle: true,
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '解题思路与步骤',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: t.textSecondary,
                  ),
                ),
                const SizedBox(height: 6),
                if (q.explanation.isNotEmpty)
                  ContentBlockRenderer(blocks: q.explanation)
                else
                  Text(
                    '暂无详细步骤，可点击右上角「重新求解」生成完整过程。',
                    style: TextStyle(fontSize: 12.5, color: t.textMuted),
                  ),
                if (item.keyPoints.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final kp in item.keyPoints)
                        InouBadge(label: '#$kp'),
                    ],
                  ),
                ],
                if (item.pitfallNote != null &&
                    item.pitfallNote!.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: t.warningSoft,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '易错提醒：${item.pitfallNote}',
                      style: TextStyle(fontSize: 12, color: t.warning),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (q.meta.uncertainNote != null &&
              q.meta.uncertainNote!.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            InouSurface(
              backgroundColor: t.warningSoft,
              borderColor: t.warning.withValues(alpha: 0.35),
              padding: const EdgeInsets.all(10),
              child: Text(
                q.meta.uncertainNote!,
                style: TextStyle(fontSize: 12, color: t.warning),
              ),
            ),
          ],
          if (item.duplicateOfTitle != null && !isInLibrary) ...[
            const SizedBox(height: 8),
            InouSurface(
              subtle: true,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              child: Row(
                children: [
                  Icon(Icons.copy_all_outlined, size: 15, color: t.warning),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '题库已有相似题「${item.duplicateOfTitle}」，如仍需记录可手动加入',
                      style: TextStyle(fontSize: 12, color: t.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                style: FilledButton.styleFrom(
                  backgroundColor: t.accentSoft,
                  foregroundColor: t.accent,
                  elevation: 0,
                ),
                onPressed: isInLibrary
                    ? null
                    : () async {
                        final saved = await notifier
                            .savePhotoSearchItemToLibrary(session.id, item.id);
                        if (!context.mounted || saved == null) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Text('已加入题库'),
                            action: SnackBarAction(
                              label: '去题库',
                              onPressed: () => context.go('/library'),
                            ),
                          ),
                        );
                      },
                icon: Icon(
                  isInLibrary
                      ? Icons.check_circle_outline
                      : Icons.library_add_outlined,
                  size: 16,
                ),
                label: Text(isInLibrary ? '已加入题库' : '加入题库'),
              ),
              FilledButton.icon(
                onPressed: isInWrongBook
                    ? null
                    : () async {
                        final saved = await notifier
                            .savePhotoSearchItemToWrongBook(
                              session.id,
                              item.id,
                            );
                        if (!context.mounted || saved.wrongItem == null) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Text('已加入题库与错题本'),
                            action: SnackBarAction(
                              label: '去错题本',
                              onPressed: () => context.go('/wrongbook'),
                            ),
                          ),
                        );
                      },
                icon: Icon(
                  isInWrongBook
                      ? Icons.bookmark_added_outlined
                      : Icons.bookmark_add_outlined,
                  size: 16,
                ),
                label: Text(isInWrongBook ? '已在错题本' : '加入错题本'),
              ),
              OutlinedButton.icon(
                onPressed: () => notifier.openCopilot(
                  questionId: targetQuestionId,
                  hintLevel: HintLevel.l3FullSolution,
                ),
                icon: const Icon(Icons.auto_awesome_outlined, size: 16),
                label: const Text('问诺诺'),
              ),
              OutlinedButton.icon(
                onPressed: () => notifier.openBlackboard(
                  questionId: targetQuestionId,
                  hintLevel: HintLevel.l3FullSolution,
                ),
                icon: const Icon(Icons.co_present_outlined, size: 16),
                label: const Text('黑板讲题'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QuestionBodyPreview extends StatelessWidget {
  const _QuestionBodyPreview({required this.question});

  final Question question;

  static Map<String, Object?> _asMap(Object? raw) {
    if (raw is Map<String, Object?>) return raw;
    if (raw is Map) {
      return raw.map((k, v) => MapEntry(k.toString(), v));
    }
    return const <String, Object?>{};
  }

  static String _blocksPlain(Object? rawContent, {String fallback = ''}) {
    if (rawContent is List) {
      final blocks = <ContentBlock>[];
      for (final item in rawContent) {
        if (item is Map) {
          try {
            blocks.add(ContentBlock.fromJson(_asMap(item)));
          } catch (_) {}
        }
      }
      final txt = ContentTextUtils.extractPlainText(blocks).trim();
      if (txt.isNotEmpty) return txt;
    }
    return fallback;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.inou;
    if (question.kind == QuestionKind.choice) {
      final rawOpts =
          question.body['options'] as List<Object?>? ?? const [];
      if (rawOpts.isEmpty) return const SizedBox.shrink();
      final selectedIds = <String>{};
      final sets = question.grading['answerSets'] as List<Object?>? ?? const [];
      if (sets.isNotEmpty && sets.first is Map) {
        final exp = _asMap(_asMap(sets.first)['expected']);
        for (final id in (exp['selectedIds'] as List<Object?>? ?? const [])) {
          selectedIds.add(id.toString());
        }
      }
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final rawOpt in rawOpts)
              Builder(
                builder: (context) {
                  final om = _asMap(rawOpt);
                  final oid = (om['id'] ?? '').toString();
                  final optTxt = _blocksPlain(
                    om['content'],
                    fallback: (om['text'] ?? '').toString(),
                  );
                  final isAns = selectedIds.contains(oid);
                  return Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 4),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: isAns ? t.successSoft : t.surfaceMuted,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isAns
                            ? t.success.withValues(alpha: 0.45)
                            : t.borderHairline,
                      ),
                    ),
                    child: Text(
                      '$oid. $optTxt',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isAns ? FontWeight.w700 : FontWeight.w500,
                        color: t.textPrimary,
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      );
    }

    if (question.isSequence) {
      final bank = question.body['bank'] as List<Object?>? ?? const [];
      if (bank.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final rawItem in bank)
              Builder(
                builder: (context) {
                  final bm = _asMap(rawItem);
                  final label = _blocksPlain(
                    bm['content'],
                    fallback: (bm['text'] ?? bm['id'] ?? '').toString(),
                  );
                  return InouBadge(label: label);
                },
              ),
          ],
        ),
      );
    }

    if (question.kind == QuestionKind.match) {
      final left = question.body['left'] as List<Object?>? ?? const [];
      final right = question.body['right'] as List<Object?>? ?? const [];
      if (left.isEmpty && right.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final item in left)
              InouBadge(
                label: _blocksPlain(
                  _asMap(item)['content'],
                  fallback: (_asMap(item)['id'] ?? '').toString(),
                ),
                tone: InouBadgeTone.accent,
              ),
            for (final item in right)
              InouBadge(
                label: _blocksPlain(
                  _asMap(item)['content'],
                  fallback: (_asMap(item)['id'] ?? '').toString(),
                ),
              ),
          ],
        ),
      );
    }

    if (question.kind == QuestionKind.group) {
      final subs = question.subQuestions;
      if (subs.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < subs.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '(${i + 1}) ${subs[i].plainText}',
                  style: TextStyle(fontSize: 12.5, color: t.textSecondary),
                ),
              ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }
}
