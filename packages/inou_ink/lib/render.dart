import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'src/ink_controller.dart';
import 'src/ink_models.dart';

/// Shared stroke smooth-path drawing helper used by both [InouInkCanvas] and
/// [InkSnapshotExporter].
abstract final class InkStrokePainterHelper {
  static void paintStroke(
    Canvas canvas,
    InkStroke stroke, {
    double scale = 1.0,
    bool highlighted = false,
  }) {
    if (stroke.points.isEmpty) return;

    final color = Color(stroke.colorArgb);
    final isHighlighter = stroke.tool == InkToolKind.highlighter;
    final paint = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..blendMode = isHighlighter ? BlendMode.multiply : BlendMode.srcOver
      ..strokeWidth = stroke.width * scale;

    if (stroke.points.length == 1) {
      final p = stroke.points.first;
      canvas.drawCircle(
        Offset(p.x * scale, p.y * scale),
        (stroke.width * scale) / 2,
        paint..style = PaintingStyle.fill,
      );
      return;
    }

    final path = Path();
    final first = stroke.points.first;
    path.moveTo(first.x * scale, first.y * scale);
    for (var i = 1; i < stroke.points.length; i++) {
      final prev = stroke.points[i - 1];
      final curr = stroke.points[i];
      final midX = ((prev.x + curr.x) * 0.5) * scale;
      final midY = ((prev.y + curr.y) * 0.5) * scale;
      path.quadraticBezierTo(prev.x * scale, prev.y * scale, midX, midY);
    }
    final last = stroke.points.last;
    path.lineTo(last.x * scale, last.y * scale);

    if (highlighted) {
      final glowPaint = Paint()
        ..color = const Color(0x553F6AF5)
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke
        ..strokeWidth = (stroke.width + 6) * scale;
      canvas.drawPath(path, glowPaint);
    }
    canvas.drawPath(path, paint);
  }

  static void paintPaperBackground(
    Canvas canvas,
    Size size, {
    required PaperBackgroundKind kind,
    double scale = 1.0,
    bool darkSurface = false,
  }) {
    if (kind == PaperBackgroundKind.blank) return;
    final step = 24.0 * scale;
    final ruleColor = darkSurface
        ? const Color(0x18FFFFFF)
        : const Color(0x180F172A);
    final paint = Paint()
      ..color = ruleColor
      ..strokeWidth = 0.8;

    switch (kind) {
      case PaperBackgroundKind.blank:
        return;
      case PaperBackgroundKind.lined:
        for (var y = step; y < size.height; y += step) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
        }
      case PaperBackgroundKind.grid:
        for (var y = step; y < size.height; y += step) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
        }
        for (var x = step; x < size.width; x += step) {
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
        }
      case PaperBackgroundKind.dotted:
        final dotPaint = Paint()
          ..color = darkSurface
              ? const Color(0x2EFFFFFF)
              : const Color(0x280F172A)
          ..style = PaintingStyle.fill;
        for (var y = step; y < size.height; y += step) {
          for (var x = step; x < size.width; x += step) {
            canvas.drawCircle(Offset(x, y), 0.9, dotPaint);
          }
        }
    }
  }
}

/// High-performance two-layer handwritten canvas with static committed ink cache
/// and lightweight live stroke / lasso overlay.
class InouInkCanvas extends StatefulWidget {
  const InouInkCanvas({
    super.key,
    required this.controller,
    this.scale = 1.0,
    this.darkSurface = false,
    this.paintBackground = true,
    this.readOnly = false,
    this.regionResolver,
    this.onLassoCompleted,
  });

  final InkController controller;
  final double scale;
  final bool darkSurface;
  final bool paintBackground;
  final bool readOnly;
  final String? Function(Offset logicalPosition)? regionResolver;
  final void Function(Rect logicalRect, List<InkStroke> selected)?
  onLassoCompleted;

  @override
  State<InouInkCanvas> createState() => _InouInkCanvasState();
}

class _InouInkCanvasState extends State<InouInkCanvas> {
  Rect? _lastNotifiedLasso;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleControllerChanged);
  }

  @override
  void didUpdateWidget(covariant InouInkCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleControllerChanged);
      widget.controller.addListener(_handleControllerChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChanged);
    super.dispose();
  }

  void _handleControllerChanged() {
    final rect = widget.controller.lassoRect;
    if (rect != _lastNotifiedLasso &&
        widget.controller.activeTool == InkToolKind.lasso &&
        widget.controller.activeLiveStroke == null &&
        rect != null &&
        widget.controller.lassoSelectedStrokes.isNotEmpty) {
      _lastNotifiedLasso = rect;
      widget.onLassoCompleted?.call(
        rect,
        widget.controller.lassoSelectedStrokes,
      );
    } else if (rect == null) {
      _lastNotifiedLasso = null;
    }
  }

  Offset _toLogical(Offset localPos) {
    final s = widget.scale <= 0 ? 1.0 : widget.scale;
    return Offset(localPos.dx / s, localPos.dy / s);
  }

  @override
  Widget build(BuildContext context) {
    final size = Size(
      widget.controller.page.pageW * widget.scale,
      widget.controller.page.pageH * widget.scale,
    );

    final layers = ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final selectedIds = widget.controller.lassoSelectedStrokes
            .map((s) => s.id)
            .toSet();
        return SizedBox(
          width: size.width,
          height: size.height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              RepaintBoundary(
                child: CustomPaint(
                  size: size,
                  painter: _CommittedInkPainter(
                    page: widget.controller.page,
                    revision: widget.controller.committedRevision,
                    backgroundKind: widget.controller.backgroundKind,
                    paintBackground: widget.paintBackground,
                    darkSurface: widget.darkSurface,
                    scale: widget.scale,
                    selectedStrokeIds: selectedIds,
                  ),
                ),
              ),
              CustomPaint(
                size: size,
                painter: _LiveInkPainter(
                  liveStroke: widget.controller.activeLiveStroke,
                  eraserCursor: widget.controller.eraserCursor,
                  eraserRadius: widget.controller.eraserRadius,
                  lassoRect: widget.controller.lassoRect,
                  scale: widget.scale,
                ),
              ),
            ],
          ),
        );
      },
    );

    if (widget.readOnly) {
      return IgnorePointer(child: layers);
    }

    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (event) {
        final logical = _toLogical(event.localPosition);
        widget.controller.handlePointerDown(
          pointerId: event.pointer,
          kind: event.kind,
          logicalPosition: logical,
          pressure: event.pressure,
          regionId: widget.regionResolver?.call(logical),
        );
      },
      onPointerMove: (event) {
        widget.controller.handlePointerMove(
          pointerId: event.pointer,
          logicalPosition: _toLogical(event.localPosition),
          pressure: event.pressure,
        );
      },
      onPointerUp: (event) {
        widget.controller.handlePointerUp(pointerId: event.pointer);
      },
      onPointerCancel: (event) {
        widget.controller.handlePointerCancel(pointerId: event.pointer);
      },
      child: layers,
    );
  }
}

class _CommittedInkPainter extends CustomPainter {
  const _CommittedInkPainter({
    required this.page,
    required this.revision,
    required this.backgroundKind,
    required this.paintBackground,
    required this.darkSurface,
    required this.scale,
    required this.selectedStrokeIds,
  });

  final InkPageData page;
  final int revision;
  final PaperBackgroundKind backgroundKind;
  final bool paintBackground;
  final bool darkSurface;
  final double scale;
  final Set<String> selectedStrokeIds;

  @override
  void paint(Canvas canvas, Size size) {
    if (paintBackground) {
      InkStrokePainterHelper.paintPaperBackground(
        canvas,
        size,
        kind: backgroundKind,
        scale: scale,
        darkSurface: darkSurface,
      );
    }
    for (final stroke in page.strokes) {
      InkStrokePainterHelper.paintStroke(
        canvas,
        stroke,
        scale: scale,
        highlighted: selectedStrokeIds.contains(stroke.id),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CommittedInkPainter oldDelegate) {
    return oldDelegate.revision != revision ||
        oldDelegate.backgroundKind != backgroundKind ||
        oldDelegate.darkSurface != darkSurface ||
        oldDelegate.scale != scale ||
        !_setEquals(oldDelegate.selectedStrokeIds, selectedStrokeIds);
  }

  static bool _setEquals(Set<String> a, Set<String> b) {
    if (a.length != b.length) return false;
    return a.containsAll(b);
  }
}

class _LiveInkPainter extends CustomPainter {
  const _LiveInkPainter({
    required this.liveStroke,
    required this.eraserCursor,
    required this.eraserRadius,
    required this.lassoRect,
    required this.scale,
  });

  final InkStroke? liveStroke;
  final Offset? eraserCursor;
  final double eraserRadius;
  final Rect? lassoRect;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    if (liveStroke != null) {
      InkStrokePainterHelper.paintStroke(canvas, liveStroke!, scale: scale);
    }
    if (eraserCursor != null) {
      final c = Offset(eraserCursor!.dx * scale, eraserCursor!.dy * scale);
      final r = eraserRadius * scale;
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..color = const Color(0x33EF4444)
          ..style = PaintingStyle.fill,
      );
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..color = const Color(0xFFEF4444)
          ..strokeWidth = 1.2
          ..style = PaintingStyle.stroke,
      );
    }
    if (lassoRect != null) {
      final scaled = Rect.fromLTRB(
        lassoRect!.left * scale,
        lassoRect!.top * scale,
        lassoRect!.right * scale,
        lassoRect!.bottom * scale,
      );
      canvas.drawRect(
        scaled,
        Paint()
          ..color = const Color(0x183F6AF5)
          ..style = PaintingStyle.fill,
      );
      _drawDashedRect(canvas, scaled);
    }
  }

  void _drawDashedRect(Canvas canvas, Rect rect) {
    final paint = Paint()
      ..color = const Color(0xFF3F6AF5)
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;
    const dash = 6.0;
    const gap = 4.0;
    void drawSeg(Offset a, Offset b) {
      final dist = (b - a).distance;
      if (dist <= 0) return;
      final dir = (b - a) / dist;
      var pos = 0.0;
      while (pos < dist) {
        final end = math.min(pos + dash, dist);
        canvas.drawLine(a + dir * pos, a + dir * end, paint);
        pos = end + gap;
      }
    }

    drawSeg(rect.topLeft, rect.topRight);
    drawSeg(rect.topRight, rect.bottomRight);
    drawSeg(rect.bottomRight, rect.bottomLeft);
    drawSeg(rect.bottomLeft, rect.topLeft);
  }

  @override
  bool shouldRepaint(covariant _LiveInkPainter oldDelegate) {
    return oldDelegate.liveStroke != liveStroke ||
        oldDelegate.eraserCursor != eraserCursor ||
        oldDelegate.lassoRect != lassoRect ||
        oldDelegate.scale != scale;
  }
}

/// Renders handwritten strokes (optionally cropped to a [cropRect]) into PNG
/// bytes suitable for multimodal VLM judging or NuoNuo lasso tutoring.
abstract final class InkSnapshotExporter {
  static Future<Uint8List?> exportRegionPng(
    InkPageData page, {
    Rect? cropRect,
    double pixelRatio = 2.0,
    int backgroundColorArgb = 0xFFFFFFFF,
  }) async {
    final region = cropRect ?? Rect.fromLTWH(0, 0, page.pageW, page.pageH);
    final w = math.max(1, (region.width * pixelRatio).round());
    final h = math.max(1, (region.height * pixelRatio).round());

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      Paint()..color = Color(backgroundColorArgb),
    );

    canvas.save();
    canvas.scale(pixelRatio);
    canvas.translate(-region.left, -region.top);
    for (final stroke in page.strokes) {
      if (stroke.bounds.overlaps(region)) {
        InkStrokePainterHelper.paintStroke(canvas, stroke);
      }
    }
    canvas.restore();

    final picture = recorder.endRecording();
    final image = await picture.toImage(w, h);
    try {
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }
}
