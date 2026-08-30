import 'package:communal_collector/data/api_client.dart';
import 'package:communal_collector/data/local_cache.dart';
import 'package:communal_collector/data/models.dart';
import 'package:communal_collector/data/outbox.dart';
import 'package:communal_collector/data/repository.dart';
import 'package:communal_collector/data/session_store.dart';
import 'package:communal_collector/screens/record_collection_screen.dart';
import 'package:communal_collector/state/outbox_cubit.dart';
import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The receipt screen with no network under it: obligations and standing come back
/// immediately so a test can drive the buttons a collector actually presses.
class _StubRepository extends CollectorRepository {
  _StubRepository(this.obligations)
      : super(ApiClient(SessionStore(), dio: Dio(BaseOptions(baseUrl: 'http://127.0.0.1'))));

  final List<MemberObligation> obligations;

  @override
  Future<Cached<MemberObligation>> memberObligations(
    String cooperativeId,
    String ledgerNumber,
  ) async =>
      Cached(obligations);

  @override
  Future<CollectorStanding> standing(String cooperativeId) async =>
      const CollectorStanding(
        floatBalance: 0,
        pendingTotal: 0,
        pendingCount: 0,
        cashInHand: 0,
        cashLimitMinor: 5000000,
        headroom: 5000000,
        collectorCode: 'CL-TEST',
        fullName: 'Test Collector',
        status: 'active',
      );
}

class _StubConnectivity extends ConnectivityPlatform {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async =>
      [ConnectivityResult.wifi];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      const Stream<List<ConnectivityResult>>.empty();
}

MemberObligation _obligation(String code, String name, int amount) =>
    MemberObligation(
      id: code,
      accountCode: code,
      accountName: name,
      amount: amount,
      amountPaid: 0,
      frequency: 'monthly',
      nextDueDate: DateTime.now().add(const Duration(days: 3)),
    );

const _grant = CollectorGrant(
  collectorId: 'col-1',
  collectorCode: 'CL-TEST',
  cooperativeId: 'Dco-8306',
  cooperativeName: 'Dev Cooperative',
  fullName: 'Test Collector',
  settlementMode: 'on_approval',
  commissionType: 'percentage',
  commissionValue: 250,
  cashLimitMinor: 5000000,
  status: 'active',
);

const _member = CollectorMember(
  ledgerNumber: 'Dco-8306-13',
  fullName: 'Chidi Okafor',
  phone: '08000000000',
  deactivated: false,
  collectible: true,
  standing: 'active',
);

Future<void> _pumpScreen(
  WidgetTester tester,
  List<MemberObligation> obligations,
) async {
  final repository = _StubRepository(obligations);
  await tester.pumpWidget(
    RepositoryProvider<CollectorRepository>.value(
      value: repository,
      child: BlocProvider<OutboxCubit>(
        create: (_) => OutboxCubit(outbox: Outbox(), repository: repository),
        child: MaterialApp(
          home: RecordCollectionScreen(grant: _grant, member: _member),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ConnectivityPlatform.instance = _StubConnectivity();
  });

  testWidgets('filling every owed amount and clearing it again does not throw',
      (tester) async {
    tester.view.physicalSize = const Size(720, 1612);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await _pumpScreen(tester, [
      _obligation('Dco-C-180302', 'Thrift Savings', 25000000),
      _obligation('Dco-C-936038', 'Share Capital', 15500000),
    ]);

    await tester.tap(find.text('Fill owed'));
    await tester.pumpAndSettle();
    expect(find.text('Clear'), findsOneWidget);

    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Clear'), findsNothing);
    expect(find.text('Enter what the member paid'), findsOneWidget);
  });

  testWidgets('an amount entered through the row sheet survives being cleared',
      (tester) async {
    tester.view.physicalSize = const Size(720, 1612);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await _pumpScreen(tester, [
      _obligation('Dco-C-180302', 'Thrift Savings', 25000000),
      _obligation('Dco-C-936038', 'Share Capital', 15500000),
    ]);

    await tester.tap(find.text('Thrift Savings'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Pay all'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Add ₦'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Back to the accounts'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a whole chart of accounts filters, searches and clears',
      (tester) async {
    tester.view.physicalSize = const Size(720, 1612);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await _pumpScreen(tester, [
      _obligation('A', 'Thrift Savings', 25000000),
      _obligation('B', 'Share Capital', 15500000),
      _obligation('C', 'Development Levy', 5000000),
      _obligation('D', 'Building Fund', 12000000),
      _obligation('E', 'Welfare', 2500000),
      _obligation('F', 'Target Savings', 9000000),
      _obligation('G', 'Stationery', 100000),
    ]);

    expect(find.text('Owing'), findsOneWidget);
    await tester.tap(find.text('Fill owed'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'welfare');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Due now'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
