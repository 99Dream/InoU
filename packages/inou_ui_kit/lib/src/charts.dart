import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import 'inou_theme.dart';

/// Data point on a radar axis.
@immutable
class RadarAxisDatum {
  const RadarAxisDatum({required this.label, required this.value});

  final String label;

  /// Normalized value in `[0.0, 1.0]`.
  final double value;
}

/// Custom-painted minimalist N-axis mastery radar chart.
class InouRadarChart extends StatelessWidget {
  const InouRadarChart({
    super.key,
    required this.axes,
    this.size = 200,
    this.accentColor,
  });

  final List<RadarAxisDatum> axes;
  final double size;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final t = context.inou;
    if (axes.length < 3) {
      return SizedBox(
        width: size,
        height: size * 0.72,
        child: Center(
          child: Text(
            '累计作答 3 科以上后\n自动生成学科雷达图',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, height: 1.5, color: t.textMuted),
          ),
        ),
      );
    }
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RadarPainter(
          axes: axes,
          accent: accentColor ?? t.accent,
          ringColor: t.borderHairline,
          labelColor: t.textSecondary,
          valueColor: t.textPrimary,
        ),
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  const _RadarPainter({
    required this.axes,
    required this.accent,
    required this.ringColor,
    required this.labelColor,
    required this.valueColor,
  });

  final List<RadarAxisDatum> axes;
  final Color accent;
  final Color ringColor;
  final Color labelColor;
  final Color valueColor;

  @override
  void paint(Canvas canvas, Size size) {
    final n = axes.length;
    if (n < 3) return;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) * 0.34;

    final gridPaint = Paint()
      ..color = ringColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9;

    // 4 concentric rings (25%, 50%, 75%, 100%)
    for (var ring = 1; ring <= 4; ring++) {
      final r = radius * (ring / 4);
      final ringPath = Path();
      for (var i = 0; i < n; i++) {
        final angle = -math.pi / 2 + (2 * math.pi * i / n);
        final pt = Offset(
          center.dx + math.cos(angle) * r,
          center.dy + math.sin(angle) * r,
        );
        if (i == 0) {
          ringPath.moveTo(pt.dx, pt.dy);
        } else {
          ringPath.lineTo(pt.dx, pt.dy);
        }
      }
      ringPath.close();
      canvas.drawPath(ringPath, gridPaint);
    }

    // Spokes & vertex labels
    for (var i = 0; i < n; i++) {
      final angle = -math.pi / 2 + (2 * math.pi * i / n);
      final outer = Offset(
        center.dx + math.cos(angle) * radius,
        center.dy + math.sin(angle) * radius,
      );
      canvas.drawLine(center, outer, gridPaint);

      final labelPos = Offset(
        center.dx + math.cos(angle) * (radius + 22),
        center.dy + math.sin(angle) * (radius + 20),
      );
      final pct = '${(axes[i].value.clamp(0.0, 1.0) * 100).round()}%';
      final tp = TextPainter(
        text: TextSpan(
          text: '${axes[i].label}\n',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: labelColor,
            height: 1.15,
          ),
          children: [
            TextSpan(
              text: pct,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: valueColor,
              ),
            ),
          ],
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, labelPos - Offset(tp.width / 2, tp.height / 2));
    }

    // Filled data polygon
    final dataPath = Path();
    final vertices = <Offset>[];
    for (var i = 0; i < n; i++) {
      final angle = -math.pi / 2 + (2 * math.pi * i / n);
      final v = axes[i].value.clamp(0.05, 1.0);
      final pt = Offset(
        center.dx + math.cos(angle) * radius * v,
        center.dy + math.sin(angle) * radius * v,
      );
      vertices.add(pt);
      if (i == 0) {
        dataPath.moveTo(pt.dx, pt.dy);
      } else {
        dataPath.lineTo(pt.dx, pt.dy);
      }
    }
    dataPath.close();

    canvas.drawPath(
      dataPath,
      Paint()
        ..color = accent.withValues(alpha: 0.18)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      dataPath,
      Paint()
        ..color = accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0,
    );

    final dotPaint = Paint()
      ..color = accent
      ..style = PaintingStyle.fill;
    for (final v in vertices) {
      canvas.drawCircle(v, 3.2, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _RadarPainter old) {
    return old.axes != axes || old.accent != accent;
  }
}

/// Segment datum for [InouDonutChart].
@immutable
class DonutSliceDatum {
  const DonutSliceDatum({
    required this.label,
    required this.count,
    required this.color,
  });

  final String label;
  final int count;
  final Color color;
}

/// Minimalist error-distribution donut ring with interactive legend chips.
class InouDonutChart extends StatelessWidget {
  const InouDonutChart({
    super.key,
    required this.slices,
    this.centerLabel = '错题总计',
    this.ringSize = 132,
  });

  final List<DonutSliceDatum> slices;
  final String centerLabel;
  final double ringSize;

  @override
  Widget build(BuildContext context) {
    final t = context.inou;
    final total = slices.fold<int>(0, (acc, s) => acc + s.count);
    return Row(
      children: [
        SizedBox(
          width: ringSize,
          height: ringSize,
          child: CustomPaint(
            painter: _DonutPainter(slices: slices, trackColor: t.surfaceMuted),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$total',
                    style: InouTypography.tabular(
                      TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: t.textPrimary,
                      ),
                    ),
                  ),
                  Text(
                    centerLabel,
                    style: TextStyle(fontSize: 10.5, color: t.textMuted),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              for (final s in slices)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: s.color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${s.label} · ${s.count}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: t.textSecondary,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DonutPainter extends CustomPainter {
  const _DonutPainter({required this.slices, required this.trackColor});

  final List<DonutSliceDatum> slices;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    const strokeW = 14.0;
    final radius = (math.min(size.width, size.height) - strokeW) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    canvas.drawArc(
      rect,
      0,
      2 * math.pi,
      false,
      Paint()
        ..color = trackColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeW,
    );

    final total = slices.fold<int>(0, (acc, s) => acc + s.count);
    if (total <= 0) return;

    var start = -math.pi / 2;
    for (final s in slices) {
      if (s.count <= 0) continue;
      final sweep = (s.count / total) * 2 * math.pi;
      canvas.drawArc(
        rect,
        start,
        math.max(0.06, sweep - 0.04),
        false,
        Paint()
          ..color = s.color
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = strokeW,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) => old.slices != slices;
}

/// Datum for [InouTrendLineChart].
@immutable
class TrendPointDatum {
  const TrendPointDatum({required this.label, required this.value});

  final String label;

  /// Percentage `[0.0, 100.0]`.
  final double value;
}

/// Smooth 6-week accuracy/mastery trend curve with subtle gradient fill.
class InouTrendLineChart extends StatelessWidget {
  const InouTrendLineChart({
    super.key,
    required this.points,
    this.height = 148,
    this.lineColor,
  });

  final List<TrendPointDatum> points;
  final double height;
  final Color? lineColor;

  @override
  Widget build(BuildContext context) {
    final t = context.inou;
    final hasData = points.any((p) => p.value > 0);
    if (!hasData) {
      return SizedBox(
        height: height * 0.65,
        width: double.infinity,
        child: Center(
          child: Text(
            '完成首次练习后显示近期正确率曲线',
            style: TextStyle(fontSize: 12, color: t.textMuted),
          ),
        ),
      );
    }
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _TrendLinePainter(
          points: points,
          color: lineColor ?? t.accent,
          gridColor: t.borderHairline,
          labelColor: t.textMuted,
          dotInnerColor: t.surface,
        ),
      ),
    );
  }
}

class _TrendLinePainter extends CustomPainter {
  const _TrendLinePainter({
    required this.points,
    required this.color,
    required this.gridColor,
    required this.labelColor,
    required this.dotInnerColor,
  });

  final List<TrendPointDatum> points;
  final Color color;
  final Color gridColor;
  final Color labelColor;
  final Color dotInnerColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    const leftPad = 28.0;
    const rightPad = 14.0;
    const topPad = 14.0;
    const bottomPad = 24.0;
    final chartW = math.max(10.0, size.width - leftPad - rightPad);
    final chartH = math.max(10.0, size.height - topPad - bottomPad);

    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 0.8;

    for (final tick in [0, 50, 100]) {
      final y = topPad + chartH * (1 - tick / 100);
      canvas.drawLine(
        Offset(leftPad, y),
        Offset(size.width - rightPad, y),
        gridPaint,
      );
      final tp = TextPainter(
        text: TextSpan(
          text: '$tick',
          style: TextStyle(fontSize: 9.5, color: labelColor),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(0, y - tp.height / 2));
    }

    final coords = <Offset>[];
    for (var i = 0; i < points.length; i++) {
      final x = points.length == 1
          ? leftPad + chartW / 2
          : leftPad + (chartW * i / (points.length - 1));
      final norm = (points[i].value / 100).clamp(0.0, 1.0);
      final y = topPad + chartH * (1 - norm);
      coords.add(Offset(x, y));

      final xLabel = TextPainter(
        text: TextSpan(
          text: points[i].label,
          style: TextStyle(fontSize: 10, color: labelColor),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      xLabel.paint(
        canvas,
        Offset(x - xLabel.width / 2, size.height - bottomPad + 6),
      );
    }

    final linePath = Path()..moveTo(coords.first.dx, coords.first.dy);
    for (var i = 0; i < coords.length - 1; i++) {
      final p0 = coords[i];
      final p1 = coords[i + 1];
      final midX = (p0.dx + p1.dx) / 2;
      linePath.cubicTo(midX, p0.dy, midX, p1.dy, p1.dx, p1.dy);
    }

    final areaPath = Path.from(linePath)
      ..lineTo(coords.last.dx, topPad + chartH)
      ..lineTo(coords.first.dx, topPad + chartH)
      ..close();

    canvas.drawPath(
      areaPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.24), color.withValues(alpha: 0.0)],
        ).createShader(Rect.fromLTWH(leftPad, topPad, chartW, chartH)),
    );

    canvas.drawPath(
      linePath,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round,
    );

    for (final c in coords) {
      canvas.drawCircle(c, 4.2, Paint()..color = color);
      canvas.drawCircle(c, 2.0, Paint()..color = dotInnerColor);
    }
  }

  @override
  bool shouldRepaint(covariant _TrendLinePainter old) => old.points != points;
}

/// Crisp circular mastery/score ring with tabular numeric readout.
class InouScoreRing extends StatelessWidget {
  const InouScoreRing({
    super.key,
    required this.ratio,
    required this.headline,
    this.caption = '',
    this.size = 86,
    this.strokeWidth = 7.5,
    this.color,
  });

  final double ratio;
  final String headline;
  final String caption;
  final double size;
  final double strokeWidth;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = context.inou;
    final active = color ?? t.accent;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _ScoreRingPainter(
          ratio: ratio.clamp(0.0, 1.0),
          activeColor: active,
          trackColor: t.surfaceMuted,
          strokeWidth: strokeWidth,
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                headline,
                style: InouTypography.tabular(
                  TextStyle(
                    fontSize: size * 0.21,
                    fontWeight: FontWeight.w700,
                    color: t.textPrimary,
                    height: 1.05,
                  ),
                ),
              ),
              if (caption.isNotEmpty)
                Text(
                  caption,
                  style: TextStyle(fontSize: 9.5, color: t.textMuted),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScoreRingPainter extends CustomPainter {
  const _ScoreRingPainter({
    required this.ratio,
    required this.activeColor,
    required this.trackColor,
    required this.strokeWidth,
  });

  final double ratio;
  final Color activeColor;
  final Color trackColor;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    canvas.drawArc(
      rect,
      0,
      2 * math.pi,
      false,
      Paint()
        ..color = trackColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth,
    );
    if (ratio > 0) {
      canvas.drawArc(
        rect,
        -math.pi / 2,
        2 * math.pi * ratio,
        false,
        Paint()
          ..color = activeColor
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = strokeWidth,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ScoreRingPainter old) {
    return old.ratio != ratio || old.activeColor != activeColor;
  }
}
