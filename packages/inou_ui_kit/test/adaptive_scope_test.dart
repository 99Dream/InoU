import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inou_ui_kit/inou_ui_kit.dart';

void main() {
  test('WindowClass classifies breakpoints accurately', () {
    expect(WindowClass.fromWidth(390), WindowClass.compact);
    expect(WindowClass.fromWidth(599.9), WindowClass.compact);
    expect(WindowClass.fromWidth(600), WindowClass.medium);
    expect(WindowClass.fromWidth(839.9), WindowClass.medium);
    expect(WindowClass.fromWidth(840), WindowClass.expanded);
    expect(WindowClass.fromWidth(1280), WindowClass.expanded);
  });

  testWidgets('AdaptiveBuilder selects compact and expanded builders', (
    tester,
  ) async {
    Widget buildForWidth(double width) {
      return MediaQuery(
        data: MediaQueryData(size: Size(width, 800)),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: AdaptiveScopeProvider(
            child: AdaptiveBuilder(
              compact: (_) => const Text('compact'),
              medium: (_) => const Text('medium'),
              expanded: (_) => const Text('expanded'),
            ),
          ),
        ),
      );
    }

    await tester.pumpWidget(buildForWidth(390));
    expect(find.text('compact'), findsOneWidget);

    await tester.pumpWidget(buildForWidth(700));
    expect(find.text('medium'), findsOneWidget);

    await tester.pumpWidget(buildForWidth(1024));
    expect(find.text('expanded'), findsOneWidget);
  });
}
