import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../core/money.dart';
import '../core/theme.dart';
import '../data/api_client.dart';
import '../data/local_cache.dart';
import '../data/models.dart';
import '../data/outbox.dart';
import '../data/repository.dart';
import '../state/outbox_cubit.dart';
import '../widgets/common.dart';

/// Writing the receipt.
///
/// The whole screen is one decision made several times: of the cash in the
/// collector's hand, how much goes against which obligation. Nothing is filled in
/// by default — a collector takes what a member gives them, which is often not what
/// is due — but what is due is shown beside every field and is one tap away.
class RecordCollectionScreen extends StatefulWidget {
  const RecordCollectionScreen({
    super.key,
    required this.grant,
    required this.member,
  });

  final CollectorGrant grant;
  final CollectorMember member;

  @override
  State<RecordCollectionScreen> createState() => _RecordCollectionScreenState();
}

class _RecordCollectionScreenState extends State<RecordCollectionScreen> {
  final _note = TextEditingController();
  final Map<String, TextEditingController> _amounts = {};

  Future<Cached<MemberObligation>>? _future;
  CollectorStanding? _standing;
  bool _saving = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _future = context.read<CollectorRepository>().memberObligations(
          widget.grant.cooperativeId,
          widget.member.ledgerNumber,
        );
    _loadStanding();
  }

  @override
  void dispose() {
    _note.dispose();
    for (final controller in _amounts.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadStanding() async {
    try {
      final standing = await context
          .read<CollectorRepository>()
          .standing(widget.grant.cooperativeId);
      if (mounted) setState(() => _standing = standing);
    } catch (_) {
      // No standing to check against. The server still checks the limit when the
      // receipt reaches it; this screen just cannot warn first.
    }
  }

  TextEditingController _controllerFor(String code) =>
      _amounts.putIfAbsent(code, () => TextEditingController());

  int get _total => _amounts.values
      .fold<int>(0, (sum, controller) => sum + moneyFieldMinor(controller));

  /// What this collector may still take before they have to remit.
  ///
  /// The server's headroom counts the float and the receipts it has already seen.
  /// Receipts still sitting on this phone are cash in the same pocket, so they come
  /// off too — otherwise the app would wave through a collection the server is
  /// certain to refuse the moment there is signal.
  int? get _headroom {
    final standing = _standing;
    if (standing == null || standing.headroom == null) return null;
    final queued = context
        .read<OutboxCubit>()
        .state
        .queued
        .where((i) => i.cooperativeId == widget.grant.cooperativeId)
        .fold<int>(0, (sum, i) => sum + i.totalAmount);
    return standing.headroom! - queued;
  }

  Future<void> _record(List<MemberObligation> obligations) async {
    final allocations = <CollectionAllocation>[];
    for (final obligation in obligations) {
      final amount = moneyFieldMinor(_controllerFor(obligation.accountCode));
      if (amount <= 0) continue;
      allocations.add(CollectionAllocation(
        obligationCode: obligation.accountCode,
        title: obligation.title,
        amount: amount,
      ));
    }
    if (allocations.isEmpty) {
      setState(() => _error = 'Enter what the member paid against at least one obligation.');
      return;
    }
    final total = allocations.fold<int>(0, (sum, a) => sum + a.amount);
    final headroom = _headroom;
    if (headroom != null && total > headroom) {
      setState(() => _error =
          'You can only take ${Money.format(headroom < 0 ? 0 : headroom)} more before you '
          'reach the cash limit your cooperative set. Remit what you are holding first.');
      return;
    }

    setState(() {
      _saving = true;
      _error = '';
    });
    final receipt = await context.read<OutboxCubit>().record(
          cooperativeId: widget.grant.cooperativeId,
          ledgerNumber: widget.member.ledgerNumber,
          memberName: widget.member.fullName,
          allocations: allocations,
          note: _note.text.trim(),
        );
    if (!mounted) return;
    setState(() => _saving = false);
    await _showReceipt(receipt, total);
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _showReceipt(PendingCollection receipt, int total) async {
    final synced = !context
        .read<OutboxCubit>()
        .state
        .items
        .any((i) => i.clientReference == receipt.clientReference);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Receipt written'),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Receipt ${ReceiptBook.bookNumber(receipt.clientReference)}',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            const SizedBox(height: 4),
            Text(
              '${Money.format(total)} from '
              '${widget.member.fullName.isEmpty ? widget.member.ledgerNumber : widget.member.fullName}',
            ),
            const SizedBox(height: 12),
            Text(
              synced
                  ? widget.grant.postsOnCollection
                      ? 'It has reached the cooperative and the member\'s obligations have '
                          'already moved.'
                      : 'It has reached the cooperative and is waiting for an administrator '
                          'to countersign the cash.'
                  : 'It is saved on this phone and goes to the cooperative as soon as you '
                      'have signal. Read the receipt number to the member either way.',
              style: const TextStyle(fontSize: 13, height: 1.4, color: AppColors.muted),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.member.fullName.isEmpty
        ? widget.member.ledgerNumber
        : widget.member.fullName;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            Text(
              widget.member.ledgerNumber,
              style: const TextStyle(fontSize: 11, color: AppColors.muted),
            ),
          ],
        ),
      ),
      body: FutureBuilder<Cached<MemberObligation>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            final error = snapshot.error;
            return EmptyState(
              icon: Icons.error_outline,
              title: 'Could not load this member\'s obligations',
              message: error is ApiException
                  ? error.message
                  : 'Go back and try again when you have signal.',
            );
          }
          final result = snapshot.data!;
          final obligations = result.items;
          if (obligations.isEmpty) {
            return const EmptyState(
              icon: Icons.inbox_outlined,
              title: 'Nothing to collect against',
              message: 'This member has no obligation accounts yet. The cooperative '
                  'has to open one before a collection can be filed.',
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              if (result.stale)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Notice(
                    text: 'No connection — these figures are from the last time this '
                        'phone reached the cooperative. What is owed may have changed.',
                    icon: Icons.cloud_off,
                  ),
                ),
              Notice(
                text: widget.grant.postsOnCollection
                    ? 'Your cooperative has you on trust: what you record here moves the '
                        'member\'s obligations straight away.'
                    : 'What you record here waits for an administrator to countersign the '
                        'cash before it moves the member\'s obligations.',
                tone: AppColors.primary,
                background: AppColors.primarySoft,
                icon: Icons.info_outline,
              ),
              const SizedBox(height: 14),
              ...obligations.map(
                (obligation) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _ObligationField(
                    obligation: obligation,
                    controller: _controllerFor(obligation.accountCode),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              TextField(
                controller: _note,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Note (optional)',
                  hintText: 'Anything the cooperative should know about this payment',
                ),
              ),
              const SizedBox(height: 18),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      AmountRow(label: 'Total collected', amount: _total, bold: true),
                      if (_headroom != null) ...[
                        const Divider(height: 20),
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Left before your cash limit',
                                style: TextStyle(fontSize: 12, color: AppColors.muted),
                              ),
                            ),
                            Text(
                              Money.format(_headroom! < 0 ? 0 : _headroom!),
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppColors.muted,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (_error.isNotEmpty) ...[
                const SizedBox(height: 14),
                Notice(
                  text: _error,
                  tone: AppColors.danger,
                  background: AppColors.dangerSoft,
                  icon: Icons.error_outline,
                ),
              ],
              const SizedBox(height: 18),
              FilledButton(
                onPressed: _saving || _total <= 0 ? null : () => _record(obligations),
                child: _saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : Text(_total <= 0
                        ? 'Enter what the member paid'
                        : 'Record ${Money.format(_total)}'),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// One obligation and the amount going against it, with what is owed on it beside
/// the field and one tap away.
class _ObligationField extends StatelessWidget {
  const _ObligationField({
    required this.obligation,
    required this.controller,
    required this.onChanged,
  });

  final MemberObligation obligation;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final outstanding = obligation.outstanding;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    obligation.title,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                ),
                if (obligation.nextDueDate != null)
                  Text(
                    'Due ${Dates.day(obligation.nextDueDate)}',
                    style: const TextStyle(fontSize: 11, color: AppColors.muted),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              outstanding > 0
                  ? '${Money.format(outstanding)} outstanding of ${Money.format(obligation.amount)}'
                  : 'Nothing outstanding',
              style: const TextStyle(fontSize: 12, color: AppColors.muted),
            ),
            const SizedBox(height: 10),
            MoneyField(
              controller: controller,
              label: 'Amount collected',
              onChanged: onChanged,
            ),
            if (outstanding > 0)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () {
                    controller.text =
                        (outstanding ~/ Money.minorPerMajor).toString();
                    onChanged(controller.text);
                  },
                  child: Text('Pay all ${Money.formatWhole(outstanding)}'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
