import 'package:flutter_test/flutter_test.dart';

import 'package:communal_collector/core/money.dart';
import 'package:communal_collector/data/models.dart';
import 'package:communal_collector/data/outbox.dart';

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
    test('falls back to the account code when the cooperative named nothing', () {
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
      expect(CollectorGrant.fromJson(const {}).commissionLabel, 'No commission');
    });

    test('posts on collection only when the cooperative said so', () {
      expect(
        CollectorGrant.fromJson({'settlement_mode': 'on_collection'})
            .postsOnCollection,
        isTrue,
      );
      expect(
        CollectorGrant.fromJson({'settlement_mode': 'on_remittance'})
            .postsOnCollection,
        isFalse,
      );
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
