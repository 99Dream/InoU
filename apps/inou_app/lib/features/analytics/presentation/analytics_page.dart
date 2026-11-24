import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:inou_ai/inou_ai.dart';
import 'package:inou_domain/inou_domain.dart';
import 'package:inou_ui_kit/inou_ui_kit.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/state/app_store.dart';
import '../../settings/presentation/settings_modal.dart';

class AnalyticsPage extends ConsumerStatefulWidget {
  const AnalyticsPage({super.key});

  @override
  ConsumerState<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends ConsumerState<AnalyticsPage> {
  String _treeSubject = 'math';
  List<Question> _lastGeneratedDrill = const [];
  List<TutorToolTraceStep> _lastDrillTrace = const [];
  String? _lastDrillError;

  @override
  Widget build(BuildContext context) {
    final t = context.inou;
    final state = ref.watch(appStoreProvider);
    final notifier = ref.read(appStoreProvider.notifier);
    final ws = state.activeWorkspace;
    final snap = notifier.computeWeaknessSnapshot();
    final windowClass = AdaptiveScope.of(context);
    final wide = windowClass != WindowClass.compact;

    final radarAxes = [
      for (final entry in snap.subjectMasteryPercent.entries)
        RadarAxisDatum(
          label: SubjectCatalog.labelOf(entry.key),
          value: (entry.value / 100.0).clamp(0.05, 1.0),
        ),
    ];

    final tagPalette = <ErrorTag, Color>{
      ErrorTag.calc: const Color(0xFFEF4444),
      ErrorTag.careless: const Color(0xFFF59E0B),
      ErrorTag.concept: const Color(0xFF3F6AF5),
      ErrorTag.misread: const Color(0xFF8B5CF6),
      ErrorTag.method: const Color(0xFF10B981),
      ErrorTag.writing: const Color(0xFF06B6D4),
      ErrorTag.other: const Color(0xFF64748B),
    };

    final donutSlices = snap.errorTagCounts.entries
        .where((e) => e.value > 0)
        .map(
          (e) => DonutSliceDatum(
            label: e.key.label,
            count: e.value,
            color: tagPalette[e.key] ?? t.accent,
          ),
        )
        .toList(growable: false);

    final trendPoints = snap.weeklyTrend
        .map(
          (pt) => TrendPointDatum(label: pt.label, value: pt.accuracyPercent),
        )
        .toList(growable: false);

    final latestReport = ws.reports.isNotEmpty ? ws.reports.first : null;
    final prevReport = ws.reports.length >= 2 ? ws.reports[1] : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('学情诊断'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.icon(
              onPressed: state.coachBusy
                  ? null
                  : () async {
                      final res = await notifier.generateStudyReport();
                      if (!context.mounted) return;
                      if (res.errorMessage != null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(res.errorMessage!)),
                        );
                      }
                    },
              icon: state.coachBusy
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.auto_graph_outlined, size: 17),
              label: Text(state.coachBusy ? '分析中…' : 'AI 诊断报告'),
            ),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080),
          child: ListView(
            padding: EdgeInsets.all(wide ? 22 : 14),
            children: [
              LayoutBuilder(
                builder: (context, c) {
                  final twoCols = c.maxWidth >= 740;
                  final radarCard = InouSurface(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        const InouSectionHeader(title: '各科掌握度'),
                        const SizedBox(height: 8),
                        InouRadarChart(axes: radarAxes, size: 205),
                      ],
                    ),
                  );
                  final donutAndTrend = InouSurface(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const InouSectionHeader(title: '错因分布与正确率趋势'),
                        const SizedBox(height: 12),
                        if (donutSlices.isNotEmpty)
                          InouDonutChart(slices: donutSlices, ringSize: 110)
                        else
                          Text(
                            '暂无已标注错因数据',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: t.textMuted,
                            ),
                          ),
                        const SizedBox(height: 14),
                        InouTrendLineChart(points: trendPoints, height: 130),
                      ],
                    ),
                  );

                  if (twoCols) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(width: 270, child: radarCard),
                        const SizedBox(width: 14),
                        Expanded(child: donutAndTrend),
                      ],
                    );
                  }
                  return Column(
                    children: [
                      radarCard,
                      const SizedBox(height: 12),
                      donutAndTrend,
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),

              InouSurface(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InouSectionHeader(
                      title: '薄弱考点排行',
                      trailing: OutlinedButton.icon(
                        onPressed: state.coachBusy
                            ? null
                            : () => _openDrillDialog(
                                context,
                                state,
                                notifier,
                                snap.rankedWeakLeaves.firstOrNull,
                              ),
                        icon: const Icon(Icons.bolt_outlined, size: 16),
                        label: const Text('一键靶向出题'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (snap.rankedWeakLeaves.isEmpty)
                      Text(
                        '暂无足够失分样本。',
                        style: TextStyle(color: t.textMuted, fontSize: 13),
                      )
                    else
                      for (final leaf in snap.rankedWeakLeaves.take(5))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: wide
                              ? Row(
                                  children: [
                                    SizedBox(
                                      width: 155,
                                      child: Text(
                                        state.kpTree.nameOf(leaf.kpId) !=
                                                leaf.kpId
                                            ? state.kpTree.nameOf(leaf.kpId)
                                            : leaf.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: t.textPrimary,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                        child: LinearProgressIndicator(
                                          value: leaf.weakScore.clamp(
                                            0.08,
                                            1.0,
                                          ),
                                          minHeight: 5,
                                          backgroundColor: t.surfaceMuted,
                                          color: leaf.weakScore >= 0.65
                                              ? t.danger
                                              : t.warning,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      '${(leaf.weakScore * 100).round()}%',
                                      style: InouTypography.tabular(
                                        TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w700,
                                          color: t.textSecondary,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    TextButton(
                                      onPressed: () => _openDrillDialog(
                                        context,
                                        state,
                                        notifier,
                                        leaf,
                                      ),
                                      child: const Text('出题'),
                                    ),
                                  ],
                                )
                              : Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            state.kpTree.nameOf(leaf.kpId) !=
                                                    leaf.kpId
                                                ? state.kpTree.nameOf(leaf.kpId)
                                                : leaf.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: t.textPrimary,
                                            ),
                                          ),
                                        ),
                                        Text(
                                          '${(leaf.weakScore * 100).round()}%',
                                          style: InouTypography.tabular(
                                            TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                              color: t.textSecondary,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        TextButton(
                                          style: TextButton.styleFrom(
                                            visualDensity:
                                                VisualDensity.compact,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                            ),
                                          ),
                                          onPressed: () => _openDrillDialog(
                                            context,
                                            state,
                                            notifier,
                                            leaf,
                                          ),
                                          child: const Text('出题'),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(999),
                                      child: LinearProgressIndicator(
                                        value: leaf.weakScore.clamp(0.08, 1.0),
                                        minHeight: 5,
                                        backgroundColor: t.surfaceMuted,
                                        color: leaf.weakScore >= 0.65
                                            ? t.danger
                                            : t.warning,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                  ],
                ),
              ),

              if (_lastDrillError != null) ...[
                const SizedBox(height: 12),
                InouSurface(
                  backgroundColor: t.dangerSoft,
                  borderColor: t.danger.withValues(alpha: 0.35),
                  padding: const EdgeInsets.all(14),
                  child: Text(
                    _lastDrillError!,
                    style: TextStyle(fontSize: 13, color: t.danger),
                  ),
                ),
              ],

              if (_lastGeneratedDrill.isNotEmpty) ...[
                const SizedBox(height: 14),
                InouSurface(
                  backgroundColor: t.accentSoft,
                  borderColor: t.accent.withValues(alpha: 0.3),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '已生成 ${_lastGeneratedDrill.length} 道针对性练习题并加入题库',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: t.accent,
                              ),
                            ),
                          ),
                          FilledButton(
                            onPressed: () async {
                              await notifier.startPracticeSession(
                                title: 'AI 靶向薄弱专练',
                                kind: PracticeKind.generated,
                                inputMode: InputMode.standard,
                                feedbackTiming: FeedbackTiming.instant,
                                questionIds: _lastGeneratedDrill
                                    .map((q) => q.id)
                                    .toList(),
                              );
                              if (context.mounted) context.go('/practice');
                            },
                            child: const Text('立即作答'),
                          ),
                        ],
                      ),
                      if (_lastDrillTrace.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        InouThinkingDisclosure(
                          traces: _lastDrillTrace
                              .map((e) => e.toDisplayLine())
                              .toList(),
                        ),
                      ],
                    ],
                  ),
                ),
              ],

              if (latestReport != null) ...[
                const SizedBox(height: 16),
                InouSurface(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          InouBadge(
                            label: state.hasLiveAiKey ? 'AI 诊断报告' : '本地统计诊断',
                            tone: InouBadgeTone.accent,
                          ),
                          const Spacer(),
                          if (prevReport != null)
                            const InouBadge(
                              label: '已与上期快照对比',
                              tone: InouBadgeTone.success,
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        latestReport.overallAdvice,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.55,
                          color: t.textPrimary,
                        ),
                      ),
                      if (latestReport.plan.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          '3 日复习建议',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: t.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        for (final step in latestReport.plan)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                InouBadge(label: step.day),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    step.task,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: t.textPrimary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                      if (latestReport.toolTrace.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        InouThinkingDisclosure(traces: latestReport.toolTrace),
                      ],
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 16),
              InouSurface(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InouSectionHeader(
                      title: '课标知识图谱 (${state.kpTree.nodes.length} 节点)',
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final code in const [
                          'math',
                          'phy',
                          'eng',
                          'chn',
                          'chem',
                        ])
                          ChoiceChip(
                            label: Text(SubjectCatalog.labelOf(code)),
                            selected: _treeSubject == code,
                            onSelected: (_) =>
                                setState(() => _treeSubject = code),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _KpTreeAccordion(
                      state: state,
                      snapshot: snap,
                      subject: _treeSubject,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openDrillDialog(
    BuildContext context,
    AppState state,
    AppStoreNotifier notifier,
    KpWeaknessStat? targetLeaf,
  ) async {
    if (!state.hasLiveAiKey) {
      final goSettings = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('AI 靶向专练生成'),
          content: const Text('靶向专练会根据你的薄弱考点实时生成新题并验算答案，请先在设置中配置 AI API Key。'),
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
      if (goSettings == true && context.mounted) {
        await showSettingsModal(context);
      }
      return;
    }

    var count = 3;
    final subject = targetLeaf?.subject ?? 'math';
    final kpIds = targetLeaf != null ? [targetLeaf.kpId] : const <String>[];
    final kpNames = targetLeaf != null
        ? [targetLeaf.name]
        : [SubjectCatalog.labelOf(subject)];

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('靶向专练生成'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('目标考点：${kpNames.join(' · ')}'),
              const SizedBox(height: 10),
              Text('出题数量：$count 题'),
              Slider(
                min: 1,
                max: 5,
                divisions: 4,
                value: count.toDouble(),
                onChanged: (v) => setDialogState(() => count = v.round()),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.of(ctx).pop();
                final res = await notifier.generateTargetedDrill(
                  subject: subject,
                  targetKpIds: kpIds,
                  targetKpNames: kpNames,
                  count: count,
                );
                if (!mounted) return;
                setState(() {
                  _lastGeneratedDrill = res.questions;
                  _lastDrillTrace = res.traceSteps;
                  _lastDrillError = res.errorMessage;
                });
              },
              child: const Text('AI 开始出题'),
            ),
          ],
        ),
      ),
    );
  }
}

class _KpTreeAccordion extends StatelessWidget {
  const _KpTreeAccordion({
    required this.state,
    required this.snapshot,
    required this.subject,
  });

  final AppState state;
  final WeaknessSnapshot snapshot;
  final String subject;

  @override
  Widget build(BuildContext context) {
    final t = context.inou;
    final tree = state.kpTree;
    final stageCode = state.activeProfile.stage.code;
    var chapters = tree
        .roots(subject: subject, stage: stageCode)
        .where((n) => n.level == 1)
        .toList();
    if (chapters.isEmpty) {
      chapters = tree.nodes
          .where((n) => n.subject == subject && n.level == 1)
          .take(8)
          .toList();
    }
    if (chapters.isEmpty) {
      return Text(
        '该学科暂无节点数据',
        style: TextStyle(color: t.textMuted, fontSize: 12.5),
      );
    }

    return Column(
      children: [
        for (final ch in chapters.take(6))
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text(
              ch.name,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: t.textPrimary,
              ),
            ),
            subtitle: snapshot.allNodeStats[ch.id] != null
                ? Text(
                    '薄弱度 ${(snapshot.allNodeStats[ch.id]!.weakScore * 100).round()}%',
                    style: TextStyle(fontSize: 11.5, color: t.warning),
                  )
                : null,
            children: [
              for (final child in tree.childrenOf(ch.id))
                ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.only(left: 16, right: 8),
                  title: Text(child.name, style: const TextStyle(fontSize: 13)),
                  trailing: snapshot.allNodeStats[child.id] != null
                      ? InouBadge(
                          label:
                              '${(snapshot.allNodeStats[child.id]!.weakScore * 100).round()}%',
                          tone: InouBadgeTone.warning,
                        )
                      : null,
                ),
            ],
          ),
      ],
    );
  }
}
