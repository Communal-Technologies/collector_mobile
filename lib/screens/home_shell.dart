import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:iconsax/iconsax.dart';

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

/// This shell has no lifecycle observer of its own: leaving the app locks it, so by
/// the time the phone comes back this widget has been replaced by the lock screen
/// and rebuilt from nothing afterwards. The resume work — flushing the outbox,
/// re-reading the grants — belongs to the app entry, which outlives the lock.
class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  /// Bumped to make the standing header and the visible tab re-read. Every screen
  /// here is a view of the same few numbers, so they refresh together.
  int _revision = 0;

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
              icon: const Icon(Iconsax.arrow_swap_horizontal),
              onPressed: () => _switchCooperative(session.grants),
            ),
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Iconsax.logout),
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
            icon: Icon(Iconsax.profile_2user),
            selectedIcon: Icon(Iconsax.profile_2user5),
            label: 'Round',
          ),
          NavigationDestination(
            icon: Icon(Iconsax.receipt_item),
            selectedIcon: Icon(Iconsax.receipt_item5),
            label: 'Receipts',
          ),
          // The same bank in both states. Iconsax's filled bank sits at U+033A, a
          // combining mark, so a shaper gives it no advance and offsets it by an
          // em — the glyph paints a tab's width to the left of where it belongs.
          // The purple pill and the bold purple label are what say "selected".
          NavigationDestination(
            icon: Icon(Iconsax.bank),
            selectedIcon: Icon(Iconsax.bank),
            label: 'Remit',
          ),
          NavigationDestination(
            icon: Icon(Iconsax.money_recive),
            selectedIcon: Icon(Iconsax.money_recive5),
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
          decoration: const BoxDecoration(gradient: AppGradients.brand),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Cash in your hands',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 6),
              if (standing == null && !snapshot.hasError)
                const Skeleton(height: 30, width: 170, color: Colors.white24)
              else
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
              if (limit != null && limit > 0) ...[
                const SizedBox(height: 12),
                MeterBar(
                  fraction: (standing?.cashInHand ?? 0) / limit,
                  height: 7,
                  fill: tight ? AppColors.warning : Colors.white,
                ),
                const SizedBox(height: 7),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        headroom == null
                            ? 'Cash limit ${Money.formatWhole(limit)}'
                            : '${Money.format(headroom)} left before you must remit',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: tight ? FontWeight.w800 : FontWeight.w600,
                          color: tight ? Colors.white : Colors.white70,
                        ),
                      ),
                    ),
                    Text(
                      'of ${Money.formatWhole(limit)}',
                      style: const TextStyle(fontSize: 11.5, color: Colors.white70),
                    ),
                  ],
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
                        ? Iconsax.cloud_cross
                        : Iconsax.wifi_square,
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
                    rejected > 0 ? Iconsax.danger : Iconsax.cloud_cross,
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
