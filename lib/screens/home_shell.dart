import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../core/money.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../state/connectivity_cubit.dart';
import '../state/outbox_cubit.dart';
import '../state/session_cubit.dart';
import '../widgets/common.dart';
import 'earnings_tab.dart';
import 'members_tab.dart';
import 'receipts_tab.dart';
import 'remit_tab.dart';

/// The signed-in app. Four things a collector does, and the standing they do them
/// against sitting above all four: how much of the cooperative's money is in their
/// hands right now.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _tab = 0;

  /// Bumped to make the standing header and the visible tab re-read. Every screen
  /// here is a view of the same few numbers, so they refresh together.
  int _revision = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // A collector puts the phone in their pocket between doors. Coming back is
      // the most likely moment for signal to have returned.
      context.read<OutboxCubit>().flush();
      context.read<SessionCubit>().refreshGrants();
      _refresh();
    }
  }

  void _refresh() {
    if (mounted) setState(() => _revision++);
  }

  Future<void> _switchCooperative(List<CollectorGrant> grants) async {
    final chosen = await showModalBottomSheet<CollectorGrant>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Collecting for',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ),
            ),
            ...grants.map(
              (g) => ListTile(
                title: Text(g.cooperativeName),
                subtitle: Text(
                  '${g.collectorCode} · ${g.commissionLabel}',
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: g.isActive
                    ? null
                    : StatusChip(g.status, label: g.status),
                onTap: () => Navigator.of(sheetContext).pop(g),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (chosen == null || !mounted) return;
    await context.read<SessionCubit>().switchGrant(chosen);
    _refresh();
  }

  Future<void> _confirmSignOut() async {
    final unsent = context.read<OutboxCubit>().state.queued.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sign out?'),
        content: Text(
          unsent > 0
              ? 'You have $unsent ${unsent == 1 ? 'receipt' : 'receipts'} that have not reached '
                    'the cooperative yet. They stay on this phone and go up the next time you '
                    'sign in with signal — but nobody at the cooperative can see them until then.'
              : 'You will need your PIN and a new code to sign back in.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Stay signed in'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await context.read<SessionCubit>().signOut();
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionCubit>().state;
    final grant = session.grant;
    if (grant == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final tabs = [
      MembersTab(grant: grant, revision: _revision, onChanged: _refresh),
      ReceiptsTab(grant: grant, revision: _revision, onChanged: _refresh),
      RemitTab(grant: grant, revision: _revision, onChanged: _refresh),
      EarningsTab(grant: grant, revision: _revision),
    ];

    return BlocListener<ConnectivityCubit, ConnectivityState>(
      listenWhen: (a, b) => a.reachability != b.reachability,
      listener: (context, network) {
        if (!network.isOnline) return;
        // Signal came back. Send the queue without being asked — the collector has
        // walked on, and the receipts are owed to the cooperative either way.
        context.read<OutboxCubit>().flush();
        final queued = context.read<OutboxCubit>().state.queued.length;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              backgroundColor: AppColors.success,
              duration: const Duration(seconds: 3),
              content: Text(
                queued > 0
                    ? 'Back online. Sending $queued ${queued == 1 ? 'receipt' : 'receipts'}.'
                    : 'Back online.',
              ),
            ),
          );
        _refresh();
      },
      child: _buildShell(context, session, grant, tabs),
    );
  }

  Widget _buildShell(
    BuildContext context,
    SessionState session,
    CollectorGrant grant,
    List<Widget> tabs,
  ) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              grant.cooperativeName,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              '${grant.fullName} · ${grant.collectorCode}',
              style: const TextStyle(fontSize: 11, color: AppColors.muted),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          if (session.grants.length > 1)
            IconButton(
              tooltip: 'Switch cooperative',
              icon: const Icon(Icons.swap_horiz),
              onPressed: () => _switchCooperative(session.grants),
            ),
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: _confirmSignOut,
          ),
        ],
      ),
      body: Column(
        children: [
          _StandingHeader(grant: grant, revision: _revision),
          const _ConnectionBanner(),
          const _OutboxBanner(),
          Expanded(child: tabs[_tab]),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (index) => setState(() => _tab = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.groups_outlined),
            selectedIcon: Icon(Icons.groups),
            label: 'Round',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'Receipts',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_balance_outlined),
            selectedIcon: Icon(Icons.account_balance),
            label: 'Remit',
          ),
          NavigationDestination(
            icon: Icon(Icons.savings_outlined),
            selectedIcon: Icon(Icons.savings),
            label: 'Earnings',
          ),
        ],
      ),
    );
  }
}

/// Cash in hand, and the ceiling the cooperative set on it.
///
/// Cash in hand is the float plus what is declared and unapproved, which is the
/// honest figure: a receipt written and not yet countersigned is still money the
/// collector is carrying, and the limit is checked against it.
class _StandingHeader extends StatelessWidget {
  const _StandingHeader({required this.grant, required this.revision});

  final CollectorGrant grant;
  final int revision;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<CollectorStanding>(
      key: ValueKey('standing-${grant.collectorId}-$revision'),
      future: context.read<CollectorRepository>().standing(grant.cooperativeId),
      builder: (context, snapshot) {
        final standing = snapshot.data;
        final limit = standing?.cashLimitMinor ?? grant.cashLimitMinor;
        final headroom = standing?.headroom;
        final tight =
            limit != null &&
            headroom != null &&
            limit > 0 &&
            headroom <= limit ~/ 10;
        return Container(
          width: double.infinity,
          color: AppColors.primary,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Cash in your hands',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 4),
              Text(
                standing == null ? '—' : Money.format(standing.cashInHand),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              if (standing != null)
                Text(
                  '${Money.format(standing.floatBalance)} counted in · '
                  '${Money.format(standing.pendingTotal)} awaiting approval'
                  '${standing.pendingCount > 0 ? ' (${standing.pendingCount})' : ''}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                )
              else if (snapshot.hasError)
                const Text(
                  'Could not reach the cooperative. Showing what is on this phone.',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              if (limit != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: tight ? Colors.white : Colors.white24,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    headroom == null
                        ? 'Limit ${Money.formatWhole(limit)}'
                        : 'Limit ${Money.formatWhole(limit)} · '
                              '${Money.format(headroom)} left before you must remit',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: tight ? AppColors.primary : Colors.white,
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Whether this phone can reach the cooperative right now.
///
/// It informs, it does not stop: a collector with no signal can still open a
/// member, write a receipt and read yesterday's figures. What it must do is say so
/// plainly, because the collector is about to read a number out to somebody and is
/// entitled to know it came off the phone.
class _ConnectionBanner extends StatelessWidget {
  const _ConnectionBanner();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ConnectivityCubit, ConnectivityState>(
      builder: (context, network) {
        if (!network.isOffline) return const SizedBox.shrink();
        return Material(
          color: AppColors.surface,
          child: InkWell(
            onTap: () => context.read<ConnectivityCubit>().recheck(),
            child: Container(
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.line)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    network.hasTransport
                        ? Icons.cloud_off
                        : Icons.signal_cellular_off,
                    size: 18,
                    color: AppColors.muted,
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Working offline. Keep collecting — figures are from this phone.',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.muted,
                      ),
                    ),
                  ),
                  if (network.checking)
                    const SizedBox(
                      height: 14,
                      width: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    const Text(
                      'Check',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The queue, when there is one. It is the first thing a collector should see: a
/// receipt on the phone is a receipt the cooperative cannot act on yet.
class _OutboxBanner extends StatelessWidget {
  const _OutboxBanner();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<OutboxCubit, OutboxState>(
      builder: (context, state) {
        final queued = state.queued.length;
        final rejected = state.rejected.length;
        if (queued == 0 && rejected == 0) return const SizedBox.shrink();
        final parts = <String>[
          if (queued > 0) '$queued unsent (${Money.format(state.queuedTotal)})',
          if (rejected > 0) '$rejected refused',
        ];
        return Material(
          color: rejected > 0 ? AppColors.dangerSoft : AppColors.warningSoft,
          child: InkWell(
            onTap: () => context.read<OutboxCubit>().flush(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    rejected > 0 ? Icons.error_outline : Icons.cloud_off,
                    size: 18,
                    color: rejected > 0 ? AppColors.danger : AppColors.warning,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      parts.join(' · '),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: rejected > 0
                            ? AppColors.danger
                            : AppColors.warning,
                      ),
                    ),
                  ),
                  if (state.syncing)
                    const SizedBox(
                      height: 14,
                      width: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Text(
                      'Sync now',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: rejected > 0
                            ? AppColors.danger
                            : AppColors.warning,
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
