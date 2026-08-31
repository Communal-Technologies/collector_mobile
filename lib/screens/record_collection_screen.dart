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

/// Which of the member's obligation accounts the collector is looking at.
///
/// `due` is a recurring account's question and nothing else's: a one-off commitment
/// has no cycle to have fallen behind on, so it can never be due now — only
/// incomplete. A fine belongs here once the day it was raised for has passed.
enum _Lens { due, owing, all }

/// Writing the receipt.
///
/// The whole screen is one decision made several times: of the cash in the
/// collector's hand, how much goes against which obligation. Nothing is filled in
/// by default — a collector takes what a member gives them, which is often not what
/// is due — but what is due is on every row and one tap away.
///
/// The list has to hold a real cooperative's chart of accounts, not the two the dev
/// one has: savings, shares, development levy, building fund, welfare, thrift,
/// target savings and stationery is eight accounts before a single fine. So it is
/// one compact row per obligation and a sheet for the amount, ordered so the
/// overdue and the owing come first, and the total and the button never scroll
/// away.
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
  /// Above this many accounts the collector needs to narrow the list; below it,
  /// narrowing would only hide rows they can already see, so the lens is left on
  /// `all` and settled accounts stay reachable without a filter.
  static const int _lensThreshold = 5;

  final _note = TextEditingController();
  final _search = TextEditingController();

  /// Kobo against each thing the cash can settle, keyed by the target's own key —
  /// an `account_code` for an obligation, the fine's id for a fine.
  ///
  /// Held here rather than in a controller per row because the list is filtered and
  /// built lazily: a row that scrolls out of view or falls out of the filter takes
  /// its controller with it, and a figure the collector had already entered would go
  /// with it. The key is what the receipt is built from, so what the screen shows can
  /// change freely without touching the money.
  final Map<String, int> _allocated = {};

  Future<MemberCollectibles>? _future;
  CollectorStanding? _standing;
  _Lens _lens = _Lens.owing;
  String _query = '';
  bool _saving = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _future = context.read<CollectorRepository>().memberCollectibles(
          widget.grant.cooperativeId,
          widget.member.ledgerNumber,
        );
    _loadStanding();
  }

  @override
  void dispose() {
    _note.dispose();
    _search.dispose();
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

  int get _total => _allocated.values.fold<int>(0, (sum, a) => sum + a);

  int get _lines => _allocated.values.where((a) => a > 0).length;

  bool get _blocked => !widget.member.collectible;

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

  /// The most this one can still take, or null where nothing caps it.
  ///
  /// The target's own ceiling already counts the receipts the server has seen. A
  /// receipt written on this phone five minutes ago with no signal is the same cash
  /// against the same cap, so it comes off here — otherwise the collector writes a
  /// second receipt against a full account and finds out when there is signal, which
  /// is after the member has gone.
  int? _ceiling(CollectionTarget target) {
    final ceiling = target.ceiling;
    if (ceiling == null) return null;
    final queued = context
        .read<OutboxCubit>()
        .state
        .queued
        .where((i) =>
            i.cooperativeId == widget.grant.cooperativeId &&
            i.ledgerNumber == widget.member.ledgerNumber)
        .expand((i) => i.allocations)
        .where((a) => target.isFine
            ? a.fineId == target.fineId
            : !a.isFine && a.obligationCode == target.obligationCode)
        .fold<int>(0, (sum, a) => sum + a.amount);
    final left = ceiling - queued;
    return left > 0 ? left : 0;
  }

  /// A one-off commitment is never overdue. It has no cycle and the server sends it
  /// no due date, so what would be shown here is a deadline the cooperative never
  /// set — the member is behind on nothing, they are simply not finished yet.
  bool _isOverdue(CollectionTarget target) {
    final due = target.nextDueDate;
    if (due == null) return false;
    final now = DateTime.now();
    return !due.isAfter(DateTime(now.year, now.month, now.day));
  }

  /// Overdue and owing first, then owing by what is left on it, then settled — and
  /// alphabetically inside each band so the same account is always in the same place
  /// on the round.
  List<CollectionTarget> _ordered(List<CollectionTarget> list) {
    int band(CollectionTarget t) {
      if (t.outstanding <= 0) return 2;
      return _isOverdue(t) ? 0 : 1;
    }

    final sorted = [...list];
    sorted.sort((a, b) {
      final byBand = band(a).compareTo(band(b));
      if (byBand != 0) return byBand;
      if (a.outstanding != b.outstanding) {
        return b.outstanding.compareTo(a.outstanding);
      }
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });
    return sorted;
  }

  List<CollectionTarget> _visible(List<CollectionTarget> ordered) {
    final query = _query.trim().toLowerCase();
    return ordered.where((t) {
      // A row with money already against it is never hidden, whatever the lens or
      // the search says. The collector has to be able to see every line they are
      // about to sign for.
      if ((_allocated[t.key] ?? 0) > 0) return true;
      switch (_lens) {
        case _Lens.due:
          if (t.outstanding <= 0 || !_isOverdue(t)) return false;
        case _Lens.owing:
          if (t.outstanding <= 0) return false;
        case _Lens.all:
          break;
      }
      if (query.isEmpty) return true;
      return t.title.toLowerCase().contains(query) ||
          t.obligationCode.toLowerCase().contains(query);
    }).toList();
  }

  Future<void> _editAmount(CollectionTarget target) async {
    final amount = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AmountSheet(
        target: target,
        initial: _allocated[target.key] ?? 0,
        overdue: _isOverdue(target),
        ceiling: _ceiling(target),
      ),
    );
    if (amount == null) return;
    setState(() {
      if (amount <= 0) {
        _allocated.remove(target.key);
      } else {
        _allocated[target.key] = amount;
      }
      _error = '';
    });
  }

  /// Fills in what is owed, held to what each one can still take. A capped account
  /// with a receipt already standing against it gets the room that is left, not the
  /// figure that is outstanding — filling in more would put the whole receipt over.
  void _fillOwed(List<CollectionTarget> targets) {
    setState(() {
      for (final target in targets) {
        final ceiling = _ceiling(target);
        final amount = ceiling == null
            ? target.outstanding
            : target.outstanding < ceiling
                ? target.outstanding
                : ceiling;
        if (amount > 0) _allocated[target.key] = amount;
      }
      _error = '';
    });
  }

  void _clearAll() {
    setState(() {
      _allocated.clear();
      _error = '';
    });
  }

  Future<void> _openReview(List<CollectionTarget> targets) async {
    final byKey = {for (final t in targets) t.key: t};
    final edit = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ReviewSheet(
        lines: [
          for (final entry in _allocated.entries)
            if (entry.value > 0)
              _ReviewLine(
                key: entry.key,
                title: byKey[entry.key]?.title ?? entry.key,
                amount: entry.value,
              ),
        ],
        total: _total,
        note: _note,
        postsOnCollection: widget.grant.postsOnCollection,
        onRemove: (key) => setState(() {
          _allocated.remove(key);
          _error = '';
        }),
      ),
    );
    if (!mounted || edit == null) return;
    final target = byKey[edit];
    if (target != null) await _editAmount(target);
  }

  Future<void> _record(List<CollectionTarget> targets) async {
    // Built off the full list, never the filtered one: a lens or a search must not
    // be able to drop an amount the collector already entered.
    final allocations = <CollectionAllocation>[];
    for (final target in targets) {
      final amount = _allocated[target.key] ?? 0;
      if (amount <= 0) continue;
      // Checked again here, not only in the sheet: another receipt may have been
      // queued on this phone since the amount was entered, and the room it took is
      // gone.
      final ceiling = _ceiling(target);
      if (ceiling != null && amount > ceiling) {
        setState(() => _error = ceiling <= 0
            ? '${target.title} can take nothing more. Remove it from this receipt.'
            : '${target.title} can only take ${Money.format(ceiling)} more. '
                'Change what you put against it.');
        return;
      }
      allocations.add(CollectionAllocation(
        obligationCode: target.obligationCode,
        fineId: target.fineId,
        title: target.title,
        amount: amount,
      ));
    }
    if (allocations.isEmpty) {
      setState(() => _error =
          'Enter what the member paid against at least one account or fine.');
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
      body: FutureBuilder<MemberCollectibles>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const SkeletonRows(count: 6);
          }
          if (snapshot.hasError) {
            final error = snapshot.error;
            return EmptyState(
              icon: Iconsax.danger,
              title: 'Could not load this member\'s obligations',
              message: error is ApiException
                  ? error.message
                  : 'Go back and try again when you have signal.',
            );
          }
          final result = snapshot.data!;
          final targets = _ordered(result.targets);
          if (targets.isEmpty) {
            return const EmptyState(
              icon: Iconsax.archive_book,
              title: 'Nothing to collect against',
              message: 'This member has no obligation accounts yet. The cooperative '
                  'has to open one before a collection can be filed.',
            );
          }
          return Column(
            children: [
              _Header(
                targets: targets,
                stale: result.stale,
                finesError: result.finesError,
                member: widget.member,
                postsOnCollection: widget.grant.postsOnCollection,
                onFillOwed: _blocked ? null : () => _fillOwed(targets),
                onClear:
                    _blocked || _allocated.isEmpty ? null : _clearAll,
              ),
              if (targets.length > _lensThreshold)
                _LensBar(
                  lens: _lens,
                  search: _search,
                  onLens: (lens) => setState(() => _lens = lens),
                  onQuery: (value) => setState(() => _query = value),
                ),
              Expanded(child: _list(targets)),
              _BottomBar(
                total: _total,
                lines: _lines,
                headroom: _headroom,
                cashInHand: _standing?.cashInHand,
                cashLimit: _standing?.cashLimitMinor,
                error: _error,
                saving: _saving,
                blocked: _blocked,
                onReview: _lines == 0 ? null : () => _openReview(targets),
                onRecord: _saving || _total <= 0 || _blocked
                    ? null
                    : () => _record(targets),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _list(List<CollectionTarget> targets) {
    final visible = _visible(targets);
    if (visible.isEmpty) {
      // In a list rather than on its own: the header, the lens bar and the bottom
      // bar leave this little height on a short screen, and an empty state that
      // cannot scroll is an overflow.
      return ListView(
        children: [
          EmptyState(
            icon: Iconsax.filter,
            title: _query.isNotEmpty
                ? 'No account matches "$_query"'
                : _lens == _Lens.due
                    ? 'Nothing has fallen due'
                    : 'Nothing is outstanding',
            message: 'The member may still pay into any of their accounts.',
            action: OutlinedButton(
              onPressed: () => setState(() {
                _lens = _Lens.all;
                _query = '';
                _search.clear();
              }),
              child: const Text('Show all accounts'),
            ),
          ),
        ],
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      itemCount: visible.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final target = visible[index];
        return _TargetRow(
          target: target,
          allocated: _allocated[target.key] ?? 0,
          overdue: _isOverdue(target),
          ceiling: _ceiling(target),
          onTap: _blocked ? null : () => _editAmount(target),
        );
      },
    );
  }
}

/// What the collector needs before they read a single account: whether these
/// figures are current, whether they may write a receipt against this member at
/// all, how much the member owes in total, and the two shortcuts for the member who
/// simply pays everything.
class _Header extends StatelessWidget {
  const _Header({
    required this.targets,
    required this.stale,
    required this.finesError,
    required this.member,
    required this.postsOnCollection,
    required this.onFillOwed,
    required this.onClear,
  });

  final List<CollectionTarget> targets;
  final bool stale;
  final String finesError;
  final CollectorMember member;
  final bool postsOnCollection;
  final VoidCallback? onFillOwed;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final owed = targets.fold<int>(0, (sum, t) => sum + t.outstanding);
    final owing = targets.where((t) => t.outstanding > 0).length;
    final fines = targets.where((t) => t.isFine).length;
    final accounts = targets.length - fines;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!member.collectible)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Notice(
                text: member.standingNote,
                tone: AppColors.danger,
                background: AppColors.dangerSoft,
                icon: Iconsax.slash,
              ),
            ),
          if (stale)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Notice(
                text: 'No connection — these figures are from the last time this '
                    'phone reached the cooperative. What is owed may have changed.',
                icon: Iconsax.cloud_cross,
              ),
            ),
          if (finesError.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Notice(
                text: 'Any fine raised against this member directly could not be '
                    'read — $finesError. The accounts below are still collectable, '
                    'and so are the fines shown against them.',
                icon: Iconsax.warning_2,
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      owed > 0
                          ? '${Money.format(owed)} owed'
                          : 'Nothing outstanding',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$accounts ${accounts == 1 ? 'account' : 'accounts'}'
                      '${fines > 0 ? ' · $fines ${fines == 1 ? 'fine' : 'fines'}' : ''}'
                      '${owing > 0 ? ' · $owing owing' : ''} · '
                      '${postsOnCollection ? 'posts as you record' : 'waits to be countersigned'}',
                      style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              if (onFillOwed != null || onClear != null)
                Row(
                  children: [
                    if (onClear != null)
                      TextButton(
                        onPressed: onClear,
                        child: const Text('Clear'),
                      ),
                    if (onFillOwed != null)
                      TextButton(
                        onPressed: onFillOwed,
                        child: const Text('Fill owed'),
                      ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The lens and the search, shown only once there are enough accounts for a
/// collector to lose their place among them.
class _LensBar extends StatelessWidget {
  const _LensBar({
    required this.lens,
    required this.search,
    required this.onLens,
    required this.onQuery,
  });

  final _Lens lens;
  final TextEditingController search;
  final ValueChanged<_Lens> onLens;
  final ValueChanged<String> onQuery;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: search,
            onChanged: onQuery,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Find an account',
              prefixIcon: const Icon(Iconsax.search_normal, size: 18),
              suffixIcon: search.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Iconsax.close_circle, size: 18),
                      onPressed: () {
                        search.clear();
                        onQuery('');
                      },
                    ),
            ),
          ),
          const SizedBox(height: 10),
          // Wrapped rather than a row: three chips plus a checkmark already come to
          // more than a narrow phone's width, and a row of them has nowhere to go.
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in _Lens.values)
                ChoiceChip(
                  selected: option == lens,
                  onSelected: (_) => onLens(option),
                  showCheckmark: false,
                  label: Text(switch (option) {
                    _Lens.due => 'Due now',
                    _Lens.owing => 'Owing',
                    _Lens.all => 'All',
                  }),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One thing on one line: what it is, what stands against it, and what the
/// collector has put against it so far.
///
/// The three kinds read differently on purpose. A recurring account is a cycle, so
/// it carries what is outstanding and when it falls due. A one-off commitment has no
/// cycle to fall due in — it is paid in instalments until it is complete — so it
/// carries progress towards its target and no date at all. A fine is a fixed penalty
/// settled once, and is marked as one so nobody mistakes it for a contribution.
class _TargetRow extends StatelessWidget {
  const _TargetRow({
    required this.target,
    required this.allocated,
    required this.overdue,
    required this.ceiling,
    required this.onTap,
  });

  final CollectionTarget target;
  final int allocated;
  final bool overdue;

  /// The most this one can still take, null where nothing caps it.
  final int? ceiling;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final outstanding = target.outstanding;
    final filled = allocated > 0;
    final progress = !target.isFine && !target.recurring && target.amount > 0;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(
              color: filled ? AppColors.primary : AppColors.line,
              width: filled ? 1.4 : 1,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (target.isFine)
                          const Padding(
                            padding: EdgeInsets.only(right: 6),
                            child: Icon(Iconsax.slash,
                                size: 13, color: AppColors.danger),
                          ),
                        Expanded(
                          child: Text(
                            target.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    // One line rather than a row of two: an account name and a
                    // five-figure balance already fill a phone's width, and a row
                    // of unflexed texts has nowhere to go when they do.
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: _standing,
                            style: TextStyle(
                              color: outstanding > 0
                                  ? AppColors.muted
                                  : AppColors.success,
                            ),
                          ),
                          if (target.nextDueDate != null)
                            TextSpan(
                              text: target.isFine
                                  ? '  · for ${Dates.day(target.nextDueDate)}'
                                  : '  · ${overdue ? 'due' : 'by'} ${Dates.day(target.nextDueDate)}',
                              style: TextStyle(
                                fontWeight:
                                    overdue ? FontWeight.w700 : FontWeight.w400,
                                color:
                                    overdue ? AppColors.danger : AppColors.muted,
                              ),
                            ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11.5),
                    ),
                    if (progress) ...[
                      const SizedBox(height: 6),
                      MeterBar(
                        fraction: target.amountPaid / target.amount,
                        height: 4,
                        fill: outstanding > 0
                            ? AppColors.primary
                            : AppColors.success,
                        track: AppColors.line,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (filled)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Text(
                    Money.formatWhole(allocated),
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary,
                    ),
                  ),
                )
              else if (onTap != null)
                const Icon(Iconsax.add_circle, size: 20, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }

  String get _standing {
    final outstanding = target.outstanding;
    if (target.isFine) {
      return outstanding > 0
          ? '${Money.formatWhole(outstanding)} to settle'
          : 'Settled';
    }
    if (!target.recurring) {
      if (outstanding <= 0) return 'Complete';
      // What is outstanding and what can still be taken are the same figure until a
      // receipt is standing against the account unsigned. Where they differ it is the
      // second one the collector needs, and the reason for it in the same breath.
      final room = ceiling;
      if (room != null && room < outstanding) {
        return room <= 0
            ? 'Fully receipted — awaiting approval'
            : '${Money.formatWhole(room)} can be taken · '
                '${Money.formatWhole(outstanding - room)} awaiting approval';
      }
      return '${Money.formatWhole(target.amountPaid)} of '
          '${Money.formatWhole(target.amount)} paid';
    }
    return outstanding > 0
        ? '${Money.formatWhole(outstanding)} outstanding'
        : 'Settled';
  }
}

/// The amount for one obligation, on its own.
///
/// A sheet rather than a field on the row: with a real chart of accounts there are
/// too many rows for a field each, and the amount is worth the collector's whole
/// attention for the moment they are entering it.
class _AmountSheet extends StatefulWidget {
  const _AmountSheet({
    required this.target,
    required this.initial,
    required this.overdue,
    required this.ceiling,
  });

  final CollectionTarget target;
  final int initial;
  final bool overdue;

  /// The most this one can still take, null where nothing caps it. Already net of
  /// the receipts the server has seen and the ones still on this phone.
  final int? ceiling;

  @override
  State<_AmountSheet> createState() => _AmountSheetState();
}

class _AmountSheetState extends State<_AmountSheet> {
  late final TextEditingController _amount =
      TextEditingController(text: moneyFieldText(widget.initial));

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  void _set(int minor) {
    _amount.text = moneyFieldText(minor);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final target = widget.target;
    final outstanding = target.outstanding;
    final entered = moneyFieldMinor(_amount);
    // A fine is a fixed penalty with nowhere for an excess to go, and a one-off
    // account is capped by the cooperative's own share figure. The service refuses
    // either; refusing it here means the collector is told before the member is given
    // a receipt for it.
    final ceiling = widget.ceiling;
    final refusal =
        ceiling != null && entered > ceiling ? _refusal(target, ceiling) : '';
    // The most the collector can put here in one tap. On a capped account that is the
    // room, not what is outstanding: the difference is receipts already written.
    final settle = ceiling != null && ceiling < outstanding ? ceiling : outstanding;
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 4,
        bottom: 20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            target.title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            _standing(target),
            style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
          ),
          const SizedBox(height: 16),
          MoneyField(
            controller: _amount,
            label: 'Amount collected',
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (settle > 0)
                ActionChip(
                  label: Text(
                    '${target.isFine ? 'Settle' : target.recurring ? 'Pay all' : 'Pay the rest'} '
                    '${Money.formatWhole(settle)}',
                  ),
                  onPressed: () => _set(settle),
                ),
              // The standing charge is one cycle of a recurring account. A one-off
              // has no cycle and its whole target is the wrong figure to offer as a
              // single payment, and a fine has only itself to settle.
              if (target.recurring &&
                  target.amount > 0 &&
                  target.amount != outstanding)
                ActionChip(
                  label: Text('Standing ${Money.formatWhole(target.amount)}'),
                  onPressed: () => _set(target.amount),
                ),
              if (widget.initial > 0)
                ActionChip(
                  avatar: const Icon(Iconsax.trash, size: 15, color: AppColors.danger),
                  label: const Text('Remove'),
                  onPressed: () => Navigator.of(context).pop(0),
                ),
            ],
          ),
          if (refusal.isNotEmpty) ...[
            const SizedBox(height: 12),
            Notice(
              text: refusal,
              tone: AppColors.danger,
              background: AppColors.dangerSoft,
              icon: Iconsax.danger,
            ),
          ],
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: refusal.isNotEmpty || (entered <= 0 && widget.initial <= 0)
                  ? null
                  : () => Navigator.of(context).pop(entered),
              child: Text(entered <= 0
                  ? target.isFine
                      ? 'Leave this fine'
                      : 'Leave this account'
                  : '${widget.initial > 0 ? 'Update' : 'Add'} ${Money.format(entered)}'),
            ),
          ),
        ],
      ),
    );
  }

  /// Why the amount will not be taken, in terms of the thing that is holding it.
  ///
  /// A collector standing in front of a member reads "this account is full" as the
  /// cooperative's figure being wrong, so where a receipt of their own is what is
  /// holding the room, that is what the sentence says.
  String _refusal(CollectionTarget target, int ceiling) {
    if (target.isFine) {
      return 'A fine can only take the ${Money.format(ceiling)} still standing on '
          'it. Put the rest against one of the member\'s accounts.';
    }
    final held = target.outstanding - ceiling;
    if (held <= 0) {
      return 'This commitment is ${Money.format(target.amount)} in total and only '
          '${Money.format(ceiling)} of it is unpaid. Put the rest against another '
          'account.';
    }
    if (ceiling <= 0) {
      return 'Receipts for the whole of this ${Money.format(target.amount)} '
          'commitment have already been written and are waiting to be countersigned. '
          'Put this against another account.';
    }
    return 'Only ${Money.format(ceiling)} is left on this commitment — '
        '${Money.format(held)} of it is on receipts waiting to be countersigned. '
        'Put the rest against another account.';
  }

  /// What stands against this one, in the terms it is actually owed in.
  String _standing(CollectionTarget target) {
    final outstanding = target.outstanding;
    if (target.isFine) {
      final parts = [
        outstanding > 0
            ? '${Money.format(outstanding)} of the ${Money.format(target.amount)} '
                'fine still standing'
            : 'This fine has been settled',
        if (target.nextDueDate != null)
          'raised for ${Dates.day(target.nextDueDate)}',
      ];
      return parts.join(' · ');
    }
    if (!target.recurring) {
      if (outstanding <= 0) return 'This commitment is complete';
      final ceiling = widget.ceiling;
      if (ceiling != null && ceiling < outstanding) {
        return '${Money.format(target.amountPaid)} of ${Money.format(target.amount)} '
            'paid — ${Money.format(outstanding - ceiling)} more is on receipts '
            'waiting to be countersigned, leaving ${Money.format(ceiling)} to take';
      }
      return '${Money.format(target.amountPaid)} of ${Money.format(target.amount)} '
          'paid — ${Money.format(outstanding)} left to complete it';
    }
    final parts = [
      outstanding > 0
          ? '${Money.format(outstanding)} outstanding of ${Money.format(target.amount)}'
          : 'Nothing outstanding on this account',
      if (target.nextDueDate != null)
        '${widget.overdue ? 'was due' : 'due'} ${Dates.day(target.nextDueDate)}',
    ];
    return parts.join(' · ');
  }
}

class _ReviewLine {
  const _ReviewLine({
    required this.key,
    required this.title,
    required this.amount,
  });

  /// The target's own key — an account code, or a namespaced fine id.
  final String key;
  final String title;
  final int amount;
}

/// The receipt as the member will hear it read back, and the note.
///
/// The note lives here rather than in the list because it is the last thing written
/// and the least often written — on the list it sat between the obligations and the
/// button, where every collector had to scroll past it.
class _ReviewSheet extends StatefulWidget {
  const _ReviewSheet({
    required this.lines,
    required this.total,
    required this.note,
    required this.postsOnCollection,
    required this.onRemove,
  });

  final List<_ReviewLine> lines;
  final int total;
  final TextEditingController note;
  final bool postsOnCollection;
  final ValueChanged<String> onRemove;

  @override
  State<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<_ReviewSheet> {
  late final List<_ReviewLine> _lines = [...widget.lines];

  @override
  Widget build(BuildContext context) {
    final total = _lines.fold<int>(0, (sum, l) => sum + l.amount);
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 4,
        bottom: 20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This receipt',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              widget.postsOnCollection
                  ? 'Your cooperative has you on trust: what you record moves the '
                      'member\'s obligations straight away.'
                  : 'What you record waits for an administrator to countersign the '
                      'cash before it moves the member\'s obligations.',
              style: const TextStyle(fontSize: 12.5, color: AppColors.muted, height: 1.35),
            ),
            const SizedBox(height: 12),
            for (final line in _lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () => Navigator.of(context).pop(line.key),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  line.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Text(
                                Money.format(line.amount),
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(width: 6),
                              const Icon(Iconsax.edit_2, size: 15, color: AppColors.muted),
                            ],
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Iconsax.trash, size: 17, color: AppColors.danger),
                      onPressed: () {
                        widget.onRemove(line.key);
                        setState(() => _lines.remove(line));
                        if (_lines.isEmpty) Navigator.of(context).pop();
                      },
                    ),
                  ],
                ),
              ),
            const Divider(height: 20),
            AmountRow(label: 'Total collected', amount: total, bold: true),
            const SizedBox(height: 12),
            TextField(
              controller: widget.note,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Note (optional)',
                hintText: 'Anything the cooperative should know about this payment',
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Back to the accounts'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The total, the cash limit and the button — off the end of the scroll, where a
/// collector with a dozen accounts could not see any of them.
class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.total,
    required this.lines,
    required this.headroom,
    required this.cashInHand,
    required this.cashLimit,
    required this.error,
    required this.saving,
    required this.blocked,
    required this.onReview,
    required this.onRecord,
  });

  final int total;
  final int lines;
  final int? headroom;
  final int? cashInHand;
  final int? cashLimit;
  final String error;
  final bool saving;
  final bool blocked;
  final VoidCallback? onReview;
  final VoidCallback? onRecord;

  @override
  Widget build(BuildContext context) {
    final limit = cashLimit;
    final held = cashInHand;
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        12 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.line)),
        boxShadow: AppShadows.lifted,
      ),
      child: Column(
        children: [
          if (error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Notice(
                text: error,
                tone: AppColors.danger,
                background: AppColors.dangerSoft,
                icon: Iconsax.danger,
              ),
            ),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      Money.format(total),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      lines == 0
                          ? 'Nothing entered yet'
                          : '$lines ${lines == 1 ? 'line' : 'lines'} on this receipt',
                      style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              if (onReview != null)
                OutlinedButton(
                  onPressed: onReview,
                  child: const Text('Review'),
                ),
            ],
          ),
          if (limit != null && limit > 0 && held != null) ...[
            const SizedBox(height: 10),
            MeterBar(
              fraction: (held + total) / limit,
              fill: headroom != null && total > headroom!
                  ? AppColors.danger
                  : AppColors.primary,
              track: AppColors.line,
            ),
            const SizedBox(height: 6),
            Text(
              '${Money.formatWhole(held + total)} of your '
              '${Money.formatWhole(limit)} cash limit',
              style: const TextStyle(fontSize: 11, color: AppColors.muted),
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onRecord,
              child: saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text(blocked
                      ? 'Cannot record for this member'
                      : total <= 0
                          ? 'Enter what the member paid'
                          : 'Record ${Money.format(total)}'),
            ),
          ),
        ],
      ),
    );
  }
}
