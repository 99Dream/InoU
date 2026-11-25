import 'package:dio/dio.dart';

/// Configures platform-specific socket options for [dio] when running on VM/mobile.
void configureDioHttpClient(
  Dio dio, {
  Duration idleTimeout = const Duration(seconds: 5),
  Duration connectionTimeout = const Duration(seconds: 20),
  bool disableKeepAlive = false,
}) {}
