import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:communal_collector/data/api_client.dart';
import 'package:communal_collector/data/pin_lock.dart';
import 'package:communal_collector/data/repository.dart';
import 'package:communal_collector/data/session_store.dart';
import 'package:communal_collector/state/session_cubit.dart';

import 'support/fakes.dart';
import 'support/memory_secure_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SessionStore store;
  late PinLock lock;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    store = SessionStore(secure: MemorySecureStorage());
    lock = PinLock(secure: MemorySecureStorage());
  });

  SessionCubit build(AuthRepository auth) => SessionCubit(
    store: store,
    repository: FakeCollectorRepo(),
    auth: auth,
    lock: lock,
  );

  Future<SessionCubit> signedIn(AuthRepository auth, {String pin = ''}) async {
    final cubit = build(auth);
    await cubit.completeLogin(
      LoginResult(
        token: 'access',
        refreshToken: 'refresh',
        grant: testGrant,
        profile: testProfile,
      ),
      pin: pin,
    );
    return cubit;
  }

  test('a stored session comes back locked', () async {
    await store.saveTokens(access: 'access', refresh: 'refresh');
    await store.saveActiveGrant(testGrant);
    await store.saveProfile(testProfile);

    final cubit = build(FakeAuth());
    await cubit.bootstrap();

    expect(cubit.state.status, SessionStatus.signedIn);
    expect(cubit.state.locked, isTrue);
    await cubit.close();
  });

  test('signing in is not locked, and leaves a verifier behind', () async {
    final cubit = await signedIn(FakeAuth(), pin: '123456');
    expect(cubit.state.locked, isFalse);
    expect(await lock.isSet, isTrue);
    await cubit.close();
  });

  test('the server is asked first, and unlocks', () async {
    final auth = FakeAuth();
    final cubit = await signedIn(auth, pin: '123456');
    cubit.lockNow();

    final outcome = await cubit.unlock('123456');
    expect(outcome.result, UnlockResult.unlocked);
    expect(auth.calls, 1);
    expect(cubit.state.locked, isFalse);
    await cubit.close();
  });

  test('a refusal from the server keeps the lock on and its own words', () async {
    final cubit = await signedIn(
      FakeAuth(throws: ApiException('That PIN is not right.', statusCode: 400)),
      pin: '123456',
    );
    cubit.lockNow();

    final outcome = await cubit.unlock('000000');
    expect(outcome.result, UnlockResult.wrongPin);
    expect(outcome.message, 'That PIN is not right.');
    expect(cubit.state.locked, isTrue);
    await cubit.close();
  });

  test('an account with no PIN is sent to create one', () async {
    final cubit = await signedIn(
      FakeAuth(answer: UnlockCheck.needsPinSetup),
      pin: '',
    );
    cubit.lockNow();

    final outcome = await cubit.unlock('123456');
    expect(outcome.result, UnlockResult.needsPinSetup);
    expect(cubit.state.locked, isTrue);
    await cubit.close();
  });

  test('offline with the right PIN opens on the stored verifier', () async {
    final auth = FakeAuth();
    final cubit = await signedIn(auth, pin: '123456');
    cubit.lockNow();
    auth.goOffline();

    final outcome = await cubit.unlock('123456');
    expect(outcome.result, UnlockResult.unlocked);
    expect(cubit.state.locked, isFalse);
    await cubit.close();
  });

  test('offline before any online unlock has nothing to check', () async {
    final auth = FakeAuth();
    final cubit = await signedIn(auth, pin: '');
    cubit.lockNow();
    auth.goOffline();

    final outcome = await cubit.unlock('123456');
    expect(outcome.result, UnlockResult.needsConnection);
    expect(cubit.state.locked, isTrue);
    await cubit.close();
  });

  test('offline wrong PINs count down and then end the session', () async {
    final auth = FakeAuth();
    final cubit = await signedIn(auth, pin: '123456');
    cubit.lockNow();
    auth.goOffline();

    for (var attempt = 1; attempt < PinLock.maxOfflineAttempts; attempt++) {
      final outcome = await cubit.unlock('000000');
      expect(outcome.result, UnlockResult.wrongPin);
      expect(cubit.state.status, SessionStatus.signedIn);
    }

    final last = await cubit.unlock('000000');
    expect(last.result, UnlockResult.signedOut);
    expect(cubit.state.status, SessionStatus.signedOut);
    expect(cubit.state.notice, contains('receipts'));
    // The verifier goes with the session, so the next collector to sign in on this
    // phone cannot be unlocked with the last one's PIN.
    expect(await lock.isSet, isFalse);
    await cubit.close();
  });
}
