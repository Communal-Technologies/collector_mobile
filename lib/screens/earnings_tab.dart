import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../core/money.dart';
import '../core/theme.dart';
import '../data/api_client.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../widgets/common.dart';

/// What the collector has earned, and where each part of it stands.
///
/// Three figures rather than two: still to be raised, on a payout awaiting a second
/// administrator, and paid. "On its way" is a different answer from "still owed", and
/// a collector chasing their commission deserves to be told which one it is.
class EarningsTab extends StatefulWidget {
  const EarningsTab({
    super.key,
    required this.grant,
    required this.revision,
  });

  final CollectorGrant grant;
  final int revision;

  @override
  State<EarningsTab> createState() => _EarningsTabState();
}

class _EarningsTabState extends State<EarningsTab> {
  Future<(EarningsSummary, List<CommissionEntry>)>? _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(EarningsTab oldWidget) {
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
          .earnings(widget.grant.cooperativeId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async => _load(),
      child: FutureBuilder<(EarningsSummary, List<CommissionEntry>)>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            final error = snapshot.error;
            return ListView(
              children: [
                const SizedBox(height: 60),
                EmptyState(
                  icon: Icons.wifi_off,
                  title: 'Could not load your earnings',
                  message: error is ApiException
                      ? error.message
                      : 'Pull down to try again.',
                ),
              ],
            );
          }
          final (summary, entries) = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
            children: [
              SectionCard(
                title: 'Your commission',
                trailing: Text(
                  widget.grant.commissionLabel,
                  style: const TextStyle(fontSize: 11, color: AppColors.muted),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: StatTile(
                            label: 'Still to be paid',
                            value: Money.format(summary.outstanding),
                            tone: AppColors.primary,
                          ),
                        ),
                        Expanded(
                          child: StatTile(
                            label: 'On a payout',
                            value: Money.format(summary.claimed),
                            tone: AppColors.warning,
                            hint: 'Awaiting a second administrator',
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: StatTile(
                            label: 'Paid to you',
                            value: Money.format(summary.paid),
                            tone: AppColors.success,
                          ),
                        ),
                        Expanded(
                          child: StatTile(
                            label: 'Collections',
                            value: '${summary.collections}',
                            hint: '${Money.formatWhole(summary.earned)} earned in all',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (summary.outstanding > 0)
                const Notice(
                  text: 'Commission is paid out by the cooperative in a batch, and every '
                      'payout needs two administrators to sign it off. Nothing here is '
                      'lost while it waits.',
                  icon: Icons.info_outline,
                ),
              const SizedBox(height: 14),
              SectionCard(
                title: 'Per collection',
                child: entries.isEmpty
                    ? const Text(
                        'No commission yet. It is priced when a collection posts, on '
                        'the terms in force at that moment.',
                        style: TextStyle(fontSize: 13, color: AppColors.muted),
                      )
                    : Column(
                        children: entries
                            .map((entry) => _CommissionRow(entry: entry))
                            .toList(),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CommissionRow extends StatelessWidget {
  const _CommissionRow({required this.entry});

  final CommissionEntry entry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.collectionReference.isEmpty
                      ? 'Collection'
                      : entry.collectionReference,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
                Text(
                  'On ${Money.format(entry.basisAmount)} · '
                  '${Dates.day(entry.paidAt ?? entry.createdAt)}',
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                Money.format(entry.amount),
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
              ),
              const SizedBox(height: 4),
              StatusChip(
                entry.status,
                label: entry.status == 'accrued' ? 'owed' : entry.status,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
