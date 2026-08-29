import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../core/money.dart';
import '../core/theme.dart';
import '../data/api_client.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../widgets/common.dart';

/// Handing the cash in.
///
/// The collector declares what they are giving back and which of the cooperative's
/// accounts it is going to. Nothing leaves their float on the strength of this
/// declaration — an administrator has to count the money first — and the screen says
/// so, because a collector who believes they are square when they are not will be
/// short at the next reconciliation.
class RemitTab extends StatefulWidget {
  const RemitTab({
    super.key,
    required this.grant,
    required this.revision,
    required this.onChanged,
  });

  final CollectorGrant grant;
  final int revision;
  final VoidCallback onChanged;

  @override
  State<RemitTab> createState() => _RemitTabState();
}

class _RemitTabState extends State<RemitTab> {
  final _amount = TextEditingController();
  final _narration = TextEditingController();

  Future<_RemitData>? _future;
  String? _accountId;
  bool _submitting = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(RemitTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.revision != widget.revision ||
        oldWidget.grant.collectorId != widget.grant.collectorId) {
      _load();
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _narration.dispose();
    super.dispose();
  }

  void _load() {
    final repository = context.read<CollectorRepository>();
    setState(() {
      _future = _RemitData.load(repository, widget.grant.cooperativeId);
    });
  }

  Future<void> _submit(_RemitData data) async {
    final amount = moneyFieldMinor(_amount);
    if (amount <= 0) {
      setState(() => _error = 'Enter how much cash you are handing in.');
      return;
    }
    final accountId = _accountId;
    if (accountId == null) {
      setState(
        () => _error = 'Choose the account you are paying the cash into.',
      );
      return;
    }
    setState(() {
      _submitting = true;
      _error = '';
    });
    try {
      await context.read<CollectorRepository>().createRemittance(
        cooperativeId: widget.grant.cooperativeId,
        toRepositoryId: accountId,
        amount: amount,
        narration: _narration.text.trim(),
      );
      if (!mounted) return;
      _amount.clear();
      _narration.clear();
      setState(() => _submitting = false);
      showToast(context, 'Declared. An administrator confirms the cash.');
      _load();
      widget.onChanged();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async {
        _load();
        widget.onChanged();
      },
      child: FutureBuilder<_RemitData>(
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
                  title: 'Could not open the remittance screen',
                  message: error is ApiException
                      ? error.message
                      : 'Handing in cash needs a connection. Pull down to try again.',
                ),
              ],
            );
          }
          final data = snapshot.data!;
          if (_accountId == null && data.accounts.length == 1) {
            _accountId = data.accounts.first.id;
          }
          final typed = moneyFieldMinor(_amount);
          final overCash =
              data.standing != null && typed > data.standing!.cashInHand;
          final offline = isOffline(context);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
            children: [
              if (data.standing != null)
                SectionCard(
                  title: 'What you are holding',
                  child: Column(
                    children: [
                      AmountRow(
                        label: 'Counted into your float',
                        sublabel: 'Cash an administrator has already confirmed',
                        amount: data.standing!.floatBalance,
                      ),
                      AmountRow(
                        label: 'Declared, not yet approved',
                        sublabel:
                            '${data.standing!.pendingCount} receipt'
                            '${data.standing!.pendingCount == 1 ? '' : 's'} waiting',
                        amount: data.standing!.pendingTotal,
                      ),
                      const Divider(height: 20),
                      AmountRow(
                        label: 'Cash in your hands',
                        amount: data.standing!.cashInHand,
                        bold: true,
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 14),
              SectionCard(
                title: 'Hand in cash',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (data.accounts.isEmpty)
                      const Notice(
                        text:
                            'Your cooperative has not opened an account for you to '
                            'pay into. Ask an administrator to set one up before you '
                            'hand cash over.',
                        icon: Icons.info_outline,
                      )
                    else ...[
                      const Text(
                        'Paying into',
                        style: TextStyle(fontSize: 12, color: AppColors.muted),
                      ),
                      const SizedBox(height: 8),
                      ...data.accounts.map(
                        (account) => _AccountChoice(
                          account: account,
                          selected: _accountId == account.id,
                          onTap: () => setState(() => _accountId = account.id),
                        ),
                      ),
                      const SizedBox(height: 14),
                      MoneyField(
                        controller: _amount,
                        label: 'Amount you are handing in',
                        onChanged: (_) => setState(() {}),
                      ),
                      if (data.standing != null &&
                          data.standing!.cashInHand > 0) ...[
                        const SizedBox(height: 4),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            onPressed: () {
                              _amount.text =
                                  (data.standing!.cashInHand ~/
                                          Money.minorPerMajor)
                                      .toString();
                              setState(() {});
                            },
                            child: Text(
                              'Hand in all ${Money.formatWhole(data.standing!.cashInHand)}',
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 6),
                      TextField(
                        controller: _narration,
                        decoration: const InputDecoration(
                          labelText: 'Note (optional)',
                          hintText: 'Who you handed it to, or anything else',
                        ),
                      ),
                      if (overCash) ...[
                        const SizedBox(height: 12),
                        Notice(
                          text:
                              'That is more than the '
                              '${Money.format(data.standing!.cashInHand)} the '
                              'cooperative has you down as holding. Check the figure — '
                              'they may not accept it.',
                          icon: Icons.warning_amber_rounded,
                        ),
                      ],
                      if (_error.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Notice(
                          text: _error,
                          tone: AppColors.danger,
                          background: AppColors.dangerSoft,
                          icon: Icons.error_outline,
                        ),
                      ],
                      const SizedBox(height: 14),
                      const OfflineNotice(
                        reason:
                            'A hand-in has to reach the cooperative to be '
                            'counted, so it cannot be queued on this phone like a '
                            'receipt can.',
                      ),
                      FilledButton(
                        onPressed: _submitting || typed <= 0 || offline
                            ? null
                            : () => _submit(data),
                        child: _submitting
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                offline
                                    ? 'Waiting for a connection'
                                    : typed <= 0
                                    ? 'Enter an amount'
                                    : 'Declare ${Money.format(typed)}',
                              ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'This comes off your float only once an administrator confirms '
                        'the cash. Until then you are still down as holding it.',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.muted,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),
              SectionCard(
                title: 'Hand-ins',
                child: data.remittances.isEmpty
                    ? const Text(
                        'Nothing handed in yet.',
                        style: TextStyle(fontSize: 13, color: AppColors.muted),
                      )
                    : Column(
                        children: data.remittances
                            .map(
                              (remittance) =>
                                  _RemittanceRow(remittance: remittance),
                            )
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

/// Everything the screen needs, fetched together so it renders once.
class _RemitData {
  const _RemitData({
    required this.standing,
    required this.accounts,
    required this.remittances,
  });

  final CollectorStanding? standing;
  final List<RemittanceAccount> accounts;
  final List<Remittance> remittances;

  static Future<_RemitData> load(
    CollectorRepository repository,
    String cooperativeId,
  ) async {
    final accounts = await repository.remittanceAccounts(cooperativeId);
    final remittances = await repository.remittances(cooperativeId);
    CollectorStanding? standing;
    try {
      standing = await repository.standing(cooperativeId);
    } on ApiException {
      // The figures are context, not the point of the screen. A collector who is
      // handing cash over knows how much is in their hand.
      standing = null;
    }
    return _RemitData(
      standing: standing,
      accounts: accounts,
      remittances: remittances,
    );
  }
}

class _AccountChoice extends StatelessWidget {
  const _AccountChoice({
    required this.account,
    required this.selected,
    required this.onTap,
  });

  final RemittanceAccount account;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected ? AppColors.primarySoft : Colors.white,
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.line,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(
                selected ? Icons.check_circle : Icons.circle_outlined,
                size: 20,
                color: selected ? AppColors.primary : AppColors.muted,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      account.label,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    if (account.accountType.isNotEmpty)
                      Text(
                        account.accountType.replaceAll('_', ' '),
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.muted,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RemittanceRow extends StatelessWidget {
  const _RemittanceRow({required this.remittance});

  final Remittance remittance;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      remittance.toAccountName.isEmpty
                          ? remittance.reference
                          : remittance.toAccountName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      Dates.dayTime(remittance.createdAt),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    Money.format(remittance.amount),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  StatusChip(remittance.status),
                ],
              ),
            ],
          ),
          if (remittance.failureReason.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              remittance.failureReason,
              style: const TextStyle(fontSize: 12, color: AppColors.danger),
            ),
          ],
        ],
      ),
    );
  }
}
