import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inou_ai/inou_ai.dart';
import 'package:inou_domain/inou_domain.dart';
import 'package:inou_ink/inou_ink.dart';
import 'package:inou_ink/render.dart';
import 'package:inou_ui_kit/inou_ui_kit.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/platform/display_cutout_helper.dart';
import '../../../core/platform/platform_media_service.dart';
import '../../../core/state/app_store.dart';

/// Cohesive, warm pastel chalkboard palette designed to feel calm and
/// child-friendly instead of mixing harsh neon accents.
abstract final class _BlackboardPalette {
  static const Color outerBackdrop = Color(0xFF13221C);
  static const Color boardTop = Color(0xFF233D34);
  static const Color boardBottom = Color(0xFF1B312A);
  static const Color woodFrame = Color(0xFF9C7450);

  static const Color topStripBg = Color(0xFF162A23);
  static const Color chromeBg = Color(0xEB152822);
  static const Color overlayCardBg = Color(0xF5172B24);
  static const Color sideNoteBg = Color(0xFF29433A);
  static const Color calloutBg = Color(0x280F1E18);

  static const Color hairline = Color(0x26FFFFFF);
  static const Color softBorder = Color(0x36FFFFFF);
  static const Color activeBorder = Color(0x55FBF8F1);

  static const Color primaryBtn = Color(0xFF3B9B7E);

  static const Color chalkPrimary = Color(0xFFFBF8F1);
  static const Color chalkMuted = Color(0xFFC7D8CE);
  static const Color accentWarm = Color(0xFFFFCFA3);
  static const Color accentWarmSoft = Color(0x22FFCFA3);
  static const Color underlineStroke = Color(0x88FFCFA3);
  static const Color underlineText = Color(0xFFFFE7CC);
  static const Color accentMint = Color(0xFFAEE2C2);
  static const Color accentMintSoft = Color(0x24AEE2C2);
  static const Color accentBlush = Color(0xFFF6B4AE);
  static const Color accentBlushSoft = Color(0x24F6B4AE);

  static const Color teacherCardigan = Color(0xFF3B9B7E);
  static const Color teacherSleeve = Color(0xFF2E7D65);
  static const Color teacherBow = Color(0xFFF29D94);
  static const Color teacherPointer = Color(0xFFD4A373);
}

/// Full-screen / immersive AI Blackboard Classroom where NuoNuo writes
/// step-by-step colored chalk derivations, draws synchronized diagrams,
/// handles circle-to-ask screen regions, and grades student chalk strokes.
class BlackboardClassroomOverlay extends ConsumerStatefulWidget {
  const BlackboardClassroomOverlay({super.key});

  @override
  ConsumerState<BlackboardClassroomOverlay> createState() =>
      _BlackboardClassroomOverlayState();
}

class _BlackboardClassroomOverlayState
    extends ConsumerState<BlackboardClassroomOverlay>
    with WidgetsBindingObserver {
  final ScrollController _stepsScrollCtrl = ScrollController();
  final TextEditingController _quickAskCtrl = TextEditingController();
  final TextEditingController _circleAskCtrl = TextEditingController();
  final ValueNotifier<double> _chalkWritingPhase = ValueNotifier<double>(0.0);
  bool _disposed = false;

  void _setChalkWritingPhase(double value) {
    if (_disposed || !mounted || _chalkWritingPhase.value == value) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!_disposed && mounted && _chalkWritingPhase.value != value) {
          _chalkWritingPhase.value = value;
        }
      });
      return;
    }
    _chalkWritingPhase.value = value;
  }

  final GlobalKey _boardStackKey = GlobalKey();
  final GlobalKey _diagramKey = GlobalKey();
  final Map<String, GlobalKey> _stepKeys = {};

  late final InkController _studentInkCtrl = InkController(
    initialPage: const InkPageData(pageW: 900, pageH: 560),
    backgroundKind: PaperBackgroundKind.blank,
  )..setColorArgb(ChalkColor.yellow.argb);

  int _lastSyncedRevision = 0;
  String? _loadedInkLessonId;
  bool _syncingFromLesson = false;
  bool _stemPinnedExpanded = true;
  bool _autoFollowBoard = true;
  String _lastBoardFingerprint = '';
  final Stopwatch _autoScrollSw = Stopwatch();
  int _lastAutoScrollMs = -1000;
  int _teacherActionTick = 0;
  bool _phoneAskOpen = false;
  bool _phoneCaptionDismissed = false;
  String? _selectedStepId;
  EdgeInsets _nativeCutout = EdgeInsets.zero;

  // Circle-to-ask transient gesture & popup state
  final List<Offset> _circlePoints = <Offset>[];
  Rect? _circlePendingRect;
  String? _circleHitStepId;
  String _circleHitLabel = '';
  bool _circleHitIsDiagram = false;
  Uint8List? _circleSnapshotPng;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _autoScrollSw.start();
    _studentInkCtrl.addListener(_onStudentInkChanged);
    unawaited(
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky),
    );
    unawaited(
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]),
    );
    unawaited(_loadNativeCutout());
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    unawaited(_loadNativeCutout());
  }

  Future<void> _loadNativeCutout() async {
    try {
      final insets = await ref
          .read(platformMediaServiceProvider)
          .getDisplayCutoutInsets();
      if (!mounted || _disposed) return;
      if (insets != _nativeCutout) {
        setState(() => _nativeCutout = insets);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _autoScrollSw.stop();
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    unawaited(SystemChrome.setPreferredOrientations(const []));
    _studentInkCtrl.removeListener(_onStudentInkChanged);
    _studentInkCtrl.dispose();
    _stepsScrollCtrl.dispose();
    _quickAskCtrl.dispose();
    _circleAskCtrl.dispose();
    _chalkWritingPhase.dispose();
    super.dispose();
  }

  void _onStudentInkChanged() {
    if (_syncingFromLesson) return;
    final rev = _studentInkCtrl.committedRevision;
    if (rev != _lastSyncedRevision) {
      _lastSyncedRevision = rev;
      ref
          .read(appStoreProvider.notifier)
          .saveBlackboardStudentInk(_studentInkCtrl.page);
    }
    if (mounted) setState(() {});
  }

  void _syncInkFromLesson(BlackboardLessonRecord? lesson) {
    if (lesson == null) return;
    if (_loadedInkLessonId == lesson.id) return;
    _loadedInkLessonId = lesson.id;
    _syncingFromLesson = true;
    try {
      if (lesson.studentInkData != null) {
        final page = InkPageData.fromJson(lesson.studentInkData!);
        _studentInkCtrl.loadPage(page, clearHistory: true);
      } else {
        _studentInkCtrl.loadPage(
          const InkPageData(pageW: 900, pageH: 560),
          clearHistory: true,
        );
      }
      _lastSyncedRevision = _studentInkCtrl.committedRevision;
    } finally {
      _syncingFromLesson = false;
    }
  }

  GlobalKey _keyForStep(String stepId) =>
      _stepKeys.putIfAbsent(stepId, GlobalKey.new);

  String _computeBoardFingerprint(
    BlackboardSolutionTrack? track,
    AppState state,
  ) {
    if (track == null) return '';
    final cur = track.currentStep;
    final lineRunes =
        cur?.lines.fold<int>(
          0,
          (sum, l) => sum + l.text.length + (l.latex?.length ?? 0),
        ) ??
        0;
    final noteCount = cur?.sideNotes.length ?? 0;
    final noteRunes =
        cur?.sideNotes.fold<int>(
          0,
          (sum, n) => sum + n.spokenReply.length + n.chalkLines.length,
        ) ??
        0;
    final cpState =
        '${cur?.checkpoint?.answeredSelection}:${cur?.checkpoint?.feedbackVerdict}:${cur?.checkpoint?.skipped}:${cur?.checkpoint?.studentReply}';
    return '${track.id}:${track.revealedCount}:${cur?.id}:${cur?.lines.length}:$lineRunes:$noteCount:$noteRunes:$cpState:${cur?.studentFeedbackTag}:${cur?.teacherReaction}:${track.takeaway}:${state.blackboardStepStreaming}';
  }

  void _followBoardToBottom({bool force = false, bool animate = true}) {
    if (_disposed || !mounted) return;
    if (!force && !_autoFollowBoard) return;
    final nowMs = _autoScrollSw.elapsedMilliseconds;
    if (!force && nowMs - _lastAutoScrollMs < 75) return;
    _lastAutoScrollMs = nowMs;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed || !mounted || !_stepsScrollCtrl.hasClients) return;
      final pos = _stepsScrollCtrl.position;
      final target = pos.maxScrollExtent;
      if ((target - pos.pixels).abs() < 2.0) return;
      if (animate) {
        _stepsScrollCtrl.animateTo(
          target,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      } else {
        _stepsScrollCtrl.jumpTo(target);
      }
    });
  }

  void _syncPenModeToInkController(BlackboardPenMode mode) {
    if (mode == BlackboardPenMode.eraser) {
      _studentInkCtrl.setTool(InkToolKind.eraser);
    } else if (mode == BlackboardPenMode.studentChalk) {
      _studentInkCtrl.setTool(InkToolKind.pen);
    }
  }

  Future<void> _finalizeCircleGesture(
    BlackboardSolutionTrack? track,
  ) async {
    if (_circlePoints.length < 2) {
      setState(_circlePoints.clear);
      return;
    }
    var minX = _circlePoints.first.dx;
    var maxX = _circlePoints.first.dx;
    var minY = _circlePoints.first.dy;
    var maxY = _circlePoints.first.dy;
    for (final p in _circlePoints.skip(1)) {
      minX = math.min(minX, p.dx);
      maxX = math.max(maxX, p.dx);
      minY = math.min(minY, p.dy);
      maxY = math.max(maxY, p.dy);
    }
    final rawRect = Rect.fromLTRB(minX, minY, maxX, maxY).inflate(8);
    if (rawRect.width < 12 && rawRect.height < 12) {
      setState(_circlePoints.clear);
      return;
    }

    // Hit-test diagram & visible step cards in _boardStackKey coordinates
    final boardBox =
        _boardStackKey.currentContext?.findRenderObject() as RenderBox?;
    String? hitStepId;
    var hitDiagram = false;
    var hitLabel = '黑板当前区域';

    if (boardBox != null) {
      final diagBox =
          _diagramKey.currentContext?.findRenderObject() as RenderBox?;
      if (diagBox != null) {
        final diagTopLeft = diagBox.localToGlobal(
          Offset.zero,
          ancestor: boardBox,
        );
        final diagRect = diagTopLeft & diagBox.size;
        if (diagRect.overlaps(rawRect) ||
            diagRect.contains(rawRect.center)) {
          hitDiagram = true;
          hitLabel = '动态示意图区';
        }
      }

      if (track != null) {
        var bestDist = double.infinity;
        for (final step in track.visibleSteps) {
          final stepBox =
              _stepKeys[step.id]?.currentContext?.findRenderObject()
                  as RenderBox?;
          if (stepBox == null) continue;
          final tl = stepBox.localToGlobal(Offset.zero, ancestor: boardBox);
          final rect = tl & stepBox.size;
          if (rect.overlaps(rawRect) || rect.contains(rawRect.center)) {
            hitStepId = step.id;
            hitLabel = '第 ${step.stepNumber} 步 · ${step.title}';
            break;
          }
          final d = (rect.center - rawRect.center).distance;
          if (d < bestDist) {
            bestDist = d;
            hitStepId = step.id;
            hitLabel = '第 ${step.stepNumber} 步 · ${step.title}';
          }
        }
      }
    }

    hitStepId ??= track?.currentStep?.id;
    if (hitDiagram && hitStepId == null && track != null) {
      hitStepId = track.currentStep?.id;
    } else if (hitDiagram && hitStepId != null) {
      hitLabel = '$hitLabel（含示意图）';
    }

    // Export composite ink snapshot via injectable provider (safe in FakeAsync tests)
    final exporter = ref.read(inkSnapshotExporterProvider);
    final circleInk = InkStroke(
      id: '_circle_ask',
      tool: InkToolKind.pen,
      colorArgb: ChalkColor.pink.argb,
      width: 3.0,
      points: _circlePoints
          .map(
            (p) => InkPoint(
              x: p.dx,
              y: p.dy,
              pressure: 0.7,
              tMs: 0,
            ),
          )
          .toList(growable: false),
    );
    final snapPage = _studentInkCtrl.page.addStroke(circleInk);
    final png = await exporter(
      snapPage,
      cropRect: rawRect.inflate(24),
      pixelRatio: 1.5,
    );

    if (!mounted) return;
    setState(() {
      _circlePendingRect = rawRect;
      _circleHitStepId = hitStepId;
      _circleHitLabel = hitLabel;
      _circleHitIsDiagram = hitDiagram;
      _circleSnapshotPng = png;
      _selectedStepId = hitStepId;
    });
  }

  void _clearCirclePopup() {
    setState(() {
      _circlePoints.clear();
      _circlePendingRect = null;
      _circleHitStepId = null;
      _circleHitLabel = '';
      _circleHitIsDiagram = false;
      _circleSnapshotPng = null;
      _circleAskCtrl.clear();
    });
  }

  Future<void> _submitCircleQuestion(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final targetId = _circleHitStepId ?? _selectedStepId;
    final png = _circleSnapshotPng;
    final strokeCount = _studentInkCtrl.page.strokes.length;
    final isAlt = trimmed.contains('解法二') || trimmed.contains('换种解法');
    _clearCirclePopup();

    await ref
        .read(appStoreProvider.notifier)
        .askBlackboardQuestion(
          questionText: trimmed,
          targetStepId: targetId,
          compositePng: png,
          studentStrokeCount: strokeCount,
          requestAlternateMethod: isAlt,
        );
    if (mounted) {
      setState(() {
        _autoFollowBoard = true;
        _teacherActionTick++;
      });
      ref
          .read(appStoreProvider.notifier)
          .setBlackboardPenMode(BlackboardPenMode.none);
      _followBoardToBottom(force: true);
    }
  }

  Future<void> _submitQuickQuestion(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    _quickAskCtrl.clear();
    if (mounted) {
      setState(() {
        if (_phoneAskOpen) {
          _phoneAskOpen = false;
          _phoneCaptionDismissed = false;
        }
        _autoFollowBoard = true;
        _teacherActionTick++;
      });
    }
    await ref
        .read(appStoreProvider.notifier)
        .askBlackboardQuestion(
          questionText: trimmed,
          targetStepId: _selectedStepId,
          studentStrokeCount: _studentInkCtrl.page.strokes.length,
        );
    if (mounted) _followBoardToBottom(force: true);
  }

  Future<void> _gradeStudentChalk() async {
    final strokes = _studentInkCtrl.page.strokes;
    if (strokes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先用「学生粉笔」在黑板上写下算式或画辅助线哦～')),
      );
      return;
    }
    final exporter = ref.read(inkSnapshotExporterProvider);
    final png = await exporter(_studentInkCtrl.page, pixelRatio: 1.5);
    if (!mounted) return;
    await ref
        .read(appStoreProvider.notifier)
        .askBlackboardQuestion(
          questionText: '请帮我批改一下我在黑板上写的步骤或画的辅助线对不对？',
          targetStepId: _selectedStepId,
          compositePng: png,
          studentStrokeCount: strokes.length,
        );
    if (mounted) {
      setState(() {
        _autoFollowBoard = true;
        _teacherActionTick++;
      });
      ref
          .read(appStoreProvider.notifier)
          .setBlackboardPenMode(BlackboardPenMode.none);
      _followBoardToBottom(force: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.inou;
    final state = ref.watch(appStoreProvider);
    final notifier = ref.read(appStoreProvider.notifier);
    final lesson = state.activeBlackboardLesson;
    _syncInkFromLesson(lesson);

    final track = lesson?.activeTrack;
    final boundQ = state.findQuestionById(state.copilotQuestionId);
    final hintLevel = state.copilotHintLevel == HintLevel.none
        ? HintLevel.l1Concept
        : state.copilotHintLevel;
    final penMode = state.blackboardPenMode;

    final currentStep = track?.currentStep;
    final currentUnresolvedCheckpoint =
        currentStep?.checkpoint != null && !currentStep!.checkpoint!.isResolved;
    final latestSideNote =
        currentStep != null && currentStep.sideNotes.isNotEmpty
        ? currentStep.sideNotes.last
        : null;
    final hasInlineFeedbackOnBoard =
        latestSideNote != null ||
        (currentStep?.teacherReaction?.trim().isNotEmpty ?? false) ||
        (currentStep?.checkpoint?.teacherFeedback?.trim().isNotEmpty ?? false);
    final spokenBubbleText =
        latestSideNote?.spokenReply ??
        currentStep?.teacherReaction ??
        currentStep?.checkpoint?.teacherFeedback ??
        currentStep?.spokenText ??
        '诺诺正在准备黑板板书，稍等一下下～';

    final boardFingerprint = _computeBoardFingerprint(track, state);
    if (boardFingerprint != _lastBoardFingerprint) {
      _lastBoardFingerprint = boardFingerprint;
      if (boardFingerprint.isNotEmpty) {
        _followBoardToBottom();
      }
    }

    final screenSize = MediaQuery.sizeOf(context);
    final isPortraitScreen = screenSize.height > screenSize.width;
    final cutoutPad = DisplayCutoutInsets.resolve(
      context,
      nativeCutout: _nativeCutout,
      immersiveLandscape: !isPortraitScreen,
    );

    return Material(
      color: _BlackboardPalette.outerBackdrop,
      child: Padding(
        padding: cutoutPad,
        child: MediaQuery.removePadding(
          context: context,
          removeLeft: true,
          removeTop: true,
          removeRight: true,
          removeBottom: true,
          child: LayoutBuilder(
          builder: (context, outerBox) {
            final needsPortraitRotate = outerBox.maxHeight > outerBox.maxWidth;
            final landscapeW = needsPortraitRotate
                ? outerBox.maxHeight
                : outerBox.maxWidth;
            final landscapeH = needsPortraitRotate
                ? outerBox.maxWidth
                : outerBox.maxHeight;
            final isPhoneLandscape = landscapeH < 500 || landscapeW < 900;
            final leftQuestionWidth = isPhoneLandscape
                ? (landscapeW * 0.29).clamp(180.0, 236.0)
                : (landscapeW * 0.24).clamp(220.0, 285.0);
            final teacherColWidth = (landscapeW * 0.22).clamp(216.0, 256.0);
            final isTightHeight = landscapeH < 460;

            final classroomShell = SizedBox.expand(
              child: Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      _BlackboardPalette.boardTop,
                      _BlackboardPalette.boardBottom,
                    ],
                  ),
                  border: Border.all(
                    color: _BlackboardPalette.woodFrame,
                    width: isTightHeight ? 3 : 5,
                  ),
                ),
                child: Column(
                  children: [
                    if (state.blackboardBusy || state.blackboardStepStreaming)
                      const LinearProgressIndicator(
                        minHeight: 2,
                        backgroundColor: _BlackboardPalette.topStripBg,
                        color: _BlackboardPalette.primaryBtn,
                      ),
                    _buildChalkboardTopStrip(
                      t,
                      state,
                      notifier,
                      lesson,
                      boundQ,
                      hintLevel,
                      isPhoneLandscape: isPhoneLandscape,
                    ),
                    Expanded(
                      child: Row(
                        children: [
                          if (boundQ != null)
                            _BlackboardPinnedQuestionDock(
                              question: boundQ,
                              expanded: _stemPinnedExpanded,
                              isPhoneLandscape: isPhoneLandscape,
                              expandedWidth: leftQuestionWidth,
                              onToggleExpand: () => setState(
                                () => _stemPinnedExpanded =
                                    !_stemPinnedExpanded,
                              ),
                            ),
                          // Main Blackboard Writing & Diagram Area
                          Expanded(
                            child: Stack(
                              key: _boardStackKey,
                              children: [
                                _buildChalkBoardBody(
                                  context,
                                  state,
                                  notifier,
                                  track,
                                  penMode,
                                  bottomClearance:
                                      (isPhoneLandscape ? 58.0 : 72.0) +
                                      MediaQuery.viewInsetsOf(context).bottom,
                                ),
                                // Student freehand chalk canvas
                                if (penMode ==
                                        BlackboardPenMode.studentChalk ||
                                    penMode == BlackboardPenMode.eraser ||
                                    _studentInkCtrl.page.strokes.isNotEmpty)
                                  Positioned.fill(
                                    child: IgnorePointer(
                                      ignoring:
                                          penMode !=
                                              BlackboardPenMode
                                                  .studentChalk &&
                                          penMode != BlackboardPenMode.eraser,
                                      child: LayoutBuilder(
                                        builder: (context, box) {
                                          final scale = math.min(
                                            box.maxWidth /
                                                _studentInkCtrl.page.pageW,
                                            box.maxHeight /
                                                _studentInkCtrl.page.pageH,
                                          );
                                          return InouInkCanvas(
                                            controller: _studentInkCtrl,
                                            scale: scale <= 0 ? 1.0 : scale,
                                            darkSurface: true,
                                            paintBackground: false,
                                            readOnly:
                                                penMode !=
                                                    BlackboardPenMode
                                                        .studentChalk &&
                                                penMode !=
                                                    BlackboardPenMode.eraser,
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                // Circle-to-Ask pointer overlay
                                if (penMode == BlackboardPenMode.circleAsk)
                                  Positioned.fill(
                                    child: Listener(
                                      behavior: HitTestBehavior.opaque,
                                      onPointerDown: (e) {
                                        setState(() {
                                          _circlePendingRect = null;
                                          _circlePoints
                                            ..clear()
                                            ..add(e.localPosition);
                                        });
                                      },
                                      onPointerMove: (e) {
                                        setState(() {
                                          _circlePoints.add(e.localPosition);
                                        });
                                      },
                                      onPointerUp: (_) =>
                                          _finalizeCircleGesture(track),
                                      onPointerCancel: (_) =>
                                          setState(_circlePoints.clear),
                                      child: CustomPaint(
                                        painter: _CircleGesturePainter(
                                          points: _circlePoints,
                                          pendingRect: _circlePendingRect,
                                        ),
                                        child: _circlePoints.isEmpty &&
                                                _circlePendingRect == null
                                            ? Align(
                                                alignment:
                                                    Alignment.topCenter,
                                                child: Container(
                                                  margin: const EdgeInsets.only(
                                                    top: 8,
                                                  ),
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 12,
                                                        vertical: 5,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color:
                                                        _BlackboardPalette
                                                            .chromeBg,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          999,
                                                        ),
                                                    border: Border.all(
                                                      color: _BlackboardPalette
                                                          .accentWarm
                                                          .withValues(
                                                            alpha: 0.55,
                                                          ),
                                                    ),
                                                  ),
                                                  child: const Text(
                                                    '圈出不懂的位置即可向诺诺提问',
                                                    style: TextStyle(
                                                      color: _BlackboardPalette
                                                          .chalkPrimary,
                                                      fontSize: 11.5,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                ),
                                              )
                                            : null,
                                      ),
                                    ),
                                  ),
                                // Floating Auto-Follow Camera Resume Pill when user scrolls up
                                if (!_autoFollowBoard &&
                                    _circlePendingRect == null &&
                                    (track?.visibleSteps.isNotEmpty ?? false))
                                  Positioned(
                                    left: 12,
                                    bottom: isPhoneLandscape ? 58 : 66,
                                    child: GestureDetector(
                                      onTap: () {
                                        setState(() => _autoFollowBoard = true);
                                        _followBoardToBottom(force: true);
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 11,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: _BlackboardPalette.primaryBtn,
                                          borderRadius: BorderRadius.circular(
                                            999,
                                          ),
                                          border: Border.all(
                                            color:
                                                _BlackboardPalette.chalkPrimary
                                                    .withValues(alpha: 0.45),
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withValues(
                                                alpha: 0.3,
                                              ),
                                              blurRadius: 8,
                                              offset: const Offset(0, 3),
                                            ),
                                          ],
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.arrow_downward_rounded,
                                              size: 13,
                                              color: Colors.white,
                                            ),
                                            SizedBox(width: 4),
                                            Text(
                                              '回到书写位置',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                // Tablet: floating Chalk Ledge toolbar at bottom center
                                if (!isPhoneLandscape &&
                                    _circlePendingRect == null)
                                  Positioned(
                                    left: 10,
                                    right: 10,
                                    bottom: 8,
                                    child: Center(
                                      child: _buildFloatingChalkLedge(
                                        notifier,
                                        penMode,
                                      ),
                                    ),
                                  ),
                                // Phone Landscape: drawing palette sub-tray when writing chalk
                                if (isPhoneLandscape &&
                                    _circlePendingRect == null &&
                                    (penMode ==
                                            BlackboardPenMode.studentChalk ||
                                        penMode == BlackboardPenMode.eraser))
                                  Positioned(
                                    left: 10,
                                    bottom: 56,
                                    child: _buildPhoneDrawPaletteTray(
                                      notifier,
                                      penMode,
                                    ),
                                  ),
                                // Phone Landscape: lightweight spoken subtitle above teacher
                                if (isPhoneLandscape &&
                                    !_phoneAskOpen &&
                                    !_phoneCaptionDismissed &&
                                    !hasInlineFeedbackOnBoard &&
                                    _circlePendingRect == null)
                                  Positioned(
                                    right: 60,
                                    bottom: 56,
                                    child: ConstrainedBox(
                                      constraints: BoxConstraints(
                                        maxWidth: math.min(
                                          270,
                                          landscapeW * 0.46,
                                        ),
                                      ),
                                      child: _buildPhoneSpeechPill(
                                        spokenBubbleText,
                                      ),
                                    ),
                                  ),
                                // Phone Landscape: collapsible floating Ask Drawer
                                if (isPhoneLandscape &&
                                    _phoneAskOpen &&
                                    _circlePendingRect == null)
                                  Positioned(
                                    right: 10,
                                    bottom: 56,
                                    child: ConstrainedBox(
                                      constraints: BoxConstraints(
                                        maxWidth: math.min(
                                          340,
                                          landscapeW * 0.64,
                                        ),
                                        maxHeight: math.max(
                                          120,
                                          landscapeH - 104,
                                        ),
                                      ),
                                      child: SingleChildScrollView(
                                        child: _buildPhoneAskDrawer(
                                          state,
                                          spokenBubbleText,
                                        ),
                                      ),
                                    ),
                                  ),
                                // Phone Landscape: integrated ultra-slim bottom classroom bar
                                if (isPhoneLandscape &&
                                    _circlePendingRect == null)
                                  Positioned(
                                    left: 8,
                                    right: 8,
                                    bottom: 6,
                                    child: _buildPhoneBottomBar(
                                      state,
                                      notifier,
                                      track,
                                      penMode,
                                      currentUnresolvedCheckpoint,
                                    ),
                                  ),
                                  // Floating circle-to-ask bubble
                                  if (_circlePendingRect != null)
                                    _buildCircleAskPopup(t, state.blackboardBusy),
                                ],
                              ),
                            ),
                          // Tablet Landscape only: spacious right standing teacher column
                          if (!isPhoneLandscape) ...[
                            Container(width: 1, color: const Color(0x1EFFFFFF)),
                            SizedBox(
                              width: teacherColWidth,
                              child: _buildTeacherPodiumColumn(
                                context,
                                state,
                                notifier,
                                track,
                                spokenBubbleText,
                                currentUnresolvedCheckpoint,
                                isTightHeight,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );

            if (needsPortraitRotate) {
              return RotatedBox(
                quarterTurns: 1,
                child: classroomShell,
              );
            }
            return classroomShell;
          },
        ),
      ),
    ),
  );
  }

  Widget _buildChalkboardTopStrip(
    InouTokens t,
    AppState state,
    AppStoreNotifier notifier,
    BlackboardLessonRecord? lesson,
    Question? boundQ,
    HintLevel hintLevel, {
    required bool isPhoneLandscape,
  }) {
    final depthLabel = switch (hintLevel) {
      HintLevel.l1Concept => '思路点拨',
      HintLevel.l2KeyStep => '关键步骤',
      HintLevel.l3FullSolution => '详细解答',
      HintLevel.none => '思路点拨',
    };

    Future<void> handleArchive() async {
      final messenger = ScaffoldMessenger.of(context);
      final ok = await notifier.archiveBlackboardToWrongbook();
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(ok ? '已将板书存入错题笔记！' : '暂无可保存的板书内容')),
      );
    }

    return Container(
      width: double.infinity,
      color: _BlackboardPalette.topStripBg,
      padding: EdgeInsets.symmetric(
        horizontal: isPhoneLandscape ? 8 : 10,
        vertical: isPhoneLandscape ? 3 : 5,
      ),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(right: 5),
            decoration: const BoxDecoration(
              color: _BlackboardPalette.accentWarm,
              shape: BoxShape.circle,
            ),
          ),
          Text(
            'AI 黑板讲堂',
            style: TextStyle(
              fontSize: isPhoneLandscape ? 11.5 : 12.5,
              fontWeight: FontWeight.w700,
              color: _BlackboardPalette.chalkPrimary,
            ),
          ),
          SizedBox(width: isPhoneLandscape ? 6 : 8),
          Expanded(
            child: Text(
              boundQ != null ? boundQ.header.title : '自由黑板问答',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: isPhoneLandscape ? 11 : 11.5,
                color: _BlackboardPalette.chalkMuted,
              ),
            ),
          ),
          const SizedBox(width: 6),
          if (isPhoneLandscape) ...[
            PopupMenuButton<HintLevel>(
              enabled: !state.blackboardBusy,
              tooltip: '切换讲解深度',
              color: _BlackboardPalette.overlayCardBg,
              initialValue: hintLevel,
              onSelected: notifier.setBlackboardHintLevel,
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: HintLevel.l1Concept,
                  child: Text(
                    '思路点拨',
                    style: TextStyle(
                      color: _BlackboardPalette.chalkPrimary,
                      fontSize: 13,
                    ),
                  ),
                ),
                PopupMenuItem(
                  value: HintLevel.l2KeyStep,
                  child: Text(
                    '关键步骤',
                    style: TextStyle(
                      color: _BlackboardPalette.chalkPrimary,
                      fontSize: 13,
                    ),
                  ),
                ),
                PopupMenuItem(
                  value: HintLevel.l3FullSolution,
                  child: Text(
                    '详细解答',
                    style: TextStyle(
                      color: _BlackboardPalette.chalkPrimary,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: const Color(0x1CFFFFFF),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: _BlackboardPalette.softBorder),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      depthLabel,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _BlackboardPalette.accentWarm,
                      ),
                    ),
                    const SizedBox(width: 2),
                    const Icon(
                      Icons.arrow_drop_down,
                      size: 14,
                      color: _BlackboardPalette.accentWarm,
                    ),
                  ],
                ),
              ),
            ),
            if (boundQ != null)
              IconButton(
                tooltip: lesson?.archivedToWrongbook == true
                    ? '已存笔记'
                    : '收入错题笔记',
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                padding: EdgeInsets.zero,
                onPressed: lesson == null ? null : handleArchive,
                icon: Icon(
                  lesson?.archivedToWrongbook == true
                      ? Icons.bookmark_added_rounded
                      : Icons.bookmark_add_outlined,
                  size: 16,
                  color: lesson?.archivedToWrongbook == true
                      ? _BlackboardPalette.accentWarm
                      : _BlackboardPalette.chalkPrimary,
                ),
              ),
          ] else ...[
            // Tablet: 3-segment compact depth selector
            Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: const Color(0x38000000),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: const Color(0x2EFFFFFF)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final entry in const [
                    (HintLevel.l1Concept, '思路点拨'),
                    (HintLevel.l2KeyStep, '关键步骤'),
                    (HintLevel.l3FullSolution, '详细解答'),
                  ])
                    _ChalkHeaderPill(
                      label: entry.$2,
                      selected: hintLevel == entry.$1,
                      compact: true,
                      onTap: state.blackboardBusy
                          ? null
                          : () => notifier.setBlackboardHintLevel(entry.$1),
                    ),
                ],
              ),
            ),
            if (boundQ != null) ...[
              const SizedBox(width: 6),
              _ChalkHeaderPill(
                icon: lesson?.archivedToWrongbook == true
                    ? Icons.bookmark_added_rounded
                    : Icons.bookmark_add_outlined,
                label: lesson?.archivedToWrongbook == true
                    ? '已存笔记'
                    : '收入错题笔记',
                selected: lesson?.archivedToWrongbook == true,
                onTap: lesson == null ? null : handleArchive,
              ),
            ],
          ],
          const SizedBox(width: 2),
          IconButton(
            tooltip: '关闭黑板',
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            padding: EdgeInsets.zero,
            onPressed: notifier.closeBlackboard,
            icon: const Icon(
              Icons.close,
              size: 17,
              color: Color(0xCCFFFFFF),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChalkBoardBody(
    BuildContext context,
    AppState state,
    AppStoreNotifier notifier,
    BlackboardSolutionTrack? track,
    BlackboardPenMode penMode, {
    double bottomClearance = 72.0,
  }) {
    if (track == null || track.steps.isEmpty) {
      final loading = state.blackboardBusy || state.blackboardStepStreaming;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.draw_outlined,
                size: 36,
                color: _BlackboardPalette.accentWarm,
              ),
              const SizedBox(height: 10),
              Text(
                loading ? '诺诺拿起粉笔，马上写第 1 步…' : '暂无板书内容，点击下方重新生成',
                style: const TextStyle(
                  color: _BlackboardPalette.chalkPrimary,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (!loading) ...[
                const SizedBox(height: 12),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _BlackboardPalette.primaryBtn,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: notifier.regenerateBlackboardLesson,
                  child: const Text('生成分步板书'),
                ),
              ],
            ],
          ),
        ),
      );
    }

    final visibleSteps = track.visibleSteps;
    final hasDiagram = track.diagram.isNotEmpty;
    final activeStepId = _selectedStepId ?? track.currentStep?.id;

    final stepsList = NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollUpdateNotification &&
            notification.dragDetails != null) {
          final distFromBottom =
              notification.metrics.maxScrollExtent -
              notification.metrics.pixels;
          final shouldFollow = distFromBottom <= 36.0;
          if (shouldFollow != _autoFollowBoard) {
            setState(() => _autoFollowBoard = shouldFollow);
          }
        } else if (notification is ScrollEndNotification) {
          final distFromBottom =
              notification.metrics.maxScrollExtent -
              notification.metrics.pixels;
          if (distFromBottom <= 16.0 && !_autoFollowBoard) {
            setState(() => _autoFollowBoard = true);
          }
        }
        return false;
      },
      child: ListView.separated(
        controller: _stepsScrollCtrl,
        padding: EdgeInsets.fromLTRB(12, 8, 12, bottomClearance),
        itemCount:
            visibleSteps.length +
            (track.takeaway.isNotEmpty && !track.canStepForward ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          if (index >= visibleSteps.length) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: _BlackboardPalette.sideNoteBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _BlackboardPalette.accentMint.withValues(alpha: 0.35),
                  width: 0.9,
                ),
              ),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      width: 3,
                      decoration: BoxDecoration(
                        color: _BlackboardPalette.accentMint,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    const SizedBox(width: 9),
                    const Padding(
                      padding: EdgeInsets.only(top: 1),
                      child: Icon(
                        Icons.lightbulb_outline_rounded,
                        size: 16,
                        color: _BlackboardPalette.accentMint,
                      ),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        track.takeaway,
                        style: const TextStyle(
                          color: _BlackboardPalette.chalkPrimary,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          height: 1.48,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          final step = visibleSteps[index];
          final isNewest = index == visibleSteps.length - 1;
          final isSelected = step.id == _selectedStepId;

          return KeyedSubtree(
            key: _keyForStep(step.id),
            child: _ChalkStepCard(
              step: step,
              animateWriteIn: isNewest,
              isSelected: isSelected,
              isCurrentActiveStep: isNewest,
              feedbackBusy: state.blackboardFeedbackBusy,
              onWritingPhaseChanged: isNewest ? _setChalkWritingPhase : null,
              onWritingProgress: isNewest ? _followBoardToBottom : null,
              onTapSelect: () => setState(() => _selectedStepId = step.id),
              onAnswerCheckpoint: (idx, {bool skip = false}) async {
                if (mounted) {
                  setState(() {
                    _autoFollowBoard = true;
                    _teacherActionTick++;
                  });
                }
                await notifier.answerBlackboardCheckpoint(
                  step.id,
                  idx,
                  skip: skip,
                );
                if (mounted) _followBoardToBottom(force: true);
              },
              onSubmitStepFeedback: (
                replyText, {
                bool isConfused = false,
              }) async {
                if (mounted) {
                  setState(() {
                    _autoFollowBoard = true;
                    _teacherActionTick++;
                  });
                }
                await notifier.submitBlackboardStepFeedback(
                  stepId: step.id,
                  replyText: replyText,
                  isConfused: isConfused,
                );
                if (mounted) {
                  setState(() => _teacherActionTick++);
                  _followBoardToBottom(force: true);
                }
              },
              onMarkUnderstood: () async {
                if (mounted) {
                  setState(() {
                    _autoFollowBoard = true;
                    _teacherActionTick++;
                  });
                }
                await notifier.markBlackboardStepUnderstood(step.id);
                if (mounted) {
                  setState(() => _teacherActionTick++);
                  _followBoardToBottom(force: true);
                }
              },
            ),
          );
        },
      ),
    );

    final diagramPanel = KeyedSubtree(
      key: _diagramKey,
      child: _BlackboardDiagramPanel(
        diagram: track.diagram,
        revealedStepIndex: track.revealedCount - 1,
        activeStepId: activeStepId,
        highlightedByCircle: _circleHitIsDiagram,
      ),
    );

    final tracks =
        state.activeBlackboardLesson?.tracks ??
        const <BlackboardSolutionTrack>[];
    final activeIdx = state.activeBlackboardLesson?.activeTrackIndex ?? 0;

    final bodyContent = !hasDiagram
        ? stepsList
        : Row(
            children: [
              Expanded(
                flex: 4,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 6, 62),
                  child: diagramPanel,
                ),
              ),
              Container(width: 1, color: const Color(0x22FFFFFF)),
              Expanded(flex: 6, child: stepsList),
            ],
          );

    if (tracks.length <= 1) {
      return bodyContent;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < tracks.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: _ChalkHeaderPill(
                      label: tracks[i].label,
                      selected: i == activeIdx,
                      compact: true,
                      onTap: () => notifier.switchBlackboardTrack(i),
                    ),
                  ),
              ],
            ),
          ),
        ),
        Expanded(child: bodyContent),
      ],
    );
  }

  Widget _buildFloatingChalkLedge(
    AppStoreNotifier notifier,
    BlackboardPenMode penMode,
  ) {
    final isDrawing =
        penMode == BlackboardPenMode.studentChalk ||
        penMode == BlackboardPenMode.eraser;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _BlackboardPalette.chromeBg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _BlackboardPalette.hairline),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _PenModeChip(
              icon: Icons.pan_tool_alt_outlined,
              label: '浏览',
              selected: penMode == BlackboardPenMode.none,
              onTap: () {
                notifier.setBlackboardPenMode(BlackboardPenMode.none);
                _clearCirclePopup();
              },
            ),
            const SizedBox(width: 4),
            _PenModeChip(
              icon: Icons.radio_button_unchecked,
              label: '圈选提问笔',
              selected: penMode == BlackboardPenMode.circleAsk,
              onTap: () {
                notifier.setBlackboardPenMode(BlackboardPenMode.circleAsk);
                _clearCirclePopup();
              },
            ),
            const SizedBox(width: 4),
            _PenModeChip(
              icon: Icons.edit_outlined,
              label: '写粉笔',
              selected: penMode == BlackboardPenMode.studentChalk,
              onTap: () {
                _syncPenModeToInkController(BlackboardPenMode.studentChalk);
                notifier.setBlackboardPenMode(BlackboardPenMode.studentChalk);
                _clearCirclePopup();
              },
            ),
            const SizedBox(width: 4),
            _PenModeChip(
              icon: Icons.cleaning_services_outlined,
              label: '橡皮',
              selected: penMode == BlackboardPenMode.eraser,
              onTap: () {
                _syncPenModeToInkController(BlackboardPenMode.eraser);
                notifier.setBlackboardPenMode(BlackboardPenMode.eraser);
                _clearCirclePopup();
              },
            ),
            if (isDrawing) ...[
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 6),
                width: 1,
                height: 18,
                color: const Color(0x33FFFFFF),
              ),
              for (final c in const [
                ChalkColor.yellow,
                ChalkColor.white,
                ChalkColor.pink,
                ChalkColor.blue,
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 5),
                  child: GestureDetector(
                    onTap: () {
                      _studentInkCtrl.setColorArgb(c.argb);
                      _studentInkCtrl.setTool(InkToolKind.pen);
                      notifier.setBlackboardPenMode(
                        BlackboardPenMode.studentChalk,
                      );
                    },
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: Color(c.argb),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _studentInkCtrl.colorArgb == c.argb
                              ? Colors.white
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                ),
              IconButton(
                tooltip: '撤销一笔',
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                padding: EdgeInsets.zero,
                onPressed: _studentInkCtrl.canUndo
                    ? _studentInkCtrl.undo
                    : null,
                icon: const Icon(Icons.undo, size: 16, color: Colors.white),
              ),
              IconButton(
                tooltip: '清空学生粉笔',
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                padding: EdgeInsets.zero,
                onPressed: _studentInkCtrl.page.strokes.isNotEmpty
                    ? () {
                        _studentInkCtrl.clearAll();
                        notifier.saveBlackboardStudentInk(
                          _studentInkCtrl.page,
                        );
                      }
                    : null,
                icon: const Icon(
                  Icons.delete_outline,
                  size: 16,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 4),
              FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 26),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 2,
                  ),
                ),
                onPressed: _gradeStudentChalk,
                child: const Text('批改', style: TextStyle(fontSize: 11)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCircleAskPopup(InouTokens t, bool busy) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.all(12),
        constraints: const BoxConstraints(maxWidth: 520),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: t.accent, width: 1.4),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.28),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome, size: 16, color: t.accent),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '已圈选：$_circleHitLabel',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: t.accent,
                    ),
                  ),
                ),
                if (_circleSnapshotPng != null)
                  const Padding(
                    padding: EdgeInsets.only(right: 4),
                    child: InouBadge(
                      label: '已截图',
                      tone: InouBadgeTone.success,
                    ),
                  ),
                IconButton(
                  tooltip: '取消圈选',
                  visualDensity: VisualDensity.compact,
                  onPressed: _clearCirclePopup,
                  icon: const Icon(Icons.close, size: 17),
                ),
              ],
            ),
            const SizedBox(height: 6),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final preset in const [
                    '这一步怎么来的？',
                    '这个符号或辅助线是什么意思？',
                    '换种解法（写解法二）',
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ActionChip(
                        label: Text(
                          preset,
                          style: const TextStyle(fontSize: 11.5),
                        ),
                        onPressed: busy
                            ? null
                            : () => _submitCircleQuestion(preset),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _circleAskCtrl,
                    decoration: const InputDecoration(
                      hintText: '输入你对圈选处的疑问…',
                    ),
                    onSubmitted: busy ? null : _submitCircleQuestion,
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: busy
                      ? null
                      : () => _submitCircleQuestion(_circleAskCtrl.text),
                  child: const Text('发送'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhoneDrawPaletteTray(
    AppStoreNotifier notifier,
    BlackboardPenMode penMode,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _BlackboardPalette.chromeBg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _BlackboardPalette.softBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final c in const [
            ChalkColor.yellow,
            ChalkColor.white,
            ChalkColor.pink,
            ChalkColor.blue,
          ])
            Padding(
              padding: const EdgeInsets.only(right: 5),
              child: GestureDetector(
                onTap: () {
                  _studentInkCtrl.setColorArgb(c.argb);
                  _studentInkCtrl.setTool(InkToolKind.pen);
                  notifier.setBlackboardPenMode(
                    BlackboardPenMode.studentChalk,
                  );
                },
                child: Container(
                  width: 15,
                  height: 15,
                  decoration: BoxDecoration(
                    color: Color(c.argb),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color:
                          penMode == BlackboardPenMode.studentChalk &&
                              _studentInkCtrl.colorArgb == c.argb
                          ? Colors.white
                          : Colors.transparent,
                      width: 2,
                    ),
                  ),
                ),
              ),
            ),
          IconButton(
            tooltip: '橡皮',
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
            padding: EdgeInsets.zero,
            onPressed: () {
              _syncPenModeToInkController(BlackboardPenMode.eraser);
              notifier.setBlackboardPenMode(BlackboardPenMode.eraser);
            },
            icon: Icon(
              Icons.cleaning_services_outlined,
              size: 15,
              color: penMode == BlackboardPenMode.eraser
                  ? _BlackboardPalette.accentMint
                  : _BlackboardPalette.chalkMuted,
            ),
          ),
          IconButton(
            tooltip: '撤销一笔',
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
            padding: EdgeInsets.zero,
            onPressed: _studentInkCtrl.canUndo ? _studentInkCtrl.undo : null,
            icon: const Icon(
              Icons.undo,
              size: 15,
              color: _BlackboardPalette.chalkPrimary,
            ),
          ),
          IconButton(
            tooltip: '清空学生粉笔',
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
            padding: EdgeInsets.zero,
            onPressed: _studentInkCtrl.page.strokes.isNotEmpty
                ? () {
                    _studentInkCtrl.clearAll();
                    notifier.saveBlackboardStudentInk(_studentInkCtrl.page);
                  }
                : null,
            icon: const Icon(
              Icons.delete_outline,
              size: 15,
              color: _BlackboardPalette.chalkPrimary,
            ),
          ),
          const SizedBox(width: 2),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _BlackboardPalette.primaryBtn,
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 24),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            ),
            onPressed: _gradeStudentChalk,
            child: const Text('批改', style: TextStyle(fontSize: 10.5)),
          ),
        ],
      ),
    );
  }

  Widget _buildPhoneSpeechPill(String text) {
    return GestureDetector(
      onTap: () => setState(() => _phoneAskOpen = true),
      child: Container(
        padding: const EdgeInsets.fromLTRB(9, 6, 6, 6),
        decoration: BoxDecoration(
          color: _BlackboardPalette.chromeBg,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: _BlackboardPalette.hairline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Flexible(
              child: Text(
                text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  height: 1.35,
                  color: _BlackboardPalette.chalkPrimary,
                ),
              ),
            ),
            const SizedBox(width: 4),
            GestureDetector(
              onTap: () => setState(() => _phoneCaptionDismissed = true),
              child: const Padding(
                padding: EdgeInsets.all(2),
                child: Icon(
                  Icons.close,
                  size: 13,
                  color: _BlackboardPalette.chalkMuted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhoneAskDrawer(AppState state, String spokenBubbleText) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _BlackboardPalette.overlayCardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _BlackboardPalette.softBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.32),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.record_voice_over_outlined,
                size: 14,
                color: _BlackboardPalette.accentWarm,
              ),
              const SizedBox(width: 5),
              const Expanded(
                child: Text(
                  '向诺诺老师提问',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: _BlackboardPalette.chalkPrimary,
                  ),
                ),
              ),
              IconButton(
                tooltip: '收起提问框',
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                padding: EdgeInsets.zero,
                onPressed: () => setState(() => _phoneAskOpen = false),
                icon: const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 18,
                  color: _BlackboardPalette.chalkMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 72),
            child: SingleChildScrollView(
              child: Text(
                spokenBubbleText,
                style: const TextStyle(
                  fontSize: 11.5,
                  height: 1.4,
                  color: _BlackboardPalette.chalkMuted,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.only(left: 10, right: 4),
            decoration: BoxDecoration(
              color: const Color(0x45000000),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _BlackboardPalette.softBorder),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _quickAskCtrl,
                    style: const TextStyle(
                      fontSize: 12,
                      color: _BlackboardPalette.chalkPrimary,
                    ),
                    cursorColor: _BlackboardPalette.accentWarm,
                    decoration: const InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      hintText: '有问题直接问老师…',
                      hintStyle: TextStyle(
                        fontSize: 11.5,
                        color: _BlackboardPalette.chalkMuted,
                      ),
                      contentPadding: EdgeInsets.symmetric(vertical: 8),
                    ),
                    onSubmitted: state.blackboardBusy
                        ? null
                        : _submitQuickQuestion,
                  ),
                ),
                IconButton(
                  tooltip: '提问',
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                  padding: EdgeInsets.zero,
                  onPressed: state.blackboardBusy
                      ? null
                      : () => _submitQuickQuestion(_quickAskCtrl.text),
                  icon: Icon(
                    Icons.send_rounded,
                    size: 16,
                    color: state.blackboardBusy
                        ? const Color(0x55FFFFFF)
                        : _BlackboardPalette.accentWarm,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhoneBottomBar(
    AppState state,
    AppStoreNotifier notifier,
    BlackboardSolutionTrack? track,
    BlackboardPenMode penMode,
    bool currentUnresolvedCheckpoint,
  ) {
    final revealed = track?.revealedCount ?? 0;
    final total = track?.displayTotalSteps ?? 0;
    final canBack = track?.canStepBackward ?? false;
    final canForward =
        (track?.canStepForward ?? false) && !currentUnresolvedCheckpoint;
    final isStreamingOrBusy =
        state.blackboardBusy || state.blackboardStepStreaming;
    final forwardLabel = currentUnresolvedCheckpoint
        ? '先完成上方小提问'
        : (state.blackboardStepStreaming
              ? '正在写这一步…'
              : ((track?.canStepForward ?? false) ? '听懂了，写下一步' : '板书已写完'));
    final emotion = NuoNuoExpression.fromCode(state.copilotLastEmotion.code);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Left: compact pen-mode icon pill
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
          decoration: BoxDecoration(
            color: _BlackboardPalette.chromeBg,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: _BlackboardPalette.hairline),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _PhoneIconToggle(
                tooltip: '浏览',
                icon: Icons.pan_tool_alt_outlined,
                selected: penMode == BlackboardPenMode.none,
                onTap: () {
                  notifier.setBlackboardPenMode(BlackboardPenMode.none);
                  _clearCirclePopup();
                },
              ),
              _PhoneIconToggle(
                tooltip: '圈选提问笔',
                icon: Icons.radio_button_unchecked,
                selected: penMode == BlackboardPenMode.circleAsk,
                onTap: () {
                  notifier.setBlackboardPenMode(BlackboardPenMode.circleAsk);
                  _clearCirclePopup();
                },
              ),
              _PhoneIconToggle(
                tooltip: '写粉笔',
                icon: Icons.edit_outlined,
                selected:
                    penMode == BlackboardPenMode.studentChalk ||
                    penMode == BlackboardPenMode.eraser,
                onTap: () {
                  _syncPenModeToInkController(BlackboardPenMode.studentChalk);
                  notifier.setBlackboardPenMode(
                    BlackboardPenMode.studentChalk,
                  );
                  _clearCirclePopup();
                },
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        // Center: unified stepper bar
        Expanded(
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: _BlackboardPalette.chromeBg,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: _BlackboardPalette.hairline),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: '上一步',
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(
                      minWidth: 26,
                      minHeight: 26,
                    ),
                    padding: EdgeInsets.zero,
                    onPressed: canBack
                        ? () async {
                            await notifier.stepBlackboardBackward();
                            if (mounted) {
                              setState(() => _phoneCaptionDismissed = false);
                            }
                          }
                        : null,
                    icon: Icon(
                      Icons.chevron_left_rounded,
                      size: 17,
                      color: canBack
                          ? _BlackboardPalette.chalkPrimary
                          : const Color(0x44FFFFFF),
                    ),
                  ),
                  Text(
                    '第 $revealed/$total 步',
                    style: InouTypography.tabular(
                      const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _BlackboardPalette.chalkMuted,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: _BlackboardPalette.primaryBtn,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: const Color(0x24FFFFFF),
                        disabledForegroundColor: _BlackboardPalette.chalkMuted,
                        minimumSize: const Size(0, 28),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 3,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      onPressed: canForward && !isStreamingOrBusy
                          ? () async {
                              if (mounted) {
                                setState(() {
                                  _autoFollowBoard = true;
                                  _teacherActionTick++;
                                });
                              }
                              await notifier.stepBlackboardForward();
                              if (mounted) {
                                setState(() => _phoneCaptionDismissed = false);
                              }
                              _followBoardToBottom(force: true);
                            }
                          : null,
                      child: Text(
                        forwardLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        // Right: Collapsible '问老师' pill + mini Little Teacher figure
        GestureDetector(
          onTap: () => setState(() {
            _phoneAskOpen = !_phoneAskOpen;
            if (!_phoneAskOpen) _phoneCaptionDismissed = false;
          }),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                margin: const EdgeInsets.only(bottom: 4),
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: _phoneAskOpen
                      ? _BlackboardPalette.primaryBtn
                      : _BlackboardPalette.chromeBg,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: _phoneAskOpen
                        ? _BlackboardPalette.primaryBtn
                        : _BlackboardPalette.softBorder,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _phoneAskOpen
                          ? Icons.close_rounded
                          : Icons.chat_bubble_outline_rounded,
                      size: 13,
                      color: _phoneAskOpen
                          ? Colors.white
                          : _BlackboardPalette.accentWarm,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _phoneAskOpen ? '收起' : '问老师',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _phoneAskOpen
                            ? Colors.white
                            : _BlackboardPalette.chalkPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 2),
              _NuoNuoTeacherFigure(
                emotion: emotion,
                animate: state.snapshot.preferences.mascotAnimating,
                height: 46,
                writingPhase: _chalkWritingPhase,
                actionTick: _teacherActionTick,
                onTap: () => setState(() => _teacherActionTick++),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Replaces the bulky white chat sidebar with an in-board standing teacher
  /// figure, compact speech bubble, step controls, and a single question box.
  Widget _buildTeacherPodiumColumn(
    BuildContext context,
    AppState state,
    AppStoreNotifier notifier,
    BlackboardSolutionTrack? track,
    String spokenBubbleText,
    bool currentUnresolvedCheckpoint,
    bool isTightHeight,
  ) {
    final revealed = track?.revealedCount ?? 0;
    final total = track?.displayTotalSteps ?? 0;
    final canBack = track?.canStepBackward ?? false;
    final canForward =
        (track?.canStepForward ?? false) && !currentUnresolvedCheckpoint;
    final emotion = NuoNuoExpression.fromCode(state.copilotLastEmotion.code);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        8,
        isTightHeight ? 6 : 10,
        10,
        isTightHeight ? 6 : 10,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Speech Bubble from Little Teacher
          Expanded(
            child: _TeacherSpeechBubble(
              text: spokenBubbleText,
              isTightHeight: isTightHeight,
              revealed: revealed,
              total: total,
              canBack: canBack,
              canForward: canForward,
              busy: state.blackboardBusy,
              stepStreaming: state.blackboardStepStreaming,
              blockedByCheckpoint: currentUnresolvedCheckpoint,
              onBack: () async {
                await notifier.stepBlackboardBackward();
              },
              onForward: () async {
                if (mounted) {
                  setState(() {
                    _autoFollowBoard = true;
                    _teacherActionTick++;
                  });
                }
                await notifier.stepBlackboardForward();
                _followBoardToBottom(force: true);
              },
            ),
          ),
          SizedBox(height: isTightHeight ? 4 : 6),
          // 2. Cute Standing Little Teacher Figure pointing to the blackboard
          Center(
            child: _NuoNuoTeacherFigure(
              emotion: emotion,
              animate: state.snapshot.preferences.mascotAnimating,
              height: isTightHeight ? 68 : 96,
              writingPhase: _chalkWritingPhase,
              actionTick: _teacherActionTick,
              onTap: () => setState(() => _teacherActionTick++),
            ),
          ),
          SizedBox(height: isTightHeight ? 4 : 6),
          // 3. Single Clean Input Box directly beneath the teacher
          Container(
            padding: const EdgeInsets.only(left: 10, right: 4),
            decoration: BoxDecoration(
              color: _BlackboardPalette.calloutBg,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: _BlackboardPalette.softBorder),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _quickAskCtrl,
                    style: const TextStyle(
                      fontSize: 12,
                      color: _BlackboardPalette.chalkPrimary,
                    ),
                    cursorColor: _BlackboardPalette.accentWarm,
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      hintText: '有问题直接问老师…',
                      hintStyle: const TextStyle(
                        fontSize: 11.5,
                        color: _BlackboardPalette.chalkMuted,
                      ),
                      contentPadding: EdgeInsets.symmetric(
                        vertical: isTightHeight ? 7 : 9,
                      ),
                    ),
                    onSubmitted: state.blackboardBusy
                        ? null
                        : _submitQuickQuestion,
                  ),
                ),
                IconButton(
                  tooltip: '提问',
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(
                    minWidth: 30,
                    minHeight: 30,
                  ),
                  padding: EdgeInsets.zero,
                  onPressed: state.blackboardBusy
                      ? null
                      : () => _submitQuickQuestion(_quickAskCtrl.text),
                  icon: Icon(
                    Icons.send_rounded,
                    size: 16,
                    color: state.blackboardBusy
                        ? const Color(0x55FFFFFF)
                        : _BlackboardPalette.accentWarm,
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

class _PhoneIconToggle extends StatelessWidget {
  const _PhoneIconToggle({
    required this.tooltip,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          width: 28,
          height: 26,
          decoration: BoxDecoration(
            color: selected ? _BlackboardPalette.primaryBtn : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Icon(
            icon,
            size: 15,
            color: selected ? Colors.white : _BlackboardPalette.chalkMuted,
          ),
        ),
      ),
    );
  }
}

class _BlackboardPinnedQuestionDock extends StatelessWidget {
  const _BlackboardPinnedQuestionDock({
    required this.question,
    required this.expanded,
    required this.isPhoneLandscape,
    required this.expandedWidth,
    required this.onToggleExpand,
  });

  final Question question;
  final bool expanded;
  final bool isPhoneLandscape;
  final double expandedWidth;
  final VoidCallback onToggleExpand;

  @override
  Widget build(BuildContext context) {
    if (!expanded) {
      return InkWell(
        onTap: onToggleExpand,
        child: Container(
          width: isPhoneLandscape ? 32.0 : 36.0,
          height: double.infinity,
          decoration: const BoxDecoration(
            color: Color(0xFF182C25),
            border: Border(
              right: BorderSide(
                color: _BlackboardPalette.softBorder,
                width: 0.9,
              ),
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.chevron_right_rounded,
                size: 16,
                color: _BlackboardPalette.accentWarm,
              ),
              const SizedBox(height: 6),
              RotatedBox(
                quarterTurns: 3,
                child: Text(
                  '展开原题',
                  style: TextStyle(
                    fontSize: isPhoneLandscape ? 10.5 : 11,
                    fontWeight: FontWeight.w700,
                    color: _BlackboardPalette.accentWarm,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final cleanedBlocks = QuestionBlackboardFormatter.cleanedPromptBlocks(
      question,
    );
    final options = QuestionBlackboardFormatter.extractOptionItems(question);
    final wordBank = QuestionBlackboardFormatter.extractWordBank(question);
    final matchLines = QuestionBlackboardFormatter.extractMatchSummary(
      question,
    );
    final classifyLines = QuestionBlackboardFormatter.extractClassifySummary(
      question,
    );
    final countTag = QuestionBlackboardFormatter.countTagLabel(question);

    return Container(
      width: expandedWidth,
      height: double.infinity,
      decoration: const BoxDecoration(
        color: Color(0xFF1A3028),
        border: Border(
          right: BorderSide(
            color: _BlackboardPalette.softBorder,
            width: 0.9,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onToggleExpand,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: 9,
                vertical: isPhoneLandscape ? 6 : 8,
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1.5,
                    ),
                    decoration: BoxDecoration(
                      color: _BlackboardPalette.accentWarmSoft,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      '原题',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: _BlackboardPalette.accentWarm,
                      ),
                    ),
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: countTag != null
                        ? Align(
                            alignment: Alignment.centerLeft,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1.5,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0x18FFFFFF),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                countTag,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: _BlackboardPalette.chalkMuted,
                                ),
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    '收起原题',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: _BlackboardPalette.accentWarm,
                    ),
                  ),
                  const SizedBox(width: 2),
                  const Icon(
                    Icons.chevron_left_rounded,
                    size: 16,
                    color: _BlackboardPalette.accentWarm,
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1, color: Color(0x1EFFFFFF)),
          Expanded(
            child: Theme(
              data: InouTheme.dark(),
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  10,
                  isPhoneLandscape ? 7 : 10,
                  10,
                  isPhoneLandscape ? 12 : 16,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '原题与题目内容',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: _BlackboardPalette.chalkMuted,
                      ),
                    ),
                    const SizedBox(height: 5),
                    ContentBlockRenderer(
                      blocks: cleanedBlocks,
                      textStyle: TextStyle(
                        fontSize: isPhoneLandscape ? 12 : 13,
                        height: 1.5,
                        color: _BlackboardPalette.chalkPrimary,
                      ),
                    ),
                    if (wordBank.isNotEmpty) ...[
                      SizedBox(height: isPhoneLandscape ? 7 : 9),
                      const Text(
                        '待排列词块：',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: _BlackboardPalette.chalkMuted,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Wrap(
                        spacing: 5,
                        runSpacing: 5,
                        children: [
                          for (final word in wordBank)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0x1EFFFFFF),
                                borderRadius: BorderRadius.circular(7),
                                border: Border.all(
                                  color: _BlackboardPalette.softBorder,
                                ),
                              ),
                              child: Text(
                                word,
                                style: TextStyle(
                                  fontSize: isPhoneLandscape ? 11.5 : 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: _BlackboardPalette.chalkPrimary,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                    if (options.isNotEmpty) ...[
                      SizedBox(height: isPhoneLandscape ? 7 : 9),
                      for (final opt in options)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 5),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                margin: const EdgeInsets.only(
                                  top: 1,
                                  right: 7,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: _BlackboardPalette.accentWarmSoft,
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                child: Text(
                                  opt.id,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: _BlackboardPalette.accentWarm,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  opt.text,
                                  style: TextStyle(
                                    fontSize: isPhoneLandscape ? 12 : 12.5,
                                    height: 1.45,
                                    color: _BlackboardPalette.chalkPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                    if (matchLines.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      for (final line in matchLines)
                        Text(
                          line,
                          style: TextStyle(
                            fontSize: isPhoneLandscape ? 11.5 : 12,
                            height: 1.45,
                            color: _BlackboardPalette.chalkMuted,
                          ),
                        ),
                    ],
                    if (classifyLines.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      for (final line in classifyLines)
                        Text(
                          line,
                          style: TextStyle(
                            fontSize: isPhoneLandscape ? 11.5 : 12,
                            height: 1.45,
                            color: _BlackboardPalette.chalkMuted,
                          ),
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
}

class _ChalkHeaderPill extends StatelessWidget {
  const _ChalkHeaderPill({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.compact = false,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 7 : 8,
          vertical: compact ? 3 : 4,
        ),
        decoration: BoxDecoration(
          color: selected
              ? _BlackboardPalette.accentWarmSoft
              : const Color(0x16FFFFFF),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? _BlackboardPalette.accentWarm.withValues(alpha: 0.65)
                : _BlackboardPalette.hairline,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 13,
                color: selected
                    ? _BlackboardPalette.accentWarm
                    : _BlackboardPalette.chalkMuted,
              ),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected
                    ? _BlackboardPalette.accentWarm
                    : _BlackboardPalette.chalkPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PenModeChip extends StatelessWidget {
  const _PenModeChip({
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
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: selected
              ? _BlackboardPalette.primaryBtn
              : const Color(0x14FFFFFF),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? _BlackboardPalette.primaryBtn
                : _BlackboardPalette.hairline,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: selected ? Colors.white : _BlackboardPalette.chalkMuted,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected
                    ? Colors.white
                    : _BlackboardPalette.chalkPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TeacherSpeechBubble extends StatelessWidget {
  const _TeacherSpeechBubble({
    required this.text,
    required this.isTightHeight,
    required this.revealed,
    required this.total,
    required this.canBack,
    required this.canForward,
    required this.busy,
    required this.stepStreaming,
    required this.blockedByCheckpoint,
    required this.onBack,
    required this.onForward,
  });

  final String text;
  final bool isTightHeight;
  final int revealed;
  final int total;
  final bool canBack;
  final bool canForward;
  final bool busy;
  final bool stepStreaming;
  final bool blockedByCheckpoint;
  final VoidCallback onBack;
  final VoidCallback onForward;

  @override
  Widget build(BuildContext context) {
    final forwardLabel = blockedByCheckpoint
        ? '先完成上方小提问'
        : (stepStreaming
              ? '正在写这一步…'
              : (canForward || (total > 0 && revealed < total)
                    ? '听懂了，写下一步'
                    : '板书已写完'));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Container(
            padding: EdgeInsets.fromLTRB(
              10,
              isTightHeight ? 8 : 10,
              10,
              isTightHeight ? 6 : 8,
            ),
            decoration: BoxDecoration(
              color: _BlackboardPalette.calloutBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _BlackboardPalette.softBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: Text(
                      text,
                      style: TextStyle(
                        color: _BlackboardPalette.chalkPrimary,
                        fontSize: isTightHeight ? 11.5 : 12.5,
                        height: 1.48,
                      ),
                    ),
                  ),
                ),
                SizedBox(height: isTightHeight ? 5 : 8),
                const Divider(height: 1, color: Color(0x22FFFFFF)),
                SizedBox(height: isTightHeight ? 5 : 7),
                Row(
                  children: [
                    IconButton(
                      tooltip: '上一步',
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                      padding: EdgeInsets.zero,
                      onPressed: canBack ? onBack : null,
                      icon: Icon(
                        Icons.chevron_left_rounded,
                        size: 18,
                        color: canBack
                            ? _BlackboardPalette.chalkPrimary
                            : const Color(0x44FFFFFF),
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: Text(
                          '第 $revealed/$total 步',
                          style: InouTypography.tabular(
                            const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: _BlackboardPalette.chalkMuted,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _BlackboardPalette.primaryBtn,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0x24FFFFFF),
                    disabledForegroundColor: _BlackboardPalette.chalkMuted,
                    minimumSize: Size(0, isTightHeight ? 30 : 34),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: canForward && !busy && !stepStreaming
                      ? onForward
                      : null,
                  child: Text(
                    forwardLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: isTightHeight ? 11.5 : 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        // Speech bubble downward pointer aiming at little teacher
        const Align(
          alignment: Alignment(0.18, 0),
          child: CustomPaint(
            size: Size(16, 8),
            painter: _SpeechBubbleTailPainter(),
          ),
        ),
      ],
    );
  }
}

class _SpeechBubbleTailPainter extends CustomPainter {
  const _SpeechBubbleTailPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width * 0.55, size.height)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0x46000000)
        ..style = PaintingStyle.fill,
    );
    canvas.drawLine(
      Offset.zero,
      Offset(size.width * 0.55, size.height),
      Paint()
        ..color = const Color(0x36FFFFFF)
        ..strokeWidth = 1,
    );
    canvas.drawLine(
      Offset(size.width * 0.55, size.height),
      Offset(size.width, 0),
      Paint()
        ..color = const Color(0x36FFFFFF)
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _SpeechBubbleTailPainter oldDelegate) => false;
}

class _NuoNuoTeacherFigure extends StatefulWidget {
  const _NuoNuoTeacherFigure({
    required this.emotion,
    required this.animate,
    required this.height,
    this.writingPhase,
    this.actionTick = 0,
    this.onTap,
  });

  final NuoNuoExpression emotion;
  final bool animate;
  final double height;
  final ValueNotifier<double>? writingPhase;
  final int actionTick;
  final VoidCallback? onTap;

  @override
  State<_NuoNuoTeacherFigure> createState() => _NuoNuoTeacherFigureState();
}

class _NuoNuoTeacherFigureState extends State<_NuoNuoTeacherFigure>
    with SingleTickerProviderStateMixin {
  late final AnimationController _actionCtrl;
  bool _manualWave = false;

  @override
  void initState() {
    super.initState();
    _actionCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
      value: 1.0,
    );
  }

  @override
  void didUpdateWidget(covariant _NuoNuoTeacherFigure oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.animate) return;
    if (widget.actionTick != oldWidget.actionTick ||
        (widget.emotion != oldWidget.emotion &&
            widget.emotion != NuoNuoExpression.neutral)) {
      _manualWave = false;
      _actionCtrl.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _actionCtrl.dispose();
    super.dispose();
  }

  void _triggerTapAction() {
    if (widget.animate) {
      setState(() => _manualWave = true);
      _actionCtrl.forward(from: 0.0);
    }
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    final width = widget.height * 1.18;
    final headSize = widget.height * 0.56;
    final listenable = widget.writingPhase == null
        ? _actionCtrl
        : Listenable.merge([_actionCtrl, widget.writingPhase!]);

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: _triggerTapAction,
      child: SizedBox(
        width: width,
        height: widget.height,
        child: AnimatedBuilder(
          animation: listenable,
          builder: (context, _) {
            final writePhase = widget.writingPhase?.value ?? 0.0;
            final act = _actionCtrl.isAnimating ? _actionCtrl.value : 1.0;
            final isActing = _actionCtrl.isAnimating;

            var bounceY = 0.0;
            var headTilt = 0.0;
            if (isActing) {
              if (widget.emotion == NuoNuoExpression.celebrate && !_manualWave) {
                bounceY =
                    -math.sin(act * math.pi * 2).abs() * (widget.height * 0.09);
                headTilt = math.sin(act * math.pi * 2) * 0.05;
              } else if (widget.emotion == NuoNuoExpression.thinking &&
                  !_manualWave) {
                headTilt = math.sin(act * math.pi) * 0.09;
              } else {
                bounceY =
                    -math.sin(act * math.pi).abs() * (widget.height * 0.045);
                headTilt = math.sin(act * math.pi) * -0.04;
              }
            } else if (widget.emotion == NuoNuoExpression.thinking) {
              headTilt = 0.06;
            }
            if (writePhase > 0.01 && writePhase < 0.99) {
              headTilt = -0.04;
            }

            return Transform.translate(
              offset: Offset(0, bounceY),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _TeacherBodyPainter(
                        headRadius: headSize / 2,
                        writingPhase: writePhase,
                        emotion: widget.emotion,
                        actionProgress: act,
                        isActing: isActing,
                        manualWave: _manualWave,
                      ),
                    ),
                  ),
                  Positioned(
                    left: width * 0.58 - headSize / 2,
                    top: 0,
                    child: Transform.rotate(
                      angle: headTilt,
                      child: NuoNuoMascotView(
                        emotion: widget.emotion,
                        size: headSize,
                        showGlowRing: false,
                        animate: widget.animate,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _TeacherBodyPainter extends CustomPainter {
  const _TeacherBodyPainter({
    required this.headRadius,
    this.writingPhase = 0.0,
    this.emotion = NuoNuoExpression.neutral,
    this.actionProgress = 1.0,
    this.isActing = false,
    this.manualWave = false,
  });

  final double headRadius;
  final double writingPhase;
  final NuoNuoExpression emotion;
  final double actionProgress;
  final bool isActing;
  final bool manualWave;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final centerX = w * 0.58;
    final neckY = headRadius * 1.88;

    // 1. Podium edge / chalkboard ledge grounding shadow
    canvas.drawLine(
      Offset(w * 0.22, h * 0.96),
      Offset(w * 0.92, h * 0.96),
      Paint()
        ..color = _BlackboardPalette.woodFrame.withValues(alpha: 0.45)
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );

    // 2. Teacher cardigan / gown torso
    final torsoPath = Path()
      ..moveTo(centerX - headRadius * 0.45, neckY)
      ..quadraticBezierTo(
        centerX - headRadius * 0.95,
        neckY + h * 0.14,
        centerX - headRadius * 0.85,
        h * 0.95,
      )
      ..lineTo(centerX + headRadius * 0.85, h * 0.95)
      ..quadraticBezierTo(
        centerX + headRadius * 0.95,
        neckY + h * 0.14,
        centerX + headRadius * 0.45,
        neckY,
      )
      ..close();
    canvas.drawPath(
      torsoPath,
      Paint()..color = _BlackboardPalette.teacherCardigan,
    );

    // Inner cardigan V lapel
    final innerShirt = Path()
      ..moveTo(centerX - headRadius * 0.30, neckY)
      ..lineTo(centerX, neckY + h * 0.26)
      ..lineTo(centerX + headRadius * 0.30, neckY)
      ..close();
    canvas.drawPath(
      innerShirt,
      Paint()..color = _BlackboardPalette.chalkPrimary,
    );

    // Cute soft coral bow tie
    final bowY = neckY + h * 0.08;
    final bowPaint = Paint()..color = _BlackboardPalette.teacherBow;
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(centerX - 4.5, bowY),
        width: 7,
        height: 4.5,
      ),
      bowPaint,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(centerX + 4.5, bowY),
        width: 7,
        height: 4.5,
      ),
      bowPaint,
    );
    canvas.drawCircle(Offset(centerX, bowY), 2.2, bowPaint);

    // Subtle chalk-writing arm sweep while characters appear
    final activeWrite = writingPhase > 0.01 && writingPhase < 0.99;
    final sweepX = activeWrite
        ? math.cos(writingPhase * 18) * (w * 0.025)
        : 0.0;
    final sweepY = activeWrite
        ? math.sin(writingPhase * 28) * (h * 0.055)
        : 0.0;

    // 3. Raised left arm pointing left toward the chalkboard
    final shoulderL = Offset(centerX - headRadius * 0.62, neckY + h * 0.08);
    final handL = Offset(
      w * 0.27 + sweepX * 0.5,
      neckY + h * 0.04 + sweepY * 0.5,
    );
    canvas.drawLine(
      shoulderL,
      handL,
      Paint()
        ..color = _BlackboardPalette.teacherSleeve
        ..strokeWidth = math.max(5.0, h * 0.09)
        ..strokeCap = StrokeCap.round,
    );

    // 4. Right arm expresses celebrate cheer, wave, encourage, or thinking
    final shoulderR = Offset(centerX + headRadius * 0.62, neckY + h * 0.08);
    var handR = Offset(centerX + headRadius * 0.96, h * 0.80);
    var showWaveHand = false;
    if (isActing &&
        (manualWave ||
            emotion == NuoNuoExpression.celebrate ||
            emotion == NuoNuoExpression.encourage ||
            emotion == NuoNuoExpression.happy)) {
      final waveOsc = math.sin(actionProgress * math.pi * 3) * (w * 0.055);
      final lift = math.sin(actionProgress * math.pi) * (h * 0.36);
      handR = Offset(centerX + headRadius * 1.05 + waveOsc, h * 0.78 - lift);
      showWaveHand = lift > h * 0.1;
    } else if (emotion == NuoNuoExpression.thinking) {
      handR = Offset(centerX + headRadius * 0.88, neckY + h * 0.02);
      showWaveHand = true;
    }
    canvas.drawLine(
      shoulderR,
      handR,
      Paint()
        ..color = _BlackboardPalette.teacherSleeve
        ..strokeWidth = math.max(4.5, h * 0.085)
        ..strokeCap = StrokeCap.round,
    );
    if (showWaveHand) {
      canvas.drawCircle(
        handR,
        math.max(3.0, h * 0.044),
        Paint()..color = const Color(0xFFFFE4D6),
      );
    }

    // Pointer stick & warm milk-cream chalk tip
    final pointerTip = Offset(w * 0.03 + sweepX, neckY - h * 0.20 + sweepY);
    canvas.drawLine(
      handL,
      pointerTip,
      Paint()
        ..color = _BlackboardPalette.teacherPointer
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(
      pointerTip,
      activeWrite ? 3.2 : 2.6,
      Paint()..color = _BlackboardPalette.chalkPrimary,
    );
    // Cute hand circle over stick handle
    canvas.drawCircle(
      handL,
      math.max(3.2, h * 0.048),
      Paint()..color = const Color(0xFFFFE4D6),
    );

    // 5. Micro-action sparkles / chalk dust / thinking dots
    if (activeWrite) {
      for (var i = 0; i < 3; i++) {
        final angle = writingPhase * 12 + i * 2.1;
        final dist = 6.0 + (i * 2.5);
        final dotOffset = Offset(
          pointerTip.dx + math.cos(angle) * dist,
          pointerTip.dy + math.sin(angle) * dist,
        );
        canvas.drawCircle(
          dotOffset,
          1.4,
          Paint()
            ..color = _BlackboardPalette.accentWarm.withValues(alpha: 0.72),
        );
      }
    }
    if (isActing && emotion == NuoNuoExpression.celebrate && !manualWave) {
      final alpha = (1.0 - (actionProgress - 0.5).abs() * 1.4).clamp(0.0, 1.0);
      final starPaint = Paint()
        ..color = _BlackboardPalette.accentMint.withValues(alpha: alpha);
      canvas.drawCircle(Offset(w * 0.24, headRadius * 0.42), 2.3, starPaint);
      canvas.drawCircle(Offset(w * 0.92, headRadius * 0.35), 2.5, starPaint);
      canvas.drawCircle(
        Offset(w * 0.86, neckY - h * 0.06),
        2.0,
        Paint()
          ..color = _BlackboardPalette.accentWarm.withValues(alpha: alpha),
      );
    }
    if (emotion == NuoNuoExpression.thinking) {
      final dotBaseX = w * 0.84;
      final dotBaseY = headRadius * 0.36;
      for (var i = 0; i < 3; i++) {
        final dy = isActing
            ? -math.sin((actionProgress * 2 + i * 0.3) * math.pi).abs() * 3.0
            : 0.0;
        canvas.drawCircle(
          Offset(dotBaseX + i * 4.5, dotBaseY + dy - i * 1.5),
          1.6 + i * 0.2,
          Paint()
            ..color = _BlackboardPalette.accentWarm.withValues(alpha: 0.85),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TeacherBodyPainter oldDelegate) =>
      oldDelegate.headRadius != headRadius ||
      oldDelegate.writingPhase != writingPhase ||
      oldDelegate.emotion != emotion ||
      oldDelegate.actionProgress != actionProgress ||
      oldDelegate.isActing != isActing ||
      oldDelegate.manualWave != manualWave;
}

int _runeLen(String text) => text.runes.length;

String _takeRunes(String text, int count) {
  if (count <= 0) return '';
  final runes = text.runes;
  if (count >= runes.length) return text;
  return String.fromCharCodes(runes.take(count));
}

class _ChalkStepCard extends StatefulWidget {
  const _ChalkStepCard({
    required this.step,
    required this.animateWriteIn,
    required this.isSelected,
    required this.onTapSelect,
    required this.onAnswerCheckpoint,
    this.isCurrentActiveStep = false,
    this.feedbackBusy = false,
    this.onWritingPhaseChanged,
    this.onWritingProgress,
    this.onSubmitStepFeedback,
    this.onMarkUnderstood,
  });

  final BlackboardStep step;
  final bool animateWriteIn;
  final bool isSelected;
  final VoidCallback onTapSelect;
  final void Function(int? selection, {bool skip}) onAnswerCheckpoint;
  final bool isCurrentActiveStep;
  final bool feedbackBusy;
  final ValueChanged<double>? onWritingPhaseChanged;
  final VoidCallback? onWritingProgress;
  final Future<void> Function(String replyText, {bool isConfused})?
  onSubmitStepFeedback;
  final Future<void> Function()? onMarkUnderstood;

  @override
  State<_ChalkStepCard> createState() => _ChalkStepCardState();
}

class _ChalkStepCardState extends State<_ChalkStepCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  double _startRune = 0;
  int _targetRunes = 0;
  int _lastProgressRune = 0;
  bool _skipped = false;

  int _computeTotalRunes(BlackboardStep step) {
    var total = _runeLen(step.title);
    for (final line in step.lines) {
      total += _runeLen(line.text);
      if (line.latex != null && line.latex!.trim().isNotEmpty) {
        total += _runeLen(MathBlockView.formatReadableLatex(line.latex!));
      }
    }
    return math.max(1, total);
  }

  double get _currentRunePos =>
      _startRune + _ctrl.value * (_targetRunes - _startRune);

  void _syncWritingPhase() {
    widget.onWritingPhaseChanged?.call(_ctrl.isAnimating ? _ctrl.value : 0.0);
    if (_ctrl.isAnimating) {
      final cur = _currentRunePos.round();
      if ((cur - _lastProgressRune).abs() >= 14) {
        _lastProgressRune = cur;
        widget.onWritingProgress?.call();
      }
    }
  }

  void _startWriteAnimation(int fromRune, int toRune) {
    _startRune = fromRune.toDouble().clamp(0.0, toRune.toDouble());
    _lastProgressRune = _startRune.round();
    _targetRunes = toRune;
    final delta = math.max(0.0, _targetRunes - _startRune);
    if (delta < 0.5) {
      _ctrl.value = 1.0;
      _syncWritingPhase();
      return;
    }
    final ms = (delta * 18).round().clamp(120, 1400);
    _ctrl.duration = Duration(milliseconds: ms);
    _ctrl.forward(from: 0.0);
  }

  void _skipToEnd() {
    if (_skipped && _ctrl.value >= 1.0) return;
    setState(() {
      _skipped = true;
      _startRune = _targetRunes.toDouble();
      _lastProgressRune = _targetRunes;
      _ctrl.stop();
      _ctrl.value = 1.0;
      _syncWritingPhase();
    });
    widget.onWritingProgress?.call();
  }

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this)
      ..addListener(_syncWritingPhase)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed ||
            status == AnimationStatus.dismissed) {
          _syncWritingPhase();
          if (status == AnimationStatus.completed) {
            _lastProgressRune = _targetRunes;
            widget.onWritingProgress?.call();
          }
        }
      });
    _targetRunes = _computeTotalRunes(widget.step);
    if (!widget.animateWriteIn) {
      _startRune = _targetRunes.toDouble();
      _lastProgressRune = _targetRunes;
      _ctrl.value = 1.0;
    } else {
      _startWriteAnimation(0, _targetRunes);
    }
  }

  @override
  void didUpdateWidget(covariant _ChalkStepCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newTotal = _computeTotalRunes(widget.step);
    if (!widget.animateWriteIn) {
      _ctrl.stop();
      _startRune = newTotal.toDouble();
      _lastProgressRune = newTotal;
      _targetRunes = newTotal;
      _ctrl.value = 1.0;
      _syncWritingPhase();
      return;
    }
    if (oldWidget.step.id != widget.step.id) {
      _skipped = false;
      _startWriteAnimation(0, newTotal);
      return;
    }
    if (newTotal != _targetRunes) {
      if (_skipped) {
        _startRune = newTotal.toDouble();
        _lastProgressRune = newTotal;
        _targetRunes = newTotal;
        _ctrl.value = 1.0;
      } else if (newTotal > _targetRunes) {
        final cur = _currentRunePos.round().clamp(0, newTotal);
        _startWriteAnimation(cur, newTotal);
      } else {
        final cur = math.min(_currentRunePos.round(), newTotal);
        _startWriteAnimation(cur, newTotal);
      }
    }
  }

  @override
  void dispose() {
    widget.onWritingPhaseChanged?.call(0.0);
    _ctrl.removeListener(_syncWritingPhase);
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (_ctrl.isAnimating) {
          _skipToEnd();
        }
        widget.onTapSelect();
      },
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          final revealedRunes = widget.animateWriteIn
              ? _currentRunePos.ceil().clamp(0, _targetRunes)
              : _targetRunes;
          final stillWriting =
              widget.animateWriteIn &&
              !_skipped &&
              (_ctrl.isAnimating || revealedRunes < _targetRunes);

          var remaining = revealedRunes;
          final headerFull = widget.step.title;
          final headerLen = _runeLen(headerFull);
          final headerTake = remaining.clamp(0, headerLen);
          final headerStr = _takeRunes(headerFull, headerTake);
          final cursorInHeader =
              stillWriting && remaining > 0 && remaining <= headerLen;
          remaining = math.max(0, remaining - headerLen);

          final lineWidgets = <Widget>[];
          for (var i = 0; i < widget.step.lines.length; i++) {
            final line = widget.step.lines[i];
            if (remaining <= 0 && stillWriting) break;
            final textLen = _runeLen(line.text);
            final formulaStr =
                (line.latex != null && line.latex!.trim().isNotEmpty)
                ? MathBlockView.formatReadableLatex(line.latex!)
                : '';
            final formulaLen = _runeLen(formulaStr);
            final lineTotal = textLen + formulaLen;

            final lineTake = stillWriting
                ? remaining.clamp(0, lineTotal)
                : lineTotal;
            final showCursorHere =
                stillWriting && remaining > 0 && remaining <= lineTotal;
            remaining = math.max(0, remaining - lineTotal);

            lineWidgets.add(
              _ChalkLineView(
                line: line,
                visibleRunes: stillWriting ? lineTake : null,
                showCursor: showCursorHere,
              ),
            );
            if (i < widget.step.lines.length - 1) {
              lineWidgets.add(const SizedBox(height: 6));
            }
          }

          final showCheckpoint =
              widget.step.checkpoint != null &&
              (!stillWriting || widget.step.checkpoint!.isResolved);

          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
            decoration: BoxDecoration(
              color: widget.isSelected
                  ? const Color(0x18FFFFFF)
                  : const Color(0x0EFFFFFF),
              borderRadius: BorderRadius.circular(11),
              border: Border.all(
                color: widget.isSelected
                    ? _BlackboardPalette.activeBorder
                    : const Color(0x1EFFFFFF),
                width: widget.isSelected ? 1.2 : 0.9,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 22,
                      height: 22,
                      alignment: Alignment.center,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: const BoxDecoration(
                        color: _BlackboardPalette.accentWarmSoft,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${widget.step.stepNumber}',
                        style: InouTypography.tabular(
                          const TextStyle(
                            color: _BlackboardPalette.accentWarm,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          text: headerStr,
                          children: [
                            if (cursorInHeader)
                              const TextSpan(
                                text: ' ✎',
                                style: TextStyle(
                                  color: _BlackboardPalette.accentWarm,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                          ],
                        ),
                        style: const TextStyle(
                          color: _BlackboardPalette.chalkPrimary,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                if (lineWidgets.isNotEmpty) const SizedBox(height: 8),
                ...lineWidgets,
                if (showCheckpoint) ...[
                  const SizedBox(height: 8),
                  _BlackboardCheckpointCard(
                    checkpoint: widget.step.checkpoint!,
                    busy: widget.feedbackBusy,
                    onSelect: (idx) =>
                        widget.onAnswerCheckpoint(idx, skip: false),
                    onSubmitOpenReply: widget.onSubmitStepFeedback == null
                        ? null
                        : (replyText, {bool confused = false}) =>
                              widget.onSubmitStepFeedback!(
                                replyText,
                                isConfused: confused,
                              ),
                    onSkip: () => widget.onAnswerCheckpoint(null, skip: true),
                  ),
                ],
                if (widget.step.teacherReaction != null &&
                    widget.step.teacherReaction!.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _TeacherReactionCard(
                    studentNote: widget.step.studentFeedbackNote,
                    feedbackTag: widget.step.studentFeedbackTag,
                    teacherReaction: widget.step.teacherReaction!,
                  ),
                ],
                if (widget.step.checkpoint == null &&
                    widget.isCurrentActiveStep &&
                    !stillWriting &&
                    widget.step.studentFeedbackTag != 'understood' &&
                    (widget.onMarkUnderstood != null ||
                        widget.onSubmitStepFeedback != null)) ...[
                  const SizedBox(height: 8),
                  _StepFeedbackPulseBar(
                    busy: widget.feedbackBusy,
                    alreadyReplied: widget.step.studentFeedbackTag != null,
                    onMarkUnderstood: widget.onMarkUnderstood,
                    onSubmitFeedback: widget.onSubmitStepFeedback,
                    onLayoutChanged: widget.onWritingProgress,
                  ),
                ],
                for (var ni = 0; ni < widget.step.sideNotes.length; ni++) ...[
                  const SizedBox(height: 8),
                  _BlackboardSideNoteCard(
                    note: widget.step.sideNotes[ni],
                    animateWriteIn:
                        widget.animateWriteIn &&
                        ni == widget.step.sideNotes.length - 1,
                    onWritingProgress: widget.onWritingProgress,
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ChalkLineView extends StatelessWidget {
  const _ChalkLineView({
    required this.line,
    this.visibleRunes,
    this.showCursor = false,
  });

  final BlackboardLineItem line;
  final int? visibleRunes;
  final bool showCursor;

  @override
  Widget build(BuildContext context) {
    final isUnderline = line.annotation == ChalkAnnotationKind.underline;
    final isCalloutBox = line.annotation == ChalkAnnotationKind.box;
    final isWarn = line.annotation == ChalkAnnotationKind.warn;
    final isArrow = line.annotation == ChalkAnnotationKind.arrow;

    final Color textColor = isUnderline
        ? _BlackboardPalette.underlineText
        : (isCalloutBox || isWarn || isArrow
              ? _BlackboardPalette.chalkPrimary
              : Color(line.color.argb));

    final hasFormula = line.latex != null && line.latex!.trim().isNotEmpty;
    final readableFormula = hasFormula
        ? MathBlockView.formatReadableLatex(line.latex!)
        : '';

    final fullTextLen = _runeLen(line.text);
    final shownText = visibleRunes == null
        ? line.text
        : _takeRunes(line.text, visibleRunes!.clamp(0, fullTextLen));
    final remAfterText = visibleRunes == null
        ? _runeLen(readableFormula)
        : math.max(0, visibleRunes! - fullTextLen);
    final shownFormula = readableFormula.isEmpty
        ? ''
        : (visibleRunes == null
              ? readableFormula
              : _takeRunes(readableFormula, remAfterText));

    final cursorInText = showCursor && (visibleRunes ?? 0) <= fullTextLen;
    final cursorInFormula =
        showCursor && readableFormula.isNotEmpty && !cursorInText;

    final richText = Text.rich(
      TextSpan(
        text: shownText,
        children: [
          if (cursorInText)
            const TextSpan(
              text: ' ✎',
              style: TextStyle(
                color: _BlackboardPalette.accentWarm,
                fontWeight: FontWeight.w800,
              ),
            ),
        ],
      ),
      style: TextStyle(
        color: textColor,
        fontSize: 13.5,
        fontWeight: (isUnderline || isCalloutBox)
            ? FontWeight.w600
            : FontWeight.w400,
        height: 1.52,
      ),
    );

    final Widget textBlock;
    if (isUnderline) {
      textBlock = DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: _BlackboardPalette.underlineStroke,
              width: 1.8,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: richText,
        ),
      );
    } else if (isWarn) {
      textBlock = Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 6,
        runSpacing: 4,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
            decoration: BoxDecoration(
              color: _BlackboardPalette.accentBlushSoft,
              borderRadius: BorderRadius.circular(5),
            ),
            child: const Text(
              '小提醒',
              style: TextStyle(
                color: _BlackboardPalette.accentBlush,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          richText,
        ],
      );
    } else {
      textBlock = richText;
    }

    final content = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isArrow)
          const Padding(
            padding: EdgeInsets.only(top: 3, right: 5),
            child: Icon(
              Icons.subdirectory_arrow_right_rounded,
              size: 14,
              color: _BlackboardPalette.accentMint,
            ),
          ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (shownText.isNotEmpty || cursorInText) textBlock,
              if (shownFormula.isNotEmpty || cursorInFormula)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: _BlackboardPalette.calloutBg,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0x22FFFFFF)),
                    ),
                    child: SelectableText(
                      cursorInFormula ? '$shownFormula ✎' : shownFormula,
                      style: const TextStyle(
                        color: _BlackboardPalette.chalkPrimary,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );

    if (isCalloutBox || isWarn) {
      final ribbonColor = isWarn
          ? _BlackboardPalette.accentBlush
          : (line.color == ChalkColor.white
                ? _BlackboardPalette.accentMint
                : Color(line.color.argb));
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: _BlackboardPalette.calloutBg,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: ribbonColor.withValues(alpha: 0.25),
            width: 0.9,
          ),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 3,
                decoration: BoxDecoration(
                  color: ribbonColor,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(child: content),
            ],
          ),
        ),
      );
    }

    return content;
  }
}

class _BlackboardCheckpointCard extends StatefulWidget {
  const _BlackboardCheckpointCard({
    required this.checkpoint,
    required this.onSelect,
    required this.onSkip,
    this.onSubmitOpenReply,
    this.busy = false,
  });

  final BlackboardCheckpoint checkpoint;
  final ValueChanged<int> onSelect;
  final VoidCallback onSkip;
  final Future<void> Function(String replyText, {bool confused})?
  onSubmitOpenReply;
  final bool busy;

  @override
  State<_BlackboardCheckpointCard> createState() =>
      _BlackboardCheckpointCardState();
}

class _BlackboardCheckpointCardState extends State<_BlackboardCheckpointCard> {
  final TextEditingController _replyCtrl = TextEditingController();

  @override
  void dispose() {
    _replyCtrl.dispose();
    super.dispose();
  }

  Future<void> _submitReply({required bool confused}) async {
    final cb = widget.onSubmitOpenReply;
    if (cb == null || widget.busy) return;
    final text = _replyCtrl.text.trim();
    if (!confused && text.isEmpty) return;
    await cb(text, confused: confused);
    if (!mounted) return;
    if (confused ||
        widget.checkpoint.feedbackVerdict == 'correct' ||
        widget.checkpoint.feedbackVerdict == 'partial') {
      _replyCtrl.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cp = widget.checkpoint;
    final isOpen = cp.isOpenEnded;
    final answered = cp.answeredSelection;
    final isRightChoice = answered != null && answered == cp.correctIndex;
    final openVerdict = cp.feedbackVerdict;
    final openPositive =
        openVerdict == 'correct' || openVerdict == 'partial';

    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: _BlackboardPalette.overlayCardBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: cp.isResolved
              ? _BlackboardPalette.accentMint.withValues(alpha: 0.7)
              : _BlackboardPalette.softBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isOpen ? Icons.edit_note_rounded : Icons.quiz_outlined,
                size: 16,
                color: _BlackboardPalette.accentWarm,
              ),
              const SizedBox(width: 6),
              if (isOpen) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1.5,
                  ),
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(
                    color: _BlackboardPalette.accentWarmSoft,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    '轮到你试试',
                    style: TextStyle(
                      color: _BlackboardPalette.accentWarm,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
              Expanded(
                child: Text(
                  cp.prompt,
                  style: const TextStyle(
                    color: _BlackboardPalette.chalkPrimary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (!cp.isResolved)
                TextButton(
                  style: TextButton.styleFrom(
                    minimumSize: Size.zero,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 3,
                    ),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: widget.onSkip,
                  child: Text(
                    isOpen ? '跳过' : '跳过直接写下一步',
                    style: const TextStyle(
                      fontSize: 11,
                      color: _BlackboardPalette.chalkMuted,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (!isOpen) ...[
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (var i = 0; i < cp.options.length; i++)
                  Builder(
                    builder: (context) {
                      final selected = answered == i;
                      final correct = i == cp.correctIndex;
                      Color borderCol = _BlackboardPalette.softBorder;
                      Color bgCol = const Color(0x16FFFFFF);
                      if (selected && correct) {
                        borderCol = _BlackboardPalette.accentMint;
                        bgCol = _BlackboardPalette.accentMintSoft;
                      } else if (selected && !correct) {
                        borderCol = _BlackboardPalette.accentBlush;
                        bgCol = _BlackboardPalette.accentBlushSoft;
                      }
                      return OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _BlackboardPalette.chalkPrimary,
                          backgroundColor: bgCol,
                          side: BorderSide(color: borderCol),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                        ),
                        onPressed: () => widget.onSelect(i),
                        child: Text(
                          cp.options[i],
                          style: const TextStyle(fontSize: 12),
                        ),
                      );
                    },
                  ),
              ],
            ),
            if (answered != null) ...[
              const SizedBox(height: 8),
              Text(
                isRightChoice
                    ? '✓ ${cp.encouragement}'
                    : '再想想看～对照上面的重点提示再选一次吧！',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isRightChoice
                      ? _BlackboardPalette.accentMint
                      : _BlackboardPalette.accentBlush,
                ),
              ),
            ],
          ] else ...[
            if (!cp.isResolved && widget.onSubmitOpenReply != null) ...[
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 34,
                      child: TextField(
                        controller: _replyCtrl,
                        enabled: !widget.busy,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _submitReply(confused: false),
                        style: const TextStyle(
                          color: _BlackboardPalette.chalkPrimary,
                          fontSize: 12,
                        ),
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: '写下你的答案或想法…',
                          hintStyle: const TextStyle(
                            color: _BlackboardPalette.chalkMuted,
                            fontSize: 11.5,
                          ),
                          filled: true,
                          fillColor: const Color(0x280A1510),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(
                              color: _BlackboardPalette.softBorder,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(
                              color: _BlackboardPalette.softBorder,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(
                              color: _BlackboardPalette.accentWarm,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: _BlackboardPalette.primaryBtn,
                      foregroundColor: _BlackboardPalette.chalkPrimary,
                      minimumSize: const Size(0, 34),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 6,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: widget.busy
                        ? null
                        : () => _submitReply(confused: false),
                    child: widget.busy
                        ? const SizedBox(
                            width: 13,
                            height: 13,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: _BlackboardPalette.chalkPrimary,
                            ),
                          )
                        : const Text(
                            '提交',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                  const SizedBox(width: 5),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _BlackboardPalette.accentWarm,
                      side: BorderSide(
                        color: _BlackboardPalette.accentWarm.withValues(
                          alpha: 0.45,
                        ),
                      ),
                      minimumSize: const Size(0, 34),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 6,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: widget.busy
                        ? null
                        : () => _submitReply(confused: true),
                    child: const Text(
                      '有点懵',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (cp.studentReply != null &&
                cp.studentReply!.trim().isNotEmpty) ...[
              if (!cp.isResolved) const SizedBox(height: 8),
              Text(
                '你的作答：${cp.studentReply}',
                style: const TextStyle(
                  color: _BlackboardPalette.chalkMuted,
                  fontSize: 11.5,
                ),
              ),
            ],
            if (cp.teacherFeedback != null &&
                cp.teacherFeedback!.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 9,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: openPositive
                      ? _BlackboardPalette.accentMintSoft
                      : _BlackboardPalette.accentWarmSoft,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color:
                        (openPositive
                                ? _BlackboardPalette.accentMint
                                : _BlackboardPalette.accentWarm)
                            .withValues(alpha: 0.4),
                    width: 0.9,
                  ),
                ),
                child: Text(
                  '${openPositive ? "✓ 诺诺点评" : "诺诺提醒"}：${cp.teacherFeedback}',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.45,
                    fontWeight: FontWeight.w600,
                    color: openPositive
                        ? _BlackboardPalette.accentMint
                        : _BlackboardPalette.accentWarm,
                  ),
                ),
              ),
            ] else if (cp.skipped) ...[
              const Text(
                '已跳过这一步互动，继续跟着诺诺往下看～',
                style: TextStyle(
                  color: _BlackboardPalette.chalkMuted,
                  fontSize: 11.5,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _TeacherReactionCard extends StatelessWidget {
  const _TeacherReactionCard({
    required this.teacherReaction,
    this.studentNote,
    this.feedbackTag,
  });

  final String teacherReaction;
  final String? studentNote;
  final String? feedbackTag;

  @override
  Widget build(BuildContext context) {
    final isConfused = feedbackTag == 'confused';
    final accent = isConfused
        ? _BlackboardPalette.accentWarm
        : _BlackboardPalette.accentMint;
    final bg = isConfused
        ? _BlackboardPalette.accentWarmSoft
        : _BlackboardPalette.accentMintSoft;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: accent.withValues(alpha: 0.35), width: 0.9),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (studentNote != null && studentNote!.trim().isNotEmpty) ...[
            Text(
              '你的反馈：$studentNote',
              style: const TextStyle(
                color: _BlackboardPalette.chalkMuted,
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 3),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                margin: const EdgeInsets.only(right: 6, top: 1),
                decoration: BoxDecoration(
                  color: _BlackboardPalette.overlayCardBg,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '诺诺回应',
                  style: TextStyle(
                    color: accent,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  teacherReaction,
                  style: const TextStyle(
                    color: _BlackboardPalette.chalkPrimary,
                    fontSize: 12,
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StepFeedbackPulseBar extends StatefulWidget {
  const _StepFeedbackPulseBar({
    required this.busy,
    required this.alreadyReplied,
    this.onMarkUnderstood,
    this.onSubmitFeedback,
    this.onLayoutChanged,
  });

  final bool busy;
  final bool alreadyReplied;
  final Future<void> Function()? onMarkUnderstood;
  final Future<void> Function(String replyText, {bool isConfused})?
  onSubmitFeedback;
  final VoidCallback? onLayoutChanged;

  @override
  State<_StepFeedbackPulseBar> createState() => _StepFeedbackPulseBarState();
}

class _StepFeedbackPulseBarState extends State<_StepFeedbackPulseBar> {
  final TextEditingController _inputCtrl = TextEditingController();
  bool _inputOpen = false;

  @override
  void dispose() {
    _inputCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendReply() async {
    final cb = widget.onSubmitFeedback;
    if (cb == null || widget.busy) return;
    final text = _inputCtrl.text.trim();
    if (text.isEmpty) return;
    await cb(text, isConfused: false);
    if (!mounted) return;
    _inputCtrl.clear();
    setState(() => _inputOpen = false);
    widget.onLayoutChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0x16000000),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: _BlackboardPalette.hairline, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text(
                '这一步学得怎么样？',
                style: TextStyle(
                  color: _BlackboardPalette.chalkMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (widget.onMarkUnderstood != null)
                _FeedbackActionChip(
                  label: '听懂了 ✓',
                  accent: _BlackboardPalette.accentMint,
                  filled: false,
                  onTap: widget.busy ? null : widget.onMarkUnderstood,
                ),
              if (widget.onSubmitFeedback != null)
                _FeedbackActionChip(
                  label: widget.alreadyReplied ? '再答一句' : '试试回答',
                  accent: _BlackboardPalette.accentWarm,
                  filled: _inputOpen,
                  onTap: widget.busy
                      ? null
                      : () {
                          setState(() => _inputOpen = !_inputOpen);
                          widget.onLayoutChanged?.call();
                        },
                ),
              if (widget.onSubmitFeedback != null)
                _FeedbackActionChip(
                  label: '没太懂',
                  accent: _BlackboardPalette.accentBlush,
                  filled: false,
                  onTap: widget.busy
                      ? null
                      : () => widget.onSubmitFeedback!('', isConfused: true),
                ),
              if (widget.busy)
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.8,
                    color: _BlackboardPalette.accentWarm,
                  ),
                ),
            ],
          ),
          if (_inputOpen) ...[
            const SizedBox(height: 7),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 32,
                    child: TextField(
                      controller: _inputCtrl,
                      enabled: !widget.busy,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendReply(),
                      style: const TextStyle(
                        color: _BlackboardPalette.chalkPrimary,
                        fontSize: 11.5,
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: '说说你的答案、疑问或哪里卡住了…',
                        hintStyle: const TextStyle(
                          color: _BlackboardPalette.chalkMuted,
                          fontSize: 11,
                        ),
                        filled: true,
                        fillColor: const Color(0x280A1510),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 7,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(9),
                          borderSide: const BorderSide(
                            color: _BlackboardPalette.softBorder,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(9),
                          borderSide: const BorderSide(
                            color: _BlackboardPalette.softBorder,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(9),
                          borderSide: const BorderSide(
                            color: _BlackboardPalette.accentWarm,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _BlackboardPalette.primaryBtn,
                    foregroundColor: _BlackboardPalette.chalkPrimary,
                    minimumSize: const Size(0, 32),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(9),
                    ),
                  ),
                  onPressed: widget.busy ? null : _sendReply,
                  child: const Text(
                    '发给诺诺',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _FeedbackActionChip extends StatelessWidget {
  const _FeedbackActionChip({
    required this.label,
    required this.accent,
    required this.filled,
    this.onTap,
  });

  final String label;
  final Color accent;
  final bool filled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
        decoration: BoxDecoration(
          color: filled ? accent.withValues(alpha: 0.22) : const Color(0x14FFFFFF),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: accent.withValues(alpha: filled ? 0.75 : 0.45),
            width: 0.9,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: accent,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _BlackboardSideNoteCard extends StatefulWidget {
  const _BlackboardSideNoteCard({
    required this.note,
    this.animateWriteIn = false,
    this.onWritingProgress,
  });

  final BlackboardSideNote note;
  final bool animateWriteIn;
  final VoidCallback? onWritingProgress;

  @override
  State<_BlackboardSideNoteCard> createState() =>
      _BlackboardSideNoteCardState();
}

class _BlackboardSideNoteCardState extends State<_BlackboardSideNoteCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late int _totalRunes;
  int _lastProgressRune = 0;
  bool _skipped = false;

  int _countNoteRunes(BlackboardSideNote n) {
    var sum = _runeLen(n.spokenReply);
    for (final line in n.chalkLines) {
      sum += _runeLen(line.text);
      if (line.latex != null && line.latex!.trim().isNotEmpty) {
        sum += _runeLen(MathBlockView.formatReadableLatex(line.latex!));
      }
    }
    return math.max(1, sum);
  }

  void _handleWriteTick() {
    if (!_ctrl.isAnimating) return;
    final cur = (_ctrl.value * _totalRunes).ceil().clamp(0, _totalRunes);
    if ((cur - _lastProgressRune).abs() >= 14) {
      _lastProgressRune = cur;
      widget.onWritingProgress?.call();
    }
  }

  @override
  void initState() {
    super.initState();
    _totalRunes = _countNoteRunes(widget.note);
    _ctrl = AnimationController(
      vsync: this,
      duration: Duration(
        milliseconds: (_totalRunes * 18).clamp(180, 1200),
      ),
    )
      ..addListener(_handleWriteTick)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _lastProgressRune = _totalRunes;
          widget.onWritingProgress?.call();
        }
      });
    if (widget.animateWriteIn) {
      _ctrl.forward(from: 0);
    } else {
      _lastProgressRune = _totalRunes;
      _ctrl.value = 1.0;
    }
  }

  @override
  void dispose() {
    _ctrl.removeListener(_handleWriteTick);
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (_ctrl.isAnimating) {
          setState(() {
            _skipped = true;
            _ctrl.stop();
            _ctrl.value = 1.0;
          });
        }
      },
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          final stillWriting =
              widget.animateWriteIn && !_skipped && _ctrl.isAnimating;
          final revealed = stillWriting
              ? (_ctrl.value * _totalRunes).ceil().clamp(0, _totalRunes)
              : _totalRunes;
          final replyLen = _runeLen(widget.note.spokenReply);
          final shownReply = stillWriting
              ? _takeRunes(widget.note.spokenReply, revealed.clamp(0, replyLen))
              : widget.note.spokenReply;
          final cursorInReply = stillWriting && revealed <= replyLen;
          var rem = math.max(0, revealed - replyLen);

          return Padding(
            padding: const EdgeInsets.only(left: 8, top: 2),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _BlackboardPalette.sideNoteBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _BlackboardPalette.accentWarm.withValues(alpha: 0.25),
                  width: 0.9,
                ),
              ),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      width: 3.5,
                      decoration: BoxDecoration(
                        color: _BlackboardPalette.accentWarm,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: _BlackboardPalette.accentWarmSoft,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: const Text(
                                  '老师批注',
                                  style: TextStyle(
                                    color: _BlackboardPalette.accentWarm,
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  '「${widget.note.studentQuestion}」',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: _BlackboardPalette.chalkMuted,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text.rich(
                            TextSpan(
                              text: shownReply,
                              children: [
                                if (cursorInReply)
                                  const TextSpan(
                                    text: ' ✎',
                                    style: TextStyle(
                                      color: _BlackboardPalette.accentWarm,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                              ],
                            ),
                            style: const TextStyle(
                              color: _BlackboardPalette.chalkPrimary,
                              fontSize: 12.5,
                              height: 1.5,
                            ),
                          ),
                          if (widget.note.chalkLines.isNotEmpty) ...[
                            const Divider(
                              height: 12,
                              color: Color(0x1AFFFFFF),
                            ),
                            for (final line in widget.note.chalkLines)
                              if (!stillWriting || rem > 0) ...[
                                Builder(
                                  builder: (_) {
                                    final fLen =
                                        (line.latex != null &&
                                            line.latex!.trim().isNotEmpty)
                                        ? _runeLen(
                                            MathBlockView.formatReadableLatex(
                                              line.latex!,
                                            ),
                                          )
                                        : 0;
                                    final lTotal = _runeLen(line.text) + fLen;
                                    final take = stillWriting
                                        ? rem.clamp(0, lTotal)
                                        : lTotal;
                                    final cursorHere =
                                        stillWriting &&
                                        rem > 0 &&
                                        rem <= lTotal;
                                    rem = math.max(0, rem - lTotal);
                                    return Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: _ChalkLineView(
                                        line: line,
                                        visibleRunes: stillWriting ? take : null,
                                        showCursor: cursorHere,
                                      ),
                                    );
                                  },
                                ),
                              ],
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _BlackboardDiagramPanel extends StatelessWidget {
  const _BlackboardDiagramPanel({
    required this.diagram,
    required this.revealedStepIndex,
    required this.activeStepId,
    required this.highlightedByCircle,
  });

  final BlackboardDiagramSpec diagram;
  final int revealedStepIndex;
  final String? activeStepId;
  final bool highlightedByCircle;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0x28000000),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: highlightedByCircle
              ? Color(ChalkColor.pink.argb)
              : const Color(0x38FFFFFF),
          width: highlightedByCircle ? 1.8 : 1.0,
        ),
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.polyline_outlined,
                size: 15,
                color: Color(ChalkColor.blue.argb),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  diagram.title.isNotEmpty
                      ? diagram.title
                      : diagram.kind.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Color(ChalkColor.blue.argb),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '常驻动态示意图',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.65),
                  fontSize: 10.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Expanded(
            child: TweenAnimationBuilder<double>(
              key: ValueKey('diag_step_$revealedStepIndex'),
              tween: Tween<double>(begin: 0, end: 1),
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOut,
              builder: (context, animT, _) {
                return CustomPaint(
                  size: Size.infinite,
                  painter: _BlackboardDiagramPainter(
                    diagram: diagram,
                    revealedStepIndex: revealedStepIndex,
                    activeStepId: activeStepId,
                    animProgress: animT,
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

class _BlackboardDiagramPainter extends CustomPainter {
  const _BlackboardDiagramPainter({
    required this.diagram,
    required this.revealedStepIndex,
    required this.activeStepId,
    required this.animProgress,
  });

  final BlackboardDiagramSpec diagram;
  final int revealedStepIndex;
  final String? activeStepId;
  final double animProgress;

  Offset _toCanvas(BlackboardDiagramPoint p, Size size) {
    const pad = 18.0;
    final w = math.max(1.0, size.width - pad * 2);
    final h = math.max(1.0, size.height - pad * 2);
    return Offset(
      pad + (p.x.clamp(0, 100) / 100.0) * w,
      pad + (p.y.clamp(0, 100) / 100.0) * h,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    for (final el in diagram.elements) {
      if (el.appearAtStepIndex > revealedStepIndex) continue;
      final isNewlyAppeared =
          revealedStepIndex > 0 && el.appearAtStepIndex == revealedStepIndex;
      final alpha = isNewlyAppeared ? animProgress.clamp(0.15, 1.0) : 1.0;
      final isHighlighted =
          isNewlyAppeared ||
          (activeStepId != null &&
              el.highlightOnStepIds.contains(activeStepId));
      final baseColor = Color(el.color.argb).withValues(alpha: alpha);

      final paint = Paint()
        ..color = baseColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = isHighlighted ? 2.6 : 1.9
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      if (isHighlighted) {
        final glowPaint = Paint()
          ..color = baseColor.withValues(alpha: 0.25 * alpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6.0
          ..strokeCap = StrokeCap.round;
        _paintElementGeometry(canvas, size, el, glowPaint, drawLabels: false);
      }

      _paintElementGeometry(canvas, size, el, paint, drawLabels: true);
    }
  }

  void _paintElementGeometry(
    Canvas canvas,
    Size size,
    BlackboardDiagramElement el,
    Paint paint, {
    required bool drawLabels,
  }) {
    final pts = el.points.map((p) => _toCanvas(p, size)).toList();

    switch (el.type) {
      case 'axes':
        final origin = pts.isNotEmpty
            ? pts.first
            : _toCanvas(const BlackboardDiagramPoint(50, 56), size);
        final left = Offset(14, origin.dy);
        final right = Offset(size.width - 14, origin.dy);
        final bottom = Offset(origin.dx, size.height - 14);
        final top = Offset(origin.dx, 14);
        _drawArrow(canvas, left, right, paint);
        _drawArrow(canvas, bottom, top, paint);
        if (drawLabels) {
          _drawText(canvas, 'x', Offset(right.dx - 10, right.dy + 4), paint.color);
          _drawText(canvas, 'y', Offset(top.dx + 6, top.dy), paint.color);
          _drawText(
            canvas,
            el.points.firstOrNull?.label ?? 'O',
            Offset(origin.dx - 14, origin.dy + 4),
            paint.color,
          );
        }
      case 'segment':
        if (pts.length >= 2) {
          _drawSeg(canvas, pts[0], pts[1], paint, dashed: el.dashed);
          if (drawLabels && el.label != null) {
            final mid = Offset(
              (pts[0].dx + pts[1].dx) / 2,
              (pts[0].dy + pts[1].dy) / 2,
            );
            _drawText(canvas, el.label!, mid + const Offset(4, -14), paint.color);
          }
        }
      case 'polygon':
        if (pts.length >= 2) {
          for (var i = 0; i < pts.length; i++) {
            final a = pts[i];
            final b = pts[(i + 1) % pts.length];
            _drawSeg(canvas, a, b, paint, dashed: el.dashed);
          }
        }
      case 'circle':
        if (pts.isNotEmpty) {
          final r = ((el.radius ?? 16) / 100.0) *
              math.min(size.width, size.height);
          if (el.dashed) {
            const segs = 24;
            for (var i = 0; i < segs; i += 2) {
              final startAngle = (i / segs) * 2 * math.pi;
              const sweep = (1 / segs) * 2 * math.pi;
              canvas.drawArc(
                Rect.fromCircle(center: pts.first, radius: r),
                startAngle,
                sweep,
                false,
                paint,
              );
            }
          } else {
            canvas.drawCircle(pts.first, r, paint);
          }
          if (drawLabels && el.label != null) {
            _drawText(
              canvas,
              el.label!,
              pts.first + Offset(-16, -r - 16),
              paint.color,
            );
          }
        }
      case 'angle':
        if (pts.length >= 3) {
          final corner = pts[0];
          final p1 = pts[1];
          final p2 = pts[2];
          final cornerDiag = Offset(
            p1.dx + p2.dx - corner.dx,
            p1.dy + p2.dy - corner.dy,
          );
          canvas.drawLine(p1, cornerDiag, paint);
          canvas.drawLine(cornerDiag, p2, paint);
          if (drawLabels && el.label != null) {
            _drawText(
              canvas,
              el.label!,
              cornerDiag + const Offset(4, -12),
              paint.color,
            );
          }
        }
      case 'arrow':
        if (pts.length >= 2) {
          _drawArrow(canvas, pts[0], pts[1], paint, dashed: el.dashed);
          if (drawLabels && el.label != null) {
            _drawText(canvas, el.label!, pts[1] + const Offset(5, -8), paint.color);
          }
        }
      case 'curve':
        if (pts.length >= 2) {
          final path = Path()..moveTo(pts.first.dx, pts.first.dy);
          for (var i = 1; i < pts.length; i++) {
            final prev = pts[i - 1];
            final curr = pts[i];
            final midX = (prev.dx + curr.dx) / 2;
            final midY = (prev.dy + curr.dy) / 2;
            path.quadraticBezierTo(prev.dx, prev.dy, midX, midY);
          }
          path.lineTo(pts.last.dx, pts.last.dy);
          canvas.drawPath(path, paint);
          if (drawLabels && el.label != null) {
            _drawText(
              canvas,
              el.label!,
              pts.last + const Offset(-38, -14),
              paint.color,
            );
          }
        }
      case 'box':
        if (pts.length >= 2) {
          final rect = Rect.fromPoints(pts[0], pts[1]);
          canvas.drawRect(rect, paint);
          if (drawLabels && el.label != null) {
            _drawText(
              canvas,
              el.label!,
              rect.topLeft + const Offset(-6, -16),
              paint.color,
            );
          }
        }
      case 'point':
        for (final pt in pts) {
          canvas.drawCircle(
            pt,
            4.2,
            Paint()
              ..color = paint.color
              ..style = PaintingStyle.fill,
          );
        }
    }

    if (drawLabels) {
      for (var i = 0; i < el.points.length; i++) {
        final lbl = el.points[i].label;
        if (lbl != null && lbl.isNotEmpty && el.type != 'axes') {
          canvas.drawCircle(
            pts[i],
            3.0,
            Paint()
              ..color = paint.color
              ..style = PaintingStyle.fill,
          );
          _drawText(canvas, lbl, pts[i] + const Offset(4, -14), paint.color);
        }
      }
    }
  }

  void _drawSeg(
    Canvas canvas,
    Offset a,
    Offset b,
    Paint paint, {
    bool dashed = false,
  }) {
    if (!dashed) {
      canvas.drawLine(a, b, paint);
      return;
    }
    final dist = (b - a).distance;
    if (dist <= 0) return;
    final dir = (b - a) / dist;
    var pos = 0.0;
    const dash = 6.0;
    const gap = 4.0;
    while (pos < dist) {
      final end = math.min(pos + dash, dist);
      canvas.drawLine(a + dir * pos, a + dir * end, paint);
      pos = end + gap;
    }
  }

  void _drawArrow(
    Canvas canvas,
    Offset a,
    Offset b,
    Paint paint, {
    bool dashed = false,
  }) {
    _drawSeg(canvas, a, b, paint, dashed: dashed);
    final dir = b - a;
    final len = dir.distance;
    if (len < 6) return;
    final angle = math.atan2(dir.dy, dir.dx);
    const headLen = 9.0;
    const headAngle = 0.45;
    final p1 = Offset(
      b.dx - headLen * math.cos(angle - headAngle),
      b.dy - headLen * math.sin(angle - headAngle),
    );
    final p2 = Offset(
      b.dx - headLen * math.cos(angle + headAngle),
      b.dy - headLen * math.sin(angle + headAngle),
    );
    canvas.drawLine(b, p1, paint);
    canvas.drawLine(b, p2, paint);
  }

  void _drawText(Canvas canvas, String text, Offset offset, Color color) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          shadows: const [
            Shadow(color: Color(0xCC000000), blurRadius: 3),
          ],
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    tp.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _BlackboardDiagramPainter oldDelegate) {
    return oldDelegate.diagram != diagram ||
        oldDelegate.revealedStepIndex != revealedStepIndex ||
        oldDelegate.activeStepId != activeStepId ||
        oldDelegate.animProgress != animProgress;
  }
}

class _CircleGesturePainter extends CustomPainter {
  const _CircleGesturePainter({
    required this.points,
    required this.pendingRect,
  });

  final List<Offset> points;
  final Rect? pendingRect;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length >= 2) {
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (final p in points.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = _BlackboardPalette.accentBlush.withValues(alpha: 0.25)
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 9,
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = _BlackboardPalette.accentBlush
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 3,
      );
    }

    if (pendingRect != null) {
      canvas.drawRect(
        pendingRect!,
        Paint()
          ..color = _BlackboardPalette.accentBlush.withValues(alpha: 0.12)
          ..style = PaintingStyle.fill,
      );
      canvas.drawRect(
        pendingRect!,
        Paint()
          ..color = _BlackboardPalette.accentBlush
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CircleGesturePainter oldDelegate) {
    return oldDelegate.points.length != points.length ||
        oldDelegate.pendingRect != pendingRect;
  }
}
