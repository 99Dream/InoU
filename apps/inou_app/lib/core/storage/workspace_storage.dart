import 'dart:async';
import 'dart:typed_data';

import 'storage_stub.dart' if (dart.library.io) 'storage_io.dart' as platform;

/// Minimal key-value UTF-8 blob + binary attachment storage interface
/// decoupling persistence from Web / tests / mobile implementations.
abstract interface class KeyValueBlobStorage {
  Future<String?> readString(String key);
  Future<void> writeString(String key, String value);
  Future<void> deleteKey(String key);
  Future<void> writeBinary(String relativePath, Uint8List bytes);
  Future<Uint8List?> readBinary(String relativePath);
}

/// Pure in-memory storage ideal for isolated widget/unit tests.
class InMemoryBlobStorage implements KeyValueBlobStorage {
  InMemoryBlobStorage([Map<String, String>? seed])
    : _store = Map<String, String>.from(seed ?? const {});

  final Map<String, String> _store;
  final Map<String, Uint8List> _binaries = {};

  @override
  Future<String?> readString(String key) async => _store[key];

  @override
  Future<void> writeString(String key, String value) async {
    _store[key] = value;
  }

  @override
  Future<void> deleteKey(String key) async {
    _store.remove(key);
  }

  @override
  Future<void> writeBinary(String relativePath, Uint8List bytes) async {
    _binaries[relativePath] = bytes;
  }

  @override
  Future<Uint8List?> readBinary(String relativePath) async =>
      _binaries[relativePath];
}

/// Resolves the default persistent platform storage (local directory on IO
/// targets, in-memory fallback on web/sandboxed environments).
KeyValueBlobStorage createDefaultBlobStorage() =>
    platform.createPlatformBlobStorage();
