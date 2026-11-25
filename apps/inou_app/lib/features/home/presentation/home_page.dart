import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:inou_domain/inou_domain.dart';
import 'package:inou_ui_kit/inou_ui_kit.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/state/app_store.dart';
import '../../capture/presentation/capture_sheet.dart';
import '../../settings/presentation/settings_modal.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.inou;
    final state = ref.watch(appStoreProvider);
    final notifier = ref.read(appStoreProvider.notifier);
    final windowClass = AdaptiveScope.of(context);
    final wide =
        windowClass != WindowClass.compact &&
        MediaQuery.sizeOf(context).height >= 500;

    final profile = state.activeProfile;
    final ws = state.activeWorkspace;
    final snap = notifier.computeWeaknessSnapshot();

    final unverifiedCount = ws.questions
        .where((q) => q.meta.answerSource == AnswerSource.ai)
        .length;
    final pendingWrongCount = ws.wrongItems
        .where((w) => w.mastery != MasteryState.mastered)
        .length;
    final masteredWrongCount = ws.wrongItems
        .where((w) => w.mastery == MasteryState.mastered)
        .length;
    final draftCount = ws.captureDrafts.length;

    final radarAxes = [
      for (final entry in snap.subjectMasteryPercent.entries)
        RadarAxisDatum(
          label: SubjectCatalog.labelOf(entry.key),
          value: (entry.value / 100.0).clamp(0.05, 1.0),
        ),
    ];

    final metricBar = InouMetricBar(
      items: [
        InouMetricItem(
          label: '待校对',
          value: '$draftCount',
          valueColor: draftCount > 0 ? t.accent : null,
          onTap: draftCount > 0
              ? () => context.go('/review')
              : () => showCaptureModal(context),
        ),
        InouMetricItem(
          label: '待核对',
          value: '$unverifiedCount',
          valueColor: unverifiedCount > 0 ? t.warning : null,
          onTap: () => context.go('/library'),
        ),
        InouMetricItem(
          label: '待复习',
          value: '$pendingWrongCount',
          valueColor: pendingWrongCount > 0 ? t.danger : null,
          onTap: () => context.go('/wrongbook'),
        ),
        InouMetricItem(
          label: '已掌握',
          value: '$masteredWrongCount',
          valueColor: masteredWrongCount > 0 ? t.success : null,
          onTap: () => context.go('/wrongbook'),
        ),
      ],
    );

    final greetingHeader = Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      alignment: WrapAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '你好，${profile.name}',
              style: TextStyle(
                fontSize: wide ? 24 : 21,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.45,
                color: t.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${profile.stage.label} · ${profile.grade} · 题库 ${ws.questions.length} 题',
              style: TextStyle(fontSize: 12.5, color: t.textSecondary),
            ),
          ],
        ),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _ProfileDropdownChip(
              profiles: state.snapshot.profiles,
              activeProfile: profile,
              onSelect: notifier.switchProfile,
              onCreateNew: () => _showAddProfileDialog(context, notifier),
            ),
            InouStatusDot(
              label: state.hasLiveAiKey
                  ? '${state.activeEndpoint.name} · 已连接'
                  : '未配置 AI',
              connected: state.hasLiveAiKey,
              onTap: () => showSettingsModal(context),
            ),
          ],
        ),
      ],
    );

    final emptyStarterCard = InouSurface(
      elevated: true,
      padding: EdgeInsets.all(wide ? 22 : 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: t.accentSoft,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  Icons.document_scanner_outlined,
                  color: t.accent,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '建立你的第一份错题与练习本',
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                        color: t.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '相机拍摄试卷、单题快拍或进入题库手工录入。',
                      style: TextStyle(fontSize: 12.5, color: t.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => showCaptureModal(context),
                  icon: const Icon(Icons.camera_alt_outlined, size: 17),
                  label: const Text('拍照录题'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => context.go('/library'),
                  icon: const Icon(Icons.edit_outlined, size: 17),
                  label: const Text('去题库录题'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonalIcon(
              style: FilledButton.styleFrom(
                backgroundColor: t.accentSoft,
                foregroundColor: t.accent,
                elevation: 0,
              ),
              onPressed: () => context.go('/photo-search'),
              icon: const Icon(Icons.saved_search_rounded, size: 17),
              label: const Text('拍照搜题'),
            ),
          ),
        ],
      ),
    );

    final weaknessSection = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InouSectionHeader(
          title: '近期薄弱知识点',
          trailing: TextButton(
            onPressed: () => context.go('/analytics'),
            child: const Text('详情'),
          ),
        ),
        const SizedBox(height: 8),
        if (snap.rankedWeakLeaves.isEmpty)
          InouSurface(
            subtle: true,
            padding: const EdgeInsets.all(14),
            child: Text(
              '完成练习或录错题后，这里会自动定位高频失分考点。',
              style: TextStyle(fontSize: 12.5, color: t.textSecondary),
            ),
          )
        else
          InouSurface(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < snap.rankedWeakLeaves.take(3).length; i++)
                  Builder(
                    builder: (context) {
                      final stat = snap.rankedWeakLeaves[i];
                      final kpLabel =
                          state.kpTree.nameOf(stat.kpId) != stat.kpId
                          ? state.kpTree.nameOf(stat.kpId)
                          : stat.name;
                      return Column(
                        children: [
                          if (i > 0)
                            Divider(height: 1, color: t.borderHairline),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            child: Row(
                              children: [
                                InouBadge(
                                  label: SubjectCatalog.labelOf(stat.subject),
                                  tone: InouBadgeTone.accent,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              kpLabel,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 13.5,
                                                fontWeight: FontWeight.w600,
                                                color: t.textPrimary,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            '${(stat.weakScore * 100).round()}%',
                                            style: InouTypography.tabular(
                                              TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color: stat.weakScore >= 0.6
                                                    ? t.danger
                                                    : t.warning,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                        child: LinearProgressIndicator(
                                          value: stat.weakScore.clamp(
                                            0.08,
                                            1.0,
                                          ),
                                          minHeight: 4,
                                          backgroundColor: t.surfaceMuted,
                                          color: stat.weakScore >= 0.6
                                              ? t.danger
                                              : t.warning,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                TextButton(
                                  onPressed: () => _handleGenerateDrill(
                                    context,
                                    state,
                                    notifier,
                                    stat,
                                  ),
                                  child: const Text('生成专练'),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
              ],
            ),
          ),
      ],
    );

    if (!wide) {
      // Dedicated Phone / Compact Layout
      return Scaffold(
        appBar: AppBar(
          title: const Text('InoU'),
          actions: [
            IconButton(
              tooltip: '问诺诺',
              onPressed: notifier.openCopilot,
              icon: const Icon(Icons.auto_awesome_outlined, size: 21),
            ),
            IconButton(
              tooltip: '拍照录题',
              onPressed: () => showCaptureModal(context),
              icon: const Icon(Icons.photo_camera_outlined, size: 21),
            ),
            IconButton(
              tooltip: '设置',
              onPressed: () => showSettingsModal(context),
              icon: const Icon(Icons.tune_rounded, size: 21),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 28),
          children: [
            greetingHeader,
            const SizedBox(height: 16),
            metricBar,
            const SizedBox(height: 14),
            if (ws.questions.isEmpty) ...[
              emptyStarterCard,
            ] else ...[
              Row(
                children: [
                  Expanded(
                    child: _CompactHeroAction(
                      accent: true,
                      icon: Icons.photo_camera_outlined,
                      title: '拍照录题',
                      subtitle: '扫码 / 答案双照',
                      onTap: () => showCaptureModal(context),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _CompactHeroAction(
                      accent: false,
                      icon: Icons.play_arrow_rounded,
                      title: pendingWrongCount > 0 ? '错题重练' : '开始做题',
                      subtitle: pendingWrongCount > 0
                          ? '$pendingWrongCount 道待复习'
                          : '标准 / A4 稿纸',
                      onTap: () => context.go('/practice'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _CompactHeroAction(
                accent: false,
                icon: Icons.saved_search_rounded,
                title: '拍照搜题',
                subtitle: '无答案试卷/单题 · AI 生成答案与解析',
                onTap: () => context.go('/photo-search'),
              ),
              const SizedBox(height: 18),
              weaknessSection,
            ],
            const SizedBox(height: 14),
            _CompactNuoNuoStrip(
              pendingWrongCount: pendingWrongCount,
              emotion: state.copilotLastEmotion.code,
              animate: state.snapshot.preferences.mascotAnimating,
              onTap: notifier.openCopilot,
            ),
            if (radarAxes.length >= 3) ...[
              const SizedBox(height: 14),
              InouSurface(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    InouSectionHeader(
                      title: '各科掌握度雷达',
                      trailing: TextButton(
                        onPressed: () => context.go('/analytics'),
                        child: const Text('详图'),
                      ),
                    ),
                    const SizedBox(height: 6),
                    InouRadarChart(axes: radarAxes, size: 190),
                  ],
                ),
              ),
            ],
          ],
        ),
      );
    }

    // Tablet / Desktop Two-Column Studio Workspace
    final mainCol = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        greetingHeader,
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: _HeroCard(
                accent: true,
                icon: Icons.photo_camera_outlined,
                title: '拍照录题',
                subtitle: '相机拍照、相册选图或答案双照对齐',
                ctaLabel: '打开录题台',
                onTap: () => showCaptureModal(context),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _HeroCard(
                accent: false,
                icon: Icons.play_arrow_rounded,
                title: pendingWrongCount > 0 ? '错题重练' : '开始做题',
                subtitle: pendingWrongCount > 0
                    ? '$pendingWrongCount 道待巩固错题，支持 A4 手写稿纸'
                    : '支持全题型作答与平板手写草稿纸模式',
                ctaLabel: '进入做题台',
                onTap: () => context.go('/practice'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        InouSurface(
          onTap: () => context.go('/photo-search'),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: t.accentSoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.saved_search_rounded,
                  size: 19,
                  color: t.accent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '拍照搜题 · AI 独立求解',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: t.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '拍摄无答案题目或整页试卷，AI 自动生成参考答案与分步解析，按需加入题库或错题本',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: t.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.tonalIcon(
                onPressed: () => context.go('/photo-search'),
                icon: const Icon(Icons.saved_search_rounded, size: 16),
                label: const Text('去搜题'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        metricBar,
        const SizedBox(height: 20),
        if (ws.questions.isEmpty) ...[
          emptyStarterCard,
          const SizedBox(height: 20),
        ],
        weaknessSection,
      ],
    );

    final rightStudioCol = Column(
      children: [
        InouSurface(
          elevated: true,
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  NuoNuoMascotView(
                    emotion: NuoNuoExpression.fromCode(
                      state.copilotLastEmotion.code,
                    ),
                    size: 48,
                    animate: state.snapshot.preferences.mascotAnimating,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '诺诺伴学助手',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: t.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '思路点拨 · 拍照答疑 · 稿纸圈选',
                          style: TextStyle(fontSize: 11.5, color: t.textMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                pendingWrongCount > 0
                    ? '还有 $pendingWrongCount 道待巩固错题，点我可以先给一点思路提示。'
                    : '随时向我提问，或直接拍照传题、圈选草稿纸内容。',
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.45,
                  color: t.textSecondary,
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: notifier.openCopilot,
                  icon: const Icon(Icons.chat_bubble_outline, size: 16),
                  label: const Text('问诺诺'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        InouSurface(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              InouSectionHeader(
                title: '各科掌握度雷达',
                trailing: TextButton(
                  onPressed: () => context.go('/analytics'),
                  child: const Text('详图'),
                ),
              ),
              const SizedBox(height: 8),
              InouRadarChart(axes: radarAxes, size: 196),
            ],
          ),
        ),
      ],
    );

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1140),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 7, child: mainCol),
                const SizedBox(width: 22),
                SizedBox(width: 310, child: rightStudioCol),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleGenerateDrill(
    BuildContext context,
    AppState state,
    AppStoreNotifier notifier,
    KpWeaknessStat stat,
  ) async {
    final res = await notifier.generateTargetedDrill(
      subject: stat.subject,
      targetKpIds: [stat.kpId],
      targetKpNames: [stat.name],
      count: 3,
    );
    if (!context.mounted) return;
    if (res.errorMessage != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(res.errorMessage!)));
      if (!state.hasLiveAiKey) {
        await showSettingsModal(context);
      }
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('AI 已生成 ${res.questions.length} 道专项练习题并存入题库')),
    );
    context.go('/practice');
  }

  Future<void> _showAddProfileDialog(
    BuildContext context,
    AppStoreNotifier notifier,
  ) async {
    final nameCtrl = TextEditingController();
    var stage = StudyStage.middle;
    var grade = '八年级';

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('新建学习档案'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: '姓名或昵称'),
              ),
              const SizedBox(height: 12),
              SegmentedButton<StudyStage>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: StudyStage.primary, label: Text('小学')),
                  ButtonSegment(value: StudyStage.middle, label: Text('初中')),
                  ButtonSegment(value: StudyStage.high, label: Text('高中')),
                ],
                selected: {stage},
                onSelectionChanged: (sel) => setState(() {
                  stage = sel.first;
                  grade = switch (stage) {
                    StudyStage.primary => '五年级',
                    StudyStage.middle => '八年级',
                    StudyStage.high => '高一',
                  };
                }),
              ),
              const SizedBox(height: 10),
              Text('默认年级：$grade'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                await notifier.addProfile(
                  name: nameCtrl.text,
                  stage: stage,
                  grade: grade,
                );
                if (ctx.mounted) Navigator.of(ctx).pop();
              },
              child: const Text('创建并切换'),
            ),
          ],
        ),
      ),
    );
    nameCtrl.dispose();
  }
}

class _CompactHeroAction extends StatelessWidget {
  const _CompactHeroAction({
    required this.accent,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final bool accent;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.inou;
    return InouSurface(
      onTap: onTap,
      elevated: !accent,
      backgroundColor: accent ? t.accent : t.surface,
      borderColor: accent ? t.accent : t.borderHairline,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: accent
                  ? Colors.white.withValues(alpha: 0.18)
                  : t.accentSoft,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(
              icon,
              size: 18,
              color: accent ? Colors.white : t.accent,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: accent ? Colors.white : t.textPrimary,
                  ),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: accent
                        ? Colors.white.withValues(alpha: 0.85)
                        : t.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactNuoNuoStrip extends StatelessWidget {
  const _CompactNuoNuoStrip({
    required this.pendingWrongCount,
    required this.emotion,
    required this.animate,
    required this.onTap,
  });

  final int pendingWrongCount;
  final String emotion;
  final bool animate;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.inou;
    return InouSurface(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        children: [
          NuoNuoMascotView(
            emotion: NuoNuoExpression.fromCode(emotion),
            size: 36,
            animate: animate,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '诺诺伴学助手',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: t.textPrimary,
                  ),
                ),
                Text(
                  pendingWrongCount > 0
                      ? '有 $pendingWrongCount 道待复习错题，点我获取思路点拨'
                      : '支持提问、拍照传题或草稿纸圈选求助',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: t.textSecondary),
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

class _ProfileDropdownChip extends StatelessWidget {
  const _ProfileDropdownChip({
    required this.profiles,
    required this.activeProfile,
    required this.onSelect,
    required this.onCreateNew,
  });

  final List<StudentProfile> profiles;
  final StudentProfile activeProfile;
  final ValueChanged<String> onSelect;
  final VoidCallback onCreateNew;

  @override
  Widget build(BuildContext context) {
    final t = context.inou;
    return PopupMenuButton<String>(
      tooltip: '切换学习档案',
      onSelected: (value) {
        if (value == '__new__') {
          onCreateNew();
        } else {
          onSelect(value);
        }
      },
      itemBuilder: (_) => [
        for (final p in profiles)
          PopupMenuItem(
            value: p.id,
            child: Row(
              children: [
                Icon(
                  p.id == activeProfile.id
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 16,
                  color: t.accent,
                ),
                const SizedBox(width: 8),
                Text('${p.name} · ${p.grade}'),
              ],
            ),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: '__new__',
          child: Row(
            children: [
              Icon(Icons.person_add_alt_1_outlined, size: 16),
              SizedBox(width: 8),
              Text('新增档案'),
            ],
          ),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: t.borderHairline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_outline, size: 14, color: t.textSecondary),
            const SizedBox(width: 4),
            Text(
              activeProfile.name,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: t.textPrimary,
              ),
            ),
            Icon(Icons.arrow_drop_down, size: 16, color: t.textMuted),
          ],
        ),
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.accent,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.ctaLabel,
    required this.onTap,
  });

  final bool accent;
  final IconData icon;
  final String title;
  final String subtitle;
  final String ctaLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.inou;
    return InouSurface(
      onTap: onTap,
      elevated: !accent,
      backgroundColor: accent ? t.accent : t.surface,
      borderColor: accent ? t.accent : t.borderHairline,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: accent
                      ? Colors.white.withValues(alpha: 0.18)
                      : t.accentSoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  size: 19,
                  color: accent ? Colors.white : t.accent,
                ),
              ),
              const Spacer(),
              Icon(
                Icons.arrow_forward_rounded,
                size: 18,
                color: accent ? Colors.white70 : t.textMuted,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: accent ? Colors.white : t.textPrimary,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              color: accent
                  ? Colors.white.withValues(alpha: 0.85)
                  : t.textSecondary,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            ctaLabel,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: accent ? Colors.white : t.accent,
            ),
          ),
        ],
      ),
    );
  }
}
