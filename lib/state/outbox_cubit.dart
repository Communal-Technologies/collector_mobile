import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/api_client.dart';
import '../data/models.dart';
import '../data/outbox.dart';
import '../data/repository.dart';

class OutboxState extends Equatable {
  const OutboxState({
    this.items = const [],
    this.syncing = false,
    this.lastSyncMessage = '',
  });

  final List<PendingCollection> items;
  final bool syncing;
  final String lastSyncMessage;

  /// Receipts still worth sending. A rejected one is not waiting for signal — it is
  /// waiting for the collector.
  Iterable<PendingCollection> get queued => items.where((i) => !i.rejected);
  Iterable<PendingCollection> get rejected => items.where((i) => i.rejected);

  int get queuedTotal => queued.fold<int>(0, (sum, i) => sum + i.totalAmount);

  OutboxState copyWith({
    List<PendingCollection>? items,
    bool? syncing,
    String? lastSyncMessage,
  }) =>
      OutboxState(
        items: items ?? this.items,
        syncing: syncing ?? this.syncing,
        lastSyncMessage: lastSyncMessage ?? this.lastSyncMessage,
      );

  @override
  List<Object?> get props => [
        items.map((i) => '${i.clientReference}:${i.attempts}:${i.rejected}').join(','),
        syncing,
        lastSyncMessage,
      ];
}

/// The device's unsent receipts, and the one place that sends them.
///
/// A collection is written locally first and always: the collector is standing in
/// front of a member, and a spinner that fails is not an answer. Sending is a
/// separate job that runs when it can — right after recording, when the connection
/// comes back, and whenever the collector pulls to refresh.
class OutboxCubit extends Cubit<OutboxState> {
  OutboxCubit({
    required Outbox outbox,
    required CollectorRepository repository,
    Connectivity? connectivity,
  })  : _outbox = outbox,
        _repository = repository,
        _connectivity = connectivity ?? Connectivity(),
        super(const OutboxState()) {
    _watchConnectivity();
  }

  final Outbox _outbox;
  final CollectorRepository _repository;
  final Connectivity _connectivity;

  bool _flushing = false;

  Future<void> load() async {
    emit(state.copyWith(items: await _outbox.read()));
  }

  void _watchConnectivity() {
    _connectivity.onConnectivityChanged.listen((results) {
      final online = results.any((r) => r != ConnectivityResult.none);
      if (online && state.queued.isNotEmpty) flush();
    });
  }

  /// Files a receipt and tries to send it. Returns the receipt so the screen can
  /// show the collector the number they just wrote.
  Future<PendingCollection> record({
    required String cooperativeId,
    required String ledgerNumber,
    required String memberName,
    required List<CollectionAllocation> allocations,
    required String note,
    DateTime? collectedAt,
  }) async {
    final pending = PendingCollection(
      clientReference: await ReceiptBook.next(),
      cooperativeId: cooperativeId,
      ledgerNumber: ledgerNumber,
      memberName: memberName,
      allocations: allocations,
      note: note,
      collectedAt: collectedAt ?? DateTime.now(),
    );
    await _outbox.add(pending);
    await load();
    await flush();
    return pending;
  }

  /// Sends the queue, oldest first and one at a time.
  ///
  /// Order matters because of the cash limit: the server checks each collection
  /// against what the collector is already holding, so sending them out of order
  /// could refuse a receipt that was within the limit when it was written.
  Future<void> flush() async {
    if (_flushing) return;
    final queue = state.queued.toList();
    if (queue.isEmpty) return;
    _flushing = true;
    emit(state.copyWith(syncing: true, lastSyncMessage: ''));
    var sent = 0;
    var message = '';
    for (final pending in queue) {
      try {
        await _repository.submitCollection(pending);
        await _outbox.remove(pending.clientReference);
        sent++;
      } on ApiException catch (e) {
        pending.attempts++;
        pending.lastError = e.message;
        // A transport failure is nothing to do with this record — stop, keep the
        // order, and try the whole queue again when there is signal. Anything the
        // server actually decided is this record's own problem.
        pending.rejected = !e.isTransport && (e.statusCode ?? 0) < 500;
        await _persist(pending);
        message = e.message;
        if (e.isTransport) break;
      } catch (e) {
        pending.attempts++;
        pending.lastError = e.toString();
        await _persist(pending);
        message = 'Could not sync. Will try again.';
        break;
      }
    }
    _flushing = false;
    await load();
    emit(state.copyWith(
      syncing: false,
      lastSyncMessage: message.isNotEmpty
          ? message
          : sent > 0
              ? '$sent ${sent == 1 ? 'receipt' : 'receipts'} synced.'
              : '',
    ));
  }

  /// Drops a receipt the server refused. Only a rejected one can be dropped: a
  /// record that is merely unsent is still owed to the cooperative.
  Future<void> discardRejected(String clientReference) async {
    final items = await _outbox.read();
    items.removeWhere((i) => i.clientReference == clientReference && i.rejected);
    await _outbox.write(items);
    await load();
  }

  /// Puts a rejected receipt back in the queue — for when the collector has had the
  /// cooperative fix whatever the server objected to.
  Future<void> retry(String clientReference) async {
    final items = await _outbox.read();
    for (final item in items) {
      if (item.clientReference == clientReference) {
        item.rejected = false;
        item.lastError = '';
      }
    }
    await _outbox.write(items);
    await load();
    await flush();
  }

  Future<void> _persist(PendingCollection pending) async {
    final items = await _outbox.read();
    for (var i = 0; i < items.length; i++) {
      if (items[i].clientReference == pending.clientReference) {
        items[i] = pending;
      }
    }
    await _outbox.write(items);
  }
}
