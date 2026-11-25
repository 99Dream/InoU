import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

/// Configures [dio]'s `IOHttpClientAdapter` to evict idle keep-alive sockets
/// aggressively (`idleTimeout` = 5s) or disable pooling (`Duration.zero`) so
/// NAT/CDN/relay gateways do not close pooled TCP sockets mid-request.
void configureDioHttpClient(
  Dio dio, {
  Duration idleTimeout = const Duration(seconds: 5),
  Duration connectionTimeout = const Duration(seconds: 20),
  bool disableKeepAlive = false,
}) {
  dio.httpClientAdapter = IOHttpClientAdapter(
    createHttpClient: () => HttpClient()
      ..idleTimeout = disableKeepAlive ? Duration.zero : idleTimeout
      ..connectionTimeout = connectionTimeout,
  );
}
