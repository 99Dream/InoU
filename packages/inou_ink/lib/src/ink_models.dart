import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

/// Writing tools available in paper handwriting mode.
enum InkToolKind { pen, highlighter, eraser, lasso }

/// Background paper rulings rendered beneath handwritten strokes.
enum PaperBackgroundKind {
  blank('blank', '空白'),
  lined('lined', '横线'),
  grid('grid', '方格'),
  dotted('dotted', '点阵');

  const PaperBackgroundKind(this.code, this.label);
  final String code;
  final String label;

  static PaperBackgroundKind fromCode(String code) {
    return PaperBackgroundKind.values.firstWhere(
      (k) => k.code == code,
      orElse: () => PaperBackgroundKind.dotted,
    );
  }
}

/// Standard logical paper sizes (in points, matching PDF coordinates).
enum PaperSizePreset {
  a4(595, 842),
  b5(499, 709);

  const PaperSizePreset(this.width, this.height);

  final double width;
  final double height;
}

/// Single sampled pointer point in logical page coordinates.
@immutable
class InkPoint {
  const InkPoint({
    required this.x,
    required this.y,
    required this.pressure,
    required this.tMs,
    this.tilt = 0,
  });

  factory InkPoint.fromJson(Map<String, Object?> json) {
    return InkPoint(
      x: (json['x'] as num?)?.toDouble() ?? 0,
      y: (json['y'] as num?)?.toDouble() ?? 0,
      pressure: (json['p'] as num?)?.toDouble() ?? 0.5,
      tMs: (json['t'] as num?)?.toInt() ?? 0,
      tilt: (json['tilt'] as num?)?.toDouble() ?? 0,
    );
  }

  final double x;
  final double y;
  final double pressure;
  final int tMs;
  final double tilt;

  Offset get offset => Offset(x, y);

  InkPoint translate(double dx, double dy) =>
      InkPoint(x: x + dx, y: y + dy, pressure: pressure, tMs: tMs, tilt: tilt);

  Map<String, Object?> toJson() => {
    'x': double.parse(x.toStringAsFixed(2)),
    'y': double.parse(y.toStringAsFixed(2)),
    'p': double.parse(pressure.toStringAsFixed(3)),
    't': tMs,
    if (tilt != 0) 'tilt': double.parse(tilt.toStringAsFixed(3)),
  };
}

/// Immutable stroke stored on an ink page.
@immutable
class InkStroke {
  InkStroke({
    required this.id,
    required this.tool,
    required this.colorArgb,
    required this.width,
    required List<InkPoint> points,
    this.regionId,
  }) : points = List<InkPoint>.unmodifiable(points),
       bounds = _computeBounds(points, width);

  factory InkStroke.fromJson(Map<String, Object?> json) {
    final toolName = json['tool'] as String? ?? 'pen';
    final pts = (json['points'] as List<Object?>? ?? const [])
        .map((e) => InkPoint.fromJson(e! as Map<String, Object?>))
        .toList(growable: false);
    return InkStroke(
      id: json['id'] as String,
      tool: InkToolKind.values.firstWhere(
        (t) => t.name == toolName,
        orElse: () => InkToolKind.pen,
      ),
      colorArgb: (json['colorArgb'] as num?)?.toInt() ?? 0xFF1F2937,
      width: (json['width'] as num?)?.toDouble() ?? 2.4,
      points: pts,
      regionId: json['regionId'] as String?,
    );
  }

  final String id;
  final InkToolKind tool;
  final int colorArgb;
  final double width;
  final List<InkPoint> points;
  final String? regionId;
  final Rect bounds;

  InkStroke translate(double dx, double dy) {
    return InkStroke(
      id: id,
      tool: tool,
      colorArgb: colorArgb,
      width: width,
      points: points.map((p) => p.translate(dx, dy)).toList(growable: false),
      regionId: regionId,
    );
  }

  /// Distance squared from [point] to nearest polyline segment in this stroke.
  double minDistanceToPoint(Offset point) {
    if (points.isEmpty) return double.infinity;
    if (points.length == 1) {
      return (points.first.offset - point).distance;
    }
    var minDist = double.infinity;
    for (var i = 0; i < points.length - 1; i++) {
      final d = _distancePointToSegment(
        point,
        points[i].offset,
        points[i + 1].offset,
      );
      if (d < minDist) minDist = d;
    }
    return minDist;
  }

  static double _distancePointToSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final lenSq = ab.dx * ab.dx + ab.dy * ab.dy;
    if (lenSq <= 1e-9) return (p - a).distance;
    final t = (((p.dx - a.dx) * ab.dx + (p.dy - a.dy) * ab.dy) / lenSq).clamp(
      0.0,
      1.0,
    );
    final proj = Offset(a.dx + ab.dx * t, a.dy + ab.dy * t);
    return (p - proj).distance;
  }

  static Rect _computeBounds(List<InkPoint> points, double strokeWidth) {
    if (points.isEmpty) return Rect.zero;
    var minX = points.first.x;
    var maxX = points.first.x;
    var minY = points.first.y;
    var maxY = points.first.y;
    for (final p in points.skip(1)) {
      minX = math.min(minX, p.x);
      maxX = math.max(maxX, p.x);
      minY = math.min(minY, p.y);
      maxY = math.max(maxY, p.y);
    }
    final pad = strokeWidth / 2;
    return Rect.fromLTRB(minX - pad, minY - pad, maxX + pad, maxY + pad);
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'tool': tool.name,
    'colorArgb': colorArgb,
    'width': width,
    if (regionId != null) 'regionId': regionId,
    'points': points.map((p) => p.toJson()).toList(growable: false),
  };
}

/// Anchored answer-box or scratchpad region in logical paper coordinates.
@immutable
class InkRegion {
  const InkRegion({
    required this.id,
    required this.logicalRect,
    this.questionId,
    this.label = '',
  });

  final String id;
  final Rect logicalRect;
  final String? questionId;
  final String label;

  InkRegion copyWith({Rect? logicalRect, String? questionId, String? label}) {
    return InkRegion(
      id: id,
      logicalRect: logicalRect ?? this.logicalRect,
      questionId: questionId ?? this.questionId,
      label: label ?? this.label,
    );
  }
}

/// Collection of strokes belonging to one logical page.
@immutable
class InkPageData {
  const InkPageData({
    required this.pageW,
    required this.pageH,
    this.strokes = const [],
  });

  factory InkPageData.fromJson(Map<String, Object?> json) {
    final raw = json['strokes'] as List<Object?>? ?? const [];
    return InkPageData(
      pageW: (json['pageW'] as num?)?.toDouble() ?? PaperSizePreset.a4.width,
      pageH: (json['pageH'] as num?)?.toDouble() ?? PaperSizePreset.a4.height,
      strokes: raw
          .map((e) => InkStroke.fromJson(e! as Map<String, Object?>))
          .toList(growable: false),
    );
  }

  final double pageW;
  final double pageH;
  final List<InkStroke> strokes;

  InkPageData addStroke(InkStroke stroke) {
    return InkPageData(
      pageW: pageW,
      pageH: pageH,
      strokes: [...strokes, stroke],
    );
  }

  InkPageData removeStrokesByIds(Set<String> idsToRemove) {
    if (idsToRemove.isEmpty) return this;
    return InkPageData(
      pageW: pageW,
      pageH: pageH,
      strokes: strokes
          .where((s) => !idsToRemove.contains(s.id))
          .toList(growable: false),
    );
  }

  /// Erases strokes whose nearest point-to-segment distance is within [radius].
  InkPageData eraseStrokesNear(
    Offset point, {
    double radius = 12,
    String? regionId,
  }) {
    final remaining = <InkStroke>[];
    var changed = false;
    for (final s in strokes) {
      if (regionId != null && s.regionId != regionId) {
        remaining.add(s);
        continue;
      }
      final hitBounds = s.bounds.inflate(radius);
      if (!hitBounds.contains(point)) {
        remaining.add(s);
        continue;
      }
      final effectiveRadius = radius + s.width / 2;
      if (s.minDistanceToPoint(point) <= effectiveRadius) {
        changed = true;
      } else {
        remaining.add(s);
      }
    }
    if (!changed) return this;
    return InkPageData(pageW: pageW, pageH: pageH, strokes: remaining);
  }

  /// Vertically shifts all strokes anchored to or below [thresholdY] inside
  /// [regionId] (or strokes belonging to [regionId]) when an answer box expands.
  InkPageData shiftStrokesInRegion(String regionId, double deltaY) {
    if (deltaY == 0) return this;
    final next = strokes
        .map((s) => s.regionId == regionId ? s.translate(0, deltaY) : s)
        .toList(growable: false);
    return InkPageData(pageW: pageW, pageH: pageH, strokes: next);
  }

  /// Shifts strokes attached to any region whose `regionId` is in [regionIds].
  InkPageData shiftStrokesForRegions(Set<String> regionIds, double deltaY) {
    if (deltaY == 0 || regionIds.isEmpty) return this;
    final next = strokes
        .map((s) => regionIds.contains(s.regionId) ? s.translate(0, deltaY) : s)
        .toList(growable: false);
    return InkPageData(pageW: pageW, pageH: pageH, strokes: next);
  }

  List<InkStroke> strokesIntersectingRect(Rect rect) {
    return strokes
        .where(
          (s) =>
              s.bounds.overlaps(rect) &&
              s.points.any((p) => rect.contains(p.offset)),
        )
        .toList(growable: false);
  }

  Map<String, Object?> toJson() => {
    'pageW': pageW,
    'pageH': pageH,
    'strokes': strokes.map((s) => s.toJson()).toList(growable: false),
  };
}

/// Undo/Redo command snapshot stack for [InkPageData].
class InkCommandStack {
  InkCommandStack({this.maxHistory = 64});

  final int maxHistory;
  final List<InkPageData> _undo = <InkPageData>[];
  final List<InkPageData> _redo = <InkPageData>[];

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  void recordBeforeMutation(InkPageData previous) {
    _undo.add(previous);
    if (_undo.length > maxHistory) {
      _undo.removeAt(0);
    }
    _redo.clear();
  }

  InkPageData? undo(InkPageData current) {
    if (_undo.isEmpty) return null;
    final prev = _undo.removeLast();
    _redo.add(current);
    return prev;
  }

  InkPageData? redo(InkPageData current) {
    if (_redo.isEmpty) return null;
    final next = _redo.removeLast();
    _undo.add(current);
    return next;
  }

  void clear() {
    _undo.clear();
    _redo.clear();
  }
}

/// Line-delimited write-ahead log (WAL) serializer for low-overhead ink backup.
abstract final class InkWalCodec {
  static String encode(InkPageData page) {
    final buf = StringBuffer();
    buf.writeln(
      jsonEncode({'type': 'meta', 'pageW': page.pageW, 'pageH': page.pageH}),
    );
    for (final s in page.strokes) {
      buf.writeln(jsonEncode({'type': 'stroke', 'data': s.toJson()}));
    }
    return buf.toString();
  }

  static InkPageData decode(String walText) {
    var pageW = PaperSizePreset.a4.width;
    var pageH = PaperSizePreset.a4.height;
    final strokes = <InkStroke>[];
    for (final rawLine in walText.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      final obj = jsonDecode(line);
      if (obj is! Map) continue;
      final type = obj['type'];
      if (type == 'meta') {
        pageW = (obj['pageW'] as num?)?.toDouble() ?? pageW;
        pageH = (obj['pageH'] as num?)?.toDouble() ?? pageH;
      } else if (type == 'stroke' && obj['data'] is Map) {
        final data = (obj['data']! as Map).map(
          (k, v) => MapEntry(k.toString(), v),
        );
        strokes.add(InkStroke.fromJson(data));
      }
    }
    return InkPageData(pageW: pageW, pageH: pageH, strokes: strokes);
  }
}

/// Enforces stylus-first palm rejection with a configurable protection window
/// (default `2000ms` per architecture spec §11.3).
class PalmRejectionStateMachine {
  PalmRejectionStateMachine({this.protectionWindowMs = 2000});

  final int protectionWindowMs;
  int? _lastStylusMs;

  void recordStylusActivity(int timestampMs) {
    _lastStylusMs = timestampMs;
  }

  bool isStylusProtectionActive(int nowMs) {
    final last = _lastStylusMs;
    if (last == null) return false;
    return (nowMs - last) < protectionWindowMs;
  }

  /// Determines whether a pointer event of [kind] should be accepted for
  /// ink drawing. Stylus and mouse always pass; touch passes only when
  /// [fingerDrawEnabled] is `true` AND the stylus protection window has elapsed.
  bool shouldAcceptPointer({
    required PointerDeviceKind kind,
    required bool fingerDrawEnabled,
    required int nowMs,
  }) {
    if (kind == PointerDeviceKind.stylus ||
        kind == PointerDeviceKind.invertedStylus) {
      recordStylusActivity(nowMs);
      return true;
    }
    if (kind == PointerDeviceKind.mouse || kind == PointerDeviceKind.trackpad) {
      return !isStylusProtectionActive(nowMs);
    }
    if (kind == PointerDeviceKind.touch) {
      if (!fingerDrawEnabled) return false;
      return !isStylusProtectionActive(nowMs);
    }
    return false;
  }
}
