import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inou_ink/inou_ink.dart';
import 'package:inou_ink/render.dart';

void main() {
  group('InkModels, Eraser, Region Shift, WAL & Palm Rejection', () {
    test('eraser hits segment proximity and supports undo/redo', () {
      final controller = InkController();
      expect(
        controller.handlePointerDown(
          pointerId: 1,
          kind: PointerDeviceKind.stylus,
          logicalPosition: const Offset(20, 20),
          pressure: 0.7,
        ),
        isTrue,
      );
      controller.handlePointerMove(
        pointerId: 1,
        logicalPosition: const Offset(120, 20),
        pressure: 0.7,
      );
      controller.handlePointerUp(pointerId: 1);
      expect(controller.page.strokes, hasLength(1));

      controller.setTool(InkToolKind.eraser);
      controller.handlePointerDown(
        pointerId: 2,
        kind: PointerDeviceKind.stylus,
        logicalPosition: const Offset(70, 24),
        pressure: 0.5,
      );
      controller.handlePointerUp(pointerId: 2);
      expect(controller.page.strokes, isEmpty);

      expect(controller.undo(), isTrue);
      expect(controller.page.strokes, hasLength(1));
      expect(controller.redo(), isTrue);
      expect(controller.page.strokes, isEmpty);
    });

    test('region-anchored shift moves only target region strokes', () {
      final controller = InkController();
      controller.handlePointerDown(
        pointerId: 1,
        kind: PointerDeviceKind.stylus,
        logicalPosition: const Offset(40, 100),
        pressure: 0.6,
        regionId: 'q1',
      );
      controller.handlePointerMove(
        pointerId: 1,
        logicalPosition: const Offset(90, 100),
        pressure: 0.6,
      );
      controller.handlePointerUp(pointerId: 1);

      controller.handlePointerDown(
        pointerId: 2,
        kind: PointerDeviceKind.stylus,
        logicalPosition: const Offset(40, 250),
        pressure: 0.6,
        regionId: 'q2',
      );
      controller.handlePointerMove(
        pointerId: 2,
        logicalPosition: const Offset(90, 250),
        pressure: 0.6,
      );
      controller.handlePointerUp(pointerId: 2);

      controller.shiftRegions({'q2'}, 64);
      final q1 = controller.page.strokes.firstWhere((s) => s.regionId == 'q1');
      final q2 = controller.page.strokes.firstWhere((s) => s.regionId == 'q2');
      expect(q1.points.first.y, 100);
      expect(q2.points.first.y, 314);
    });

    test('WAL codec preserves strokes across serialize/deserialize', () {
      final page = InkPageData(
        pageW: PaperSizePreset.b5.width,
        pageH: PaperSizePreset.b5.height,
        strokes: [
          InkStroke(
            id: 's_wal',
            tool: InkToolKind.highlighter,
            colorArgb: 0x58FACC15,
            width: 14,
            regionId: 'q_box',
            points: const [
              InkPoint(x: 10, y: 10, pressure: 0.5, tMs: 1),
              InkPoint(x: 60, y: 30, pressure: 0.6, tMs: 20),
            ],
          ),
        ],
      );
      final encoded = InkWalCodec.encode(page);
      final decoded = InkWalCodec.decode(encoded);
      expect(decoded.pageW, PaperSizePreset.b5.width);
      expect(decoded.strokes, hasLength(1));
      expect(decoded.strokes.first.tool, InkToolKind.highlighter);
      expect(decoded.strokes.first.regionId, 'q_box');
      expect(decoded.strokes.first.points.last.x, 60);
    });

    test('palm rejection blocks touch within 2s stylus protection window', () {
      final palm = PalmRejectionStateMachine(protectionWindowMs: 2000);
      expect(
        palm.shouldAcceptPointer(
          kind: PointerDeviceKind.touch,
          fingerDrawEnabled: true,
          nowMs: 1000,
        ),
        isTrue,
      );
      expect(
        palm.shouldAcceptPointer(
          kind: PointerDeviceKind.stylus,
          fingerDrawEnabled: true,
          nowMs: 2000,
        ),
        isTrue,
      );
      expect(
        palm.shouldAcceptPointer(
          kind: PointerDeviceKind.touch,
          fingerDrawEnabled: true,
          nowMs: 3200,
        ),
        isFalse,
      );
      expect(
        palm.shouldAcceptPointer(
          kind: PointerDeviceKind.touch,
          fingerDrawEnabled: true,
          nowMs: 4100,
        ),
        isTrue,
      );
    });
  });

  group('InouInkCanvas Widget & PNG Snapshot Exporter', () {
    testWidgets('renders canvas, commits pen stroke, and lassos stroke', (
      tester,
    ) async {
      final controller = InkController(fingerDrawEnabled: true);
      Rect? capturedRect;
      List<InkStroke> capturedStrokes = const [];

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: 300,
              height: 400,
              child: InouInkCanvas(
                controller: controller,
                scale: 0.5,
                onLassoCompleted: (r, s) {
                  capturedRect = r;
                  capturedStrokes = s;
                },
              ),
            ),
          ),
        ),
      );

      final origin = tester.getTopLeft(find.byType(InouInkCanvas));
      await tester.timedDragFrom(
        origin + const Offset(20, 20),
        const Offset(60, 0),
        const Duration(milliseconds: 80),
      );
      await tester.pump();
      expect(controller.page.strokes, hasLength(1));

      controller.setTool(InkToolKind.lasso);
      await tester.timedDragFrom(
        origin + const Offset(10, 10),
        const Offset(90, 40),
        const Duration(milliseconds: 80),
      );
      await tester.pump();
      expect(capturedRect, isNotNull);
      expect(capturedStrokes, hasLength(1));
    });

    test('exports logical crop region to valid PNG bytes', () async {
      final page = InkPageData(
        pageW: 200,
        pageH: 200,
        strokes: [
          InkStroke(
            id: 's_png',
            tool: InkToolKind.pen,
            colorArgb: 0xFF3F6AF5,
            width: 3,
            points: const [
              InkPoint(x: 20, y: 20, pressure: 0.6, tMs: 0),
              InkPoint(x: 160, y: 120, pressure: 0.7, tMs: 16),
            ],
          ),
        ],
      );
      final bytes = await InkSnapshotExporter.exportRegionPng(
        page,
        cropRect: const Rect.fromLTWH(0, 0, 180, 140),
        pixelRatio: 1.0,
      );
      expect(bytes, isNotNull);
      expect(bytes!.length, greaterThan(16));
      // PNG file header signature
      expect(bytes.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
    });
  });
}
