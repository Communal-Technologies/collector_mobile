import 'package:dio/dio.dart';

import 'package:communal_collector/data/api_client.dart';
import 'package:communal_collector/data/models.dart';
import 'package:communal_collector/data/repository.dart';
import 'package:communal_collector/data/session_store.dart';

import 'memory_secure_storage.dart';

final testGrant = CollectorGrant.fromJson({
  'collector_id': '41',
  'collector_code': 'CL-9F3KQ2XB',
  'cooperative_id': 'Tco-8934',
  'cooperative_name': 'Unity Coop',
  'status': 'active',
});

final testProfile = CollectorProfile.fromJson({
  'id': '7',
  'first_name': 'Ada',
  'last_name': 'Obi',
  'phone': '08031234567',
});

/// A client carrying an origin of its own, so the tests do not need the build's
/// `BASE_URL` define. Nothing here ever reaches it: every call is overridden.
ApiClient offlineClient() => ApiClient(
  SessionStore(secure: MemorySecureStorage()),
  dio: Dio(BaseOptions(baseUrl: 'http://127.0.0.1:1')),
);

/// Stands in for the platform: [answer] is what the unlock call returns, [throws]
/// what it raises instead.
class FakeAuth extends AuthRepository {
  FakeAuth({this.answer, this.throws}) : super(offlineClient());

  UnlockCheck? answer;
  ApiException? throws;
  int calls = 0;

  /// What the client raises when the request never left the phone.
  void goOffline() => throws = ApiException('No connection.', offline: true);

  @override
  Future<UnlockCheck> unlock(String pin) async {
    calls++;
    final failure = throws;
    if (failure != null) throw failure;
    return answer ?? UnlockCheck.ok;
  }
}

class FakeCollectorRepo extends CollectorRepository {
  FakeCollectorRepo() : super(offlineClient());

  @override
  Future<List<CollectorGrant>> myGrants() async => [testGrant];
}
