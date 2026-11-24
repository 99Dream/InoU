import 'package:flutter_test/flutter_test.dart';
import 'package:inou_app/features/practice/presentation/standard_question_widgets.dart';
import 'package:inou_domain/inou_domain.dart';
import 'package:inou_ui_kit/inou_ui_kit.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  Future<void> pumpQuestion(
    WidgetTester tester, {
    required Question question,
    required StudentResponse? response,
    required ValueChanged<StudentResponse> onChanged,
    ThemeData? theme,
  }) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: theme ?? InouTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: StandardQuestionWidget(
              question: question,
              response: response,
              onChanged: onChanged,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Color? textColorOf(WidgetTester tester, Finder finder) {
    final target = finder.first;
    final rich = tester.widget<RichText>(
      find.descendant(of: target, matching: find.byType(RichText)).first,
    );
    return rich.text.style?.color;
  }

  testWidgets(
    'fill.sequence keeps high contrast in light and dark modes on phone',
    (tester) async {
      final question = Question.coerceFromAiMap({
        'id': 'q_seq',
        'kind': 'fill',
        'prompt': [
          {'type': 'text', 'text': '连词成句：'},
          {'type': 'slot', 'slotId': 's1'},
        ],
        'presentation': {'interaction': 'fill.sequence'},
        'body': {
          'slots': [
            {'id': 's1', 'label': '句子'},
          ],
          'bank': [
            {
              'id': 'w1',
              'content': [
                {'type': 'text', 'text': 'No'},
              ],
            },
            {
              'id': 'w2',
              'content': [
                {'type': 'text', 'text': 'flash'},
              ],
            },
          ],
        },
        'grading': {
          'slots': {'s1': 'No flash'},
        },
      });

      final lightTheme = InouTheme.light();
      final lightTokens = lightTheme.extension<InouTokens>()!;
      StudentResponse? latest = const FillResponse(
        questionId: 'q_seq',
        inputMode: InputMode.standard,
        itemEntries: {
          's1': ['w1'],
        },
      );

      await pumpQuestion(
        tester,
        question: question,
        response: latest,
        onChanged: (r) => latest = r,
        theme: lightTheme,
      );

      expect(tester.takeException(), isNull);
      expect(textColorOf(tester, find.text('1. No')), Colors.white);
      expect(
        textColorOf(
          tester,
          find.descendant(
            of: find.byType(ActionChip),
            matching: find.text('No'),
          ),
        ),
        lightTokens.textSecondary,
      );
      expect(textColorOf(tester, find.text('flash')), lightTokens.textPrimary);

      // Whole selected chip tap removes item
      await tester.tap(find.text('1. No'));
      await tester.pumpAndSettle();
      expect((latest! as FillResponse).itemEntries['s1'], isEmpty);

      // Dark theme retains high contrast on slots and bank items
      final darkTheme = InouTheme.dark();
      final darkTokens = darkTheme.extension<InouTokens>()!;
      await pumpQuestion(
        tester,
        question: question,
        response: const FillResponse(
          questionId: 'q_seq',
          inputMode: InputMode.standard,
          itemEntries: {
            's1': ['w1'],
          },
        ),
        onChanged: (_) {},
        theme: darkTheme,
      );

      expect(tester.takeException(), isNull);
      expect(textColorOf(tester, find.text('1. No')), Colors.white);
      expect(textColorOf(tester, find.text('flash')), darkTokens.textPrimary);
    },
  );

  testWidgets('classify stacks buckets on phone and highlights placed chips', (
    tester,
  ) async {
    final question = Question.coerceFromAiMap({
      'id': 'q_cls',
      'kind': 'classify',
      'prompt': '将词语归入对应词性桶：',
      'body': {
        'items': [
          {
            'id': 'i1',
            'content': [
              {'type': 'text', 'text': 'museum'},
            ],
          },
          {
            'id': 'i2',
            'content': [
              {'type': 'text', 'text': 'quickly'},
            ],
          },
        ],
        'categories': [
          {
            'id': 'c1',
            'content': [
              {'type': 'text', 'text': '名词 Noun'},
            ],
          },
          {
            'id': 'c2',
            'content': [
              {'type': 'text', 'text': '副词 Adverb'},
            ],
          },
          {
            'id': 'c3',
            'content': [
              {'type': 'text', 'text': '介词 Prep'},
            ],
          },
        ],
      },
      'grading': {'placements': <String, Object?>{}},
    });

    final lightTheme = InouTheme.light();
    final lightTokens = lightTheme.extension<InouTokens>()!;
    StudentResponse? latest;

    await pumpQuestion(
      tester,
      question: question,
      response: latest,
      onChanged: (r) => latest = r,
      theme: lightTheme,
    );

    expect(tester.takeException(), isNull);
    expect(textColorOf(tester, find.text('museum')), lightTokens.textPrimary);

    await tester.tap(find.text('museum'));
    await tester.pumpAndSettle();
    expect(textColorOf(tester, find.text('museum')), Colors.white);

    await tester.tap(find.text('名词 Noun'));
    await tester.pumpAndSettle();
    expect((latest! as ClassifyResponse).placements['i1'], 'c1');

    // Re-pump with updated response and verify bucket chip contrast & removal
    await pumpQuestion(
      tester,
      question: question,
      response: latest,
      onChanged: (r) => latest = r,
      theme: lightTheme,
    );
    expect(tester.takeException(), isNull);
    // Unselected item chip vs white placed chip inside bucket
    final museumWidgets = find.text('museum');
    expect(museumWidgets, findsNWidgets(2));
    expect(textColorOf(tester, museumWidgets.at(0)), lightTokens.textPrimary);
    expect(textColorOf(tester, museumWidgets.at(1)), Colors.white);

    await tester.tap(museumWidgets.at(1));
    await tester.pumpAndSettle();
    expect((latest! as ClassifyResponse).placements, isEmpty);
  });

  testWidgets('match handles long labels on phone and unpairs cleanly', (
    tester,
  ) async {
    final question = Question.coerceFromAiMap({
      'id': 'q_match',
      'kind': 'match',
      'prompt': '将左列英文短语与右列中文释义连线：',
      'body': {
        'left': [
          {
            'id': 'l1',
            'content': [
              {'type': 'text', 'text': 'No flash photography allowed'},
            ],
          },
        ],
        'right': [
          {
            'id': 'r1',
            'content': [
              {'type': 'text', 'text': '展览馆内禁止使用闪光灯拍照'},
            ],
          },
        ],
      },
      'grading': {
        'pairs': {'l1': 'r1'},
      },
    });

    StudentResponse? latest = const MatchResponse(
      questionId: 'q_match',
      inputMode: InputMode.standard,
      pairs: {'l1': 'r1'},
    );

    await pumpQuestion(
      tester,
      question: question,
      response: latest,
      onChanged: (r) => latest = r,
    );

    expect(tester.takeException(), isNull);
    final badgeFinder = find.textContaining('→ 展览馆内禁止使用闪光灯拍照 ×');
    expect(badgeFinder, findsOneWidget);
    await tester.tap(badgeFinder);
    await tester.pumpAndSettle();
    expect((latest! as MatchResponse).pairs, isEmpty);
  });

  testWidgets('spatial hotspots show high-contrast white labels when placed', (
    tester,
  ) async {
    final question = Question.coerceFromAiMap({
      'id': 'q_spatial',
      'kind': 'spatial',
      'prompt': '将部件标签放入对应区域：',
      'body': {
        'targets': [
          {
            'id': 't1',
            'label': '①',
            'shape': {'type': 'rect', 'x': 0.2, 'y': 0.2, 'w': 0.35, 'h': 0.22},
          },
        ],
        'labels': [
          {
            'id': 'lb1',
            'content': [
              {'type': 'text', 'text': '细胞核'},
            ],
          },
        ],
      },
      'grading': {
        'placements': {'lb1': 't1'},
      },
    });

    StudentResponse? latest = const SpatialResponse(
      questionId: 'q_spatial',
      inputMode: InputMode.standard,
      points: [],
      placements: {'lb1': 't1'},
    );

    await pumpQuestion(
      tester,
      question: question,
      response: latest,
      onChanged: (r) => latest = r,
    );

    expect(tester.takeException(), isNull);
    final placedSpot = find.text('① 细胞核');
    expect(placedSpot, findsOneWidget);
    expect(textColorOf(tester, placedSpot), Colors.white);

    // Tapping assigned hotspot clears assignment
    await tester.tap(placedSpot);
    await tester.pumpAndSettle();
    expect((latest! as SpatialResponse).placements, isEmpty);
  });

  testWidgets('draw canvas adapts to 360px phone viewport without overflow', (
    tester,
  ) async {
    final question = Question.coerceFromAiMap({
      'id': 'q_draw',
      'kind': 'draw',
      'prompt': '在下方网格中作出函数 y = x 的图像：',
      'body': <String, Object?>{},
      'grading': <String, Object?>{},
    });

    await pumpQuestion(
      tester,
      question: question,
      response: null,
      onChanged: (_) {},
    );

    expect(tester.takeException(), isNull);
    expect(find.text('画笔'), findsOneWidget);
    expect(find.text('橡皮'), findsOneWidget);
  });
}
