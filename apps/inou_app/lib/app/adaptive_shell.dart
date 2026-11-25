import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:inou_domain/inou_domain.dart';
import 'package:inou_ui_kit/inou_ui_kit.dart';
import 'package:material_ui/material_ui.dart';

import '../core/state/app_store.dart';
import '../features/capture/presentation/capture_sheet.dart';
import '../features/onboarding/presentation/onboarding_overlay.dart';
import '../features/settings/presentation/diagnostics_log_dialog.dart';
import '../features/settings/presentation/settings_modal.dart';
import '../features/tutor/presentation/blackboard_classroom_modal.dart';
import '../features/tutor/presentation/tutor_copilot_drawer.dart';

class AdaptiveShell extends ConsumerWidget {
  const AdaptiveShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const _destinations =
      <({IconData icon, IconData active, String label})>[
        (icon: Icons.home_outlined, active: Icons.home_rounded, label: '首页'),
        (
          icon: Icons.library_books_outlined,
          active: Icons.library_books_rounded,
          label: '题库',
        ),
        (
          icon: Icons.edit_note_outlined,
          active: Icons.edit_note_rounded,
          label: '做题',
        ),
        (
          icon: Icons.auto_stories_outlined,
          active: Icons.auto_stories_rounded,
          label: '错题本',
        ),
        (
          icon: Icons.insights_outlined,
          active: Icons.insights_rounded,
          label: '诊断',
        ),
      ];

  void _onSelect(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.inou;
    final state = ref.watch(appStoreProvider);
    final notifier = ref.read(appStoreProvider.notifier);
    final size = MediaQuery.sizeOf(context);
    final viewPad = MediaQuery.viewPaddingOf(context);
    final safeWidth = math.max(0.0, size.width - viewPad.horizontal);
    final isShortLandscape = size.height < 500;
    final compact = safeWidth < 600;
    final extended = safeWidth >= 900 && !isShortLandscape;
    final showOnboarding =
        state.hydrated && !state.snapshot.preferences.onboardingCompleted;

    final Widget content = compact
        ? Scaffold(
            body: SafeArea(
              top: false,
              bottom: false,
              child: navigationShell,
            ),
            bottomNavigationBar: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (state.backgroundTasks.isNotEmpty)
                  _BackgroundTaskBar(
                    tasks: state.backgroundTasks,
                    compact: true,
                    notifier: notifier,
                  ),
                Divider(height: 1, thickness: 0.85, color: t.borderHairline),
                NavigationBar(
                  selectedIndex: navigationShell.currentIndex,
                  onDestinationSelected: _onSelect,
                  destinations: [
                    for (final d in _destinations)
                      NavigationDestination(
                        icon: Icon(d.icon),
                        selectedIcon: Icon(d.active),
                        label: d.label,
                      ),
                  ],
                ),
              ],
            ),
          )
        : Scaffold(
            body: Row(
              children: [
                ColoredBox(
                  color: t.surface,
                  child: SafeArea(
                    right: false,
                    child: LayoutBuilder(
                      builder: (context, railBox) => SingleChildScrollView(
                        child: SizedBox(
                          height: math.max(railBox.maxHeight, 540.0),
                          child: Column(
                            children: [
                              Expanded(
                                child: NavigationRail(
                                  selectedIndex: navigationShell.currentIndex,
                                  onDestinationSelected: _onSelect,
                                  extended: extended,
                                  backgroundColor: t.surface,
                                  leading: Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      12,
                                      16,
                                      12,
                                      16,
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          width: 32,
                                          height: 32,
                                          decoration: BoxDecoration(
                                            color: t.accent,
                                            borderRadius: BorderRadius.circular(
                                              9,
                                            ),
                                          ),
                                          child: const Center(
                                            child: Text(
                                              'I',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w800,
                                                fontSize: 16,
                                              ),
                                            ),
                                          ),
                                        ),
                                        if (extended) ...[
                                          const SizedBox(width: 10),
                                          Text(
                                            'InoU',
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w700,
                                              color: t.textPrimary,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  destinations: [
                                    for (final d in _destinations)
                                      NavigationRailDestination(
                                        icon: Icon(d.icon),
                                        selectedIcon: Icon(d.active),
                                        label: Text(d.label),
                                      ),
                                  ],
                                ),
                              ),
                              const Divider(height: 1),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  8,
                                  10,
                                  8,
                                  18,
                                ),
                                child: Flex(
                                  direction: extended
                                      ? Axis.horizontal
                                      : Axis.vertical,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      tooltip: '拍照录题',
                                      onPressed: () =>
                                          showCaptureModal(context),
                                      icon: const Icon(
                                        Icons.photo_camera_outlined,
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: '拍照搜题',
                                      onPressed: () =>
                                          context.go('/photo-search'),
                                      icon: const Icon(
                                        Icons.saved_search_rounded,
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: '问诺诺',
                                      onPressed: () {
                                        if (state.copilotOpen) {
                                          notifier.closeCopilot();
                                        } else {
                                          notifier.openCopilot();
                                        }
                                      },
                                      icon: NuoNuoMascotView(
                                        emotion: NuoNuoExpression.fromCode(
                                          state.copilotLastEmotion.code,
                                        ),
                                        size: 26,
                                        showGlowRing: false,
                                        animate: state
                                            .snapshot
                                            .preferences
                                            .mascotAnimating,
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: '设置',
                                      onPressed: () =>
                                          showSettingsModal(context),
                                      icon: const Icon(Icons.tune_rounded),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: SafeArea(
                    left: false,
                    child: LayoutBuilder(
                      builder: (context, bodyBox) => AdaptiveScope(
                        windowClass: WindowClass.fromWidth(bodyBox.maxWidth),
                        child: navigationShell,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );

    final hasFullOverlay =
        showOnboarding || state.blackboardOpen || state.copilotOpen;

    return PopScope(
      canPop: !state.blackboardOpen && !state.copilotOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (state.blackboardOpen) {
          notifier.closeBlackboard();
        } else if (state.copilotOpen) {
          notifier.closeCopilot();
        }
      },
      child: Stack(
        children: [
          ExcludeSemantics(excluding: hasFullOverlay, child: content),
          if (!compact && state.backgroundTasks.isNotEmpty)
            Positioned(
              right: 20 + viewPad.right,
              bottom: 20 + viewPad.bottom,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Material(
                  type: MaterialType.transparency,
                  child: _BackgroundTaskBar(
                    tasks: state.backgroundTasks,
                    compact: false,
                    notifier: notifier,
                  ),
                ),
              ),
            ),
          if (state.copilotOpen) ...[
            Positioned.fill(
              child: GestureDetector(
                onTap: notifier.closeCopilot,
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: compact ? 0.35 : 0.14),
                ),
              ),
            ),
            Align(
              alignment: compact ? Alignment.bottomCenter : Alignment.centerRight,
              child: TutorCopilotDrawer(compact: compact),
            ),
          ],
          if (state.blackboardOpen)
            const Positioned.fill(child: BlackboardClassroomOverlay()),
          if (state.aiRetryNotice != null)
            Positioned(
              top: viewPad.top + 10,
              left: 16 + viewPad.left,
              right: 16 + viewPad.right,
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Material(
                    type: MaterialType.transparency,
                    child: _AiRetryNoticeBanner(
                      message: state.aiRetryNotice!,
                      exhausted: state.aiRetryExhausted,
                      onDismiss: notifier.dismissAiRetryNotice,
                    ),
                  ),
                ),
              ),
            ),
          if (showOnboarding) const Positioned.fill(child: OnboardingOverlay()),
        ],
      ),
    );
  }
}

class _BackgroundTaskBar extends StatelessWidget {
  const _BackgroundTaskBar({
    required this.tasks,
    required this.compact,
    required this.notifier,
  });

  final List<CaptureBackgroundTask> tasks;
  final bool compact;
  final AppStoreNotifier notifier;

  @override
  Widget build(BuildContext context) {
    final t = context.inou;
    final primary = tasks.first;
    final extraCount = tasks.length - 1;

    final Widget leadingIcon = switch (primary.status) {
      CaptureTaskStatus.running => SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2, color: t.accent),
      ),
      CaptureTaskStatus.completed => Icon(
        Icons.check_circle_rounded,
        size: 18,
        color: t.success,
      ),
      CaptureTaskStatus.failed => Icon(
        Icons.error_outline_rounded,
        size: 18,
        color: t.danger,
      ),
    };

    final String titleText = switch (primary.status) {
      CaptureTaskStatus.running => '后台识题 · ${primary.docTitle}',
      CaptureTaskStatus.completed =>
        primary.subject != SubjectCatalog.autoCode && primary.subject.isNotEmpty
            ? '「${primary.docTitle}」· ${SubjectCatalog.labelOf(primary.subject)} · ${primary.drafts.length} 题'
            : '「${primary.docTitle}」已识别 ${primary.drafts.length} 题',
      CaptureTaskStatus.failed => '「${primary.docTitle}」识题失败',
    };

    final String subText = switch (primary.status) {
      CaptureTaskStatus.running => primary.stageLabel,
      CaptureTaskStatus.completed => '点击右侧「去校对」核对题干与答案后入库',
      CaptureTaskStatus.failed => primary.errorMessage ?? '请检查网络或视觉模型配置后重试',
    };

    final inner = Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 14 : 16,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: compact ? BorderRadius.zero : BorderRadius.circular(14),
        border: compact
            ? Border(top: BorderSide(color: t.accent.withValues(alpha: 0.35)))
            : Border.all(color: t.borderHairline),
        boxShadow: compact
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: t.isDark ? 0.3 : 0.08),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                ),
              ],
      ),
      child: Row(
        children: [
          leadingIcon,
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        titleText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: t.textPrimary,
                        ),
                      ),
                    ),
                    if (extraCount > 0) ...[
                      const SizedBox(width: 6),
                      InouBadge(
                        label: '+$extraCount',
                        tone: InouBadgeTone.accent,
                      ),
                    ],
                  ],
                ),
                Text(
                  subText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: primary.status == CaptureTaskStatus.failed
                        ? t.danger
                        : t.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (primary.status == CaptureTaskStatus.running)
            TextButton(
              onPressed: () => notifier.cancelBackgroundTask(primary.id),
              child: const Text('取消'),
            )
          else if (primary.status == CaptureTaskStatus.completed) ...[
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 34),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
              ),
              onPressed: () async {
                await notifier.openBackgroundTaskForReview(primary.id);
                if (context.mounted) context.go('/review');
              },
              child: const Text('去校对'),
            ),
            IconButton(
              tooltip: '关闭提示',
              visualDensity: VisualDensity.compact,
              onPressed: () => notifier.dismissBackgroundTask(primary.id),
              icon: const Icon(Icons.close, size: 17),
            ),
          ] else ...[
            TextButton(
              onPressed: () => showDiagnosticsLogDialog(
                context,
                initialErrorsOnly: true,
              ),
              child: const Text('查看报错'),
            ),
            TextButton(
              onPressed: () => notifier.retryBackgroundTask(primary.id),
              child: const Text('重试'),
            ),
            IconButton(
              tooltip: '关闭',
              visualDensity: VisualDensity.compact,
              onPressed: () => notifier.dismissBackgroundTask(primary.id),
              icon: const Icon(Icons.close, size: 17),
            ),
          ],
        ],
      ),
    );

    return inner;
  }
}

class _AiRetryNoticeBanner extends StatelessWidget {
  const _AiRetryNoticeBanner({
    required this.message,
    required this.exhausted,
    required this.onDismiss,
  });

  final String message;
  final bool exhausted;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final t = context.inou;
    final tint = exhausted ? t.danger : t.accent;
    final banner = Container(
      key: const ValueKey('ai_retry_banner'),
      padding: EdgeInsets.fromLTRB(14, 9, exhausted ? 6 : 14, 9),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tint.withValues(alpha: 0.45)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: t.isDark ? 0.3 : 0.1),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (exhausted)
            Icon(Icons.error_outline_rounded, size: 18, color: t.danger)
          else
            SizedBox(
              width: 15,
              height: 15,
              child: CircularProgressIndicator(strokeWidth: 2, color: t.accent),
            ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: t.textPrimary,
              ),
            ),
          ),
          if (exhausted) ...[
            const SizedBox(width: 4),
            IconButton(
              tooltip: '关闭提示',
              visualDensity: VisualDensity.compact,
              onPressed: onDismiss,
              icon: const Icon(Icons.close, size: 17),
            ),
          ],
        ],
      ),
    );
    return exhausted ? banner : IgnorePointer(child: banner);
  }
}
