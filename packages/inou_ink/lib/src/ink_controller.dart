import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'ink_models.dart';

/// Stateful controller coordinating handwritten ink capture, undo/redo,
/// palm-rejection, region anchoring, and lasso selection.
class InkController extends ChangeNotifier {
  InkController({
    InkPageData? initialPage,
    this.paperPreset = PaperSizePreset.a4,
    bool fingerDrawEnabled = true,
    PaperBackgroundKind backgroundKind = PaperBackgroundKind.dotted,
    int palmProtectionWindowMs = 2000,
  }) : _page =
           initialPage ??
           InkPageData(pageW: paperPreset.width, pageH: paperPreset.height),
       palmRejection = PalmRejectionStateMachine(
         protectionWindowMs: palmProtectionWindowMs,
       ) {
    _fingerDrawEnabled = fingerDrawEnabled;
    _backgroundKind = backgroundKind;
  }

  final PaperSizePreset paperPreset;
  final InkCommandStack _commands = InkCommandStack();
  final PalmRejectionStateMachine palmRejection;

  InkPageData _page;
  InkToolKind _activeTool = InkToolKind.pen;
  int _colorArgb = 0xFF1E293B;
  double _penWidth = 2.4;
  double _highlighterWidth = 14.0;
  final double _eraserRadius = 14.0;
  late bool _fingerDrawEnabled;
  late PaperBackgroundKind _backgroundKind;

  int? _activePointerId;
  String? _activeRegionId;
  final List<InkPoint> _activePoints = <InkPoint>[];
  Offset? _eraserCursor;
  bool _erasedDuringGesture = false;
  Offset? _lassoStart;
  Rect? _lassoRect;
  List<InkStroke> _lassoSelectedStrokes = const [];
  int _committedRevision = 0;
  int _strokeSeq = 0;

  InkPageData get page => _page;
  InkToolKind get activeTool => _activeTool;
  int get colorArgb => _colorArgb;
  double get penWidth => _penWidth;
  double get highlighterWidth => _highlighterWidth;
  double get eraserRadius => _eraserRadius;
  bool get fingerDrawEnabled => _fingerDrawEnabled;
  PaperBackgroundKind get backgroundKind => _backgroundKind;
  bool get canUndo => _commands.canUndo;
  bool get canRedo => _commands.canRedo;
  int get committedRevision => _committedRevision;
  bool get isStylusProtectionActive => palmRejection.isStylusProtectionActive(
    DateTime.now().millisecondsSinceEpoch,
  );

  Rect? get lassoRect => _lassoRect;
  List<InkStroke> get lassoSelectedStrokes => _lassoSelectedStrokes;
  Offset? get eraserCursor => _eraserCursor;

  InkStroke? get activeLiveStroke {
    if (_activePoints.isEmpty ||
        (_activeTool != InkToolKind.pen &&
            _activeTool != InkToolKind.highlighter)) {
      return null;
    }
    return InkStroke(
      id: '_live',
      tool: _activeTool,
      colorArgb: _activeTool == InkToolKind.highlighter
          ? ((0x58 << 24) | (_colorArgb & 0x00FFFFFF))
          : _colorArgb,
      width: _activeTool == InkToolKind.highlighter
          ? _highlighterWidth
          : _penWidth,
      points: List<InkPoint>.unmodifiable(_activePoints),
      regionId: _activeRegionId,
    );
  }

  void setTool(InkToolKind tool) {
    if (_activeTool == tool) return;
    _activeTool = tool;
    if (tool != InkToolKind.lasso) {
      _lassoRect = null;
      _lassoSelectedStrokes = const [];
    }
    notifyListeners();
  }

  void setColorArgb(int colorArgb) {
    if (_colorArgb == colorArgb) return;
    _colorArgb = colorArgb;
    notifyListeners();
  }

  void setPenWidth(double width) {
    _penWidth = width.clamp(0.8, 12.0);
    notifyListeners();
  }

  void setHighlighterWidth(double width) {
    _highlighterWidth = width.clamp(6.0, 32.0);
    notifyListeners();
  }

  void setFingerDrawEnabled(bool enabled) {
    if (_fingerDrawEnabled == enabled) return;
    _fingerDrawEnabled = enabled;
    notifyListeners();
  }

  void setBackgroundKind(PaperBackgroundKind kind) {
    if (_backgroundKind == kind) return;
    _backgroundKind = kind;
    _committedRevision++;
    notifyListeners();
  }

  void loadPage(InkPageData nextPage, {bool clearHistory = true}) {
    _page = nextPage;
    if (clearHistory) _commands.clear();
    _lassoRect = null;
    _lassoSelectedStrokes = const [];
    _committedRevision++;
    notifyListeners();
  }

  bool handlePointerDown({
    required int pointerId,
    required PointerDeviceKind kind,
    required Offset logicalPosition,
    required double pressure,
    String? regionId,
    int? timestampMs,
  }) {
    final now = timestampMs ?? DateTime.now().millisecondsSinceEpoch;
    if (!palmRejection.shouldAcceptPointer(
      kind: kind,
      fingerDrawEnabled: _fingerDrawEnabled,
      nowMs: now,
    )) {
      return false;
    }

    _activePointerId = pointerId;
    _activeRegionId = regionId;

    switch (_activeTool) {
      case InkToolKind.pen:
      case InkToolKind.highlighter:
        _lassoRect = null;
        _lassoSelectedStrokes = const [];
        _activePoints
          ..clear()
          ..add(
            InkPoint(
              x: logicalPosition.dx,
              y: logicalPosition.dy,
              pressure: pressure <= 0 ? 0.5 : pressure,
              tMs: now,
            ),
          );
      case InkToolKind.eraser:
        _eraserCursor = logicalPosition;
        _erasedDuringGesture = false;
        _commands.recordBeforeMutation(_page);
        final after = _page.eraseStrokesNear(
          logicalPosition,
          radius: _eraserRadius,
        );
        if (!identical(after, _page)) {
          _page = after;
          _erasedDuringGesture = true;
          _committedRevision++;
        }
      case InkToolKind.lasso:
        _lassoStart = logicalPosition;
        _lassoRect = Rect.fromPoints(logicalPosition, logicalPosition);
        _lassoSelectedStrokes = const [];
    }

    notifyListeners();
    return true;
  }

  void handlePointerMove({
    required int pointerId,
    required Offset logicalPosition,
    required double pressure,
    int? timestampMs,
  }) {
    if (_activePointerId != pointerId) return;
    final now = timestampMs ?? DateTime.now().millisecondsSinceEpoch;

    switch (_activeTool) {
      case InkToolKind.pen:
      case InkToolKind.highlighter:
        if (_activePoints.isNotEmpty) {
          final last = _activePoints.last;
          final dist = (logicalPosition - last.offset).distance;
          if (dist < 0.75) return;
        }
        _activePoints.add(
          InkPoint(
            x: logicalPosition.dx,
            y: logicalPosition.dy,
            pressure: pressure <= 0 ? 0.5 : pressure,
            tMs: now,
          ),
        );
      case InkToolKind.eraser:
        _eraserCursor = logicalPosition;
        final after = _page.eraseStrokesNear(
          logicalPosition,
          radius: _eraserRadius,
        );
        if (!identical(after, _page)) {
          _page = after;
          _erasedDuringGesture = true;
          _committedRevision++;
        }
      case InkToolKind.lasso:
        final start = _lassoStart ?? logicalPosition;
        _lassoRect = Rect.fromPoints(start, logicalPosition);
    }

    notifyListeners();
  }

  void handlePointerUp({required int pointerId}) {
    if (_activePointerId != pointerId) return;
    _activePointerId = null;

    switch (_activeTool) {
      case InkToolKind.pen:
      case InkToolKind.highlighter:
        if (_activePoints.isNotEmpty) {
          _commands.recordBeforeMutation(_page);
          final stroke = InkStroke(
            id: 'stk_${DateTime.now().microsecondsSinceEpoch}_${_strokeSeq++}',
            tool: _activeTool,
            colorArgb: _activeTool == InkToolKind.highlighter
                ? ((0x58 << 24) | (_colorArgb & 0x00FFFFFF))
                : _colorArgb,
            width: _activeTool == InkToolKind.highlighter
                ? _highlighterWidth
                : _penWidth,
            points: List<InkPoint>.unmodifiable(_activePoints),
            regionId: _activeRegionId,
          );
          _page = _page.addStroke(stroke);
          _activePoints.clear();
          _committedRevision++;
        }
      case InkToolKind.eraser:
        _eraserCursor = null;
        if (!_erasedDuringGesture) {
          // Discard no-op eraser snapshot by popping from undo if needed
          _commands.undo(_page);
        }
      case InkToolKind.lasso:
        final rect = _lassoRect;
        if (rect != null && (rect.width > 6 || rect.height > 6)) {
          _lassoSelectedStrokes = _page.strokesIntersectingRect(rect);
        } else {
          _lassoRect = null;
          _lassoSelectedStrokes = const [];
        }
    }

    _activeRegionId = null;
    notifyListeners();
  }

  void handlePointerCancel({required int pointerId}) {
    if (_activePointerId != pointerId) return;
    _activePointerId = null;
    _activeRegionId = null;
    _activePoints.clear();
    _eraserCursor = null;
    notifyListeners();
  }

  void addProgrammaticStroke(InkStroke stroke) {
    _commands.recordBeforeMutation(_page);
    _page = _page.addStroke(stroke);
    _committedRevision++;
    notifyListeners();
  }

  void clearLasso() {
    _lassoRect = null;
    _lassoSelectedStrokes = const [];
    notifyListeners();
  }

  void deleteLassoSelection() {
    if (_lassoSelectedStrokes.isEmpty) {
      clearLasso();
      return;
    }
    _commands.recordBeforeMutation(_page);
    _page = _page.removeStrokesByIds(
      _lassoSelectedStrokes.map((s) => s.id).toSet(),
    );
    _lassoRect = null;
    _lassoSelectedStrokes = const [];
    _committedRevision++;
    notifyListeners();
  }

  void shiftRegions(Set<String> regionIds, double deltaY) {
    if (deltaY == 0 || regionIds.isEmpty) return;
    final after = _page.shiftStrokesForRegions(regionIds, deltaY);
    if (!identical(after, _page)) {
      _commands.recordBeforeMutation(_page);
      _page = after;
      _committedRevision++;
      notifyListeners();
    }
  }

  void clearRegion(String regionId) {
    final ids = _page.strokes
        .where((s) => s.regionId == regionId)
        .map((s) => s.id)
        .toSet();
    if (ids.isEmpty) return;
    _commands.recordBeforeMutation(_page);
    _page = _page.removeStrokesByIds(ids);
    _committedRevision++;
    notifyListeners();
  }

  void clearAll() {
    if (_page.strokes.isEmpty) return;
    _commands.recordBeforeMutation(_page);
    _page = InkPageData(pageW: _page.pageW, pageH: _page.pageH);
    _lassoRect = null;
    _lassoSelectedStrokes = const [];
    _committedRevision++;
    notifyListeners();
  }

  bool undo() {
    final prev = _commands.undo(_page);
    if (prev == null) return false;
    _page = prev;
    _lassoRect = null;
    _lassoSelectedStrokes = const [];
    _committedRevision++;
    notifyListeners();
    return true;
  }

  bool redo() {
    final next = _commands.redo(_page);
    if (next == null) return false;
    _page = next;
    _lassoRect = null;
    _lassoSelectedStrokes = const [];
    _committedRevision++;
    notifyListeners();
    return true;
  }
}
