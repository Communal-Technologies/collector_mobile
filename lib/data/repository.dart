import '../core/config.dart';
import 'api_client.dart';
import 'local_cache.dart';
import 'models.dart';
import 'outbox.dart';

/// The result of verifying a login code.
class LoginResult {
  const LoginResult({
    required this.token,
    required this.refreshToken,
    required this.grant,
    required this.profile,
  });

  final String token;
  final String refreshToken;
  final CollectorGrant grant;
  final CollectorProfile profile;
}

/// Sign-in. Three steps, because a collector arrives in one of two states: someone
/// who is already a member of the cooperative has the 6-digit PIN every member has,
/// and someone registered only as a collector has never set one and sets it here.
class AuthRepository {
  AuthRepository(this._api);

  final ApiClient _api;

  Future<LoginChallenge> loginRequest({
    required String login,
    String? pin,
    String? channel,
  }) async {
    final body = <String, dynamic>{'login': login};
    if ((pin ?? '').isNotEmpty) body['pin'] = pin;
    if ((channel ?? '').isNotEmpty) body['channel'] = channel;
    final data = await _api.post(ApiPaths.loginRequest, body: body, anonymous: true);
    return LoginChallenge.fromJson(data);
  }

  Future<LoginChallenge> loginResend({
    required String challengeId,
    String? channel,
  }) async {
    final body = <String, dynamic>{'challenge_id': challengeId};
    if ((channel ?? '').isNotEmpty) body['channel'] = channel;
    final data = await _api.post(ApiPaths.loginResend, body: body, anonymous: true);
    // The resend answers with the channel it used and nothing about the grants, so
    // the challenge id and the grants already on screen are carried forward.
    return LoginChallenge.fromJson({...data, 'challenge_id': challengeId});
  }

  Future<LoginResult> loginVerify({
    required String challengeId,
    required String code,
    required String collectorId,
    String? newPin,
    bool rememberMe = true,
  }) async {
    final body = <String, dynamic>{
      'challenge_id': challengeId,
      'code': code,
      'collector_id': collectorId,
      'remember_me': rememberMe,
    };
    if ((newPin ?? '').isNotEmpty) body['new_pin'] = newPin;
    final data = await _api.post(ApiPaths.loginVerify, body: body, anonymous: true);
    return LoginResult(
      token: (data['token'] ?? '').toString(),
      refreshToken: (data['refresh_token'] ?? '').toString(),
      grant: CollectorGrant.fromJson(
        (data['collector'] as Map<String, dynamic>?) ?? const {},
      ),
      profile: CollectorProfile.fromJson(
        (data['user'] as Map<String, dynamic>?) ?? const {},
      ),
    );
  }
}

/// Everything the app reads and writes once it is signed in.
class CollectorRepository {
  CollectorRepository(this._api, {LocalCache? cache})
      : _cache = cache ?? LocalCache();

  final ApiClient _api;
  final LocalCache _cache;

  List<Map<String, dynamic>> _list(Map<String, dynamic> data, String key) =>
      ((data[key] as List<dynamic>?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList();

  /// Which cooperatives this account collects for, re-read from the server so a
  /// grant the cooperative changed — new terms, a new limit, a suspension — is not
  /// carried around stale on the device.
  Future<List<CollectorGrant>> myGrants() async {
    final data = await _api.get(ApiPaths.myCollectorAccounts);
    return _list(data, 'collectors').map(CollectorGrant.fromJson).toList();
  }

  /// Cash in hand and the ceiling on it. Cached, because it is what the app decides
  /// whether a collection is even allowed against — and a collector out of signal
  /// still needs to be told when they are at their limit rather than find out from a
  /// refusal after the money is in their pocket.
  Future<CollectorStanding> standing(String cooperativeId) async {
    final key = 'standing:$cooperativeId';
    try {
      final data = await _api.get(
        ApiPaths.standing,
        query: {'cooperative': cooperativeId},
      );
      final row = (data['standing'] as Map<String, dynamic>?) ?? const {};
      await _cache.putMap(key, row);
      return CollectorStanding.fromJson(row);
    } on ApiException catch (e) {
      if (!e.isTransport) rethrow;
      final row = await _cache.getMap(key);
      if (row == null) rethrow;
      return CollectorStanding.fromJson(row);
    }
  }

  /// The round. Falls back to the roster cached on the device when the network is
  /// gone, filtering it here rather than on the server — a collector standing at a
  /// door with no signal still has to find the right member.
  Future<Cached<CollectorMember>> members(
    String cooperativeId, {
    String query = '',
    int limit = 200,
  }) async {
    final key = 'members:$cooperativeId';
    try {
      final data = await _api.get(ApiPaths.members, query: {
        'cooperative': cooperativeId,
        if (query.trim().isNotEmpty) 'q': query.trim(),
        'limit': limit,
      });
      final rows = _list(data, 'members');
      // Only the whole roster is cached. A search result is a slice of it, and
      // caching slices would leave the device with a roster that has holes in it.
      if (query.trim().isEmpty) await _cache.putList(key, rows);
      return Cached(rows.map(CollectorMember.fromJson).toList());
    } on ApiException catch (e) {
      if (!e.isTransport) rethrow;
      final rows = await _cache.getList(key);
      if (rows == null) rethrow;
      final all = rows.map(CollectorMember.fromJson).toList();
      final needle = query.trim().toLowerCase();
      final filtered = needle.isEmpty
          ? all
          : all
              .where((m) =>
                  m.fullName.toLowerCase().contains(needle) ||
                  m.ledgerNumber.toLowerCase().contains(needle) ||
                  m.phone.contains(needle))
              .toList();
      return Cached(filtered, stale: true);
    }
  }

  Future<Cached<MemberObligation>> memberObligations(
    String cooperativeId,
    String ledgerNumber,
  ) async {
    final key = 'obligations:$cooperativeId:$ledgerNumber';
    try {
      final data = await _api.get(
        ApiPaths.memberObligations(ledgerNumber),
        query: {'cooperative': cooperativeId},
      );
      final rows = _list(data, 'obligations');
      await _cache.putList(key, rows);
      return Cached(rows.map(MemberObligation.fromJson).toList());
    } on ApiException catch (e) {
      if (!e.isTransport) rethrow;
      final rows = await _cache.getList(key);
      if (rows == null) rethrow;
      return Cached(
        rows.map(MemberObligation.fromJson).toList(),
        stale: true,
      );
    }
  }

  /// Sends one queued receipt. The client reference travels with it, so a second
  /// send of the same receipt returns the collection the first one filed.
  Future<Collection> submitCollection(PendingCollection pending) async {
    final data = await _api.post(
      ApiPaths.collections,
      body: pending.toRequestJson(),
    );
    return Collection.fromJson(
      (data['collection'] as Map<String, dynamic>?) ?? const {},
    );
  }

  Future<List<Collection>> collections(
    String cooperativeId, {
    String status = '',
    int limit = 50,
  }) async {
    final data = await _api.get(ApiPaths.collections, query: {
      'cooperative': cooperativeId,
      if (status.isNotEmpty) 'status': status,
      'limit': limit,
    });
    return _list(data, 'collections').map(Collection.fromJson).toList();
  }

  Future<List<RemittanceAccount>> remittanceAccounts(String cooperativeId) async {
    final data = await _api.get(
      ApiPaths.remittanceAccounts,
      query: {'cooperative': cooperativeId},
    );
    return _list(data, 'accounts').map(RemittanceAccount.fromJson).toList();
  }

  Future<Remittance> createRemittance({
    required String cooperativeId,
    required String toRepositoryId,
    required int amount,
    String narration = '',
  }) async {
    final data = await _api.post(ApiPaths.remittances, body: {
      'cooperative_id': cooperativeId,
      'to_repository_id': toRepositoryId,
      'amount': amount,
      'narration': narration,
    });
    return Remittance.fromJson(
      (data['data'] as Map<String, dynamic>?) ?? const {},
    );
  }

  Future<List<Remittance>> remittances(String cooperativeId, {int limit = 50}) async {
    final data = await _api.get(ApiPaths.remittances, query: {
      'cooperative': cooperativeId,
      'limit': limit,
    });
    return _list(data, 'remittances').map(Remittance.fromJson).toList();
  }

  Future<(EarningsSummary, List<CommissionEntry>)> earnings(
    String cooperativeId, {
    int limit = 50,
  }) async {
    final data = await _api.get(ApiPaths.earnings, query: {
      'cooperative': cooperativeId,
      'limit': limit,
    });
    return (
      EarningsSummary.fromJson(
        (data['summary'] as Map<String, dynamic>?) ?? const {},
      ),
      _list(data, 'commissions').map(CommissionEntry.fromJson).toList(),
    );
  }
}
