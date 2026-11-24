import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inou_ai/inou_ai.dart';
import 'package:inou_ui_kit/inou_ui_kit.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/platform/platform_media_service.dart';
import '../../../core/state/app_store.dart';

/// Slide-over / bottom-sheet NuoNuo Copilot Drawer with photo question input.
class TutorCopilotDrawer extends ConsumerStatefulWidget {
  const TutorCopilotDrawer({super.key, required this.compact});

  final bool compact;

  @override
  ConsumerState<TutorCopilotDrawer> createState() => _TutorCopilotDrawerState();
}

class _TutorCopilotDrawerState extends ConsumerState<TutorCopilotDrawer> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    _inputController.clear();
    await ref.read(appStoreProvider.notifier).sendTutorMessage(trimmed);
    if (mounted && _scrollController.hasClients) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      if (_scrollController.hasClients) {
        await _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    }
  }

  Future<void> _pickPhoto({required bool camera}) async {
    final media = ref.read(platformMediaServiceProvider);
    final res = camera
        ? await media.capturePhoto()
        : await media.pickGalleryImage();
    if (!mounted || res == null) return;
    ref.read(appStoreProvider.notifier).attachCopilotImage(res.bytes);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.inou;
    final state = ref.watch(appStoreProvider);
    final notifier = ref.read(appStoreProvider.notifier);
    final thread = state.activeCopilotThread;
    final boundQ = state.copilotQuestionId == null
        ? null
        : state.activeWorkspace.questions
              .where((q) => q.id == state.copilotQuestionId)
              .firstOrNull;
    final hintLevel = state.copilotHintLevel;

    final panel = Material(
      color: t.surface,
      elevation: 0,
      child: Container(
        decoration: BoxDecoration(
          color: t.surface,
          border: Border(
            left: widget.compact
                ? BorderSide.none
                : BorderSide(color: t.borderHairline),
            top: widget.compact
                ? BorderSide(color: t.borderHairline)
                : BorderSide.none,
          ),
          borderRadius: widget.compact
              ? const BorderRadius.vertical(top: Radius.circular(20))
              : BorderRadius.zero,
        ),
        child: SafeArea(
          left: widget.compact,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
                child: Row(
                  children: [
                    NuoNuoMascotView(
                      emotion: NuoNuoExpression.fromCode(
                        state.copilotLastEmotion.code,
                      ),
                      size: 40,
                      animate: state.snapshot.preferences.mascotAnimating,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                '诺诺',
                                style: TextStyle(
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w700,
                                  color: t.textPrimary,
                                ),
                              ),
                              const SizedBox(width: 6),
                              InouBadge(
                                label: state.hasLiveAiKey ? '在线' : '离线模式',
                                tone: state.hasLiveAiKey
                                    ? InouBadgeTone.success
                                    : InouBadgeTone.neutral,
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            boundQ != null
                                ? boundQ.header.title
                                : '自由提问 · 可拍照或圈选笔迹',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: t.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    FilledButton.tonalIcon(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 32),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                      ),
                      onPressed: () => notifier.openBlackboard(
                        questionId: state.copilotQuestionId,
                        hintLevel: state.copilotHintLevel,
                        lassoBytes: state.copilotLassoBytes,
                      ),
                      icon: const Icon(Icons.co_present_outlined, size: 15),
                      label: const Text(
                        '黑板讲堂',
                        style: TextStyle(fontSize: 11.5),
                      ),
                    ),
                    if (thread.messages.isNotEmpty)
                      IconButton(
                        tooltip: '清空对话',
                        onPressed: notifier.clearCopilotThread,
                        icon: const Icon(Icons.delete_sweep_outlined, size: 20),
                      ),
                    IconButton(
                      tooltip: '关闭',
                      onPressed: notifier.closeCopilot,
                      icon: const Icon(Icons.close, size: 20),
                    ),
                  ],
                ),
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                child: SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<HintLevel>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(
                        value: HintLevel.l1Concept,
                        label: Text('思路点拨'),
                      ),
                      ButtonSegment(
                        value: HintLevel.l2KeyStep,
                        label: Text('关键步骤'),
                      ),
                      ButtonSegment(
                        value: HintLevel.l3FullSolution,
                        label: Text('详细解答'),
                      ),
                    ],
                    selected: {
                      hintLevel == HintLevel.none
                          ? HintLevel.l1Concept
                          : hintLevel,
                    },
                    onSelectionChanged: (sel) =>
                        notifier.setCopilotHintLevel(sel.first),
                  ),
                ),
              ),
              const Divider(height: 1),

              if (thread.summary != null && thread.summary!.isNotEmpty)
                Container(
                  width: double.infinity,
                  color: t.surfaceMuted,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 7,
                  ),
                  child: Text(
                    '前情摘要：${thread.summary}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: t.textSecondary),
                  ),
                ),

              Expanded(
                child: thread.messages.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '卡在哪一步了？输入问题、拍照，或打开黑板让诺诺一步步写板书讲解～',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: t.textMuted,
                                ),
                              ),
                              const SizedBox(height: 12),
                              FilledButton.tonalIcon(
                                onPressed: () => notifier.openBlackboard(
                                  questionId: state.copilotQuestionId,
                                  hintLevel: state.copilotHintLevel,
                                  lassoBytes: state.copilotLassoBytes,
                                ),
                                icon: const Icon(
                                  Icons.co_present_outlined,
                                  size: 16,
                                ),
                                label: const Text('进入黑板讲堂（分步板书）'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.separated(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(14),
                        itemCount: thread.messages.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final m = thread.messages[index];
                          final isUser = m.role == 'user';
                          return Column(
                            crossAxisAlignment: isUser
                                ? CrossAxisAlignment.end
                                : CrossAxisAlignment.start,
                            children: [
                              Container(
                                constraints: const BoxConstraints(
                                  maxWidth: 320,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: isUser ? t.accent : t.surfaceMuted,
                                  borderRadius: BorderRadius.circular(12),
                                  border: isUser
                                      ? null
                                      : Border.all(color: t.borderHairline),
                                ),
                                child: SelectableText(
                                  m.content,
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    height: 1.5,
                                    color: isUser
                                        ? Colors.white
                                        : t.textPrimary,
                                  ),
                                ),
                              ),
                              if (!isUser &&
                                  (m.toolTrace.isNotEmpty ||
                                      m.antiSpoilerBlocked)) ...[
                                const SizedBox(height: 6),
                                InouThinkingDisclosure(
                                  traces: m.toolTrace,
                                  antiSpoilerBlocked: m.antiSpoilerBlocked,
                                ),
                              ],
                            ],
                          );
                        },
                      ),
              ),

              if (state.copilotBusy)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: LinearProgressIndicator(minHeight: 2),
                ),

              if (state.copilotLassoBytes != null)
                Container(
                  margin: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: t.accentSoft,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: t.accent.withValues(alpha: 0.35)),
                  ),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.memory(
                          state.copilotLassoBytes!,
                          width: 48,
                          height: 36,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '已附带题目图片',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: t.accent,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 16),
                        onPressed: notifier.clearCopilotAttachment,
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                ),

              Padding(
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 6),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final qPrompt in const [
                        '给我一点审题突破口',
                        '直接告诉我答案吧',
                        '帮我检查推导下一步',
                      ])
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ActionChip(
                            label: Text(
                              qPrompt,
                              style: const TextStyle(fontSize: 11.5),
                            ),
                            onPressed: state.copilotBusy
                                ? null
                                : () => _send(qPrompt),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(10, 2, 14, 12),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: '拍题图片',
                      onPressed: state.copilotBusy
                          ? null
                          : () => _pickPhoto(camera: true),
                      icon: const Icon(Icons.camera_alt_outlined, size: 20),
                    ),
                    IconButton(
                      tooltip: '相册图片',
                      onPressed: state.copilotBusy
                          ? null
                          : () => _pickPhoto(camera: false),
                      icon: const Icon(Icons.photo_outlined, size: 20),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _inputController,
                        minLines: 1,
                        maxLines: 3,
                        textInputAction: TextInputAction.send,
                        onSubmitted: state.copilotBusy ? null : _send,
                        decoration: const InputDecoration(hintText: '输入你的疑问…'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: state.copilotBusy
                          ? null
                          : () => _send(_inputController.text),
                      child: const Icon(Icons.send_rounded, size: 18),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (widget.compact) {
      return Align(
        alignment: Alignment.bottomCenter,
        child: FractionallySizedBox(
          heightFactor: 0.82,
          widthFactor: 1,
          child: panel,
        ),
      );
    }

    return SizedBox(width: 390, height: double.infinity, child: panel);
  }
}
