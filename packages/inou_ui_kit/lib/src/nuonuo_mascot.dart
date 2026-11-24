import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import 'inou_theme.dart';

/// Ten reactive mascot expressions aligned with `assets/mascot/default/pack.json`.
enum NuoNuoExpression {
  neutral,
  happy,
  thinking,
  encourage,
  surprised,
  serious,
  sorry,
  celebrate,
  sleepy,
  wink;

  static NuoNuoExpression fromCode(String code) {
    final norm = code.trim().toLowerCase();
    return NuoNuoExpression.values.firstWhere(
      (e) => e.name == norm,
      orElse: () => NuoNuoExpression.happy,
    );
  }
}

/// Animated high-tech studio companion portrait for "诺诺学姐".
/// Supports all 10 reactive expressions, subtle idle breathing, periodic eye
/// blinking, and scales smoothly from a 36px floating orb up to 120px hero.
class NuoNuoMascotView extends StatefulWidget {
  const NuoNuoMascotView({
    super.key,
    this.emotion = NuoNuoExpression.happy,
    this.size = 56,
    this.showGlowRing = true,
    this.animate = true,
  });

  final NuoNuoExpression emotion;
  final double size;
  final bool showGlowRing;
  final bool animate;

  @override
  State<NuoNuoMascotView> createState() => _NuoNuoMascotViewState();
}

class _NuoNuoMascotViewState extends State<NuoNuoMascotView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    if (widget.animate) {
      _controller.forward(from: 0);
    } else {
      _controller.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(covariant NuoNuoMascotView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate && oldWidget.emotion != widget.emotion) {
      _controller.forward(from: 0);
    } else if (!widget.animate && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.inou;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final phase = widget.animate ? _controller.value : 0.25;
        final breathY = math.sin(phase * 2 * math.pi) * (widget.size * 0.02);
        // Quick natural eye blink around phase 0.88..0.94
        final isBlinking = phase > 0.89 && phase < 0.94;
        return Transform.translate(
          offset: Offset(0, breathY),
          child: SizedBox(
            width: widget.size,
            height: widget.size,
            child: CustomPaint(
              painter: _NuoNuoPainter(
                emotion: widget.emotion,
                isBlinking: isBlinking,
                phase: phase,
                showGlowRing: widget.showGlowRing,
                accentColor: t.accent,
                surfaceColor: t.surface,
                borderColor: t.borderHairline,
                isDark: t.isDark,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _NuoNuoPainter extends CustomPainter {
  const _NuoNuoPainter({
    required this.emotion,
    required this.isBlinking,
    required this.phase,
    required this.showGlowRing,
    required this.accentColor,
    required this.surfaceColor,
    required this.borderColor,
    required this.isDark,
  });

  final NuoNuoExpression emotion;
  final bool isBlinking;
  final double phase;
  final bool showGlowRing;
  final Color accentColor;
  final Color surfaceColor;
  final Color borderColor;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final c = Offset(w / 2, h / 2);
    final r = math.min(w, h) / 2;

    final badgeColor = switch (emotion) {
      NuoNuoExpression.celebrate ||
      NuoNuoExpression.happy => const Color(0xFF10B981),
      NuoNuoExpression.serious ||
      NuoNuoExpression.sorry => const Color(0xFFF59E0B),
      NuoNuoExpression.thinking => accentColor,
      NuoNuoExpression.encourage => const Color(0xFF6366F1),
      NuoNuoExpression.sleepy => const Color(0xFF64748B),
      _ => accentColor,
    };

    // Subtle circular studio backdrop + ring
    if (showGlowRing) {
      canvas.drawCircle(
        c,
        r * 0.96,
        Paint()
          ..color = badgeColor.withValues(alpha: isDark ? 0.18 : 0.08)
          ..style = PaintingStyle.fill,
      );
      canvas.drawCircle(
        c,
        r * 0.96,
        Paint()
          ..color = badgeColor.withValues(alpha: 0.45)
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.2, r * 0.05),
      );
    }

    // Navy hair back silhouette
    const hairColor = Color(0xFF1E293B);
    canvas.drawCircle(
      Offset(c.dx, c.dy + r * 0.02),
      r * 0.72,
      Paint()..color = hairColor,
    );

    // Side twin-tail / bob hair locks
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(c.dx - r * 0.56, c.dy + r * 0.25),
        width: r * 0.34,
        height: r * 0.56,
      ),
      Paint()..color = hairColor,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(c.dx + r * 0.56, c.dy + r * 0.25),
        width: r * 0.34,
        height: r * 0.56,
      ),
      Paint()..color = hairColor,
    );

    // Warm porcelain face
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(c.dx, c.dy + r * 0.08),
        width: r * 1.06,
        height: r * 1.02,
      ),
      Paint()..color = const Color(0xFFFFEFE6),
    );

    // Swept bangs
    final bangs = Path()
      ..moveTo(c.dx - r * 0.58, c.dy - r * 0.14)
      ..quadraticBezierTo(
        c.dx - r * 0.28,
        c.dy - r * 0.52,
        c.dx,
        c.dy - r * 0.24,
      )
      ..quadraticBezierTo(
        c.dx + r * 0.28,
        c.dy - r * 0.52,
        c.dx + r * 0.58,
        c.dy - r * 0.14,
      )
      ..arcTo(
        Rect.fromCircle(center: c, radius: r * 0.68),
        -0.25,
        -math.pi + 0.5,
        false,
      )
      ..close();
    canvas.drawPath(bangs, Paint()..color = hairColor);

    // Signature indigo studio hairclip
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(c.dx + r * 0.32, c.dy - r * 0.34),
          width: r * 0.28,
          height: r * 0.11,
        ),
        Radius.circular(r * 0.05),
      ),
      Paint()..color = badgeColor,
    );

    // Soft cheek blush
    final blushPaint = Paint()..color = const Color(0x44FB7185);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(c.dx - r * 0.30, c.dy + r * 0.18),
        width: r * 0.22,
        height: r * 0.10,
      ),
      blushPaint,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(c.dx + r * 0.30, c.dy + r * 0.18),
        width: r * 0.22,
        height: r * 0.10,
      ),
      blushPaint,
    );

    // Eyes & Eyebrows per expression
    final linePaint = Paint()
      ..color = const Color(0xFF0F172A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.3, r * 0.06)
      ..strokeCap = StrokeCap.round;

    final leftEyeCenter = Offset(c.dx - r * 0.22, c.dy + r * 0.04);
    final rightEyeCenter = Offset(c.dx + r * 0.22, c.dy + r * 0.04);

    if (isBlinking || emotion == NuoNuoExpression.sleepy) {
      // Closed curved eyes
      canvas.drawArc(
        Rect.fromCenter(
          center: leftEyeCenter,
          width: r * 0.22,
          height: r * 0.12,
        ),
        0.1,
        math.pi - 0.2,
        false,
        linePaint,
      );
      canvas.drawArc(
        Rect.fromCenter(
          center: rightEyeCenter,
          width: r * 0.22,
          height: r * 0.12,
        ),
        0.1,
        math.pi - 0.2,
        false,
        linePaint,
      );
    } else if (emotion == NuoNuoExpression.happy ||
        emotion == NuoNuoExpression.celebrate) {
      // Joyful upward ^^ arcs
      canvas.drawArc(
        Rect.fromCenter(
          center: leftEyeCenter,
          width: r * 0.22,
          height: r * 0.14,
        ),
        math.pi + 0.2,
        math.pi - 0.4,
        false,
        linePaint,
      );
      canvas.drawArc(
        Rect.fromCenter(
          center: rightEyeCenter,
          width: r * 0.22,
          height: r * 0.14,
        ),
        math.pi + 0.2,
        math.pi - 0.4,
        false,
        linePaint,
      );
    } else if (emotion == NuoNuoExpression.wink) {
      _drawOpenEye(canvas, leftEyeCenter, r, accentColor);
      canvas.drawArc(
        Rect.fromCenter(
          center: rightEyeCenter,
          width: r * 0.22,
          height: r * 0.12,
        ),
        math.pi + 0.2,
        math.pi - 0.4,
        false,
        linePaint,
      );
    } else {
      _drawOpenEye(
        canvas,
        leftEyeCenter,
        r,
        accentColor,
        lookUp: emotion == NuoNuoExpression.thinking,
      );
      _drawOpenEye(
        canvas,
        rightEyeCenter,
        r,
        accentColor,
        lookUp: emotion == NuoNuoExpression.thinking,
      );
    }

    // Eyebrow tilts
    if (emotion == NuoNuoExpression.serious) {
      canvas.drawLine(
        Offset(leftEyeCenter.dx - r * 0.11, leftEyeCenter.dy - r * 0.18),
        Offset(leftEyeCenter.dx + r * 0.10, leftEyeCenter.dy - r * 0.12),
        linePaint..strokeWidth = math.max(1.2, r * 0.045),
      );
      canvas.drawLine(
        Offset(rightEyeCenter.dx - r * 0.10, rightEyeCenter.dy - r * 0.12),
        Offset(rightEyeCenter.dx + r * 0.11, rightEyeCenter.dy - r * 0.18),
        linePaint,
      );
    } else if (emotion == NuoNuoExpression.sorry) {
      canvas.drawLine(
        Offset(leftEyeCenter.dx - r * 0.11, leftEyeCenter.dy - r * 0.12),
        Offset(leftEyeCenter.dx + r * 0.10, leftEyeCenter.dy - r * 0.18),
        linePaint..strokeWidth = math.max(1.2, r * 0.045),
      );
      canvas.drawLine(
        Offset(rightEyeCenter.dx - r * 0.10, rightEyeCenter.dy - r * 0.18),
        Offset(rightEyeCenter.dx + r * 0.11, rightEyeCenter.dy - r * 0.12),
        linePaint,
      );
    }

    // Mouth per expression
    final mouthCenter = Offset(c.dx, c.dy + r * 0.28);
    if (emotion == NuoNuoExpression.surprised) {
      canvas.drawCircle(
        mouthCenter,
        r * 0.07,
        Paint()..color = const Color(0xFFEF4444),
      );
    } else if (emotion == NuoNuoExpression.serious ||
        emotion == NuoNuoExpression.sorry ||
        emotion == NuoNuoExpression.sleepy) {
      canvas.drawLine(
        Offset(mouthCenter.dx - r * 0.09, mouthCenter.dy),
        Offset(mouthCenter.dx + r * 0.09, mouthCenter.dy),
        linePaint..strokeWidth = math.max(1.2, r * 0.05),
      );
    } else if (emotion == NuoNuoExpression.thinking) {
      canvas.drawLine(
        Offset(mouthCenter.dx - r * 0.06, mouthCenter.dy),
        Offset(mouthCenter.dx + r * 0.08, mouthCenter.dy - r * 0.02),
        linePaint..strokeWidth = math.max(1.2, r * 0.05),
      );
    } else {
      // Smile arc
      canvas.drawArc(
        Rect.fromCenter(
          center: mouthCenter - Offset(0, r * 0.04),
          width: r * 0.24,
          height: r * 0.16,
        ),
        0.2,
        math.pi - 0.4,
        false,
        linePaint..strokeWidth = math.max(1.3, r * 0.055),
      );
    }

    // Accent sparkles for celebrate / thinking
    if (emotion == NuoNuoExpression.celebrate) {
      final sparkPaint = Paint()..color = const Color(0xFFF59E0B);
      final bounce = math.sin(phase * 4 * math.pi) * r * 0.04;
      canvas.drawCircle(
        Offset(c.dx - r * 0.68, c.dy - r * 0.56 + bounce),
        r * 0.07,
        sparkPaint,
      );
      canvas.drawCircle(
        Offset(c.dx + r * 0.68, c.dy - r * 0.56 - bounce),
        r * 0.06,
        Paint()..color = const Color(0xFF10B981),
      );
    }
  }

  void _drawOpenEye(
    Canvas canvas,
    Offset center,
    double r,
    Color irisColor, {
    bool lookUp = false,
  }) {
    final dyOffset = lookUp ? -r * 0.03 : 0.0;
    canvas.drawOval(
      Rect.fromCenter(center: center, width: r * 0.18, height: r * 0.22),
      Paint()..color = const Color(0xFF0F172A),
    );
    canvas.drawCircle(
      Offset(center.dx, center.dy + r * 0.02 + dyOffset),
      r * 0.06,
      Paint()..color = irisColor,
    );
    canvas.drawCircle(
      Offset(center.dx - r * 0.04, center.dy - r * 0.04 + dyOffset),
      r * 0.036,
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant _NuoNuoPainter old) {
    return old.emotion != emotion ||
        old.isBlinking != isBlinking ||
        old.phase != phase ||
        old.isDark != isDark;
  }
}
