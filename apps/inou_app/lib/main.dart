import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inou_domain/inou_domain.dart';
import 'package:material_ui/material_ui.dart';

import 'app/app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  final previousFlutterErrorHandler = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    InouDiagnosticsLogger.instance.error(
      'flutter.ui',
      details.exceptionAsString(),
      detail: details.context?.toDescription(),
      stackTrace: details.stack,
    );
    if (previousFlutterErrorHandler != null) {
      previousFlutterErrorHandler(details);
    } else {
      FlutterError.presentError(details);
    }
  };

  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    InouDiagnosticsLogger.instance.error(
      'dart.unhandled',
      error.toString(),
      error: error,
      stackTrace: stack,
    );
    return false;
  };

  InouDiagnosticsLogger.instance.info('app.lifecycle', 'InoU 应用启动');
  runApp(const ProviderScope(child: InouApp()));
}