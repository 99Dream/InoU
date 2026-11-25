import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:inou_domain/inou_domain.dart';
import 'package:inou_ui_kit/inou_ui_kit.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/state/app_store.dart';
import '../../capture/presentation/capture_sheet.dart';
import '../../library/presentation/question_editor_dialog.dart';

/// Split-View Original Exam Inspector + Editable Batch Draft Commit Screen.
class SplitProofreadPage extends ConsumerStatefulWidget {
  const SplitProofreadPage({super.key});

  @override
  ConsumerState<SplitProofreadPage> createState() => _SplitProofreadPageState();
}

class _SplitProofreadPageState extends ConsumerState<SplitProofreadPage> {
  String? _selectedDraftId;
  late final TextEditingController _docTitleCtrl = TextEditingController();
  bool _titleInitialized = false;
  Uint8List? _measuredBytes;
  double _imageAspectRatio = 595 / 842;

  @override
  void dispose() {
    _docTitleCtrl.dispose();
    super.dispose();
  }

  void _measureImageRatioIfNeeded(Uint8List? bytes) {
    if (bytes == null || identical(bytes, _measuredBytes)) return;
    _measuredBytes = bytes;
    ui.decodeImageFromList(bytes, (img) {
      if (!mounted || img.height <= 0) return;
      setState(() => _imageAspectRatio = img.width / img.height);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.inou;
    final state = ref.watch(appStoreProvider);
    final notifier = ref.read(appStoreProvider.notifier);
    final drafts = state.activeWorkspace.captureDrafts;
    final windowClass = AdaptiveScope.of(context);
    final wide = windowClass != WindowClass.compact;
    final examBytes = state.captureExamImageBytes;
    _measureImageRatioIfNeeded(examBytes);

    if (!_titleInitialized &&
        state.activeWorkspace.captureDocTitle.isNotEmpty) {
      _docTitleCtrl.text = state.activeWorkspace.captureDocTitle;
      _titleInitialized = true;
    }

    if (drafts.isNotEmpty &&
        (_selectedDraftId == null ||
            !drafts.any((d) => d.id == _selectedDraftId))) {
      _selectedDraftId = drafts.first.id;
    }

    final commitCount = drafts
        .where((d) => d.confirmed && !d.skipDuplicate)
        .length;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/home'),
        ),
        title: const Text('识题校对'),
        actions: [
          if (drafts.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: FilledButton.icon(
                onPressed: commitCount == 0
                    ? null
                    : () async {
                        final res = await notifier.commitCaptureDrafts(
                          customDocTitle: _docTitleCtrl.text,
                        );
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              '已入库 ${res.importedCount} 道题'
                              '${res.wrongCount > 0 ? '，其中 ${res.wrongCount} 道加入错题本' : ''}',
                            ),
                          ),
                        );
                        context.go('/library');
                      },
                icon: const Icon(Icons.check_circle_outline, size: 17),
                label: Text('入库 ($commitCount 题)'),
              ),
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: drafts.isEmpty
            ? InouEmptyState(
                icon: Icons.photo_camera_outlined,
                title: '暂无待校对的题目',
                subtitle: '拍照或导入试卷图片即可开始识别。',
                action: FilledButton(
                  onPressed: () => showCaptureModal(context),
                  child: const Text('拍照录题'),
                ),
              )
            : Column(
              children: [
                Container(
                  color: t.surface,
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _docTitleCtrl,
                              decoration: const InputDecoration(
                                labelText: '试卷名称',
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          TextButton(
                            onPressed: () async {
                              await notifier.clearCaptureDrafts();
                              if (!context.mounted) return;
                              context.go('/home');
                            },
                            child: const Text('清空'),
                          ),
                        ],
                      ),
                      if (state.captureTraces.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        InouThinkingDisclosure(
                          traces: state.captureTraces
                              .map((e) => e.toDisplayLine())
                              .toList(growable: false),
                        ),
                      ],
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: wide
                      ? Row(
                          children: [
                            Expanded(
                              flex: 5,
                              child: _PaperBboxViewport(
                                imageBytes: examBytes,
                                aspectRatio: _imageAspectRatio,
                                drafts: drafts,
                                selectedId: _selectedDraftId,
                                onSelect: (id) =>
                                    setState(() => _selectedDraftId = id),
                              ),
                            ),
                            const VerticalDivider(width: 1),
                            Expanded(
                              flex: 6,
                              child: _DraftCardList(
                                appState: state,
                                drafts: drafts,
                                selectedId: _selectedDraftId,
                                onSelect: (id) =>
                                    setState(() => _selectedDraftId = id),
                                onUpdate: notifier.updateCaptureDraft,
                                onDelete: notifier.deleteCaptureDraft,
                              ),
                            ),
                          ],
                        )
                      : ListView(
                          padding: const EdgeInsets.all(14),
                          children: [
                            if (examBytes != null) ...[
                              SizedBox(
                                height: 240,
                                child: _PaperBboxViewport(
                                  imageBytes: examBytes,
                                  aspectRatio: _imageAspectRatio,
                                  drafts: drafts,
                                  selectedId: _selectedDraftId,
                                  onSelect: (id) =>
                                      setState(() => _selectedDraftId = id),
                                ),
                              ),
                              const SizedBox(height: 12),
                            ],
                            ...drafts.map(
                              (d) => Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _DraftEditorCard(
                                  appState: state,
                                  draft: d,
                                  selected: d.id == _selectedDraftId,
                                  onSelect: () =>
                                      setState(() => _selectedDraftId = d.id),
                                  onUpdate: notifier.updateCaptureDraft,
                                  onDelete: () =>
                                      notifier.deleteCaptureDraft(d.id),
                                ),
                              ),
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

class _PaperBboxViewport extends StatelessWidget {
  const _PaperBboxViewport({
    required this.imageBytes,
    required this.aspectRatio,
    required this.drafts,
    required this.selectedId,
    required this.onSelect,
  });

  final Uint8List? imageBytes;
  final double aspectRatio;
  final List<CaptureDraftItem> drafts;
  final String? selectedId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final t = context.inou;
    return Container(
      color: t.canvas,
      padding: const EdgeInsets.all(14),
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
                      if (imageBytes != null)
                        Image.memory(imageBytes!, fit: BoxFit.fill)
                      else
                        Container(color: Colors.white),
                      for (var i = 0; i < drafts.length; i++)
                        _buildBboxOverlay(
                          drafts[i],
                          i,
                          w,
                          h,
                          t,
                          hasPhoto: imageBytes != null,
                        ),
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
    CaptureDraftItem draft,
    int index,
    double w,
    double h,
    InouTokens t, {
    required bool hasPhoto,
  }) {
    final bbox =
        draft.question.bbox ??
        NormalizedBbox(
          (80 + index * 200).clamp(40, 780),
          50,
          (250 + index * 200).clamp(160, 950),
          950,
        );
    final isSelected = draft.id == selectedId;
    final boxColor = draft.flaggedWrong
        ? t.redPen
        : (isSelected ? t.accent : const Color(0xFF64748B));

    return Positioned(
      left: w * (bbox.xmin / 1000),
      top: h * (bbox.ymin / 1000),
      width: w * ((bbox.xmax - bbox.xmin) / 1000).clamp(0.1, 1.0),
      height: h * ((bbox.ymax - bbox.ymin) / 1000).clamp(0.06, 1.0),
      child: GestureDetector(
        onTap: () => onSelect(draft.id),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: boxColor.withValues(alpha: isSelected ? 0.16 : 0.06),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: boxColor, width: isSelected ? 2.2 : 1.1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: boxColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '#${draft.sortOrder}',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  if (draft.flaggedWrong) ...[
                    const SizedBox(width: 4),
                    Icon(Icons.close_rounded, size: 14, color: t.redPen),
                  ],
                ],
              ),
              if (!hasPhoto) ...[
                const SizedBox(height: 3),
                Expanded(
                  child: Text(
                    draft.question.plainText,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10,
                      color: Color(0xFF334155),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DraftCardList extends StatelessWidget {
  const _DraftCardList({
    required this.appState,
    required this.drafts,
    required this.selectedId,
    required this.onSelect,
    required this.onUpdate,
    required this.onDelete,
  });

  final AppState appState;
  final List<CaptureDraftItem> drafts;
  final String? selectedId;
  final ValueChanged<String> onSelect;
  final ValueChanged<CaptureDraftItem> onUpdate;
  final ValueChanged<String> onDelete;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: drafts.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final d = drafts[index];
        return _DraftEditorCard(
          appState: appState,
          draft: d,
          selected: d.id == selectedId,
          onSelect: () => onSelect(d.id),
          onUpdate: onUpdate,
          onDelete: () => onDelete(d.id),
        );
      },
    );
  }
}

class _DraftEditorCard extends StatelessWidget {
  const _DraftEditorCard({
    required this.appState,
    required this.draft,
    required this.selected,
    required this.onSelect,
    required this.onUpdate,
    required this.onDelete,
  });

  final AppState appState;
  final CaptureDraftItem draft;
  final bool selected;
  final VoidCallback onSelect;
  final ValueChanged<CaptureDraftItem> onUpdate;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final t = context.inou;
    final q = draft.question;
    final answerSource = q.meta.answerSource;
    final sourceTone = switch (answerSource) {
      AnswerSource.paper || AnswerSource.user => InouBadgeTone.success,
      AnswerSource.aiVerified => InouBadgeTone.accent,
      AnswerSource.ai => InouBadgeTone.warning,
    };

    return InouSurface(
      onTap: onSelect,
      borderColor: selected ? t.accent : t.borderHairline,
      padding: const EdgeInsets.all(14),
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
                      label: '第 ${draft.sortOrder} 题 · ${q.displayKindLabel}',
                      tone: InouBadgeTone.accent,
                    ),
                    PopupMenuButton<String>(
                      tooltip: '点击切换学科分类',
                      initialValue: q.meta.subject,
                      onSelected: (nextSub) => onUpdate(
                        draft.copyWith(
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
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: t.accentSoft,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: t.accent.withValues(alpha: 0.45),
                            width: 1.0,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              SubjectCatalog.labelOf(q.meta.subject),
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: t.accent,
                              ),
                            ),
                            const SizedBox(width: 2),
                            Icon(
                              Icons.arrow_drop_down,
                              size: 14,
                              color: t.accent,
                            ),
                          ],
                        ),
                      ),
                    ),
                    InouBadge(label: answerSource.label, tone: sourceTone),
                  ],
                ),
              ),
              IconButton(
                tooltip: '编辑题目或答案',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.edit_outlined, size: 18),
                onPressed: () async {
                  final edited = await showQuestionEditorDialog(
                    context,
                    state: appState,
                    existing: q,
                    defaultSubject: q.meta.subject,
                  );
                  if (edited != null) {
                    onUpdate(draft.copyWith(question: edited));
                  }
                },
              ),
              IconButton(
                tooltip: '移除此条',
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.delete_outline, size: 18, color: t.danger),
                onPressed: onDelete,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            q.header.title,
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              color: t.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          ContentBlockRenderer(blocks: q.prompt),
          if (q.meta.uncertainNote != null) ...[
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
          if (draft.duplicateOfTitle != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: t.surfaceMuted,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: t.borderHairline),
              ),
              child: Row(
                children: [
                  Icon(Icons.copy_all_outlined, size: 15, color: t.warning),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '题库已有相似题「${draft.duplicateOfTitle}」',
                      style: TextStyle(fontSize: 12, color: t.textSecondary),
                    ),
                  ),
                  Switch(
                    value: draft.skipDuplicate,
                    onChanged: (skip) => onUpdate(
                      draft.copyWith(
                        skipDuplicate: skip,
                        confirmed: skip ? draft.confirmed : true,
                      ),
                    ),
                  ),
                  Text(
                    draft.skipDuplicate ? '已跳过' : '仍保留',
                    style: TextStyle(fontSize: 11.5, color: t.textMuted),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilterChip(
                selected: draft.flaggedWrong,
                label: Text(draft.flaggedWrong ? '记为错题' : '标错'),
                onSelected: (on) => onUpdate(
                  draft.copyWith(
                    flaggedWrong: on,
                    teacherMark: on ? 'wrong' : 'none',
                  ),
                ),
              ),
              FilterChip(
                selected: draft.confirmed,
                label: Text(draft.confirmed ? '入库' : '跳过'),
                onSelected: (on) => onUpdate(draft.copyWith(confirmed: on)),
              ),
            ],
          ),
          if (draft.flaggedWrong) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final tag in ErrorTag.values)
                  FilterChip(
                    label: Text(
                      tag.label,
                      style: const TextStyle(fontSize: 11),
                    ),
                    selected: draft.errorTags.contains(tag),
                    onSelected: (on) {
                      final next = List<ErrorTag>.from(draft.errorTags);
                      if (on) {
                        if (!next.contains(tag)) next.add(tag);
                      } else {
                        next.remove(tag);
                      }
                      onUpdate(draft.copyWith(errorTags: next));
                    },
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
