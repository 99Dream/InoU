import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:inou_ink/inou_ink.dart';

void main() {
  test('InkStroke computes padded bounds and InkPageData appends strokes', () {
    final stroke = InkStroke(
      id: 's1',
      tool: InkToolKind.pen,
      colorArgb: 0xFF111111,
      width: 4,
      points: const [
        InkPoint(x: 10, y: 20, pressure: 0.5, tMs: 0),
        InkPoint(x: 50, y: 80, pressure: 0.8, tMs: 16),
      ],
    );

    expect(stroke.bounds, const Rect.fromLTRB(8, 18, 52, 82));

    final page = InkPageData(
      pageW: PaperSizePreset.a4.width,
      pageH: PaperSizePreset.a4.height,
    ).addStroke(stroke);

    expect(page.strokes, hasLength(1));
    expect(page.pageW, 595);
    expect(page.pageH, 842);
  });
}
