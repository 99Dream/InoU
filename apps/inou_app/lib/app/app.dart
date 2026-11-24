import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inou_ui_kit/inou_ui_kit.dart';
import 'package:material_ui/material_ui.dart';

import '../core/state/app_store.dart';
import 'router.dart';

class InouApp extends ConsumerWidget {
  const InouApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(appStoreProvider.select((s) => s.themeMode));
    return MaterialApp.router(
      title: 'InoU 伴学工作室',
      debugShowCheckedModeBanner: false,
      theme: InouTheme.light(),
      darkTheme: InouTheme.dark(),
      themeMode: themeMode,
      routerConfig: router,
      builder: (context, child) {
        return AdaptiveScopeProvider(child: child ?? const SizedBox.shrink());
      },
    );
  }
}
