import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// What lets the app ask for the PIN on a launch with no signal.
///
/// The server is the authority on the PIN — it is one PIN on one account and it can
/// be changed from the member app — so the lock checks with it whenever it can. But
/// a collector opens this app in front of a member at a door in a village, and
/// refusing to open without a connection would make the offline round the app exists
/// for impossible. So every successful *online* unlock leaves a verifier behind, and
/// an offline launch is checked against that.
///
/// A 6-digit PIN has a million values, so anything derivable on the device is
/// derivable by someone who has the device. Three things make that expensive rather
/// than free: the verifier is a PBKDF2-SHA256 derivation rather than the PIN or a
/// bare hash of it, it lives in the keystore (Android Keymaster / iOS Keychain)
/// rather than in preferences, and the offline attempts are counted and capped — the
/// session ends before a person could work through the space by hand. What it is not
/// is a defence against an attacker who has extracted the keystore and can grind
/// offline at their own pace; that is what the server check on the next connection is
/// for, and why the verifier is refreshed from it rather than trusted forever.
class PinLock {
  PinLock({FlutterSecureStorage? secure})
      : _secure = secure ?? const FlutterSecureStorage();

  final FlutterSecureStorage _secure;

  static const String _kVerifier = 'collector_lock_verifier';
  static const String _kAttempts = 'collector_lock_attempts';

  /// Cost of one derivation. Enough to make a scripted sweep slow, small enough
  /// that a collector waits a fraction of a second on a cheap phone.
  static const int iterations = 60000;

  static const int _saltBytes = 16;
  static const int _keyBytes = 32;

  /// Wrong PINs tolerated while offline before the session is ended. The receipts
  /// already written are not part of the session and stay on the phone.
  static const int maxOfflineAttempts = 5;

  Future<bool> get isSet async => (await _read(_kVerifier)) != null;

  /// Writes the verifier for [pin], replacing any earlier one. Called after the
  /// server has just accepted the PIN, never on the strength of a local check.
  Future<void> remember(String pin) async {
    final salt = _salt();
    final key = _pbkdf2(utf8.encode(pin), salt, iterations, _keyBytes);
    await _write(
      _kVerifier,
      '$iterations.${base64Encode(salt)}.${base64Encode(key)}',
    );
    await clearFailures();
  }

  /// Whether [pin] matches the stored verifier. False when there is none — an
  /// absent verifier must never read as a match.
  Future<bool> matches(String pin) async {
    final stored = await _read(_kVerifier);
    if (stored == null) return false;
    final parts = stored.split('.');
    if (parts.length != 3) return false;
    final rounds = int.tryParse(parts[0]) ?? 0;
    if (rounds <= 0) return false;
    try {
      final salt = base64Decode(parts[1]);
      final expected = base64Decode(parts[2]);
      final actual = _pbkdf2(utf8.encode(pin), salt, rounds, expected.length);
      return _constantTimeEquals(expected, actual);
    } catch (_) {
      return false;
    }
  }

  Future<void> forget() async {
    await _delete(_kVerifier);
    await _delete(_kAttempts);
  }

  Future<int> get failures async =>
      int.tryParse(await _read(_kAttempts) ?? '') ?? 0;

  /// Counts one wrong offline attempt and answers how many there have now been.
  Future<int> recordFailure() async {
    final next = (await failures) + 1;
    await _write(_kAttempts, next.toString());
    return next;
  }

  Future<void> clearFailures() => _delete(_kAttempts);

  Uint8List _salt() {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(_saltBytes, (_) => random.nextInt(256)),
    );
  }

  /// PBKDF2-HMAC-SHA256, one block at a time (RFC 2898). Built on `crypto`'s HMAC
  /// rather than on a second package that offers the derivation ready-made: the
  /// derivation is the loop below and nothing else, and the length asked for here
  /// never exceeds one block.
  Uint8List _pbkdf2(
    List<int> password,
    List<int> salt,
    int rounds,
    int length,
  ) {
    final hmac = Hmac(sha256, password);
    final out = <int>[];
    var block = 1;
    while (out.length < length) {
      final counter = Uint8List(4)
        ..[0] = (block >> 24) & 0xff
        ..[1] = (block >> 16) & 0xff
        ..[2] = (block >> 8) & 0xff
        ..[3] = block & 0xff;
      var u = hmac.convert([...salt, ...counter]).bytes;
      final t = List<int>.from(u);
      for (var i = 1; i < rounds; i++) {
        u = hmac.convert(u).bytes;
        for (var j = 0; j < t.length; j++) {
          t[j] ^= u[j];
        }
      }
      out.addAll(t);
      block++;
    }
    return Uint8List.fromList(out.sublist(0, length));
  }

  bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  Future<String?> _read(String key) async {
    try {
      return await _secure.read(key: key);
    } catch (_) {
      // A keystore that will not open leaves the lock with nothing to check
      // against, which the online path handles.
      return null;
    }
  }

  Future<void> _write(String key, String value) async {
    try {
      await _secure.write(key: key, value: value);
    } catch (_) {
      // Nothing to fall back to and nothing worth failing a launch over: without
      // a verifier the lock simply has to reach the server.
    }
  }

  Future<void> _delete(String key) async {
    try {
      await _secure.delete(key: key);
    } catch (_) {
      // Same: a verifier that will not delete is checked against a PIN the
      // server has already refused.
    }
  }
}
