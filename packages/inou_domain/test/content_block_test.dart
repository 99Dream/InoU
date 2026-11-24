import 'package:inou_domain/inou_domain.dart';
import 'package:test/test.dart';

void main() {
  group('ContentBlock roundtrip', () {
    test('serializes and parses mixed prompt blocks', () {
      const blocks = <ContentBlock>[
        TextBlock('解方程：'),
        MathBlock('x^2 - 5x + 6 = 0', display: false),
        SlotBlock('s1'),
        FigureBlock(assetId: 'asset_01', caption: '图1'),
      ];

      final jsonList = blocks.map((b) => b.toJson()).toList();
      final decoded = jsonList.map(ContentBlock.fromJson).toList();

      expect(decoded, hasLength(4));
      expect(decoded[0], isA<TextBlock>());
      expect((decoded[0] as TextBlock).text, '解方程：');
      expect((decoded[1] as MathBlock).latex, 'x^2 - 5x + 6 = 0');
      expect((decoded[2] as SlotBlock).slotId, 's1');
      expect((decoded[3] as FigureBlock).assetId, 'asset_01');
    });

    test('rejects unknown block type', () {
      expect(
        () => ContentBlock.fromJson(const {'type': 'html', 'body': '<script>'}),
        throwsFormatException,
      );
    });
  });

  group('Enums', () {
    test('covers all 10 question kinds', () {
      expect(QuestionKind.values, hasLength(10));
      expect(QuestionKind.fromCode('solve'), QuestionKind.solve);
      expect(QuestionKind.fromCode('spatial'), QuestionKind.spatial);
      expect(() => QuestionKind.fromCode('unknown'), throwsFormatException);
    });
  });
}
