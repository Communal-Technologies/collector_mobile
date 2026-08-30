import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:communal_collector/core/money.dart';
import 'package:communal_collector/data/models.dart';
import 'package:communal_collector/data/outbox.dart';
import 'package:communal_collector/state/connectivity_cubit.dart';

void main() {
  group('Money', () {
    test('formats kobo as naira', () {
      expect(Money.format(123456), '₦1,234.56');
      expect(Money.formatWhole(123400), '₦1,234');
      expect(Money.formatWhole(123456), '₦1,234.56');
    });

    test('reads a grouped field back into kobo', () {
      expect(Money.parseToMinor('1,234'), 123400);
      expect(Money.parseToMinor('₦ 500'), 50000);
      expect(Money.parseToMinor(''), isNull);
    });
  });

  group('MemberObligation', () {
    test(
      'falls back to the account code when the cooperative named nothing',
      () {
        final named = MemberObligation.fromJson({
          'account_code': 'Bco-C-997724',
          'account_name': 'Monthly Savings',
          'amount': 500000,
          'amount_paid': 200000,
        });
        final unnamed = MemberObligation.fromJson({
          'account_code': 'Bco-C-997724',
          'amount': 500000,
          'amount_paid': 600000,
        });
        expect(named.title, 'Monthly Savings');
        expect(named.outstanding, 300000);
        expect(unnamed.title, 'Bco-C-997724');
        expect(unnamed.outstanding, 0);
      },
    );

    test('a one-off commitment carries no cycle and no due date', () {
      final equity = MemberObligation.fromJson({
        'account_code': 'Dco-C-936038',
        'account_name': 'Share Capital',
        'amount': 15500000,
        'amount_paid': 2000000,
        'category': '1523',
        'recurring': false,
      });
      expect(equity.recurring, isFalse);
      expect(equity.frequency, '');
      expect(equity.nextDueDate, isNull);
      expect(equity.outstanding, 13500000);
    });

    test('patronage recurs on the frequency the cooperative set', () {
      final patronage = MemberObligation.fromJson({
        'account_code': 'Dco-C-180302',
        'amount': 500000,
        'category': '1524',
        'recurring': true,
        'frequency': 'monthly',
        'next_due_date': '2026-09-30T00:00:00Z',
      });
      expect(patronage.recurring, isTrue);
      expect(patronage.frequency, 'monthly');
      expect(patronage.nextDueDate, isNotNull);
    });

    test(
      'a service that sends no recurring flag is read off the due date',
      () {
        // Every account looked recurring before the distinction existed, and a due
        // date is the honest signal of one: the service only ever computed one for
        // an account with a cycle to fall due in.
        expect(
          MemberObligation.fromJson({
            'account_code': 'A',
            'next_due_date': '2026-09-30T00:00:00Z',
          }).recurring,
          isTrue,
        );
        expect(
          MemberObligation.fromJson({'account_code': 'A'}).recurring,
          isFalse,
        );
      },
    );

    test('carries the fines raised against its missed cycles', () {
      final obligation = MemberObligation.fromJson({
        'account_code': 'Dco-C-180302',
        'amount': 500000,
        'fines': [
          {'id': 'f1', 'amount': 50000, 'status': 'pending'},
          {'id': 'f2', 'amount': 50000, 'status': 'waived'},
        ],
      });
      expect(obligation.fines, hasLength(2));
      expect(obligation.fines.first.collectible, isTrue);
      expect(obligation.fines.last.collectible, isFalse);
    });
  });

  group('MemberFine', () {
    test('only a pending fine with something left on it is collectible', () {
      MemberFine fine(String status, int paid) => MemberFine.fromJson({
            'id': 'f1',
            'amount': 50000,
            'amount_paid': paid,
            'status': status,
          });
      expect(fine('pending', 0).collectible, isTrue);
      expect(fine('pending', 20000).collectible, isTrue);
      expect(fine('pending', 50000).collectible, isFalse);
      expect(fine('waived', 0).collectible, isFalse);
      expect(fine('paid', 50000).collectible, isFalse);
    });
  });

  group('CollectionTarget', () {
    final savings = MemberObligation.fromJson({
      'account_code': 'Dco-C-180302',
      'account_name': 'Thrift Savings',
      'amount': 500000,
      'recurring': true,
      'next_due_date': '2026-09-30T00:00:00Z',
      'fines': [
        {'id': 'f1', 'amount': 50000, 'status': 'pending'},
        {'id': 'f2', 'amount': 50000, 'status': 'paid', 'amount_paid': 50000},
      ],
    });
    final shares = MemberObligation.fromJson({
      'account_code': 'Dco-C-936038',
      'account_name': 'Share Capital',
      'amount': 15500000,
      'amount_paid': 2000000,
      'recurring': false,
    });
    final adhoc = MemberFine.fromJson({
      'id': 'f3',
      'amount': 100000,
      'status': 'pending',
      'description': 'missed the general meeting',
    });

    test('puts each fine under what it was raised against', () {
      final targets = CollectionTarget.spread([savings, shares], [adhoc]);
      expect(
        targets.map((t) => t.title).toList(),
        [
          'Thrift Savings',
          'Fine — Thrift Savings',
          'Share Capital',
          'Fine — missed the general meeting',
        ],
      );
    });

    test('leaves out a fine the member no longer owes', () {
      final settled = CollectionTarget.spread([savings], const [])
          .where((t) => t.isFine)
          .toList();
      expect(settled, hasLength(1));
      expect(settled.single.fineId, 'f1');
    });

    test('a fine can never collide with an account', () {
      final targets = CollectionTarget.spread([savings, shares], [adhoc]);
      expect(targets.map((t) => t.key).toSet(), hasLength(targets.length));
      expect(targets[1].key, 'fine:f1');
      expect(targets[1].obligationCode, '');
      expect(targets[0].key, 'Dco-C-180302');
      expect(targets[0].fineId, '');
    });

    test('a one-off is progress towards a target, not a cycle', () {
      final target = CollectionTarget.obligation(shares);
      expect(target.recurring, isFalse);
      expect(target.nextDueDate, isNull);
      expect(target.amountPaid, 2000000);
      expect(target.outstanding, 13500000);
    });
  });

  group('PendingCollection', () {
    final pending = PendingCollection(
      clientReference: 'K7Q2-000214',
      cooperativeId: 'Tco-8934',
      ledgerNumber: 'Tco-8934-001',
      memberName: 'Ada Obi',
      allocations: const [
        CollectionAllocation(
          obligationCode: 'Bco-C-997724',
          title: 'Monthly Savings',
          amount: 200000,
        ),
        CollectionAllocation(
          obligationCode: 'Bco-C-997725',
          title: 'Development Levy',
          amount: 50000,
        ),
      ],
      note: '',
      collectedAt: DateTime.utc(2026, 8, 28, 9, 30),
    );

    test('totals its allocations', () {
      expect(pending.totalAmount, 250000);
    });

    test('never names the account to credit', () {
      // The server forces the collector's own float repository. A client that sent
      // one would either be ignored or be a way to credit somewhere it should not.
      final body = pending.toRequestJson();
      expect(body.containsKey('cash_repository_id'), isFalse);
      expect(body['client_reference'], 'K7Q2-000214');
      expect(body['allocations'], [
        {'obligation': 'Bco-C-997724', 'amount': 200000},
        {'obligation': 'Bco-C-997725', 'amount': 50000},
      ]);
    });

    test('survives a round trip through storage', () {
      final restored = PendingCollection.fromJson(pending.toJson());
      expect(restored.clientReference, pending.clientReference);
      expect(restored.totalAmount, pending.totalAmount);
      expect(restored.allocations.first.title, 'Monthly Savings');
    });

    test('a fine on the receipt names the fine and nothing else', () {
      final withFine = PendingCollection(
        clientReference: 'K7Q2-000215',
        cooperativeId: 'Tco-8934',
        ledgerNumber: 'Tco-8934-001',
        memberName: 'Ada Obi',
        allocations: const [
          CollectionAllocation(
            obligationCode: 'Bco-C-997724',
            title: 'Monthly Savings',
            amount: 200000,
          ),
          CollectionAllocation(
            obligationCode: '',
            fineId: 'fine-9a1c',
            title: 'Fine — Monthly Savings',
            amount: 50000,
          ),
        ],
        note: '',
        collectedAt: DateTime.utc(2026, 8, 28, 9, 30),
      );
      // The obligation line has to stay byte-for-byte what it always was: a
      // receipt queued by an older build sends exactly this, and the service reads
      // the absence of target_type as an obligation.
      expect(withFine.toRequestJson()['allocations'], [
        {'obligation': 'Bco-C-997724', 'amount': 200000},
        {'target_type': 'fine', 'fine_id': 'fine-9a1c', 'amount': 50000},
      ]);
      expect(withFine.totalAmount, 250000);
    });

    test('a queued fine line is still a fine after a restart', () {
      final restored = PendingCollection.fromJson(
        PendingCollection(
          clientReference: 'K7Q2-000216',
          cooperativeId: 'Tco-8934',
          ledgerNumber: 'Tco-8934-001',
          memberName: 'Ada Obi',
          allocations: const [
            CollectionAllocation(
              obligationCode: '',
              fineId: 'fine-9a1c',
              title: 'Fine — Monthly Savings',
              amount: 50000,
            ),
          ],
          note: '',
          collectedAt: DateTime.utc(2026, 8, 28, 9, 30),
        ).toJson(),
      );
      expect(restored.allocations.single.isFine, isTrue);
      expect(restored.allocations.single.fineId, 'fine-9a1c');
    });

    test('a receipt written before fines existed is read as an obligation', () {
      final restored = CollectionAllocation.fromJson({
        'obligation': 'Bco-C-997724',
        'title': 'Monthly Savings',
        'amount': 200000,
      });
      expect(restored.isFine, isFalse);
      expect(restored.toRequestJson(), {
        'obligation': 'Bco-C-997724',
        'amount': 200000,
      });
    });
  });

  group('ReceiptBook', () {
    test('reads out the counter without the install salt', () {
      expect(ReceiptBook.bookNumber('K7Q2-000214'), '000214');
    });
  });

  group('CollectorGrant', () {
    test('says the commission terms in words', () {
      expect(
        CollectorGrant.fromJson({
          'commission_type': 'percentage',
          'commission_value': 1200,
        }).commissionLabel,
        '12% of what you collect',
      );
      expect(
        CollectorGrant.fromJson({
          'commission_type': 'flat',
          'commission_value': 50000,
        }).commissionLabel,
        '₦500.00 per collection',
      );
      expect(
        CollectorGrant.fromJson(const {}).commissionLabel,
        'No commission',
      );
    });

    test('posts on collection only when the cooperative said so', () {
      expect(
        CollectorGrant.fromJson({
          'settlement_mode': 'on_collection',
        }).postsOnCollection,
        isTrue,
      );
      expect(
        CollectorGrant.fromJson({
          'settlement_mode': 'on_remittance',
        }).postsOnCollection,
        isFalse,
      );
    });
  });

  group('CollectorMember', () {
    test('an inactive membership is not collectible, and says which kind', () {
      final suspended = CollectorMember.fromJson({
        'ledger_number': 'Dco-8306-13',
        'deactivated': true,
        'collectible': false,
        'standing': 'suspended',
      });
      expect(suspended.collectible, isFalse);
      expect(suspended.standingLabel, 'suspended');
      expect(suspended.standingNote, contains('reinstate'));

      final lapsed = CollectorMember.fromJson({
        'ledger_number': 'Dco-8306-14',
        'deactivated': false,
        'collectible': false,
        'standing': 'lapsed',
      });
      expect(lapsed.collectible, isFalse);
      expect(lapsed.standingLabel, 'inactive');
      expect(lapsed.standingNote, contains('renew'));
    });

    test('a service that sends no standing at all does not lock out the round', () {
      final member = CollectorMember.fromJson({'ledger_number': 'Dco-8306-1'});
      expect(member.collectible, isTrue);
      expect(member.standing, 'active');
      expect(
        CollectorMember.fromJson({
          'ledger_number': 'Dco-8306-2',
          'deactivated': true,
        }).collectible,
        isFalse,
      );
    });
  });

  group('ConnectivityCubit', () {
    late StreamController<List<ConnectivityResult>> transport;
    ConnectivityCubit? cubit;

    setUp(() => transport = StreamController<List<ConnectivityResult>>());
    tearDown(() async {
      await cubit?.close();
      await transport.close();
    });

    ConnectivityCubit build({
      required Future<bool> Function() probe,
      List<ConnectivityResult> carrying = const [ConnectivityResult.mobile],
    }) {
      cubit = ConnectivityCubit(
        transportChanges: transport.stream,
        checkTransport: () async => carrying,
        probe: probe,
        retryInterval: const Duration(hours: 1),
      );
      return cubit!;
    }

    test('starts unknown so nothing is blocked before the first check', () {
      final c = build(probe: () async => true);
      expect(c.state.reachability, Reachability.unknown);
      expect(c.state.isOffline, isFalse);
    });

    test('a reachable host is online', () async {
      final c = build(probe: () async => true);
      await c.recheck();
      expect(c.state.isOnline, isTrue);
    });

    test(
      'signal that reaches nothing is offline, but with a transport',
      () async {
        final c = build(probe: () async => false);
        await c.recheck();
        expect(c.state.isOffline, isTrue);
        expect(c.state.hasTransport, isTrue);
      },
    );

    test('no transport is offline without probing at all', () async {
      var probed = 0;
      final c = build(
        probe: () async {
          probed++;
          return true;
        },
      );
      await c.recheck();
      final before = probed;

      transport.add(const [ConnectivityResult.none]);
      await Future<void>.delayed(Duration.zero);

      expect(c.state.isOffline, isTrue);
      expect(c.state.hasTransport, isFalse);
      expect(probed, before);
    });

    test('a real request outranks the probe', () async {
      final c = build(probe: () async => true);
      await c.recheck();

      c.markReachability(false);
      expect(c.state.isOffline, isTrue);

      c.markReachability(true);
      expect(c.state.isOnline, isTrue);
    });

    test('waiting for the platform gives up when told to', () async {
      final c = build(probe: () async => false);
      await c.recheck();
      final reachable = await c.waitUntilReachable(
        timeout: const Duration(milliseconds: 60),
      );
      expect(reachable, isFalse);
    });

    test('waiting returns at once when there is nothing to wait for', () async {
      final c = build(probe: () async => true);
      await c.recheck();
      expect(await c.waitUntilReachable(), isTrue);
    });
  });

  group('RemittanceAccount', () {
    test('labels an account without its number', () {
      final account = RemittanceAccount.fromJson({
        'account_name': 'Unity Coop Main',
        'bank': 'Providus Bank',
        'account_number': '0123456789',
      });
      expect(account.label, 'Unity Coop Main · Providus Bank');
      expect(account.label.contains('0123456789'), isFalse);
    });
  });
}
