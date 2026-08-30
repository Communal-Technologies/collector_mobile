import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:iconsax/iconsax.dart';

import '../core/money.dart';
import '../core/theme.dart';
import '../data/api_client.dart';
import '../data/models.dart';
import '../data/outbox.dart';
import '../data/repository.dart';
import '../state/outbox_cubit.dart';
import '../widgets/common.dart';

/// Everything this collector has written, in one list: what is still on the phone
/// first, then what the cooperative has. The two are kept visually apart because
/// they mean different things — a receipt the cooperative cannot see yet is the
/// collector's own risk to carry.
class ReceiptsTab extends StatefulWidget {
  const ReceiptsTab({
    super.key,
    required this.grant,
    required this.revision,
    required this.onChanged,
  });

  final CollectorGrant grant;
  final int revision;
  final VoidCallback onChanged;

  @override
  State<ReceiptsTab> createState() => _ReceiptsTabState();
}

class _ReceiptsTabState extends State<ReceiptsTab> {
  Future<List<Collection>>? _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(ReceiptsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.revision != widget.revision ||
        oldWidget.grant.collectorId != widget.grant.collectorId) {
      _load();
    }
  }

  void _load() {
    setState(() {
      _future = context
          .read<CollectorRepository>()
          .collections(widget.grant.cooperativeId);
    });
  }

  Future<void> _openPending(PendingCollection pending) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => _PendingSheet(
        pending: pending,
        onRetry: () async {
          Navigator.of(sheetContext).pop();
          await context.read<OutboxCubit>().retry(pending.clientReference);
          if (mounted) widget.onChanged();
        },
        onDiscard: pending.rejected
            ? () async {
                Navigator.of(sheetContext).pop();
                await context
                    .read<OutboxCubit>()
                    .discardRejected(pending.clientReference);
                if (mounted) widget.onChanged();
              }
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<OutboxCubit, OutboxState>(
      builder: (context, outbox) {
        final local = outbox.items.toList()
          ..sort((a, b) => b.collectedAt.compareTo(a.collectedAt));
        return RefreshIndicator(
          onRefresh: () async {
            await context.read<OutboxCubit>().flush();
            _load();
            widget.onChanged();
          },
          child: FutureBuilder<List<Collection>>(
            future: _future,
            builder: (context, snapshot) {
              final waiting =
                  snapshot.connectionState == ConnectionState.waiting;
              final server = snapshot.data ?? const <Collection>[];
              if (waiting && local.isEmpty) {
                return const SkeletonRows(count: 5);
              }
              if (local.isEmpty && server.isEmpty) {
                return ListView(
                  children: [
                    const SizedBox(height: 60),
                    EmptyState(
                      icon: Iconsax.receipt_item,
                      title: 'No receipts yet',
                      message: snapshot.hasError
                          ? snapshot.error is ApiException
                              ? (snapshot.error as ApiException).message
                              : 'Pull down to try again.'
                          : 'Collections you record show up here, whether or not '
                              'they have reached the cooperative.',
                    ),
                  ],
                );
              }
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                children: [
                  if (local.isNotEmpty) ...[
                    const _GroupLabel('On this phone'),
                    ...local.map(
                      (pending) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _PendingTile(
                          pending: pending,
                          onTap: () => _openPending(pending),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  if (server.isNotEmpty) ...[
                    const _GroupLabel('With the cooperative'),
                    ...server.map(
                      (collection) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _CollectionTile(collection: collection),
                      ),
                    ),
                  ] else if (snapshot.hasError)
                    Notice(
                      text: snapshot.error is ApiException
                          ? (snapshot.error as ApiException).message
                          : 'Could not load the cooperative\'s copy of your receipts.',
                      icon: Iconsax.cloud_cross,
                    ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 2),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
          color: AppColors.muted,
        ),
      ),
    );
  }
}

class _PendingTile extends StatelessWidget {
  const _PendingTile({required this.pending, required this.onTap});

  final PendingCollection pending;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        title: Text(
          pending.memberName.isEmpty ? pending.ledgerNumber : pending.memberName,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
        isThreeLine: true,
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Receipt ${ReceiptBook.bookNumber(pending.clientReference)}',
              style: const TextStyle(fontSize: 12),
            ),
            Text(
              Dates.dayTime(pending.collectedAt),
              style: const TextStyle(fontSize: 12, color: AppColors.muted),
            ),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              Money.format(pending.totalAmount),
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
            ),
            const SizedBox(height: 4),
            StatusChip(
              pending.rejected ? 'declined' : 'unsent',
              label: pending.rejected ? 'refused' : 'unsent',
            ),
          ],
        ),
      ),
    );
  }
}

class _CollectionTile extends StatelessWidget {
  const _CollectionTile({required this.collection});

  final Collection collection;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          title: Text(
            collection.memberName.isEmpty
                ? collection.ledgerNumber
                : collection.memberName,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                collection.reference,
                style: const TextStyle(fontSize: 12),
              ),
              Text(
                Dates.dayTime(collection.collectedAt ?? collection.createdAt),
                style: const TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            ],
          ),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                Money.format(collection.totalAmount),
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
              ),
              const SizedBox(height: 4),
              StatusChip(collection.status),
            ],
          ),
          children: [
            ...collection.allocations.map(
              (allocation) => AmountRow(
                label: allocation.title.isEmpty
                    ? allocation.obligationCode
                    : allocation.title,
                amount: allocation.amount,
              ),
            ),
            if (collection.note.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                collection.note,
                style: const TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            ],
            if (collection.isDeclined) ...[
              const SizedBox(height: 10),
              Notice(
                text: collection.declineReason.isEmpty
                    ? 'The cooperative declined this receipt. Ask an administrator why.'
                    : 'Declined: ${collection.declineReason}',
                tone: AppColors.danger,
                background: AppColors.dangerSoft,
                icon: Iconsax.danger,
              ),
            ] else if (collection.isPending)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'Waiting for an administrator to countersign the cash. The '
                  'member\'s obligations move then.',
                  style: TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// What a receipt still on the phone can be told about, and what can be done with
/// it. A merely unsent one cannot be deleted: the cash was taken, so the record is
/// owed to the cooperative whatever the phone thinks.
class _PendingSheet extends StatelessWidget {
  const _PendingSheet({
    required this.pending,
    required this.onRetry,
    this.onDiscard,
  });

  final PendingCollection pending;
  final VoidCallback onRetry;
  final VoidCallback? onDiscard;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Receipt ${ReceiptBook.bookNumber(pending.clientReference)}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 2),
            Text(
              '${pending.memberName.isEmpty ? pending.ledgerNumber : pending.memberName} · '
              '${Dates.dayTime(pending.collectedAt)}',
              style: const TextStyle(fontSize: 12, color: AppColors.muted),
            ),
            const SizedBox(height: 14),
            ...pending.allocations.map(
              (allocation) => AmountRow(
                label: allocation.title.isEmpty
                    ? allocation.obligationCode
                    : allocation.title,
                amount: allocation.amount,
              ),
            ),
            const Divider(height: 20),
            AmountRow(label: 'Total', amount: pending.totalAmount, bold: true),
            const SizedBox(height: 14),
            Notice(
              text: pending.rejected
                  ? 'The cooperative refused this receipt: ${pending.lastError}\n\n'
                      'Nothing was recorded against the member. Sort it out with an '
                      'administrator, then send it again.'
                  : pending.lastError.isEmpty
                      ? 'Not sent yet. It goes up on its own as soon as this phone has '
                          'signal.'
                      : 'Not sent yet — last try: ${pending.lastError}',
              tone: pending.rejected ? AppColors.danger : AppColors.warning,
              background:
                  pending.rejected ? AppColors.dangerSoft : AppColors.warningSoft,
              icon: pending.rejected ? Iconsax.danger : Iconsax.cloud_cross,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onRetry,
                child: Text(pending.rejected ? 'Send again' : 'Try now'),
              ),
            ),
            if (onDiscard != null)
              Align(
                alignment: Alignment.center,
                child: TextButton(
                  onPressed: onDiscard,
                  child: const Text(
                    'Discard this receipt',
                    style: TextStyle(color: AppColors.danger),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
