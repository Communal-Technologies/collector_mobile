import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

/// A collection the collector has written and the server has not accepted yet.
///
/// It is a receipt either way. The collector said a number out loud to a member and
/// wrote it down; whether there was signal at that moment is not the member's
/// problem, so the record is kept on the device until the server has it.
class PendingCollection {
  PendingCollection({
    required this.clientReference,
    required this.cooperativeId,
    required this.ledgerNumber,
    required this.memberName,
    required this.allocations,
    required this.note,
    required this.collectedAt,
    this.attempts = 0,
    this.lastError = '',
    this.rejected = false,
  });

  final String clientReference;
  final String cooperativeId;
  final String ledgerNumber;
  final String memberName;
  final List<CollectionAllocation> allocations;
  final String note;
  final DateTime collectedAt;

  int attempts;

  /// Why the last send failed, in the server's own words where it answered.
  String lastError;

  /// Set when the server refused the record on its merits — a limit, a member who
  /// is not on this round, an amount it will not take. Retrying changes nothing, so
  /// it stops being retried and starts being something the collector has to look at.
  bool rejected;

  int get totalAmount =>
      allocations.fold<int>(0, (sum, a) => sum + a.amount);

  Map<String, dynamic> toJson() => {
        'client_reference': clientReference,
        'cooperative_id': cooperativeId,
        'ledger_number': ledgerNumber,
        'member_name': memberName,
        'allocations': allocations.map((a) => a.toJson()).toList(),
        'note': note,
        'collected_at': collectedAt.toIso8601String(),
        'attempts': attempts,
        'last_error': lastError,
        'rejected': rejected,
      };

  factory PendingCollection.fromJson(Map<String, dynamic> json) {
    final raw = (json['allocations'] as List<dynamic>?) ?? const [];
    return PendingCollection(
      clientReference: (json['client_reference'] ?? '').toString(),
      cooperativeId: (json['cooperative_id'] ?? '').toString(),
      ledgerNumber: (json['ledger_number'] ?? '').toString(),
      memberName: (json['member_name'] ?? '').toString(),
      allocations: raw
          .whereType<Map<String, dynamic>>()
          .map(CollectionAllocation.fromJson)
          .toList(),
      note: (json['note'] ?? '').toString(),
      collectedAt: DateTime.tryParse((json['collected_at'] ?? '').toString()) ??
          DateTime.now(),
      attempts: int.tryParse((json['attempts'] ?? '0').toString()) ?? 0,
      lastError: (json['last_error'] ?? '').toString(),
      rejected: json['rejected'] == true,
    );
  }

  /// The wire shape obligations-svc accepts. `client_reference` is the idempotency
  /// key: the same receipt sent twice is the same collection, not a second one.
  Map<String, dynamic> toRequestJson() => {
        'cooperative': cooperativeId,
        'ledger_number': ledgerNumber,
        'client_reference': clientReference,
        'note': note.isEmpty ? null : note,
        'collected_at': collectedAt.toUtc().toIso8601String(),
        'allocations': allocations.map((a) => a.toRequestJson()).toList(),
      };
}

/// The device's own receipt book.
///
/// Two parts, and both matter. The counter is what makes a receipt readable and
/// ordered — a collector can say "receipt 214" to a member. The salt is what makes
/// it safe: it is minted once per install, so a reinstall cannot restart the
/// counter onto numbers the server has already filed. Without it, receipt 1 from a
/// fresh install would be treated as a resend of the first receipt this collector
/// ever wrote, and a real collection would vanish into an idempotent no-op.
class ReceiptBook {
  ReceiptBook._();

  static const String _kSalt = 'receipt_salt';
  static const String _kCounter = 'receipt_counter';
  static const String _alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  static Future<String> next() async {
    final prefs = await SharedPreferences.getInstance();
    var salt = prefs.getString(_kSalt) ?? '';
    if (salt.isEmpty) {
      final random = Random.secure();
      salt = List.generate(
        4,
        (_) => _alphabet[random.nextInt(_alphabet.length)],
      ).join();
      await prefs.setString(_kSalt, salt);
    }
    final counter = (prefs.getInt(_kCounter) ?? 0) + 1;
    await prefs.setInt(_kCounter, counter);
    return '$salt-${counter.toString().padLeft(6, '0')}';
  }

  /// The number the collector reads out — the book number without the install
  /// salt, which means nothing to anyone.
  static String bookNumber(String clientReference) {
    final parts = clientReference.split('-');
    return parts.isEmpty ? clientReference : parts.last;
  }
}

/// Durable storage for the queue.
///
/// SharedPreferences rather than a database: the queue is a handful of records at
/// worst, the whole list is written at once so a half-written queue is not a state
/// that exists, and it survives the app being killed — which is the only durability
/// property that matters here.
class Outbox {
  static const String _key = 'collector_outbox';

  Future<List<PendingCollection>> read() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .whereType<Map<String, dynamic>>()
          .map(PendingCollection.fromJson)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> write(List<PendingCollection> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(items.map((i) => i.toJson()).toList()),
    );
  }

  Future<void> add(PendingCollection item) async {
    final items = await read();
    items.add(item);
    await write(items);
  }

  Future<void> remove(String clientReference) async {
    final items = await read();
    items.removeWhere((i) => i.clientReference == clientReference);
    await write(items);
  }
}
