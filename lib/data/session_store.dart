import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

/// Where the session lives between launches.
///
/// The tokens go in the keystore, because they are bearer credentials for real
/// money. Everything else — which grant the collector last acted under, their
/// name, the list of cooperatives they collect for — is ordinary preference data:
/// losing it costs a round trip, and leaking it tells an attacker nothing they
/// could not read off the phone's lock screen.
class SessionStore {
  SessionStore({FlutterSecureStorage? secure}) : _secure = secure ?? const FlutterSecureStorage();

  final FlutterSecureStorage _secure;

  static const String _kAccess = 'collector_access_token';
  static const String _kRefresh = 'collector_refresh_token';
  static const String _kGrants = 'collector_grants';
  static const String _kActiveGrant = 'collector_active_grant';
  static const String _kProfile = 'collector_profile';

  String? _accessToken;
  String? _refreshToken;

  /// Cached in memory so the request interceptor never has to await the keystore.
  String? get accessToken => _accessToken;
  String? get refreshToken => _refreshToken;
  bool get hasSession => (_accessToken ?? '').isNotEmpty;

  Future<void> load() async {
    _accessToken = await _readSecure(_kAccess);
    _refreshToken = await _readSecure(_kRefresh);
  }

  Future<void> saveTokens({required String access, required String refresh}) async {
    _accessToken = access;
    _refreshToken = refresh;
    await _secure.write(key: _kAccess, value: access);
    await _secure.write(key: _kRefresh, value: refresh);
  }

  Future<void> clear() async {
    _accessToken = null;
    _refreshToken = null;
    await _secure.delete(key: _kAccess);
    await _secure.delete(key: _kRefresh);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kGrants);
    await prefs.remove(_kActiveGrant);
    await prefs.remove(_kProfile);
  }

  Future<void> saveGrants(List<CollectorGrant> grants) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kGrants,
      jsonEncode(grants.map((g) => g.toJson()).toList()),
    );
  }

  Future<List<CollectorGrant>> readGrants() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kGrants);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .whereType<Map<String, dynamic>>()
          .map(CollectorGrant.fromJson)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveActiveGrant(CollectorGrant grant) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kActiveGrant, jsonEncode(grant.toJson()));
  }

  Future<CollectorGrant?> readActiveGrant() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kActiveGrant);
    if (raw == null || raw.isEmpty) return null;
    try {
      return CollectorGrant.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveProfile(CollectorProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kProfile, jsonEncode(profile.toJson()));
  }

  Future<CollectorProfile?> readProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kProfile);
    if (raw == null || raw.isEmpty) return null;
    try {
      return CollectorProfile.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<String?> _readSecure(String key) async {
    try {
      return await _secure.read(key: key);
    } catch (_) {
      // A keystore that will not open is a dead session, not a crash on launch.
      return null;
    }
  }
}
