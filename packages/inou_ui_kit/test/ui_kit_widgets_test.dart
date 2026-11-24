import 'package:flutter_test/flutter_test.dart';
import 'package:inou_domain/inou_domain.dart';
import 'package:inou_ui_kit/inou_ui_kit.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('InouTheme light/dark + StudioWidgets + ThinkingDisclosure', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: InouTheme.light(),
        home: Scaffold(
          body: ListView(
            children: const [
              InouStatusDot(label: 'Gemini · 已连接', connected: true),
              InouBadge(label: '已自检', tone: InouBadgeTone.success),
              InouThinkingDisclosure(
                traces: ['[工具] read_question_public → 已读取脱敏题干'],
                antiSpoilerBlocked: true,
              ),
              InouScoreRing(ratio: 0.75, headline: '75%', caption: '掌握度'),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Gemini · 已连接'), findsOneWidget);
    expect(find.text('已自检'), findsOneWidget);
    expect(find.text('75%'), findsOneWidget);
    await tester.tap(find.textContaining('防剧透拦截'));
    await tester.pump();
    expect(find.textContaining('read_question_public'), findsOneWidget);
  });

  testWidgets('Charts & all 10 NuoNuoMascotView expressions render cleanly', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: InouTheme.dark(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                const InouRadarChart(
                  axes: [
                    RadarAxisDatum(label: '数学', value: 0.8),
                    RadarAxisDatum(label: '物理', value: 0.65),
                    RadarAxisDatum(label: '英语', value: 0.9),
                  ],
                ),
                const InouDonutChart(
                  slices: [
                    DonutSliceDatum(
                      label: '计算',
                      count: 4,
                      color: Color(0xFFEF4444),
                    ),
                    DonutSliceDatum(
                      label: '概念',
                      count: 2,
                      color: Color(0xFF3F6AF5),
                    ),
                  ],
                ),
                const InouTrendLineChart(
                  points: [
                    TrendPointDatum(label: 'W1', value: 55),
                    TrendPointDatum(label: 'W2', value: 78),
                  ],
                ),
                Wrap(
                  children: [
                    for (final emo in NuoNuoExpression.values)
                      NuoNuoMascotView(emotion: emo, size: 40, animate: false),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.byType(NuoNuoMascotView), findsNWidgets(10));
    expect(find.text('6'), findsOneWidget);
  });

  testWidgets('ContentBlockRenderer renders Math, Slots, Tables & Passages', (
    tester,
  ) async {
    String? tappedSlot;
    await tester.pumpWidget(
      MaterialApp(
        theme: InouTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: ContentBlockRenderer(
              blocks: const [
                TextBlock('解方程：'),
                MathBlock('x^2 + \\frac{1}{2} = \\sqrt{9}'),
                SlotBlock('s1'),
                MathBlock('x_1 = 2,\\; x_2 = 3', display: true),
                PassageBlock(
                  title: '阅读材料',
                  paragraphs: [
                    PassageParagraph(no: '1', content: [TextBlock('第一段正文')]),
                  ],
                ),
                TableBlock(
                  header: [
                    [TextBlock('项目')],
                    [TextBlock('数值')],
                  ],
                  rows: [
                    [
                      [TextBlock('速率')],
                      [TextBlock('12 m/s')],
                    ],
                  ],
                ),
              ],
              slotValues: const {'s1': '5/2'},
              onSlotTap: (id) => tappedSlot = id,
            ),
          ),
        ),
      ),
    );

    expect(find.textContaining('x²'), findsOneWidget);
    expect(find.text('5/2'), findsOneWidget);
    expect(find.text('阅读材料'), findsOneWidget);
    expect(find.text('12 m/s'), findsOneWidget);
    await tester.tap(find.text('5/2'));
    expect(tappedSlot, 's1');
  });

  testWidgets(
    'ChipTheme resolves high-contrast label colors across Choice/Input/ActionChip',
    (tester) async {
      final lightTheme = InouTheme.light();
      final lightTokens = lightTheme.extension<InouTokens>()!;
      await tester.pumpWidget(
        MaterialApp(
          theme: lightTheme,
          home: Scaffold(
            body: Wrap(
              children: [
                ChoiceChip(
                  label: const Text('ChoiceOn'),
                  selected: true,
                  onSelected: (_) {},
                ),
                ChoiceChip(
                  label: const Text('ChoiceOff'),
                  selected: false,
                  onSelected: (_) {},
                ),
                FilterChip(
                  label: const Text('FilterOn'),
                  selected: true,
                  onSelected: (_) {},
                ),
                FilterChip(
                  label: const Text('FilterOff'),
                  selected: false,
                  onSelected: (_) {},
                ),
                InputChip(label: const Text('InputPlain'), onDeleted: () {}),
                const ActionChip(
                  label: Text('ActionDisabled'),
                  onPressed: null,
                ),
              ],
            ),
          ),
        ),
      );

      Color? colorOf(String text) {
        final ctx = tester.element(find.text(text));
        return DefaultTextStyle.of(ctx).style.color;
      }

      expect(colorOf('ChoiceOn'), Colors.white);
      expect(colorOf('ChoiceOff'), lightTokens.textPrimary);
      expect(colorOf('FilterOn'), Colors.white);
      expect(colorOf('FilterOff'), lightTokens.textPrimary);
      expect(colorOf('InputPlain'), lightTokens.textPrimary);
      expect(colorOf('ActionDisabled'), lightTokens.textSecondary);

      final darkTheme = InouTheme.dark();
      final darkTokens = darkTheme.extension<InouTokens>()!;
      await tester.pumpWidget(
        MaterialApp(
          theme: darkTheme,
          home: Scaffold(
            body: Wrap(
              children: [
                ChoiceChip(
                  label: const Text('ChoiceOn'),
                  selected: true,
                  onSelected: (_) {},
                ),
                ChoiceChip(
                  label: const Text('ChoiceOff'),
                  selected: false,
                  onSelected: (_) {},
                ),
                InputChip(
                  label: const Text('InputOn'),
                  selected: true,
                  onDeleted: () {},
                ),
                InputChip(label: const Text('InputPlain'), onDeleted: () {}),
                ActionChip(label: const Text('ActionOn'), onPressed: () {}),
                const ActionChip(
                  label: Text('ActionDisabled'),
                  onPressed: null,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(colorOf('ChoiceOn'), Colors.white);
      expect(colorOf('ChoiceOff'), darkTokens.textPrimary);
      expect(colorOf('InputOn'), Colors.white);
      expect(colorOf('InputPlain'), darkTokens.textPrimary);
      expect(colorOf('ActionOn'), darkTokens.textPrimary);
      expect(colorOf('ActionDisabled'), darkTokens.textSecondary);
    },
  );
}
