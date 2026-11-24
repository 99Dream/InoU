import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'workspace_storage.dart';

class IoFileBlobStorage implements KeyValueBlobStorage {
  IoFileBlobStorage([this._rootDir]);

  static const MethodChannel _channel = MethodChannel(
    'com.inou.inou_app/native_media',
  );

  Directory? _rootDir;

  Future<Directory> _resolveDir() async {
    if (_rootDir != null) {
      if (!await _rootDir!.exists()) {
        await _rootDir!.create(recursive: true);
      }
      return _rootDir!;
    }

    String? resolvedPath;
    if (Platform.isAndroid) {
      try {
        resolvedPath = await _channel.invokeMethod<String>('getWorkspaceDir');
      } catch (_) {
        resolvedPath = null;
      }
      resolvedPath ??= p.join(
        Directory.systemTemp.parent.path,
        'files',
        'inou_workspace',
      );
    } else {
      resolvedPath = Platform.environment['INOU_DATA_DIR']?.isNotEmpty == true
          ? Platform.environment['INOU_DATA_DIR']!
          : p.join(Directory.systemTemp.path, 'inou_workspace');
    }

    final dir = Directory(resolvedPath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _rootDir = dir;
    return dir;
  }

  File _fileForKey(Directory dir, String key) {
    final safeName = key.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    return File(p.join(dir.path, '$safeName.json'));
  }

  File _safeBinaryFile(Directory dir, String relativePath) {
    final normalized = p.normalize(relativePath).replaceAll('\\', '/');
    final cleanParts = normalized
        .split('/')
        .where((s) => s.isNotEmpty && s != '..' && s != '.')
        .toList();
    return File(p.joinAll([dir.path, ...cleanParts]));
  }

  @override
  Future<String?> readString(String key) async {
    try {
      final dir = await _resolveDir();
      final f = _fileForKey(dir, key);
      if (!await f.exists()) return null;
      return await f.readAsString();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> writeString(String key, String value) async {
    try {
      final dir = await _resolveDir();
      final f = _fileForKey(dir, key);
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(value, flush: true);
      if (await f.exists()) {
        await f.delete();
      }
      await tmp.rename(f.path);
    } catch (_) {
      // Ignore write failures in read-only test sandboxes
    }
  }

  @override
  Future<void> deleteKey(String key) async {
    try {
      final dir = await _resolveDir();
      final f = _fileForKey(dir, key);
      if (await f.exists()) {
        await f.delete();
      }
    } catch (_) {
      // Ignore cleanup errors
    }
  }

  @override
  Future<void> writeBinary(String relativePath, Uint8List bytes) async {
    try {
      final dir = await _resolveDir();
      final f = _safeBinaryFile(dir, relativePath);
      if (!await f.parent.exists()) {
        await f.parent.create(recursive: true);
      }
      await f.writeAsBytes(bytes, flush: true);
    } catch (_) {
      // Ignore write failures in read-only test sandboxes
    }
  }

  @override
  Future<Uint8List?> readBinary(String relativePath) async {
    try {
      final dir = await _resolveDir();
      final f = _safeBinaryFile(dir, relativePath);
      if (!await f.exists()) return null;
      return await f.readAsBytes();
    } catch (_) {
      return null;
    }
  }
}

KeyValueBlobStorage createPlatformBlobStorage() => IoFileBlobStorage();
