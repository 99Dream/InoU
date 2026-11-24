import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:inou_ai/inou_ai.dart';
import 'package:inou_domain/inou_domain.dart';
import 'package:inou_ui_kit/inou_ui_kit.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/platform/platform_media_service.dart';
import '../../../core/state/app_store.dart';
import '../../capture/presentation/capture_sheet.dart';
import 'paper_studio_view.dart';
import 'standard_question_widgets.dart';

class PracticePage extends ConsumerStatefulWidget {
  const PracticePage({super.key});

  @override
  ConsumerState<PracticePage> createState() => _PracticePageState();
}

class _PracticePageState extends ConsumerState<PracticePage> {
  InputMode _preferredInputMode = InputMode.standard;
  FeedbackTiming _preferredTiming = FeedbackTiming.instant;
  String? _customSubject;
  int _customCount = 5;

  int _currentIndex = 0;
  final Map<String, StudentResponse> _draftResponses = {};
  final Map<String, Uint8List> _attachedPhotosByQid = {};
  final Map<String, AttemptRecord> _submittedByQid = {};
  final Set<String> _checkedWrongIds = {};
  bool _gradingBusy = false;
  bool _showScoreReport = false;
  String? _lastTrackedSessionId;

  void _syncSessionState(
    PracticeSession? session,
    List<AttemptRecord> attempts,
  ) {
    if (session == null) {
      _lastTrackedSessionId = null;
      return;
    }
    if (_lastTrackedSessionId != session.id) {
      _lastTrackedSessionId = session.id;
      _currentIndex = 0;
      _draftResponses.clear();
      _attachedPhotosByQid.clear();
      _submittedByQid.clear();
      _checkedWrongIds.clear();
      _showScoreReport = session.status == 'submitted';
      for (final a in attempts.where((a) => a.sessionId == session.id)) {
        _submittedByQid[a.questionId] = a;
        if (a.verdict == Verdict.wrong || a.verdict == Verdict.partial) {
          _checkedWrongIds.add(a.questionId);
        }
      }
    } else {
      for (final a in attempts.where((a) => a.sessionId == session.id)) {
        _submittedByQid[a.questionId] = a;
      }
    }
  }

  Future<void> _attachSolutionPhoto(String qId, {required bool camera}) async {
    final media = ref.read(platformMediaServiceProvider);
    final res = camera
        ? await media.capturePhoto()
        : await media.pickGalleryImage();
    if (!mounted || res == null) return;
    setState(() {
      _attachedPhotosByQid[qId] = res.bytes;
      _draftResponses.putIfAbsent(
        qId,
        () => SolveResponse(
          questionId: qId,
          inputMode: InputMode.standard,
          steps: const ['已拍摄纸面作答照片等待批改'],
        ),
      );
    });
  }

  Future<void> _confirmExitSession(
    BuildContext context,
    AppStoreNotifier notifier,
  ) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('离开当前练习？'),
        content: const Text('可以保存进度稍后继续，或直接交卷查看成绩。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('stay'),
            child: const Text('继续作答'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.of(ctx).pop('save_exit'),
            child: const Text('保存并退出'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop('report'),
            child: const Text('直接交卷'),
          ),
        ],
      ),
    );
    if (!mounted || choice == null || choice == 'stay') return;
    if (choice == 'save_exit') {
      notifier.exitActivePracticeSession();
    } else if (choice == 'report') {
      setState(() => _showScoreReport = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.inou;
    final state = ref.watch(appStoreProvider);
    final notifier = ref.read(appStoreProvider.notifier);
    final ws = state.activeWorkspace;
    final session = state.activeSession;
    _syncSessionState(session, ws.attempts);

    if (session == null) {
      return _buildPracticeHub(context, state, notifier);
    }

    final qMap = {for (final q in ws.questions) q.id: q};
    final sessionQuestions = session.questionIds
        .map((id) => qMap[id])
        .whereType<Question>()
        .toList();

    if (sessionQuestions.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(session.title)),
        body: InouEmptyState(
          icon: Icons.quiz_outlined,
          title: '本场题目已被移除',
          action: FilledButton(
            onPressed: notifier.exitActivePracticeSession,
            child: const Text('返回'),
          ),
        ),
      );
    }

    if (_showScoreReport) {
      return _buildScoreReport(
        context,
        t,
        state,
        notifier,
        session,
        sessionQuestions,
      );
    }

    if (session.inputMode == InputMode.paper) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => _confirmExitSession(context, notifier),
          ),
          title: Text(session.title),
        ),
        body: PaperStudioView(
          session: session,
          questions: sessionQuestions,
          attempts: _submittedByQid,
          onSubmittedSession: () {
            setState(() => _showScoreReport = true);
          },
        ),
      );
    }

    if (_currentIndex >= sessionQuestions.length) _currentIndex = 0;
    final currentQ = sessionQuestions[_currentIndex];
    final currentAttempt = _submittedByQid[currentQ.id];
    final currentDraft = _draftResponses[currentQ.id];
    final attachedPhoto = _attachedPhotosByQid[currentQ.id];
    final isSubjective =
        currentQ.kind == QuestionKind.solve ||
        currentQ.kind == QuestionKind.response ||
        currentQ.kind == QuestionKind.draw;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => _confirmExitSession(context, notifier),
        ),
        title: Text(
          '${session.title} (${_currentIndex + 1}/${sessionQuestions.length})',
        ),
        actions: [
          TextButton.icon(
            onPressed: () => notifier.openBlackboard(
              questionId: currentQ.id,
              hintLevel: HintLevel.l1Concept,
            ),
            icon: const Icon(Icons.co_present_outlined, size: 17),
            label: const Text('黑板讲题'),
          ),
          TextButton.icon(
            onPressed: () => notifier.openCopilot(
              questionId: currentQ.id,
              hintLevel: HintLevel.l1Concept,
            ),
            icon: const Icon(Icons.auto_awesome_outlined, size: 17),
            label: const Text('问诺诺'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Container(
            color: t.surface,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (var i = 0; i < sessionQuestions.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ChoiceChip(
                              label: Text('${i + 1}'),
                              selected: _currentIndex == i,
                              avatar:
                                  _submittedByQid[sessionQuestions[i].id] !=
                                      null
                                  ? Icon(
                                      _submittedByQid[sessionQuestions[i].id]!
                                                  .verdict ==
                                              Verdict.correct
                                          ? Icons.check_circle
                                          : Icons.cancel,
                                      size: 14,
                                      color:
                                          _submittedByQid[sessionQuestions[i]
                                                      .id]!
                                                  .verdict ==
                                              Verdict.correct
                                          ? t.success
                                          : t.danger,
                                    )
                                  : null,
                              onSelected: (_) =>
                                  setState(() => _currentIndex = i),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                FilledButton(
                  onPressed: _gradingBusy
                      ? null
                      : () async {
                          setState(() => _gradingBusy = true);
                          for (final q in sessionQuestions) {
                            if (!_submittedByQid.containsKey(q.id)) {
                              final resp = _draftResponses[q.id];
                              if (resp != null) {
                                final photo = _attachedPhotosByQid[q.id];
                                final att = await notifier
                                    .submitQuestionResponse(
                                      sessionId: session.id,
                                      question: q,
                                      response: resp,
                                      attachedPngs: [?photo],
                                    );
                                _submittedByQid[q.id] = att;
                                if (att.verdict == Verdict.wrong ||
                                    att.verdict == Verdict.partial) {
                                  _checkedWrongIds.add(q.id);
                                }
                              }
                            }
                          }
                          await notifier.finalizePracticeSession(session.id);
                          if (!mounted) return;
                          setState(() {
                            _gradingBusy = false;
                            _showScoreReport = true;
                          });
                        },
                  child: const Text('整卷交卷'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 820),
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Row(
                      children: [
                        InouBadge(
                          label: currentQ.displayKindLabel,
                          tone: InouBadgeTone.accent,
                        ),
                        const SizedBox(width: 8),
                        InouBadge(
                          label: SubjectCatalog.labelOf(currentQ.meta.subject),
                        ),
                        const Spacer(),
                        Text(
                          '${currentQ.maxScore.toStringAsFixed(0)} 分',
                          style: TextStyle(fontSize: 12.5, color: t.textMuted),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      currentQ.header.title,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: t.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    InouSurface(
                      padding: const EdgeInsets.all(18),
                      child: StandardQuestionWidget(
                        key: ValueKey(currentQ.id),
                        question: currentQ,
                        response: currentDraft ?? currentAttempt?.response,
                        onChanged: (resp) =>
                            setState(() => _draftResponses[currentQ.id] = resp),
                      ),
                    ),
                    if (isSubjective) ...[
                      const SizedBox(height: 10),
                      if (attachedPhoto != null)
                        InouSurface(
                          backgroundColor: t.surfaceMuted,
                          padding: const EdgeInsets.all(10),
                          child: Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.memory(
                                  attachedPhoto,
                                  width: 56,
                                  height: 44,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              const SizedBox(width: 10),
                              const Expanded(
                                child: Text(
                                  '已拍纸面作答照片（提交后用于 AI 批改）',
                                  style: TextStyle(fontSize: 12.5),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close, size: 18),
                                onPressed: () => setState(
                                  () =>
                                      _attachedPhotosByQid.remove(currentQ.id),
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        Wrap(
                          spacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: () => _attachSolutionPhoto(
                                currentQ.id,
                                camera: true,
                              ),
                              icon: const Icon(
                                Icons.camera_alt_outlined,
                                size: 16,
                              ),
                              label: const Text('拍纸面解答'),
                            ),
                            OutlinedButton.icon(
                              onPressed: () => _attachSolutionPhoto(
                                currentQ.id,
                                camera: false,
                              ),
                              icon: const Icon(
                                Icons.photo_library_outlined,
                                size: 16,
                              ),
                              label: const Text('传解答图'),
                            ),
                          ],
                        ),
                    ],
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        if (_currentIndex > 0)
                          OutlinedButton.icon(
                            onPressed: () => setState(() => _currentIndex--),
                            icon: const Icon(Icons.chevron_left, size: 18),
                            label: const Text('上一题'),
                          ),
                        const Spacer(),
                        if (session.feedbackTiming == FeedbackTiming.instant)
                          FilledButton.icon(
                            onPressed:
                                _gradingBusy ||
                                    (currentDraft == null &&
                                        attachedPhoto == null)
                                ? null
                                : () async {
                                    setState(() => _gradingBusy = true);
                                    final effectiveResp =
                                        currentDraft ??
                                        SolveResponse(
                                          questionId: currentQ.id,
                                          inputMode: InputMode.standard,
                                          steps: const ['拍照上传纸面过程'],
                                        );
                                    final att = await notifier
                                        .submitQuestionResponse(
                                          sessionId: session.id,
                                          question: currentQ,
                                          response: effectiveResp,
                                          attachedPngs: [?attachedPhoto],
                                        );
                                    if (!mounted) return;
                                    setState(() {
                                      _submittedByQid[currentQ.id] = att;
                                      if (att.verdict == Verdict.wrong ||
                                          att.verdict == Verdict.partial) {
                                        _checkedWrongIds.add(currentQ.id);
                                      }
                                      _gradingBusy = false;
                                    });
                                  },
                            icon: const Icon(Icons.check, size: 16),
                            label: Text(_gradingBusy ? '批改中…' : '提交本题'),
                          ),
                        const SizedBox(width: 8),
                        if (_currentIndex < sessionQuestions.length - 1)
                          OutlinedButton.icon(
                            onPressed: () => setState(() => _currentIndex++),
                            icon: const Icon(Icons.chevron_right, size: 18),
                            label: const Text('下一题'),
                          ),
                      ],
                    ),
                    if (currentAttempt != null) ...[
                      const SizedBox(height: 16),
                      _buildAttemptFeedbackCard(
                        t,
                        notifier,
                        currentQ,
                        currentAttempt,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttemptFeedbackCard(
    InouTokens t,
    AppStoreNotifier notifier,
    Question q,
    AttemptRecord attempt,
  ) {
    final isOk = attempt.verdict == Verdict.correct;
    return InouSurface(
      backgroundColor: isOk
          ? t.successSoft
          : (attempt.verdict == Verdict.ungraded
                ? t.surfaceMuted
                : t.dangerSoft),
      borderColor:
          (isOk
                  ? t.success
                  : (attempt.verdict == Verdict.ungraded
                        ? t.borderHairline
                        : t.danger))
              .withValues(alpha: 0.45),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              InouBadge(
                label:
                    '${attempt.verdict.label} (${attempt.score}/${attempt.maxScore})',
                tone: isOk
                    ? InouBadgeTone.success
                    : (attempt.verdict == Verdict.ungraded
                          ? InouBadgeTone.neutral
                          : InouBadgeTone.danger),
              ),
              for (final v in const [
                Verdict.correct,
                Verdict.partial,
                Verdict.wrong,
              ])
                ChoiceChip(
                  label: Text(
                    '记为${v.label}',
                    style: const TextStyle(fontSize: 11),
                  ),
                  selected: attempt.verdict == v,
                  onSelected: (_) async {
                    final next = await notifier.overrideAttemptVerdict(
                      attemptId: attempt.id,
                      newVerdict: v,
                    );
                    if (next != null && mounted) {
                      setState(() => _submittedByQid[q.id] = next);
                    }
                  },
                ),
            ],
          ),
          if (attempt.feedbackSummary != null &&
              attempt.feedbackSummary!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              attempt.feedbackSummary!,
              style: TextStyle(fontSize: 13, color: t.textPrimary),
            ),
          ],
          if (q.explanation.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: t.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: t.borderHairline),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '参考解析',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: t.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  ContentBlockRenderer(blocks: q.explanation),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildScoreReport(
    BuildContext context,
    InouTokens t,
    AppState state,
    AppStoreNotifier notifier,
    PracticeSession session,
    List<Question> sessionQuestions,
  ) {
    final earned = _submittedByQid.values.fold<double>(
      0,
      (acc, a) => acc + a.score,
    );
    final total = sessionQuestions.fold<double>(
      0,
      (acc, q) => acc + q.maxScore,
    );
    final ratio = total > 0 ? (earned / total).clamp(0.0, 1.0) : 0.0;

    return Scaffold(
      appBar: AppBar(title: const Text('练习成绩单')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(22),
            children: [
              InouSurface(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    InouScoreRing(
                      ratio: ratio,
                      headline: '${(ratio * 100).round()}%',
                      caption: '得分率',
                      size: 92,
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            session.title,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: t.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${earned.toStringAsFixed(1)} / ${total.toStringAsFixed(1)} 分 · 已作答 ${_submittedByQid.length}/${sessionQuestions.length} 题',
                            style: TextStyle(
                              fontSize: 13.5,
                              color: t.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              FilledButton(
                                onPressed: () async {
                                  if (_checkedWrongIds.isNotEmpty) {
                                    await notifier
                                        .collectQuestionsIntoWrongBook(
                                          _checkedWrongIds.toList(),
                                        );
                                  }
                                  notifier.exitActivePracticeSession();
                                  if (context.mounted) {
                                    context.go('/wrongbook');
                                  }
                                },
                                child: Text(
                                  _checkedWrongIds.isNotEmpty
                                      ? '收录错题 (${_checkedWrongIds.length})'
                                      : '去错题本',
                                ),
                              ),
                              OutlinedButton(
                                onPressed: notifier.exitActivePracticeSession,
                                child: const Text('返回'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              for (var i = 0; i < sessionQuestions.length; i++)
                Builder(
                  builder: (context) {
                    final q = sessionQuestions[i];
                    final att = _submittedByQid[q.id];
                    final isWrong =
                        att == null || att.verdict != Verdict.correct;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: InouSurface(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            Checkbox(
                              value: _checkedWrongIds.contains(q.id),
                              onChanged: (v) {
                                setState(() {
                                  if (v == true) {
                                    _checkedWrongIds.add(q.id);
                                  } else {
                                    _checkedWrongIds.remove(q.id);
                                  }
                                });
                              },
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '第 ${i + 1} 题 · ${q.header.title}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  if (att?.feedbackSummary != null)
                                    Text(
                                      att!.feedbackSummary!,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: t.textMuted,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            InouBadge(
                              label: att != null
                                  ? '${att.verdict.label} (${att.score}/${att.maxScore})'
                                  : '未作答',
                              tone: isWrong
                                  ? InouBadgeTone.danger
                                  : InouBadgeTone.success,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPracticeHub(
    BuildContext context,
    AppState state,
    AppStoreNotifier notifier,
  ) {
    final t = context.inou;
    final ws = state.activeWorkspace;
    final wide = AdaptiveScope.of(context) != WindowClass.compact;
    final wrongQIds = ws.wrongItems
        .where((w) => w.mastery != MasteryState.mastered)
        .map((w) => w.questionId)
        .toList();

    final customFiltered = ws.questions
        .where(
          (q) => _customSubject == null || q.meta.subject == _customSubject,
        )
        .toList();
    final customPool =
        (_customCount <= 0 ? customFiltered : customFiltered.take(_customCount))
            .map((q) => q.id)
            .toList();

    final modeSelectors = wide
        ? Row(
            children: [
              SegmentedButton<InputMode>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: InputMode.standard, label: Text('标准作答')),
                  ButtonSegment(value: InputMode.paper, label: Text('A4 手写稿纸')),
                ],
                selected: {_preferredInputMode},
                onSelectionChanged: (sel) =>
                    setState(() => _preferredInputMode = sel.first),
              ),
              const SizedBox(width: 12),
              SegmentedButton<FeedbackTiming>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: FeedbackTiming.instant,
                    label: Text('逐题核对'),
                  ),
                  ButtonSegment(
                    value: FeedbackTiming.afterSubmit,
                    label: Text('交卷判分'),
                  ),
                ],
                selected: {_preferredTiming},
                onSelectionChanged: (sel) =>
                    setState(() => _preferredTiming = sel.first),
              ),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<InputMode>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: InputMode.standard, label: Text('标准作答')),
                  ButtonSegment(value: InputMode.paper, label: Text('A4 手写稿纸')),
                ],
                selected: {_preferredInputMode},
                onSelectionChanged: (sel) =>
                    setState(() => _preferredInputMode = sel.first),
              ),
              const SizedBox(height: 8),
              SegmentedButton<FeedbackTiming>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: FeedbackTiming.instant,
                    label: Text('逐题核对'),
                  ),
                  ButtonSegment(
                    value: FeedbackTiming.afterSubmit,
                    label: Text('交卷判分'),
                  ),
                ],
                selected: {_preferredTiming},
                onSelectionChanged: (sel) =>
                    setState(() => _preferredTiming = sel.first),
              ),
            ],
          );

    final customPackCard = InouSurface(
      elevated: true,
      padding: EdgeInsets.all(wide ? 18 : 15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '按学科 / 题量自选组卷',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: t.textPrimary,
                  ),
                ),
              ),
              PopupMenuButton<String>(
                tooltip: '选择学科',
                onSelected: (v) =>
                    setState(() => _customSubject = v == '__all__' ? null : v),
                itemBuilder: (_) => [
                  const PopupMenuItem(value: '__all__', child: Text('全科')),
                  for (final code in const [
                    'math',
                    'phy',
                    'eng',
                    'chn',
                    'chem',
                  ])
                    PopupMenuItem(
                      value: code,
                      child: Text(SubjectCatalog.labelOf(code)),
                    ),
                ],
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _customSubject != null ? t.accent : t.surfaceMuted,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _customSubject != null
                          ? t.accent
                          : t.borderHairline,
                      width: 1.0,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _customSubject != null
                            ? SubjectCatalog.labelOf(_customSubject!)
                            : '全科',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: _customSubject != null
                              ? FontWeight.w700
                              : FontWeight.w600,
                          color: _customSubject != null
                              ? Colors.white
                              : t.textPrimary,
                        ),
                      ),
                      Icon(
                        Icons.arrow_drop_down,
                        size: 16,
                        color: _customSubject != null
                            ? Colors.white
                            : t.textSecondary,
                      ),
                    ],
                  ),
                ),
              ),
              if (wide) ...[
                const SizedBox(width: 10),
                FilledButton(
                  onPressed: customPool.isEmpty
                      ? null
                      : () => notifier.startPracticeSession(
                          title:
                              '${_customSubject != null ? SubjectCatalog.labelOf(_customSubject!) : "综合"}练习',
                          kind: PracticeKind.custom,
                          inputMode: _preferredInputMode,
                          feedbackTiming: _preferredTiming,
                          questionIds: customPool,
                        ),
                  child: Text('开练 (${customPool.length} 题)'),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final cnt in const [3, 5, 10, 0])
                ChoiceChip(
                  label: Text(cnt == 0 ? '全部' : '$cnt 题'),
                  selected: _customCount == cnt,
                  onSelected: (_) => setState(() => _customCount = cnt),
                ),
            ],
          ),
          if (!wide) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: customPool.isEmpty
                    ? null
                    : () => notifier.startPracticeSession(
                        title:
                            '${_customSubject != null ? SubjectCatalog.labelOf(_customSubject!) : "综合"}练习',
                        kind: PracticeKind.custom,
                        inputMode: _preferredInputMode,
                        feedbackTiming: _preferredTiming,
                        questionIds: customPool,
                      ),
                child: Text('开练 (${customPool.length} 题)'),
              ),
            ),
          ],
        ],
      ),
    );

    final fullTrainingCard = _HubLaunchCard(
      icon: Icons.layers_outlined,
      title: '全题型综合训练 (${ws.questions.length} 题)',
      subtitle: '覆盖全部题型，按当前模式作答',
      buttonLabel: '开始训练',
      onPressed: ws.questions.isEmpty
          ? null
          : () => notifier.startPracticeSession(
              title: '全题型综合训练',
              kind: PracticeKind.exam,
              inputMode: _preferredInputMode,
              feedbackTiming: _preferredTiming,
              questionIds: ws.questions.map((q) => q.id).toList(),
            ),
    );

    final redoWrongCard = _HubLaunchCard(
      icon: Icons.replay_circle_filled_outlined,
      title: '未掌握错题专项重练 (${wrongQIds.length} 题)',
      subtitle: '连对 ${state.snapshot.preferences.masteryStreak} 次即可掌握毕业',
      buttonLabel: '重练错题',
      onPressed: wrongQIds.isEmpty
          ? null
          : () => notifier.startPracticeSession(
              title: '未掌握错题专项重练',
              kind: PracticeKind.redo,
              inputMode: _preferredInputMode,
              feedbackTiming: _preferredTiming,
              questionIds: wrongQIds,
            ),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('做题中心')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: ListView(
            padding: EdgeInsets.all(wide ? 22 : 16),
            children: [
              if (ws.questions.isEmpty) ...[
                InouSurface(
                  subtle: true,
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Icon(Icons.edit_note_outlined, color: t.accent, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '当前题库暂无题目',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13.5,
                              ),
                            ),
                            Text(
                              '先拍照录题或在题库手工添加题目',
                              style: TextStyle(
                                fontSize: 12,
                                color: t.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: () => showCaptureModal(context),
                        icon: const Icon(Icons.camera_alt_outlined, size: 15),
                        label: const Text('拍照录题'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],
              modeSelectors,
              const SizedBox(height: 14),
              customPackCard,
              const SizedBox(height: 12),
              if (wide)
                Row(
                  children: [
                    Expanded(child: fullTrainingCard),
                    const SizedBox(width: 12),
                    Expanded(child: redoWrongCard),
                  ],
                )
              else ...[
                fullTrainingCard,
                const SizedBox(height: 10),
                redoWrongCard,
              ],
              const SizedBox(height: 10),
              _HubLaunchCard(
                icon: Icons.draw_outlined,
                title: 'A4 手写稿纸专场',
                subtitle: '手写演算、作图或圈选笔迹问诺诺',
                buttonLabel: '进入稿纸',
                onPressed: ws.questions.isEmpty
                    ? null
                    : () {
                        final paperQs = ws.questions
                            .take(5)
                            .map((q) => q.id)
                            .toList();
                        notifier.startPracticeSession(
                          title: '手写稿纸练习',
                          kind: PracticeKind.exam,
                          inputMode: InputMode.paper,
                          feedbackTiming: FeedbackTiming.afterSubmit,
                          questionIds: paperQs,
                        );
                      },
              ),
              if (ws.sessions.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text(
                  '最近练习记录（点击继续或查看成绩）',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: t.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                for (final s in ws.sessions.take(5))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: InouSurface(
                      onTap: () => notifier.resumePracticeSession(s.id),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  s.title,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  '${s.questionIds.length} 题 · ${s.status == 'submitted' ? '已交卷' : '进行中'}',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: t.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          InouBadge(
                            label:
                                '${s.totalScore.toStringAsFixed(0)}/${s.maxScore.toStringAsFixed(0)}分',
                            tone: s.status == 'submitted'
                                ? InouBadgeTone.accent
                                : InouBadgeTone.warning,
                          ),
                        ],
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

class _HubLaunchCard extends StatelessWidget {
  const _HubLaunchCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.buttonLabel,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String buttonLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final t = context.inou;
    return InouSurface(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: t.accentSoft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: t.accent, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 12, color: t.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          FilledButton(onPressed: onPressed, child: Text(buttonLabel)),
        ],
      ),
    );
  }
}
