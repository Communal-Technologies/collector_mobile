import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:communal_collector/data/models.dart';
import 'package:communal_collector/data/outbox.dart';
import 'package:communal_collector/data/pin_lock.dart';
import 'package:communal_collector/data/repository.dart';
import 'package:communal_collector/data/session_store.dart';
import 'package:communal_collector/state/outbox_cubit.dart';
import 'package:communal_collector/state/session_cubit.dart';
import 'package:communal_collector/widgets/session_guard.dart';

import 'support/fakes.dart';
import 'support/memory_secure_storage.dart';

/// A cooperative that ends the grant partway through the test — while the app is in
/// the collector's pocket, which is the case worth proving.
class LapsingGrantsRepo extends CollectorRepository {
  LapsingGrantsRepo() : super(offlineClient());

  bool revoked = false;

  @override
  Future<List<CollectorGrant>> myGrants() async => revoked ? [] : [testGrant];
}

void main() {
  late SessionCubit session;

  /// The app's idle figures are minutes long, so the test moves the clock rather
  /// than waiting on it. The ticks come from `pump`; what they read comes from here.
  late DateTime now;

  SessionCubit newSession({CollectorRepository? repository}) => SessionCubit(
    store: SessionStore(secure: MemorySecureStorage()),
    repository: repository ?? FakeCollectorRepo(),
    auth: FakeAuth(),
    lock: PinLock(secure: MemorySecureStorage()),
    clock: () => now,
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    now = DateTime(2026, 8, 31, 9);
    session = newSession();
  });

  /// The idle watch is a timer on the cubit, which outlives the widget tree, and the
  /// framework checks for pending timers before a test is allowed to finish. Closing
  /// cancels the timer on the way in, so this is not awaited: the future it returns
  /// belongs to the test's own async zone and would never complete in a `tearDown`.
  void stopWatching() => session.close();

  Future<void> pumpGuard(WidgetTester tester) async {
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider.value(value: session),
          BlocProvider<OutboxCubit>(
            create: (_) =>
                OutboxCubit(outbox: Outbox(), repository: FakeCollectorRepo()),
          ),
        ],
        child: MaterialApp(
          home: SessionGuard(
            child: BlocBuilder<SessionCubit, SessionState>(
              builder: (context, state) => Scaffold(
                body: Center(child: Text(state.locked ? 'LOCKED' : 'ROUND')),
              ),
            ),
          ),
        ),
      ),
    );
    await session.completeLogin(
      LoginResult(
        token: 'access',
        refreshToken: 'refresh',
        grant: testGrant,
        profile: testProfile,
      ),
      pin: '123456',
    );
    await tester.pump();
    expect(find.text('ROUND'), findsOneWidget);
  }

  /// Backgrounding the way the platform does it: the binding generates the
  /// intermediate states, and a jump straight to `paused` is not one of them.
  ///
  /// Nothing is rendered afterwards — the binding disables frames for `paused`,
  /// `hidden` and `detached` — so these tests read the lock off the session, which
  /// is where it lives anyway.
  void background(WidgetTester tester) {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
  }

  testWidgets('leaving the app locks it at once, with no grace', (tester) async {
    await pumpGuard(tester);
    background(tester);
    expect(session.state.locked, isTrue);
    stopWatching();
  });

  testWidgets('the notification shade is not leaving the app', (tester) async {
    await pumpGuard(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(session.state.locked, isFalse);
    expect(find.text('ROUND'), findsOneWidget);
    stopWatching();
  });

  testWidgets('a swipe away locks it too', (tester) async {
    await pumpGuard(tester);
    background(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.detached);
    expect(session.state.locked, isTrue);
    stopWatching();
  });

  testWidgets('coming back re-reads the grants even behind the lock', (
    tester,
  ) async {
    stopWatching();
    final repo = LapsingGrantsRepo();
    session = newSession(repository: repo);
    await pumpGuard(tester);
    background(tester);
    expect(session.state.locked, isTrue);

    repo.revoked = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));
    expect(session.state.status, SessionStatus.signedOut);
    stopWatching();
  });

  /// Time passing with nobody touching the phone: the clock moves, and the frames
  /// carrying the idle ticks are pumped over the same span.
  Future<void> sitIdle(WidgetTester tester, Duration span) async {
    now = now.add(span);
    await tester.pump(span);
  }

  group('the idle prompt', () {
    testWidgets('asks, and Stay carries on with the round', (tester) async {
      await pumpGuard(tester);
      await sitIdle(tester, const Duration(minutes: 3, seconds: 30));
      await tester.pumpAndSettle();
      expect(find.text('Are you still there?'), findsOneWidget);

      await tester.tap(find.text('Stay'));
      await tester.pumpAndSettle();
      expect(find.text('Are you still there?'), findsNothing);
      expect(find.text('ROUND'), findsOneWidget);
      stopWatching();
    });

    testWidgets('takes itself down when the lock it warned about arrives', (
      tester,
    ) async {
      await pumpGuard(tester);
      await sitIdle(tester, const Duration(minutes: 3, seconds: 30));
      await tester.pumpAndSettle();
      expect(find.text('Are you still there?'), findsOneWidget);

      await sitIdle(tester, const Duration(minutes: 2));
      await tester.pumpAndSettle();
      expect(find.text('Are you still there?'), findsNothing);
      expect(find.text('LOCKED'), findsOneWidget);
      stopWatching();
    });

    testWidgets('Lock now answers it the other way', (tester) async {
      await pumpGuard(tester);
      await sitIdle(tester, const Duration(minutes: 3, seconds: 30));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Lock now'));
      await tester.pumpAndSettle();
      expect(find.text('Are you still there?'), findsNothing);
      expect(find.text('LOCKED'), findsOneWidget);
      stopWatching();
    });
  });
}
