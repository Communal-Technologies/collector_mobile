import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// The last answer the server gave, kept so the app still works where the signal
/// does not.
///
/// A collector's round is a walk through a neighbourhood, and the parts of it with
/// no coverage are exactly the parts where members cannot use the app themselves.
/// So the roster and each member's obligations are written down on the way past and
/// read back when the network is gone — enough to find the right person and write a
/// correct receipt. Nothing here is authoritative: every cached read says so, and
/// the record itself is still settled by the server.
class LocalCache {
  static const String _prefix = 'cache:';

  Future<void> putList(String key, List<Map<String, dynamic>> rows) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_prefix$key', jsonEncode(rows));
  }

  Future<void> putMap(String key, Map<String, dynamic> row) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_prefix$key', jsonEncode(row));
  }

  Future<Map<String, dynamic>?> getMap(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_prefix$key');
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  Future<List<Map<String, dynamic>>?> getList(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_prefix$key');
    if (raw == null || raw.isEmpty) return null;
    try {
      return (jsonDecode(raw) as List<dynamic>)
          .whereType<Map<String, dynamic>>()
          .toList();
    } catch (_) {
      return null;
    }
  }
}

/// A list and whether it came off the device rather than the server.
class Cached<T> {
  const Cached(this.items, {this.stale = false});

  final List<T> items;
  final bool stale;
}
