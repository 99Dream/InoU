import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:inou_ai/inou_ai.dart';
import 'package:inou_domain/inou_domain.dart';
import 'package:inou_ui_kit/inou_ui_kit.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/state/app_store.dart';
import '../../capture/presentation/capture_sheet.dart';
import '../../settings/presentation/settings_modal.dart';

class WrongbookPage extends ConsumerStatefulWidget {
  const WrongbookPage({super.key});

  @override
  ConsumerState<WrongbookPage> createState() => _WrongbookPageState();
}

class _WrongbookPageState extends ConsumerState<WrongbookPage> {
  MasteryState? _stateFilter;
  String? _subjectFilter;
  String? _selectedWrongId;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appStoreProvider);
    final notifier = ref.read(appStoreProvider.notifier);
    final ws = state.activeWorkspace;
    final streakTarget = state.snapshot.preferences.masteryStreak;
    final windowClass = AdaptiveScope.of(context);
    final wide = windowClass != WindowClass.compact;

    final qMap = {for (final q in ws.questions) q.id: q};

    final counts = <MasteryState, int>{
      for (final s in MasteryState.values) s: 0,
    };
    for (final w in ws.wrongItems) {
      counts[w.mastery] = (counts[w.mastery] ?? 0) + 1;
    }

    final filtered = ws.wrongItems.where((w) {
      if (_stateFilter != null && w.mastery != _stateFilter) return false;
      final q = qMap[w.questionId];
      if (_subjectFilter != null && q?.meta.subject != _subjectFilter) {
        return false;
      }
      return true;
    }).toList();

    WrongItem? selectedItem;
    if (filtered.isNotEmpty) {
      selectedItem = filtered.firstWhere(
        (w) => w.id == _selectedWrongId,
        orElse: () => filtered.first,
      );
      _selectedWrongId = selectedItem.id;
    }

    final unmasteredIds = ws.wrongItems
        .where((w) => w.mastery != MasteryState.mastered)
        .map((w) => w.questionId)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('错题本'),
        actions: [
          if (unmasteredIds.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton.icon(
                onPressed: () async {
                  await notifier.startPracticeSession(
                    title: '错题攻坚重练 (${unmasteredIds.length} 题)',
                    kind: PracticeKind.redo,
                    inputMode: InputMode.standard,
                    feedbackTiming: FeedbackTiming.instant,
                    questionIds: unmasteredIds,
                  );
                  if (context.mounted) context.go('/practice');
                },
                icon: const Icon(Icons.replay_rounded, size: 17),
                label: Text('复练未掌握 (${unmasteredIds.length})'),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(wide ? 20 : 14, 4, wide ? 20 : 14, 10),
            child: Row(
              children: [
                PopupMenuButton<String>(
                  tooltip: '按学科筛选',
                  onSelected: (v) => setState(
                    () => _subjectFilter = v == '__all__' ? null : v,
                  ),
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: '__all__', child: Text('全科')),
                    for (final entry in SubjectCatalog.labels.entries)
                      PopupMenuItem(value: entry.key, child: Text(entry.value)),
                  ],
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: _subjectFilter != null
                          ? context.inou.accent
                          : context.inou.surfaceMuted,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _subjectFilter != null
                              ? SubjectCatalog.labelOf(_subjectFilter!)
                              : '全科',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: _subjectFilter != null
                                ? FontWeight.w700
                                : FontWeight.w600,
                            color: _subjectFilter != null
                                ? Colors.white
                                : context.inou.textPrimary,
                          ),
                        ),
                        Icon(
                          Icons.arrow_drop_down,
                          size: 16,
                          color: _subjectFilter != null
                              ? Colors.white
                              : context.inou.textMuted,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        FilterChip(
                          label: Text('全部 (${ws.wrongItems.length})'),
                          selected: _stateFilter == null,
                          onSelected: (_) =>
                              setState(() => _stateFilter = null),
                        ),
                        const SizedBox(width: 6),
                        for (final ms in MasteryState.values)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: FilterChip(
                              label: Text('${ms.label} (${counts[ms] ?? 0})'),
                              selected: _stateFilter == ms,
                              onSelected: (on) =>
                                  setState(() => _stateFilter = on ? ms : null),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: filtered.isEmpty
                ? InouEmptyState(
                    icon: Icons.emoji_events_outlined,
                    title: ws.wrongItems.isEmpty ? '错题本还是空的' : '当前筛选下没有错题',
                    subtitle: '拍照录题标错或做错的题目会收敛到这里。',
                    action: ws.wrongItems.isEmpty
                        ? FilledButton.icon(
                            onPressed: () => showCaptureModal(context),
                            icon: const Icon(
                              Icons.camera_alt_outlined,
                              size: 16,
                            ),
                            label: const Text('拍照录错题'),
                          )
                        : null,
                  )
                : wide
                ? Row(
                    children: [
                      Expanded(
                        flex: 5,
                        child: _WrongList(
                          items: filtered,
                          qMap: qMap,
                          selectedId: selectedItem?.id,
                          streakTarget: streakTarget,
                          onSelect: (w) =>
                              setState(() => _selectedWrongId = w.id),
                        ),
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(
                        flex: 6,
                        child: selectedItem == null
                            ? const SizedBox.shrink()
                            : _WrongDetailPanel(
                                item: selectedItem,
                                question: qMap[selectedItem.questionId],
                                streakTarget: streakTarget,
                                state: state,
                                notifier: notifier,
                              ),
                      ),
                    ],
                  )
                : _WrongList(
                    items: filtered,
                    qMap: qMap,
                    selectedId: selectedItem?.id,
                    streakTarget: streakTarget,
                    onSelect: (w) {
                      setState(() => _selectedWrongId = w.id);
                      showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        builder: (sheetCtx) => FractionallySizedBox(
                          heightFactor: 0.86,
                          child: _WrongDetailPanel(
                            item: w,
                            question: qMap[w.questionId],
                            streakTarget: streakTarget,
                            state: state,
                            notifier: notifier,
                            onDismissSheet: () => Navigator.of(sheetCtx).pop(),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _WrongList extends StatelessWidget {
  const _WrongList({
    required this.items,
    required this.qMap,
    required this.selectedId,
    required this.streakTarget,
    required this.onSelect,
  });

  final List<WrongItem> items;
  final Map<String, Question> qMap;
  final String? selectedId;
  final int streakTarget;
  final ValueChanged<WrongItem> onSelect;

  @override
  Widget build(BuildContext context) {
    final t = context.inou;
    return ListView.separated(
      padding: const EdgeInsets.all(14),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final w = items[index];
        final q = qMap[w.questionId];
        final selected = w.id == selectedId;
        final tone = switch (w.mastery) {
          MasteryState.newWrong => InouBadgeTone.danger,
          MasteryState.learning => InouBadgeTone.warning,
          MasteryState.reviewing => InouBadgeTone.accent,
          MasteryState.mastered => InouBadgeTone.success,
        };
        return InouSurface(
          onTap: () => onSelect(w),
          borderColor: selected ? t.accent : t.borderHairline,
          borderWidth: selected ? 2.0 : 0.9,
          backgroundColor: selected ? t.accentSoft : t.surface,
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  InouBadge(label: w.mastery.label, tone: tone),
                  const SizedBox(width: 6),
                  if (q != null)
                    InouBadge(label: SubjectCatalog.labelOf(q.meta.subject)),
                  const Spacer(),
                  Text(
                    '连对 ${w.correctStreak}/$streakTarget',
                    style: InouTypography.tabular(
                      TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: t.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                q?.header.title ?? '错题 ${w.questionId}',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: t.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                q?.plainText ?? '',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: t.textSecondary),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _WrongDetailPanel extends StatefulWidget {
  const _WrongDetailPanel({
    required this.item,
    required this.question,
    required this.streakTarget,
    required this.state,
    required this.notifier,
    this.onDismissSheet,
  });

  final WrongItem item;
  final Question? question;
  final int streakTarget;
  final AppState state;
  final AppStoreNotifier notifier;
  final VoidCallback? onDismissSheet;

  @override
  State<_WrongDetailPanel> createState() => _WrongDetailPanelState();
}

class _WrongDetailPanelState extends State<_WrongDetailPanel> {
  late final TextEditingController _noteCtrl = TextEditingController(
    text: widget.item.note,
  );
  bool _generatingVariant = false;
  bool _showAnswer = true;

  @override
  void didUpdateWidget(covariant _WrongDetailPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id != widget.item.id ||
        (oldWidget.item.note != widget.item.note &&
            _noteCtrl.text != widget.item.note)) {
      _noteCtrl.text = widget.item.note;
    }
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _generateVariants(Question q) async {
    if (!widget.state.hasLiveAiKey) {
      final goSettings = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('生成同源变式题'),
          content: const Text('生成同源变式题需要连接实时 AI 模型，请先在设置中配置 API Key。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('去配置 AI'),
            ),
          ],
        ),
      );
      if (goSettings == true && mounted) {
        await showSettingsModal(context);
      }
      return;
    }
    setState(() => _generatingVariant = true);
    final res = await widget.notifier.generateTargetedDrill(
      subject: q.meta.subject,
      targetKpIds: q.meta.kpIds,
      targetKpNames: q.meta.tags,
      sourceWrongQuestion: q,
      count: 3,
    );
    if (!mounted) return;
    setState(() => _generatingVariant = false);
    if (res.errorMessage != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(res.errorMessage!)));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('AI 已生成 ${res.questions.length} 道同源变式题存入题库')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.inou;
    final w = widget.item;
    final q = widget.question;
    final progress = (w.correctStreak / widget.streakTarget).clamp(0.0, 1.0);

    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        InouSurface(
          subtle: true,
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '掌握进度 · ${w.mastery.label}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: t.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '连对 ${w.correctStreak}/${widget.streakTarget} · 错 ${w.wrongCount} 次',
                    style: InouTypography.tabular(
                      TextStyle(fontSize: 12, color: t.textSecondary),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: '移出错题本',
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      widget.onDismissSheet?.call();
                      widget.notifier.removeWrongItem(w.id);
                    },
                    icon: Icon(Icons.delete_outline, size: 18, color: t.danger),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  backgroundColor: t.surface,
                  color: w.mastery == MasteryState.mastered
                      ? t.success
                      : t.accent,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () async {
                        final out = await widget.notifier.simulateCorrectReview(
                          w.id,
                        );
                        if (!context.mounted) return;
                        final mastered =
                            out.item?.mastery == MasteryState.mastered;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              mastered
                                  ? '恭喜毕业！连续 ${widget.streakTarget} 次答对，已标记为「已掌握」'
                                  : '已记录一次答对（${out.item?.correctStreak}/${widget.streakTarget}）',
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.check_rounded, size: 16),
                      label: const Text('打卡答对 +1'),
                    ),
                  ),
                  if (q != null) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          await widget.notifier.startPracticeSession(
                            title: '错题重练 · ${q.header.title}',
                            kind: PracticeKind.redo,
                            inputMode: InputMode.standard,
                            feedbackTiming: FeedbackTiming.instant,
                            questionIds: [q.id],
                          );
                          if (context.mounted) context.go('/practice');
                        },
                        icon: const Icon(Icons.edit_outlined, size: 16),
                        label: const Text('真实重练'),
                      ),
                    ),
                  ],
                ],
              ),
              if (q != null) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () {
                        widget.onDismissSheet?.call();
                        widget.notifier.openCopilot(
                          questionId: q.id,
                          hintLevel: HintLevel.l3FullSolution,
                        );
                      },
                      icon: const Icon(Icons.auto_awesome_outlined, size: 15),
                      label: const Text('诺诺讲解'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () {
                        widget.onDismissSheet?.call();
                        widget.notifier.openBlackboard(
                          questionId: q.id,
                          hintLevel: HintLevel.l3FullSolution,
                          isPostMortem: true,
                        );
                      },
                      icon: const Icon(Icons.co_present_outlined, size: 15),
                      label: const Text('黑板板书'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _generatingVariant
                          ? null
                          : () => _generateVariants(q),
                      icon: const Icon(Icons.dynamic_feed_outlined, size: 15),
                      label: Text(_generatingVariant ? '出题中…' : 'AI 变式题 ×3'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (q != null) ...[
          Text(
            q.header.title,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: t.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          InouSurface(
            padding: const EdgeInsets.all(14),
            child: ContentBlockRenderer(blocks: q.prompt),
          ),
          const SizedBox(height: 10),
          if (w.myWrongAnswer.isNotEmpty)
            InouSurface(
              backgroundColor: t.dangerSoft,
              borderColor: t.danger.withValues(alpha: 0.35),
              padding: const EdgeInsets.all(12),
              child: Text(
                '我的历史错答：${w.myWrongAnswer}',
                style: TextStyle(fontSize: 12.5, color: t.danger),
              ),
            ),
          if (w.note.contains('【黑板板书笔记')) ...[
            const SizedBox(height: 10),
            InouSurface(
              backgroundColor: const Color(0xFF152D24),
              borderColor: const Color(0xFF86EFAC).withValues(alpha: 0.45),
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(
                        Icons.co_present_outlined,
                        size: 15,
                        color: Color(0xFFFDE047),
                      ),
                      SizedBox(width: 6),
                      Text(
                        '黑板板书笔记摘要',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFFDE047),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    w.note,
                    maxLines: 6,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.45,
                      color: Color(0xFFF8FAFC),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (q.explanation.isNotEmpty) ...[
            const SizedBox(height: 10),
            InkWell(
              onTap: () => setState(() => _showAnswer = !_showAnswer),
              child: Row(
                children: [
                  Text(
                    '正解与要点',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: t.accent,
                    ),
                  ),
                  Icon(
                    _showAnswer ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: t.accent,
                  ),
                ],
              ),
            ),
            if (_showAnswer) ...[
              const SizedBox(height: 8),
              InouSurface(
                backgroundColor: t.surfaceMuted,
                padding: const EdgeInsets.all(14),
                child: ContentBlockRenderer(blocks: q.explanation),
              ),
            ],
          ],
        ],
        const SizedBox(height: 16),
        Text(
          '错因标签',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: t.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final tag in ErrorTag.values)
              FilterChip(
                label: Text(tag.label),
                selected: w.errorTags.contains(tag),
                onSelected: (on) {
                  final next = List<ErrorTag>.from(w.errorTags);
                  if (on) {
                    if (!next.contains(tag)) next.add(tag);
                  } else {
                    next.remove(tag);
                  }
                  widget.notifier.updateWrongItemDetails(w.id, errorTags: next);
                },
              ),
          ],
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _noteCtrl,
          maxLines: 2,
          decoration: InputDecoration(
            labelText: '订正笔记',
            suffixIcon: IconButton(
              tooltip: '保存笔记',
              onPressed: () {
                widget.notifier.updateWrongItemDetails(
                  w.id,
                  note: _noteCtrl.text.trim(),
                );
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('笔记已保存')));
              },
              icon: const Icon(Icons.save_outlined),
            ),
          ),
        ),
      ],
    );
  }
}
