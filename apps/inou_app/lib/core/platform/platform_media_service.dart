import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show EdgeInsets;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Media or document payload returned by native camera, gallery, or file picker.
class PickedMediaResult {
  const PickedMediaResult({
    required this.bytes,
    required this.name,
    this.mimeType = 'image/jpeg',
  });

  final Uint8List bytes;
  final String name;
  final String mimeType;
}

/// Platform bridge abstracting native camera, gallery picker, file save/open,
/// system share sheet, and lossless JPEG 90° rotation.
abstract interface class PlatformMediaService {
  Future<PickedMediaResult?> capturePhoto();
  Future<PickedMediaResult?> pickGalleryImage();
  Future<PickedMediaResult?> pickFile({String mimeType = '*/*'});
  Future<bool> saveFile({
    required String filename,
    required String mimeType,
    required Uint8List bytes,
  });
  Future<bool> shareFile({
    required String filename,
    required String mimeType,
    required Uint8List bytes,
  });
  Future<Uint8List?> rotateImage90(Uint8List bytes);
  Future<EdgeInsets> getDisplayCutoutInsets();
}

final platformMediaServiceProvider = Provider<PlatformMediaService>(
  (ref) => const MethodChannelPlatformMediaService(),
);

class MethodChannelPlatformMediaService implements PlatformMediaService {
  const MethodChannelPlatformMediaService();

  static const MethodChannel _channel = MethodChannel(
    'com.inou.inou_app/native_media',
  );

  @override
  Future<PickedMediaResult?> capturePhoto() async {
    return _invokeMediaMap('capturePhoto');
  }

  @override
  Future<PickedMediaResult?> pickGalleryImage() async {
    return _invokeMediaMap('pickGalleryImage');
  }

  @override
  Future<PickedMediaResult?> pickFile({String mimeType = '*/*'}) async {
    return _invokeMediaMap('pickFile', {'mimeType': mimeType});
  }

  Future<PickedMediaResult?> _invokeMediaMap(
    String method, [
    Map<String, Object?>? args,
  ]) async {
    try {
      final raw = await _channel.invokeMapMethod<String, Object?>(method, args);
      if (raw == null) return null;
      final bytes = raw['bytes'];
      if (bytes is! Uint8List || bytes.isEmpty) return null;
      return PickedMediaResult(
        bytes: bytes,
        name: (raw['name'] as String?) ?? 'file',
        mimeType: (raw['mimeType'] as String?) ?? 'application/octet-stream',
      );
    } on MissingPluginException {
      throw PlatformException(
        code: 'UNSUPPORTED_PLATFORM',
        message: '当前运行环境不支持原生相机或文件对话框（请在 Android 设备上使用）',
      );
    }
  }

  @override
  Future<bool> saveFile({
    required String filename,
    required String mimeType,
    required Uint8List bytes,
  }) async {
    try {
      final ok = await _channel.invokeMethod<bool>('saveFile', {
        'filename': filename,
        'mimeType': mimeType,
        'bytes': bytes,
      });
      return ok ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<bool> shareFile({
    required String filename,
    required String mimeType,
    required Uint8List bytes,
  }) async {
    try {
      final ok = await _channel.invokeMethod<bool>('shareFile', {
        'filename': filename,
        'mimeType': mimeType,
        'bytes': bytes,
      });
      return ok ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<Uint8List?> rotateImage90(Uint8List bytes) async {
    try {
      return await _channel.invokeMethod<Uint8List>('rotateImage90', {
        'bytes': bytes,
      });
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<EdgeInsets> getDisplayCutoutInsets() async {
    try {
      final raw = await _channel.invokeMapMethod<String, Object?>(
        'getDisplayCutoutInsets',
      );
      if (raw == null) return EdgeInsets.zero;
      return EdgeInsets.fromLTRB(
        (raw['left'] as num?)?.toDouble() ?? 0.0,
        (raw['top'] as num?)?.toDouble() ?? 0.0,
        (raw['right'] as num?)?.toDouble() ?? 0.0,
        (raw['bottom'] as num?)?.toDouble() ?? 0.0,
      );
    } catch (_) {
      return EdgeInsets.zero;
    }
  }
}
