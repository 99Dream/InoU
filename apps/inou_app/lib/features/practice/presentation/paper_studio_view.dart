import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inou_ai/inou_ai.dart';
import 'package:inou_domain/inou_domain.dart';
import 'package:inou_ink/inou_ink.dart';
import 'package:inou_ink/render.dart';
import 'package:inou_ui_kit/inou_ui_kit.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/state/app_store.dart';

/// Tablet A4/B5 Digital Paper Studio supporting per-question interactive
/// handwriting pads (`InouInkCanvas`), expandable solve-box height without
/// obscuring UI controls, lasso-to-NuoNuo PNG export, collapsible scratchpad,
/// and AI Red-Pen grading + 1-tap verdict override.
class PaperStudioView extends ConsumerStatefulWidget {
  const PaperStudioView({
    super.key,
    required this.session,
    required this.questions,
    required this.attempts,
    required this.onSubmittedSession,
  });

  final PracticeSession session;
  final List<Question> questions;
  final Map<String, AttemptRecord> attempts;
  final VoidCallback onSubmittedSession;

  @override
  ConsumerState<PaperStudioView> createState() => _PaperStudioViewState();
}

class _PaperStudioViewState extends ConsumerState<PaperStudioView> {
  final Map<String, InkController> _inkByQuestion = {};
  final Map<String, double> _boxHeights = {};
  final Map<String, TextEditingController> _finalAnswerCtrls = {};
  final InkController _scratchInk = InkController(
    initialPage: const InkPageData(pageW: 320, pageH: 520),
    backgroundKind: PaperBackgroundKind.grid,
  );

  InkToolKind _activeTool = InkToolKind.pen;
  int _colorArgb = 0xFF1E293B;
  PaperBackgroundKind _backgroundKind = PaperBackgroundKind.dotted;
  bool _fingerDrawEnabled = true;
  bool _scratchpadOpen = false;
  bool _submitting = false;

  String? _activeQuestionId;
  Rect? _lassoLogicalRect;
  String? _lassoQuestionId;

  @override
  void initState() {
    super.initState();
    final ws = ref.read(appStoreProvider).activeWorkspace;
    for (final q in widget.questions) {
      final h = q.kind == QuestionKind.solve || q.kind == QuestionKind.draw
          ? 200.0
          : 136.0;
      _boxHeights[q.id] = h;
      _finalAnswerCtrls[q.id] = TextEditingController();
      final saved = ws.inkPagesByQuestionId[q.id];
      final ctrl = InkController(
        initialPage: saved ?? InkPageData(pageW: 604, pageH: h),
        backgroundKind: _backgroundKind,
        fingerDrawEnabled: _fingerDrawEnabled,
      );
      _inkByQuestion[q.id] = ctrl;
    }
    _activeQuestionId = widget.questions.firstOrNull?.id;
  }

  @override
  void dispose() {
    for (final ctrl in _inkByQuestion.values) {
      ctrl.dispose();
    }
    _scratchInk.dispose();
    for (final c in _finalAnswerCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _syncToolbarToAll() {
    for (final ctrl in _inkByQuestion.values) {
      ctrl.setTool(_activeTool);
      ctrl.setColorArgb(_colorArgb);
      ctrl.setBackgroundKind(_backgroundKind);
      ctrl.setFingerDrawEnabled(_fingerDrawEnabled);
    }
  }

  InkController? get _focusedInk =>
      _inkByQuestion[_activeQuestionId] ?? _inkByQuestion.values.firstOrNull;

  void _expandBox(Question q) {
    final ctrl = _inkByQuestion[q.id];
    final nextH = (_boxHeights[q.id] ?? 150) + 110;
    setState(() {
      _boxHeights[q.id] = nextH;
      if (ctrl != null) {
        ctrl.loadPage(
          InkPageData(
            pageW: ctrl.page.pageW,
            pageH: nextH,
            strokes: ctrl.page.strokes,
          ),
          clearHistory: false,
        );
      }
    });
  }

  Future<void> _lassoAskTutor({bool openBlackboard = false}) async {
    final qId = _lassoQuestionId ?? _activeQuestionId;
    final ctrl = _inkByQuestion[qId];
    final notifier = ref.read(appStoreProvider.notifier);
    final exporter = ref.read(inkSnapshotExporterProvider);
    final png = ctrl == null
        ? null
        : await exporter(
            ctrl.page,
            cropRect: _lassoLogicalRect,
            pixelRatio: 1.8,
          );
    ctrl?.clearLasso();
    setState(() {
      _lassoLogicalRect = null;
      _lassoQuestionId = null;
    });
    final targetQId = qId ?? widget.questions.firstOrNull?.id;
    if (openBlackboard) {
      await notifier.openBlackboard(
        questionId: targetQId,
        hintLevel: HintLevel.l1Concept,
        lassoBytes: png,
      );
    } else {
      notifier.openCopilot(
        questionId: targetQId,
        hintLevel: HintLevel.l1Concept,
        lassoBytes: png,
      );
    }
  }

  Future<void> _gradeAllOnPaper() async {
    setState(() => _submitting = true);
    final notifier = ref.read(appStoreProvider.notifier);
    final exporter = ref.read(inkSnapshotExporterProvider);

    try {
      for (final q in widget.questions) {
        final ctrl = _inkByQuestion[q.id];
        final page = ctrl?.page;
        if (page != null) {
          await notifier.saveInkPage(q.id, page);
        }
        final png = (page != null && page.strokes.isNotEmpty)
            ? await exporter(page, pixelRatio: 1.5)
            : null;
        final strokeCount = page?.strokes.length ?? 0;

        final typed = _finalAnswerCtrls[q.id]?.text.trim() ?? '';
        final StudentResponse resp = switch (q.kind) {
          QuestionKind.choice => ChoiceResponse(
            questionId: q.id,
            inputMode: InputMode.paper,
            selectedIds: typed.isNotEmpty ? [typed.toUpperCase()] : const [],
            inkRegionId: strokeCount > 0 ? q.id : null,
          ),
          QuestionKind.fill => FillResponse(
            questionId: q.id,
            inputMode: InputMode.paper,
            textEntries: typed.isNotEmpty ? {'s1': typed} : const {},
            inkRegionId: strokeCount > 0 ? q.id : null,
          ),
          QuestionKind.draw => DrawResponse(
            questionId: q.id,
            inputMode: InputMode.paper,
            inkRegionId: strokeCount > 0 ? q.id : null,
            note: typed.isNotEmpty ? typed : '稿纸手绘 ($strokeCount 笔)',
          ),
          QuestionKind.response => TextResponse(
            questionId: q.id,
            inputMode: InputMode.paper,
            parts: typed.isNotEmpty ? {'p1': typed} : const {},
            inkRegionId: strokeCount > 0 ? q.id : null,
          ),
          _ => SolveResponse(
            questionId: q.id,
            inputMode: InputMode.paper,
            steps: strokeCount > 0 ? ['稿纸手写过程（$strokeCount 笔）'] : const [],
            finalAnswer: typed.isNotEmpty ? typed : null,
            inkRegionId: strokeCount > 0 ? q.id : null,
          ),
        };

        await notifier.submitQuestionResponse(
          sessionId: widget.session.id,
          question: q,
          response: resp,
          attachedPngs: [?png],
        );
      }

      await notifier.finalizePracticeSession(widget.session.id);
      if (mounted) widget.onSubmittedSession();
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.inou;
    final notifier = ref.read(appStoreProvider.notifier);

    return Column(
      children: [
        // Floating Studio Ink Toolbar
        Container(
          color: t.surface,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _ToolPill(
                        icon: Icons.edit_outlined,
                        label: '钢笔',
                        selected: _activeTool == InkToolKind.pen,
                        onTap: () => setState(() {
                          _activeTool = InkToolKind.pen;
                          _syncToolbarToAll();
                        }),
                      ),
                      const SizedBox(width: 6),
                      _ToolPill(
                        icon: Icons.highlight_outlined,
                        label: '荧光笔',
                        selected: _activeTool == InkToolKind.highlighter,
                        onTap: () => setState(() {
                          _activeTool = InkToolKind.highlighter;
                          _syncToolbarToAll();
                        }),
                      ),
                      const SizedBox(width: 6),
                      _ToolPill(
                        icon: Icons.cleaning_services_outlined,
                        label: '橡皮',
                        selected: _activeTool == InkToolKind.eraser,
                        onTap: () => setState(() {
                          _activeTool = InkToolKind.eraser;
                          _syncToolbarToAll();
                        }),
                      ),
                      const SizedBox(width: 6),
                      _ToolPill(
                        icon: Icons.gesture_outlined,
                        label: '套索问AI',
                        selected: _activeTool == InkToolKind.lasso,
                        onTap: () => setState(() {
                          _activeTool = InkToolKind.lasso;
                          _syncToolbarToAll();
                        }),
                      ),
                      const SizedBox(width: 10),
                      for (final hex in const [
                        0xFF1E293B,
                        0xFF3F6AF5,
                        0xFFE11D48,
                        0xFFFACC15,
                      ])
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: GestureDetector(
                            onTap: () => setState(() {
                              _colorArgb = hex;
                              _syncToolbarToAll();
                            }),
                            child: Container(
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(
                                color: Color(hex),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: _colorArgb == hex
                                      ? t.accent
                                      : t.borderHairline,
                                  width: _colorArgb == hex ? 2.5 : 1,
                                ),
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(width: 6),
                      IconButton(
                        tooltip: '撤销',
                        onPressed: _focusedInk?.canUndo == true
                            ? () => setState(() => _focusedInk?.undo())
                            : null,
                        icon: const Icon(Icons.undo, size: 19),
                      ),
                      IconButton(
                        tooltip: '重做',
                        onPressed: _focusedInk?.canRedo == true
                            ? () => setState(() => _focusedInk?.redo())
                            : null,
                        icon: const Icon(Icons.redo, size: 19),
                      ),
                      PopupMenuButton<PaperBackgroundKind>(
                        tooltip: '切换稿纸底纹',
                        onSelected: (k) => setState(() {
                          _backgroundKind = k;
                          _syncToolbarToAll();
                        }),
                        itemBuilder: (_) => [
                          for (final kind in PaperBackgroundKind.values)
                            PopupMenuItem(value: kind, child: Text(kind.label)),
                        ],
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Chip(
                            backgroundColor: t.surface,
                            side: BorderSide(color: t.borderHairline),
                            label: Text(
                              _backgroundKind.label,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: t.textPrimary,
                              ),
                            ),
                            avatar: Icon(
                              Icons.grid_on,
                              size: 14,
                              color: t.accent,
                            ),
                          ),
                        ),
                      ),
                      FilterChip(
                        label: const Text('防误触只用笔'),
                        selected: !_fingerDrawEnabled,
                        onSelected: (penOnly) => setState(() {
                          _fingerDrawEnabled = !penOnly;
                          _syncToolbarToAll();
                        }),
                      ),
                      const SizedBox(width: 6),
                      FilterChip(
                        label: const Text('手写草稿栏'),
                        selected: _scratchpadOpen,
                        onSelected: (on) =>
                            setState(() => _scratchpadOpen = on),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: _submitting ? null : _gradeAllOnPaper,
                icon: _submitting
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.fact_check_outlined, size: 16),
                label: Text(_submitting ? '批改中…' : '交卷批改'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),

        // Lasso Floating Action Pill
        if (_lassoLogicalRect != null)
          Container(
            width: double.infinity,
            color: t.accentSoft,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Icon(Icons.auto_awesome, size: 16, color: t.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '已圈选手写区域，可导出截图交给诺诺学姐诊断！',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: t.accent,
                    ),
                  ),
                ),
                FilledButton(
                  onPressed: _lassoAskTutor,
                  child: const Text('圈选问诺诺'),
                ),
                const SizedBox(width: 8),
                FilledButton.tonal(
                  onPressed: () => _lassoAskTutor(openBlackboard: true),
                  child: const Text('圈选上黑板'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () {
                    _inkByQuestion[_lassoQuestionId]?.deleteLassoSelection();
                    setState(() {
                      _lassoLogicalRect = null;
                      _lassoQuestionId = null;
                    });
                  },
                  child: const Text('删笔迹'),
                ),
              ],
            ),
          ),

        // Paper Sheet + Optional Collapsible Side Scratchpad
        Expanded(
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Center(
                    child: Container(
                      width: 680,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: t.borderHairline),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x0B000000),
                            blurRadius: 16,
                            offset: Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                widget.session.title,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                              const Spacer(),
                              const InouBadge(label: 'A4 数字稿纸模式'),
                            ],
                          ),
                          const SizedBox(height: 16),
                          for (var i = 0; i < widget.questions.length; i++)
                            _buildQuestionSheetBlock(
                              context,
                              widget.questions[i],
                              i,
                              widget.attempts[widget.questions[i].id],
                              notifier,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (_scratchpadOpen) ...[
                const VerticalDivider(width: 1),
                SizedBox(
                  width: 300,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(10),
                        child: Row(
                          children: [
                            const Text(
                              '侧边草稿演算区',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            const Spacer(),
                            TextButton(
                              onPressed: _scratchInk.clearAll,
                              child: const Text('清空'),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      Expanded(
                        child: Container(
                          color: Colors.white,
                          child: InouInkCanvas(controller: _scratchInk),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildQuestionSheetBlock(
    BuildContext context,
    Question q,
    int index,
    AttemptRecord? attempt,
    AppStoreNotifier notifier,
  ) {
    final t = context.inou;
    final boxH = _boxHeights[q.id] ?? 150;
    final inkCtrl = _inkByQuestion[q.id]!;

    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: attempt != null
              ? (attempt.verdict == Verdict.correct ? t.success : t.redPen)
              : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${index + 1}. ${q.header.title} (${q.displayKindLabel} · ${q.maxScore.toStringAsFixed(0)}分)',
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () => _expandBox(q),
                icon: const Icon(Icons.unfold_more, size: 15),
                label: const Text('扩高作答区', style: TextStyle(fontSize: 11.5)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ContentBlockRenderer(
            blocks: q.prompt,
            textStyle: const TextStyle(
              fontSize: 14,
              color: Color(0xFF1E293B),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 10),
          // Dedicated non-obscuring handwritten canvas for this solve region
          Listener(
            onPointerDown: (_) => _activeQuestionId = q.id,
            child: Container(
              width: 604,
              height: boxH,
              decoration: BoxDecoration(
                color: const Color(0xFFFCFDFF),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              clipBehavior: Clip.antiAlias,
              child: InouInkCanvas(
                controller: inkCtrl,
                paintBackground: true,
                regionResolver: (_) => q.id,
                onLassoCompleted: (rect, _) {
                  setState(() {
                    _lassoLogicalRect = rect;
                    _lassoQuestionId = q.id;
                  });
                },
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 36,
            child: TextField(
              controller: _finalAnswerCtrls[q.id],
              style: const TextStyle(fontSize: 12.5),
              decoration: const InputDecoration(
                hintText: '可选：补充终值/选项号加快判分（手写区域留给直接作答）',
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
              ),
            ),
          ),
          if (attempt != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: attempt.verdict == Verdict.correct
                    ? t.successSoft
                    : t.dangerSoft,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color:
                      (attempt.verdict == Verdict.correct
                              ? t.success
                              : t.redPen)
                          .withValues(alpha: 0.4),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      InouBadge(
                        label:
                            '红笔批注：${attempt.verdict.label} (${attempt.score}/${attempt.maxScore}分)',
                        tone: attempt.verdict == Verdict.correct
                            ? InouBadgeTone.success
                            : InouBadgeTone.danger,
                      ),
                      for (final v in const [
                        Verdict.correct,
                        Verdict.partial,
                        Verdict.wrong,
                      ])
                        ChoiceChip(
                          label: Text(
                            v.label,
                            style: const TextStyle(fontSize: 11),
                          ),
                          selected: attempt.verdict == v,
                          onSelected: (_) => notifier.overrideAttemptVerdict(
                            attemptId: attempt.id,
                            newVerdict: v,
                          ),
                        ),
                    ],
                  ),
                  if (attempt.feedbackSummary != null &&
                      attempt.feedbackSummary!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      attempt.feedbackSummary!,
                      style: TextStyle(fontSize: 12, color: t.textPrimary),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ToolPill extends StatelessWidget {
  const _ToolPill({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.inou;
    return ChoiceChip(
      avatar: Icon(
        icon,
        size: 16,
        color: selected ? t.accent : t.textSecondary,
      ),
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
    );
  }
}
