import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

/// Resolves safe content padding that accounts for system cutouts, punch-holes,
/// notches, rounded display corners, and system gesture bars in both portrait
/// and immersive landscape orientations.
abstract final class DisplayCutoutInsets {
  static EdgeInsets resolve(
    BuildContext context, {
    EdgeInsets nativeCutout = EdgeInsets.zero,
    bool immersiveLandscape = false,
  }) {
    final mq = MediaQuery.of(context);
    var cutoutLeft = 0.0;
    var cutoutTop = 0.0;
    var cutoutRight = 0.0;
    var cutoutBottom = 0.0;

    final w = mq.size.width;
    final h = mq.size.height;
    if (w > 0 && h > 0) {
      for (final feature in mq.displayFeatures) {
        if (feature.type != ui.DisplayFeatureType.cutout) continue;
        final b = feature.bounds;
        if (b.isEmpty) continue;
        if (b.left <= 1.0 && b.right < w * 0.5) {
          cutoutLeft = math.max(cutoutLeft, b.right);
        }
        if (b.right >= w - 1.0 && b.left > w * 0.5) {
          cutoutRight = math.max(cutoutRight, w - b.left);
        }
        if (b.top <= 1.0 && b.bottom < h * 0.5) {
          cutoutTop = math.max(cutoutTop, b.bottom);
        }
        if (b.bottom >= h - 1.0 && b.top > h * 0.5) {
          cutoutBottom = math.max(cutoutBottom, h - b.top);
        }
      }
    }

    final left = math.max(
      mq.padding.left,
      math.max(mq.viewPadding.left, math.max(cutoutLeft, nativeCutout.left)),
    );
    final right = math.max(
      mq.padding.right,
      math.max(mq.viewPadding.right, math.max(cutoutRight, nativeCutout.right)),
    );
    final top = immersiveLandscape
        ? math.max(mq.padding.top, math.max(cutoutTop, nativeCutout.top))
        : math.max(
            mq.padding.top,
            math.max(mq.viewPadding.top, math.max(cutoutTop, nativeCutout.top)),
          );
    final bottom = immersiveLandscape
        ? math.max(
            mq.padding.bottom,
            math.max(cutoutBottom, nativeCutout.bottom),
          )
        : math.max(
            mq.padding.bottom,
            math.max(
              mq.viewPadding.bottom,
              math.max(cutoutBottom, nativeCutout.bottom),
            ),
          );

    return EdgeInsets.fromLTRB(left, top, right, bottom);
  }

  /// Concise screen/cutout summary appended to exported diagnostic logs.
  static String describeMetrics(
    BuildContext context, {
    EdgeInsets nativeCutout = EdgeInsets.zero,
  }) {
    final mq = MediaQuery.of(context);
    final resolved = resolve(context, nativeCutout: nativeCutout);
    final cutouts = mq.displayFeatures
        .where((f) => f.type == ui.DisplayFeatureType.cutout)
        .map((f) => f.bounds.toString())
        .join('; ');
    return '${mq.size.width.toStringAsFixed(0)}x${mq.size.height.toStringAsFixed(0)} '
        'dpr=${mq.devicePixelRatio.toStringAsFixed(2)} '
        'pad=${mq.padding} viewPad=${mq.viewPadding} '
        'resolved=$resolved'
        '${cutouts.isNotEmpty ? ' cutouts=[$cutouts]' : ''}';
  }
}