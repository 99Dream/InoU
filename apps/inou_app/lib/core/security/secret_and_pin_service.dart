import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../storage/workspace_storage.dart';

/// Isolated credential store keeping BYOK endpoint API keys outside the
/// main non-secret workspace snapshot and `.inou` backup packages.
class SecretKeyStore {
  SecretKeyStore(this._storage);

  static const String _storageKey = 'inou_secrets_v1';
  final KeyValueBlobStorage _storage;

  Future<Map<String, String>> loadAllKeys() async {
    final raw = await _storage.readString(_storageKey);
    if (raw == null || raw.trim().isEmpty) return const <String, String>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded.map(
          (k, v) => MapEntry(k.toString(), v?.toString() ?? ''),
        );
      }
    } catch (_) {
      // Ignore corrupted key file
    }
    return const <String, String>{};
  }

  Future<void> saveKey(String endpointId, String apiKey) async {
    final map = Map<String, String>.from(await loadAllKeys());
    final trimmed = apiKey.trim();
    if (trimmed.isEmpty) {
      map.remove(endpointId);
    } else {
      map[endpointId] = trimmed;
    }
    await _storage.writeString(_storageKey, jsonEncode(map));
  }

  Future<void> saveAllKeys(Map<String, String> keys) async {
    final clean = <String, String>{
      for (final e in keys.entries)
        if (e.value.trim().isNotEmpty) e.key: e.value.trim(),
    };
    await _storage.writeString(_storageKey, jsonEncode(clean));
  }
}

/// Verification result for parent PIN gate.
class PinCheckResult {
  const PinCheckResult({
    required this.ok,
    this.lockedRemainingSeconds = 0,
    this.failedAttempts = 0,
    this.message = '',
  });

  final bool ok;
  final int lockedRemainingSeconds;
  final int failedAttempts;
  final String message;
}

/// Salted 10,000-round iterated SHA-256 Parent PIN security service with
/// 5-failure 30-second cooldown lockout (aligned with dev doc §13.3).
class ParentPinService {
  ParentPinService(this._storage);

  static const String _pinBlobKey = 'inou_parent_pin_v1';
  static const int _iterations = 10000;
  static const int maxAttemptsBeforeLock = 5;
  static const int lockCooldownSeconds = 30;

  final KeyValueBlobStorage _storage;
  final Random _random = Random.secure();

  Future<bool> hasPinConfigured() async {
    final rec = await _loadRecord();
    return rec != null &&
        (rec['hash'] as String? ?? '').isNotEmpty &&
        (rec['salt'] as String? ?? '').isNotEmpty;
  }

  Future<void> setPin(String pin) async {
    final trimmed = pin.trim();
    if (trimmed.length < 4) {
      throw ArgumentError('家长密码至少 4 位数字/字符');
    }
    final saltBytes = List<int>.generate(16, (_) => _random.nextInt(256));
    final saltB64 = base64Encode(saltBytes);
    final hash = _deriveIteratedSha256(trimmed, saltB64);
    await _storage.writeString(
      _pinBlobKey,
      jsonEncode({
        'salt': saltB64,
        'hash': hash,
        'failedAttempts': 0,
        'lockedUntilMs': 0,
      }),
    );
  }

  Future<void> clearPin() async {
    await _storage.deleteKey(_pinBlobKey);
  }

  Future<PinCheckResult> verifyPin(String candidate, {int? nowMs}) async {
    final rec = await _loadRecord();
    if (rec == null || (rec['hash'] as String? ?? '').isEmpty) {
      return const PinCheckResult(ok: true, message: '未启用家长锁');
    }
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final lockedUntil = (rec['lockedUntilMs'] as num?)?.toInt() ?? 0;
    if (lockedUntil > now) {
      final rem = ((lockedUntil - now) / 1000).ceil();
      return PinCheckResult(
        ok: false,
        lockedRemainingSeconds: rem,
        failedAttempts: (rec['failedAttempts'] as num?)?.toInt() ?? 5,
        message: '输错次数过多，请等待 $rem 秒后再试',
      );
    }

    final salt = rec['salt'] as String;
    final expectedHash = rec['hash'] as String;
    final actualHash = _deriveIteratedSha256(candidate.trim(), salt);

    if (_constantTimeEquals(actualHash, expectedHash)) {
      rec['failedAttempts'] = 0;
      rec['lockedUntilMs'] = 0;
      await _storage.writeString(_pinBlobKey, jsonEncode(rec));
      return const PinCheckResult(ok: true, message: '验证通过');
    }

    final prevFails = (rec['failedAttempts'] as num?)?.toInt() ?? 0;
    final nextFails = prevFails + 1;
    var nextLock = 0;
    var msg = '密码错误（第 $nextFails / $maxAttemptsBeforeLock 次）';
    if (nextFails >= maxAttemptsBeforeLock) {
      nextLock = now + lockCooldownSeconds * 1000;
      msg = '连续输错 $maxAttemptsBeforeLock 次，已锁定 $lockCooldownSeconds 秒';
    }
    rec['failedAttempts'] = nextFails >= maxAttemptsBeforeLock ? 0 : nextFails;
    rec['lockedUntilMs'] = nextLock;
    await _storage.writeString(_pinBlobKey, jsonEncode(rec));

    return PinCheckResult(
      ok: false,
      lockedRemainingSeconds: nextLock > now ? lockCooldownSeconds : 0,
      failedAttempts: nextFails,
      message: msg,
    );
  }

  Future<Map<String, Object?>?> _loadRecord() async {
    final raw = await _storage.readString(_pinBlobKey);
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry(k.toString(), v));
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  String _deriveIteratedSha256(String pin, String saltB64) {
    List<int> digestBytes = utf8.encode('$saltB64:$pin');
    for (var i = 0; i < _iterations; i++) {
      digestBytes = sha256.convert(digestBytes).bytes;
    }
    return base64Encode(digestBytes);
  }

  bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}
