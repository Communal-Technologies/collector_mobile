import 'package:flutter_test/flutter_test.dart';

import 'package:communal_collector/data/pin_lock.dart';

import 'support/memory_secure_storage.dart';

void main() {
  late MemorySecureStorage secure;
  late PinLock lock;

  setUp(() {
    secure = MemorySecureStorage();
    lock = PinLock(secure: secure);
  });

  test('nothing matches before an online unlock has been made', () async {
    expect(await lock.isSet, isFalse);
    expect(await lock.matches('123456'), isFalse);
  });

  test('the remembered PIN matches and a wrong one does not', () async {
    await lock.remember('123456');
    expect(await lock.isSet, isTrue);
    expect(await lock.matches('123456'), isTrue);
    expect(await lock.matches('123457'), isFalse);
  });

  test('the PIN itself is never written down', () async {
    await lock.remember('123456');
    expect(secure.values.values.any((v) => v.contains('123456')), isFalse);
  });

  test('two verifiers for the same PIN differ', () async {
    await lock.remember('123456');
    final first = secure.values['collector_lock_verifier'];
    await lock.remember('123456');
    expect(secure.values['collector_lock_verifier'], isNot(first));
  });

  test('a changed PIN replaces the old one', () async {
    await lock.remember('123456');
    await lock.remember('654321');
    expect(await lock.matches('123456'), isFalse);
    expect(await lock.matches('654321'), isTrue);
  });

  test('failures count up, and a fresh verifier clears them', () async {
    await lock.remember('123456');
    expect(await lock.failures, 0);
    expect(await lock.recordFailure(), 1);
    expect(await lock.recordFailure(), 2);
    expect(await lock.failures, 2);
    await lock.remember('123456');
    expect(await lock.failures, 0);
  });

  test('forgetting leaves nothing behind', () async {
    await lock.remember('123456');
    await lock.recordFailure();
    await lock.forget();
    expect(await lock.isSet, isFalse);
    expect(await lock.failures, 0);
    expect(secure.values, isEmpty);
  });

  test('a corrupted verifier refuses rather than admits', () async {
    await lock.remember('123456');
    secure.values['collector_lock_verifier'] = 'not-a-verifier';
    expect(await lock.matches('123456'), isFalse);
  });
}
