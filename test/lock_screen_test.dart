import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:communal_collector/data/pin_lock.dart';
import 'package:communal_collector/data/repository.dart';
import 'package:communal_collector/data/session_store.dart';
import 'package:communal_collector/screens/lock_screen.dart';
import 'package:communal_collector/state/connectivity_cubit.dart';
import 'package:communal_collector/state/session_cubit.dart';

import 'support/fakes.dart';
import 'support/memory_secure_storage.dart';

void main() {
  late FakeAuth auth;
  late PinLock lock;
  late SessionCubit session;
  late ConnectivityCubit connectivity;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    auth = FakeAuth();
    lock = PinLock(secure: MemorySecureStorage());
    session = SessionCubit(
      store: SessionStore(secure: MemorySecureStorage()),
      repository: FakeCollectorRepo(),
      auth: auth,
      lock: lock,
    );
    connectivity = ConnectivityCubit(
      transportChanges: const Stream<List<ConnectivityResult>>.empty(),
      checkTransport: () async => const [ConnectivityResult.mobile],
      probe: () async => true,
      retryInterval: const Duration(hours: 1),
    );
  });

  tearDown(() async {
    await session.close();
    await connectivity.close();
  });

  Future<void> signIn(WidgetTester tester, {String pin = '123456'}) async {
    await session.completeLogin(
      LoginResult(
        token: 'access',
        refreshToken: 'refresh',
        grant: testGrant,
        profile: testProfile,
      ),
      pin: pin,
    );
    session.lockNow();
    await tester.pump();
  }

  Future<void> pumpLock(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(430, 932)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      RepositoryProvider<AuthRepository>.value(
        value: auth,
        child: MultiBlocProvider(
          providers: [
            BlocProvider.value(value: session),
            BlocProvider.value(value: connectivity),
          ],
          child: const MaterialApp(home: LockScreen()),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('says who is signed in and which round is behind the lock', (
    tester,
  ) async {
    await pumpLock(tester);
    await signIn(tester);

    expect(find.textContaining('Welcome back, Ada'), findsOneWidget);
    expect(find.textContaining('Unity Coop'), findsOneWidget);
    expect(find.textContaining('08031234567'), findsOneWidget);
    expect(find.text('Unlock'), findsOneWidget);
  });

  testWidgets('a short PIN is not sent anywhere', (tester) async {
    await pumpLock(tester);
    await signIn(tester);

    await tester.enterText(find.byType(TextField), '123');
    await tester.tap(find.text('Unlock'));
    await tester.pump();

    expect(find.textContaining('6-digit PIN'), findsOneWidget);
    expect(auth.calls, 0);
  });

  testWidgets('offline, the right PIN opens the round', (tester) async {
    await pumpLock(tester);
    await signIn(tester);
    auth.goOffline();

    await tester.enterText(find.byType(TextField), '123456');
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();

    expect(session.state.locked, isFalse);
  });

  testWidgets('offline, a wrong PIN says how many tries are left', (
    tester,
  ) async {
    await pumpLock(tester);
    await signIn(tester);
    auth.goOffline();

    await tester.enterText(find.byType(TextField), '000000');
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();

    expect(find.textContaining('tries left'), findsOneWidget);
    expect(session.state.locked, isTrue);
  });

  testWidgets('a forgotten PIN opens the reset, on the same account', (
    tester,
  ) async {
    await pumpLock(tester);
    await signIn(tester);

    await tester.tap(find.text('Forgot your PIN?'));
    await tester.pumpAndSettle();

    expect(find.text('Reset your PIN'), findsOneWidget);
    // Prefilled from the session, so the code goes to the account already signed in.
    expect(
      tester
          .widget<TextField>(
            find.widgetWithText(TextField, 'Phone number or email'),
          )
          .controller
          ?.text,
      '08031234567',
    );
  });

  testWidgets('an account with no PIN is sent straight to creating one', (
    tester,
  ) async {
    auth.answer = UnlockCheck.needsPinSetup;
    await pumpLock(tester);
    await signIn(tester, pin: '');

    await tester.enterText(find.byType(TextField), '123456');
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();

    expect(find.text('Create your PIN'), findsOneWidget);
    expect(session.state.locked, isTrue);
  });
}
