import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:inou_ai/inou_ai.dart';
import 'package:inou_domain/inou_domain.dart';
import 'package:inou_ui_kit/inou_ui_kit.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/security/pin_guard_dialog.dart';
import '../../../core/state/app_store.dart';
import '../../../core/state/workspace_models.dart';
import '../../capture/presentation/capture_sheet.dart';
import 'question_editor_dialog.dart';

enum _LibraryTab { questions, docs, tags }

class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key});

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage> {
  _LibraryTab _tab = _LibraryTab.questions;
  String _search = '';
  String? _subjectFilter;
  QuestionKind? _kindFilter;
  bool _onlyUnverified = false;
  String? _selectedQuestionId;
  bool _showAnswer = true;

  @override
  Widget build(BuildContext context) {
    final t = context.inou;
    final state = ref.watch(appStoreProvider);
    final notifier = ref.read(appStoreProvider.notifier);
    final ws = state.activeWorkspace;
    final windowClass = AdaptiveScope.of(context);
    final wide = windowClass != WindowClass.compact;

    final filtered = ws.questions.where((q) {
      if (_subjectFilter != null && q.meta.subject != _subjectFilter) {
        return false;
      }
      if (_kindFilter != null && q.kind != _kindFilter) return false;
      if (_onlyUnverified && q.meta.answerSource != AnswerSource.ai) {
        return false;
      }
      if (_search.trim().isNotEmpty) {
        final s = _search.trim().toLowerCase();
        final match =
            q.header.title.toLowerCase().contains(s) ||
            q.plainText.toLowerCase().contains(s) ||
            q.meta.tags.any((tag) => tag.toLowerCase().contains(s));
        if (!match) return false;
      }
      return true;
    }).toList();

    Question? selectedQ;
    if (filtered.isNotEmpty) {
      selectedQ = filtered.firstWhere(
        (q) => q.id == _selectedQuestionId,
        orElse: () => filtered.first,
      );
      _selectedQuestionId = selectedQ.id;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('我的题库'),
        actions: [
          IconButton(
            tooltip: '拍照录题',
            onPressed: () => showCaptureModal(context),
            icon: const Icon(Icons.photo_camera_outlined),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.icon(
              onPressed: () => _openEditor(context, state, notifier),
              icon: const Icon(Icons.add, size: 17),
              label: const Text('录题'),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(wide ? 20 : 14, 6, wide ? 20 : 14, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (wide)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SegmentedButton<_LibraryTab>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(
                            value: _LibraryTab.questions,
                            label: Text('题目'),
                          ),
                          ButtonSegment(
                            value: _LibraryTab.docs,
                            label: Text('试卷'),
                          ),
                          ButtonSegment(
                            value: _LibraryTab.tags,
                            label: Text('标签'),
                          ),
                        ],
                        selected: {_tab},
                        onSelectionChanged: (sel) =>
                            setState(() => _tab = sel.first),
                      ),
                      SizedBox(
                        width: 240,
                        child: TextField(
                          onChanged: (v) => setState(() => _search = v),
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.search, size: 17),
                            hintText: '搜索题干或标签…',
                          ),
                        ),
                      ),
                      if (_tab == _LibraryTab.questions) ...[
                        _SubjectDropdownPill(
                          value: _subjectFilter,
                          onChanged: (v) => setState(() => _subjectFilter = v),
                        ),
                        _KindDropdownPill(
                          value: _kindFilter,
                          onChanged: (v) => setState(() => _kindFilter = v),
                        ),
                        FilterChip(
                          label: const Text('待核对'),
                          selected: _onlyUnverified,
                          onSelected: (on) =>
                              setState(() => _onlyUnverified = on),
                        ),
                      ],
                    ],
                  )
                else ...[
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<_LibraryTab>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(
                          value: _LibraryTab.questions,
                          label: Text('题目'),
                        ),
                        ButtonSegment(
                          value: _LibraryTab.docs,
                          label: Text('试卷'),
                        ),
                        ButtonSegment(
                          value: _LibraryTab.tags,
                          label: Text('标签'),
                        ),
                      ],
                      selected: {_tab},
                      onSelectionChanged: (sel) =>
                          setState(() => _tab = sel.first),
                    ),
                  ),
                  if (_tab == _LibraryTab.questions) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            onChanged: (v) => setState(() => _search = v),
                            decoration: const InputDecoration(
                              prefixIcon: Icon(Icons.search, size: 17),
                              hintText: '搜索题干或标签…',
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        _SubjectDropdownPill(
                          value: _subjectFilter,
                          onChanged: (v) => setState(() => _subjectFilter = v),
                        ),
                        const SizedBox(width: 4),
                        _KindDropdownPill(
                          value: _kindFilter,
                          onChanged: (v) => setState(() => _kindFilter = v),
                        ),
                        const SizedBox(width: 4),
                        FilterChip(
                          label: const Text('待核'),
                          selected: _onlyUnverified,
                          onSelected: (on) =>
                              setState(() => _onlyUnverified = on),
                        ),
                      ],
                    ),
                  ],
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: switch (_tab) {
              _LibraryTab.docs => _buildDocsTab(context, state, ws, notifier),
              _LibraryTab.tags => _buildTagsTab(t, ws),
              _LibraryTab.questions =>
                filtered.isEmpty
                    ? InouEmptyState(
                        icon: Icons.library_books_outlined,
                        title: ws.questions.isEmpty ? '题库还是空的' : '没有匹配的题目',
                        subtitle: ws.questions.isEmpty
                            ? '用相机拍一份试卷，或点右上角「录题」添加。'
                            : '试着切换搜索词或筛选条件。',
                        action: Wrap(
                          spacing: 8,
                          children: [
                            FilledButton.icon(
                              onPressed: () => showCaptureModal(context),
                              icon: const Icon(
                                Icons.camera_alt_outlined,
                                size: 16,
                              ),
                              label: const Text('拍照录题'),
                            ),
                            OutlinedButton.icon(
                              onPressed: () =>
                                  _openEditor(context, state, notifier),
                              icon: const Icon(Icons.add, size: 16),
                              label: const Text('手工录题'),
                            ),
                          ],
                        ),
                      )
                    : wide
                    ? Row(
                        children: [
                          Expanded(
                            flex: 5,
                            child: _QuestionListView(
                              questions: filtered,
                              selectedId: selectedQ?.id,
                              onTap: (q) =>
                                  setState(() => _selectedQuestionId = q.id),
                            ),
                          ),
                          const VerticalDivider(width: 1),
                          Expanded(
                            flex: 6,
                            child: selectedQ == null
                                ? const SizedBox.shrink()
                                : _QuestionInspector(
                                    question: selectedQ,
                                    state: state,
                                    showAnswer: _showAnswer,
                                    onToggleAnswer: () => setState(
                                      () => _showAnswer = !_showAnswer,
                                    ),
                                    onEdit: () => _openEditor(
                                      context,
                                      state,
                                      notifier,
                                      existing: selectedQ,
                                    ),
                                    onVerifyAnswer: () =>
                                        notifier.upsertQuestion(
                                          selectedQ!.copyWith(
                                            meta: selectedQ.meta.copyWith(
                                              answerSource: AnswerSource.user,
                                              uncertainNote: null,
                                            ),
                                          ),
                                        ),
                                    onPracticeSingle: () => _practiceSingle(
                                      context,
                                      notifier,
                                      selectedQ!,
                                    ),
                                    onAddToWrongBook: () async {
                                      await notifier
                                          .collectQuestionsIntoWrongBook([
                                            selectedQ!.id,
                                          ]);
                                      if (!context.mounted) return;
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(content: Text('已加入错题本')),
                                      );
                                    },
                                    onAskTutor: () => notifier.openCopilot(
                                      questionId: selectedQ!.id,
                                      hintLevel: HintLevel.l1Concept,
                                    ),
                                    onOpenBlackboard: () =>
                                        notifier.openBlackboard(
                                          questionId: selectedQ!.id,
                                          hintLevel: HintLevel.l1Concept,
                                        ),
                                    onDelete: () => _deleteQuestionWithPin(
                                      context,
                                      state,
                                      notifier,
                                      selectedQ!.id,
                                    ),
                                  ),
                          ),
                        ],
                      )
                    : _QuestionListView(
                        questions: filtered,
                        selectedId: selectedQ?.id,
                        onTap: (q) {
                          setState(() => _selectedQuestionId = q.id);
                          showModalBottomSheet<void>(
                            context: context,
                            isScrollControlled: true,
                            builder: (_) => FractionallySizedBox(
                              heightFactor: 0.85,
                              child: _QuestionInspector(
                                question: q,
                                state: state,
                                showAnswer: true,
                                onToggleAnswer: () {},
                                onEdit: () {
                                  Navigator.of(context).pop();
                                  _openEditor(
                                    context,
                                    state,
                                    notifier,
                                    existing: q,
                                  );
                                },
                                onVerifyAnswer: () => notifier.upsertQuestion(
                                  q.copyWith(
                                    meta: q.meta.copyWith(
                                      answerSource: AnswerSource.user,
                                      uncertainNote: null,
                                    ),
                                  ),
                                ),
                                onPracticeSingle: () {
                                  Navigator.of(context).pop();
                                  _practiceSingle(context, notifier, q);
                                },
                                onAddToWrongBook: () async {
                                  await notifier.collectQuestionsIntoWrongBook([
                                    q.id,
                                  ]);
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('已加入错题本')),
                                  );
                                },
                                onAskTutor: () {
                                  Navigator.of(context).pop();
                                  notifier.openCopilot(
                                    questionId: q.id,
                                    hintLevel: HintLevel.l1Concept,
                                  );
                                },
                                onOpenBlackboard: () {
                                  Navigator.of(context).pop();
                                  notifier.openBlackboard(
                                    questionId: q.id,
                                    hintLevel: HintLevel.l1Concept,
                                  );
                                },
                                onDelete: () {
                                  Navigator.of(context).pop();
                                  _deleteQuestionWithPin(
                                    context,
                                    state,
                                    notifier,
                                    q.id,
                                  );
                                },
                              ),
                            ),
                          );
                        },
                      ),
            },
          ),
        ],
      ),
    );
  }

  Future<void> _deleteQuestionWithPin(
    BuildContext context,
    AppState state,
    AppStoreNotifier notifier,
    String qId,
  ) async {
    final ok = await ensureParentPinAuthorized(
      context,
      state,
      notifier,
      reason: '删除题目需要验证家长密码',
    );
    if (!ok) return;
    await notifier.deleteQuestion(qId);
  }

  Future<void> _openEditor(
    BuildContext context,
    AppState state,
    AppStoreNotifier notifier, {
    Question? existing,
  }) async {
    final edited = await showQuestionEditorDialog(
      context,
      state: state,
      existing: existing,
      defaultSubject: _subjectFilter ?? 'math',
      onSaveAndNext: existing == null
          ? (q) => notifier.upsertQuestion(q)
          : null,
    );
    if (edited == null) return;
    await notifier.upsertQuestion(edited);
    if (!mounted) return;
    setState(() => _selectedQuestionId = edited.id);
  }

  Future<void> _practiceSingle(
    BuildContext context,
    AppStoreNotifier notifier,
    Question q,
  ) async {
    await notifier.startPracticeSession(
      title: '单题练习 · ${q.header.title}',
      kind: PracticeKind.single,
      inputMode: InputMode.standard,
      feedbackTiming: FeedbackTiming.instant,
      questionIds: [q.id],
    );
    if (context.mounted) {
      context.go('/practice');
    }
  }

  Widget _buildDocsTab(
    BuildContext context,
    AppState state,
    ProfileWorkspaceData ws,
    AppStoreNotifier notifier,
  ) {
    final docs = ws.sourceDocs;
    final questions = ws.questions;
    if (docs.isEmpty) {
      return InouEmptyState(
        icon: Icons.folder_open_outlined,
        title: '还没有录入试卷',
        subtitle: '拍照并确认入库后，试卷原图与题目归档将显示在这里。',
        action: FilledButton(
          onPressed: () => showCaptureModal(context),
          child: const Text('拍照录卷'),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: docs.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, idx) {
        final doc = docs[idx];
        final docQs = questions.where((q) => q.docId == doc.id).toList();
        return InouSurface(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              const Icon(Icons.description_outlined, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      doc.title,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${SubjectCatalog.labelOf(doc.subject)} · 共 ${docQs.length} 道题',
                      style: TextStyle(
                        fontSize: 12,
                        color: context.inou.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              if (doc.localImagePath != null)
                IconButton(
                  tooltip: '查看原卷照片',
                  onPressed: () async {
                    final bytes = await notifier.readDocImageBytes(
                      doc.localImagePath,
                    );
                    if (!context.mounted || bytes == null) return;
                    await showDialog<void>(
                      context: context,
                      builder: (ctx) => Dialog(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AppBar(
                              title: Text(doc.title),
                              automaticallyImplyLeading: false,
                              actions: [
                                IconButton(
                                  onPressed: () => Navigator.of(ctx).pop(),
                                  icon: const Icon(Icons.close),
                                ),
                              ],
                            ),
                            Flexible(
                              child: InteractiveViewer(
                                child: Image.memory(bytes, fit: BoxFit.contain),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.image_outlined, size: 20),
                ),
              IconButton(
                tooltip: '删除试卷记录',
                onPressed: () async {
                  final ok = await ensureParentPinAuthorized(
                    context,
                    state,
                    notifier,
                    reason: '删除试卷需要验证家长密码',
                  );
                  if (!ok) return;
                  await notifier.deleteSourceDoc(doc.id, deleteQuestions: true);
                },
                icon: Icon(
                  Icons.delete_outline,
                  size: 20,
                  color: context.inou.danger,
                ),
              ),
              const SizedBox(width: 4),
              FilledButton(
                onPressed: docQs.isEmpty
                    ? null
                    : () async {
                        await notifier.startPracticeSession(
                          title: doc.title,
                          kind: PracticeKind.exam,
                          inputMode: InputMode.paper,
                          feedbackTiming: FeedbackTiming.afterSubmit,
                          questionIds: docQs.map((q) => q.id).toList(),
                          docId: doc.id,
                        );
                        if (context.mounted) context.go('/practice');
                      },
                child: const Text('重做整卷'),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTagsTab(InouTokens t, ProfileWorkspaceData ws) {
    final questions = ws.questions;
    final byTag = <String, List<Question>>{};
    for (final q in questions) {
      for (final tag in q.meta.tags) {
        byTag.putIfAbsent(tag, () => []).add(q);
      }
    }
    if (byTag.isEmpty) {
      return const InouEmptyState(icon: Icons.sell_outlined, title: '暂无标签');
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final entry in byTag.entries)
              InouSurface(
                padding: const EdgeInsets.all(14),
                onTap: () {
                  setState(() {
                    _tab = _LibraryTab.questions;
                    _search = entry.key;
                  });
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.sell_outlined, size: 16, color: t.accent),
                    const SizedBox(width: 8),
                    Text(
                      entry.key,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 8),
                    InouBadge(label: '${entry.value.length} 题'),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _QuestionListView extends StatelessWidget {
  const _QuestionListView({
    required this.questions,
    required this.selectedId,
    required this.onTap,
  });

  final List<Question> questions;
  final String? selectedId;
  final ValueChanged<Question> onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.inou;
    return ListView.separated(
      padding: const EdgeInsets.all(14),
      itemCount: questions.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final q = questions[index];
        final isSelected = q.id == selectedId;
        final needsVerify = q.meta.answerSource == AnswerSource.ai;
        return InouSurface(
          onTap: () => onTap(q),
          borderWidth: isSelected ? 2.0 : 0.9,
          borderColor: isSelected ? t.accent : t.borderHairline,
          backgroundColor: isSelected ? t.accentSoft : t.surface,
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  InouBadge(
                    label:
                        '${SubjectCatalog.labelOf(q.meta.subject)} · ${q.displayKindLabel}',
                    tone: InouBadgeTone.accent,
                  ),
                  const SizedBox(width: 6),
                  if (needsVerify)
                    const InouBadge(label: '待核对', tone: InouBadgeTone.warning),
                  const Spacer(),
                  Text(
                    '${q.maxScore.toStringAsFixed(0)} 分',
                    style: TextStyle(fontSize: 11.5, color: t.textMuted),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                q.header.title,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: t.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                q.plainText,
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

class _QuestionInspector extends StatelessWidget {
  const _QuestionInspector({
    required this.question,
    required this.state,
    required this.showAnswer,
    required this.onToggleAnswer,
    required this.onEdit,
    required this.onVerifyAnswer,
    required this.onPracticeSingle,
    required this.onAddToWrongBook,
    required this.onAskTutor,
    required this.onOpenBlackboard,
    required this.onDelete,
  });

  final Question question;
  final AppState state;
  final bool showAnswer;
  final VoidCallback onToggleAnswer;
  final VoidCallback onEdit;
  final VoidCallback onVerifyAnswer;
  final VoidCallback onPracticeSingle;
  final VoidCallback onAddToWrongBook;
  final VoidCallback onAskTutor;
  final VoidCallback onOpenBlackboard;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final t = context.inou;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            InouBadge(
              label: question.displayKindLabel,
              tone: InouBadgeTone.accent,
            ),
            const SizedBox(width: 6),
            InouBadge(
              label: question.meta.answerSource.label,
              tone: question.meta.answerSource == AnswerSource.ai
                  ? InouBadgeTone.warning
                  : InouBadgeTone.success,
            ),
            const Spacer(),
            IconButton(
              tooltip: '编辑题目',
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined, size: 20),
            ),
            IconButton(
              tooltip: '删除此题',
              onPressed: onDelete,
              icon: Icon(Icons.delete_outline, color: t.danger, size: 20),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          question.header.title,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: t.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final kpId in question.meta.kpIds)
              InouBadge(label: state.kpTree.nameOf(kpId)),
            for (final tag in question.meta.tags) InouBadge(label: '#$tag'),
          ],
        ),
        const SizedBox(height: 14),
        InouSurface(
          padding: const EdgeInsets.all(16),
          child: ContentBlockRenderer(blocks: question.prompt),
        ),
        if (question.meta.uncertainNote != null) ...[
          const SizedBox(height: 10),
          InouSurface(
            backgroundColor: t.warningSoft,
            borderColor: t.warning.withValues(alpha: 0.4),
            padding: const EdgeInsets.all(12),
            child: Text(
              question.meta.uncertainNote!,
              style: TextStyle(fontSize: 12.5, color: t.warning),
            ),
          ),
        ],
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: onPracticeSingle,
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: const Text('练习这题'),
            ),
            OutlinedButton.icon(
              onPressed: onAskTutor,
              icon: const Icon(Icons.auto_awesome_outlined, size: 16),
              label: const Text('问诺诺'),
            ),
            FilledButton.tonalIcon(
              style: FilledButton.styleFrom(
                backgroundColor: t.accentSoft,
                foregroundColor: t.accent,
                elevation: 0,
              ),
              onPressed: onOpenBlackboard,
              icon: const Icon(Icons.co_present_outlined, size: 16),
              label: const Text('黑板讲题'),
            ),
            Builder(
              builder: (_) {
                final inWrongBook = state.activeWorkspace.wrongItems.any(
                  (w) => w.questionId == question.id,
                );
                return OutlinedButton.icon(
                  onPressed: inWrongBook ? null : onAddToWrongBook,
                  icon: Icon(
                    inWrongBook
                        ? Icons.bookmark_added_outlined
                        : Icons.bookmark_add_outlined,
                    size: 16,
                  ),
                  label: Text(inWrongBook ? '已在错题本' : '加入错题本'),
                );
              },
            ),
            if (question.meta.answerSource == AnswerSource.ai)
              OutlinedButton.icon(
                onPressed: onVerifyAnswer,
                icon: const Icon(Icons.verified_outlined, size: 16),
                label: const Text('确认答案无误'),
              ),
          ],
        ),
        const SizedBox(height: 18),
        InkWell(
          onTap: onToggleAnswer,
          child: Row(
            children: [
              Text(
                '答案与解析',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: t.textPrimary,
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                showAnswer ? Icons.expand_less : Icons.expand_more,
                size: 18,
              ),
            ],
          ),
        ),
        if (showAnswer) ...[
          const SizedBox(height: 8),
          InouSurface(
            subtle: true,
            padding: const EdgeInsets.all(14),
            child: question.explanation.isNotEmpty
                ? ContentBlockRenderer(blocks: question.explanation)
                : const Text('暂无文字解析'),
          ),
        ],
      ],
    );
  }
}

class _SubjectDropdownPill extends StatelessWidget {
  const _SubjectDropdownPill({required this.value, required this.onChanged});

  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.inou;
    return PopupMenuButton<String>(
      tooltip: '按学科筛选',
      onSelected: (code) => onChanged(code == '__all__' ? null : code),
      itemBuilder: (_) => [
        const PopupMenuItem(value: '__all__', child: Text('全科')),
        for (final entry in SubjectCatalog.labels.entries)
          PopupMenuItem(value: entry.key, child: Text(entry.value)),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: value != null ? t.accent : t.surfaceMuted,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value != null ? SubjectCatalog.labelOf(value!) : '全科',
              style: TextStyle(
                fontSize: 12,
                fontWeight: value != null ? FontWeight.w700 : FontWeight.w600,
                color: value != null ? Colors.white : t.textPrimary,
              ),
            ),
            Icon(
              Icons.arrow_drop_down,
              size: 16,
              color: value != null ? Colors.white : t.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}

class _KindDropdownPill extends StatelessWidget {
  const _KindDropdownPill({required this.value, required this.onChanged});

  final QuestionKind? value;
  final ValueChanged<QuestionKind?> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.inou;
    return PopupMenuButton<String>(
      tooltip: '按题型筛选',
      onSelected: (code) {
        if (code == '__all__') {
          onChanged(null);
        } else {
          onChanged(QuestionKind.fromCode(code));
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: '__all__', child: Text('全部题型')),
        for (final k in QuestionKind.values)
          PopupMenuItem(value: k.code, child: Text(k.label)),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: value != null ? t.accent : t.surfaceMuted,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value?.label ?? '题型',
              style: TextStyle(
                fontSize: 12,
                fontWeight: value != null ? FontWeight.w700 : FontWeight.w600,
                color: value != null ? Colors.white : t.textPrimary,
              ),
            ),
            Icon(
              Icons.arrow_drop_down,
              size: 16,
              color: value != null ? Colors.white : t.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}
