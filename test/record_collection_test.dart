import 'package:communal_collector/core/theme.dart';
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
  _StubRepository(this.obligations, {this.fines = const [], this.finesFail = false})
      : super(ApiClient(SessionStore(), dio: Dio(BaseOptions(baseUrl: 'http://127.0.0.1'))));

  final List<MemberObligation> obligations;

  /// The fines raised against the member directly, which are read separately from
  /// the ones riding on an obligation.
  final List<MemberFine> fines;
  final bool finesFail;

  @override
  Future<Cached<MemberObligation>> memberObligations(
    String cooperativeId,
    String ledgerNumber,
  ) async =>
      Cached(obligations);

  @override
  Future<Cached<MemberFine>> memberFines(
    String cooperativeId,
    String ledgerNumber,
  ) async {
    if (finesFail) throw ApiException('the fines could not be read');
    return Cached(fines);
  }

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

MemberObligation _obligation(
  String code,
  String name,
  int amount, {
  bool recurring = true,
  int pendingAmount = 0,
  List<MemberFine> fines = const [],
}) =>
    MemberObligation(
      id: code,
      accountCode: code,
      accountName: name,
      amount: amount,
      amountPaid: 0,
      category: recurring ? '1524' : '1523',
      recurring: recurring,
      frequency: recurring ? 'monthly' : '',
      // A one-off commitment has no cycle, so the server sends it no due date. The
      // screen reads that absence, so a test that handed one out anyway would be
      // testing a shape the server never produces.
      nextDueDate:
          recurring ? DateTime.now().add(const Duration(days: 3)) : null,
      pendingAmount: pendingAmount,
      fines: fines,
    );

MemberFine _fine(String id, int amount, {String obligationId = ''}) =>
    MemberFine(
      id: id,
      obligationId: obligationId,
      amount: amount,
      amountPaid: 0,
      status: 'pending',
      description: 'late payment',
      dueDate: DateTime.now().subtract(const Duration(days: 2)),
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
  List<MemberObligation> obligations, {
  List<MemberFine> fines = const [],
  bool finesFail = false,
}) async {
  final repository =
      _StubRepository(obligations, fines: fines, finesFail: finesFail);
  await tester.pumpWidget(
    RepositoryProvider<CollectorRepository>.value(
      value: repository,
      child: BlocProvider<OutboxCubit>(
        create: (_) => OutboxCubit(outbox: Outbox(), repository: repository),
        // The app's own theme, not the default one: the button themes carry the
        // sizes these screens are laid out against, and a bug that only exists
        // under them is invisible to a test that leaves them out.
        child: MaterialApp(
          theme: buildAppTheme(),
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

  testWidgets('a fine is collectable beside the account it was raised against',
      (tester) async {
    tester.view.physicalSize = const Size(720, 1612);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await _pumpScreen(
      tester,
      [
        _obligation('Dco-C-180302', 'Thrift Savings', 25000000,
            fines: [_fine('fine-1', 500000, obligationId: 'Dco-C-180302')]),
        _obligation('Dco-C-936038', 'Share Capital', 15500000,
            recurring: false),
      ],
      fines: [_fine('fine-2', 250000)],
    );

    // Three rows, not two: the fine on the thrift account and the one raised
    // against the member directly are each their own line on the receipt.
    expect(find.textContaining('Fine — Thrift Savings'), findsOneWidget);
    expect(find.textContaining('Fine — late payment'), findsOneWidget);

    await tester.tap(find.textContaining('Fine — Thrift Savings'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Settle'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Add ₦'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // Twice over: the row behind the sheet and the line on the receipt. What
    // matters is that the fine reached the receipt at all.
    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Fine — Thrift Savings'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('fines that cannot be read do not stop the contributions',
      (tester) async {
    tester.view.physicalSize = const Size(720, 1612);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await _pumpScreen(
      tester,
      [_obligation('Dco-C-180302', 'Thrift Savings', 25000000)],
      finesFail: true,
    );

    expect(find.textContaining('could not be'), findsOneWidget);
    expect(find.text('Thrift Savings'), findsOneWidget);
    await tester.tap(find.text('Fill owed'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Record ₦'), findsOneWidget);
  });

  testWidgets('a one-off commitment reads as progress, never as a due date',
      (tester) async {
    tester.view.physicalSize = const Size(720, 1612);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await _pumpScreen(tester, [
      _obligation('Dco-C-936038', 'Share Capital', 15500000, recurring: false),
    ]);

    expect(find.textContaining('of ₦155,000 paid'), findsOneWidget);
    expect(find.textContaining('due'), findsNothing);
    expect(find.textContaining('by '), findsNothing);

    // The sheet says what is left to finish it and offers no standing charge: a
    // one-off has no cycle for one to be the amount of.
    await tester.tap(find.text('Share Capital'));
    await tester.pumpAndSettle();
    expect(find.textContaining('left to complete it'), findsOneWidget);
    expect(find.textContaining('Pay the rest'), findsOneWidget);
    expect(find.textContaining('Standing'), findsNothing);
  });

  testWidgets('the due lens is a recurring account\'s question alone',
      (tester) async {
    tester.view.physicalSize = const Size(720, 1612);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    // Six rows so the lens bar is shown at all, and the only thing among them that
    // can have fallen due is the fine — a one-off commitment never does.
    await _pumpScreen(
      tester,
      [
        for (var i = 0; i < 6; i++)
          _obligation('E$i', 'Equity $i', 1000000, recurring: false),
      ],
      fines: [_fine('fine-2', 250000)],
    );

    await tester.tap(find.text('Due now'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Fine — late payment'), findsOneWidget);
    expect(find.textContaining('Equity'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a receipt awaiting approval holds the room on a capped account',
      (tester) async {
    tester.view.physicalSize = const Size(720, 1612);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    // ₦155,000 of share capital with ₦100,000 of it already on a receipt nobody has
    // countersigned. amount_paid does not move until one is posted, so the pending
    // figure is the only thing standing between the ₦155,000 outstanding and the
    // ₦55,000 that can actually be taken.
    await _pumpScreen(tester, [
      _obligation('Dco-C-936038', 'Share Capital', 15500000,
          recurring: false, pendingAmount: 10000000),
    ]);

    expect(find.textContaining('₦55,000 can be taken'), findsOneWidget);
    expect(find.textContaining('₦100,000 awaiting approval'), findsOneWidget);

    await tester.tap(find.text('Share Capital'));
    await tester.pumpAndSettle();

    // The one-tap amount is the room, not what is outstanding — offering the
    // outstanding figure would fill in a receipt the service is certain to refuse.
    expect(find.textContaining('waiting to be countersigned'), findsOneWidget);
    expect(find.textContaining('Pay the rest ₦55,000'), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, '60000');
    await tester.pumpAndSettle();

    expect(find.textContaining('Only ₦55,000.00 is left'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Add ₦60,000.00'),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('a capped account already fully receipted takes nothing more',
      (tester) async {
    tester.view.physicalSize = const Size(720, 1612);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await _pumpScreen(tester, [
      _obligation('Dco-C-936038', 'Share Capital', 15500000,
          recurring: false, pendingAmount: 15500000),
    ]);

    expect(find.textContaining('Fully receipted'), findsOneWidget);

    await tester.tap(find.text('Share Capital'));
    await tester.pumpAndSettle();

    // Nothing to fill in, so nothing is offered.
    expect(find.textContaining('Pay the rest'), findsNothing);

    await tester.enterText(find.byType(TextField).last, '1000');
    await tester.pumpAndSettle();

    expect(find.textContaining('have already been written'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Add ₦1,000.00'),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('more than is standing on a fine cannot be recorded',
      (tester) async {
    tester.view.physicalSize = const Size(720, 1612);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await _pumpScreen(
      tester,
      [_obligation('Dco-C-180302', 'Thrift Savings', 25000000)],
      fines: [_fine('fine-2', 250000)],
    );

    await tester.tap(find.textContaining('Fine — late payment'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '9000');
    await tester.pumpAndSettle();

    expect(find.textContaining('can only take'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Add ₦9,000.00'),
          )
          .onPressed,
      isNull,
    );
  });
}
