import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inou_app/app/app.dart';
import 'package:inou_app/core/state/app_store.dart';
import 'package:inou_app/core/storage/workspace_storage.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('Clean first-run shows 3-step onboarding then empty workspace', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          blobStorageProvider.overrideWithValue(InMemoryBlobStorage()),
        ],
        child: const InouApp(),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('欢迎使用 InoU'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '林同学');
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();

    // Privacy step -> Optional AI step
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('稍后配置'));
    await tester.pumpAndSettle();

    expect(find.text('你好，林同学'), findsOneWidget);
    expect(find.text('建立你的第一份错题与练习本'), findsOneWidget);
    expect(find.textContaining('体验包'), findsNothing);

    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    expect(find.text('安全与备份'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('做题'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('全题型综合训练 (0 题)'), findsOneWidget);
    expect(find.text('全部'), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('题库'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('题库还是空的'), findsOneWidget);

    await tester.tap(find.byTooltip('拍照录题'));
    await tester.pumpAndSettle();
    expect(find.text('录题与识别'), findsOneWidget);
    expect(find.text('示例卷快速体验'), findsNothing);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('错题本'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('错题本还是空的'), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('诊断'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('累计作答 3 科以上后'), findsOneWidget);
  });

  testWidgets('AdaptiveShell uses NavigationRail on tablet width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          blobStorageProvider.overrideWithValue(InMemoryBlobStorage()),
        ],
        child: const InouApp(),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('InoU'), findsOneWidget);
  });
}
