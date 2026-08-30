import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:iconsax/iconsax.dart';

import '../core/money.dart';
import '../core/theme.dart';
import '../data/api_client.dart';
import '../data/local_cache.dart';
import '../data/models.dart';
import '../data/outbox.dart';
import '../data/repository.dart';
import '../state/outbox_cubit.dart';
import '../widgets/common.dart';

/// Which of the member's obligation accounts the collector is looking at.
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

  /// Kobo against each obligation, keyed by `account_code`.
  ///
  /// Held here rather than in a controller per obligation because the list is now
  /// filtered and built lazily: a row that scrolls out of view or falls out of the
  /// filter takes its controller with it, and a figure the collector had already
  /// entered would go with it. The code is what the receipt is built from, so what
  /// the screen shows can change freely without touching the money.
  final Map<String, int> _allocated = {};

  Future<Cached<MemberObligation>>? _future;
  CollectorStanding? _standing;
  _Lens _lens = _Lens.owing;
  String _query = '';
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

  bool _isOverdue(MemberObligation obligation) {
    final due = obligation.nextDueDate;
    if (due == null) return false;
    final now = DateTime.now();
    return !due.isAfter(DateTime(now.year, now.month, now.day));
  }

  /// Overdue and owing first, then owing by what is left on it, then settled — and
  /// alphabetically inside each band so the same account is always in the same place
  /// on the round.
  List<MemberObligation> _ordered(List<MemberObligation> list) {
    int band(MemberObligation o) {
      if (o.outstanding <= 0) return 2;
      return _isOverdue(o) ? 0 : 1;
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

  List<MemberObligation> _visible(List<MemberObligation> ordered) {
    final query = _query.trim().toLowerCase();
    return ordered.where((o) {
      // An account with money already against it is never hidden, whatever the
      // lens or the search says. The collector has to be able to see every line
      // they are about to sign for.
      if ((_allocated[o.accountCode] ?? 0) > 0) return true;
      switch (_lens) {
        case _Lens.due:
          if (o.outstanding <= 0 || !_isOverdue(o)) return false;
        case _Lens.owing:
          if (o.outstanding <= 0) return false;
        case _Lens.all:
          break;
      }
      if (query.isEmpty) return true;
      return o.title.toLowerCase().contains(query) ||
          o.accountCode.toLowerCase().contains(query);
    }).toList();
  }

  Future<void> _editAmount(MemberObligation obligation) async {
    final amount = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AmountSheet(
        obligation: obligation,
        initial: _allocated[obligation.accountCode] ?? 0,
        overdue: _isOverdue(obligation),
      ),
    );
    if (amount == null) return;
    setState(() {
      if (amount <= 0) {
        _allocated.remove(obligation.accountCode);
      } else {
        _allocated[obligation.accountCode] = amount;
      }
      _error = '';
    });
  }

  void _fillOwed(List<MemberObligation> obligations) {
    setState(() {
      for (final obligation in obligations) {
        if (obligation.outstanding > 0) {
          _allocated[obligation.accountCode] = obligation.outstanding;
        }
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

  Future<void> _openReview(List<MemberObligation> obligations) async {
    final byCode = {for (final o in obligations) o.accountCode: o};
    final edit = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ReviewSheet(
        lines: [
          for (final entry in _allocated.entries)
            if (entry.value > 0)
              _ReviewLine(
                code: entry.key,
                title: byCode[entry.key]?.title ?? entry.key,
                amount: entry.value,
              ),
        ],
        total: _total,
        note: _note,
        postsOnCollection: widget.grant.postsOnCollection,
        onRemove: (code) => setState(() {
          _allocated.remove(code);
          _error = '';
        }),
      ),
    );
    if (!mounted || edit == null) return;
    final obligation = byCode[edit];
    if (obligation != null) await _editAmount(obligation);
  }

  Future<void> _record(List<MemberObligation> obligations) async {
    // Built off the full list, never the filtered one: a lens or a search must not
    // be able to drop an amount the collector already entered.
    final allocations = <CollectionAllocation>[];
    for (final obligation in obligations) {
      final amount = _allocated[obligation.accountCode] ?? 0;
      if (amount <= 0) continue;
      allocations.add(CollectionAllocation(
        obligationCode: obligation.accountCode,
        title: obligation.title,
        amount: amount,
      ));
    }
    if (allocations.isEmpty) {
      setState(() =>
          _error = 'Enter what the member paid against at least one obligation.');
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
          final obligations = _ordered(result.items);
          if (obligations.isEmpty) {
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
                obligations: obligations,
                stale: result.stale,
                member: widget.member,
                postsOnCollection: widget.grant.postsOnCollection,
                onFillOwed: _blocked ? null : () => _fillOwed(obligations),
                onClear:
                    _blocked || _allocated.isEmpty ? null : _clearAll,
              ),
              if (obligations.length > _lensThreshold)
                _LensBar(
                  lens: _lens,
                  search: _search,
                  onLens: (lens) => setState(() => _lens = lens),
                  onQuery: (value) => setState(() => _query = value),
                ),
              Expanded(child: _list(obligations)),
              _BottomBar(
                total: _total,
                lines: _lines,
                headroom: _headroom,
                cashInHand: _standing?.cashInHand,
                cashLimit: _standing?.cashLimitMinor,
                error: _error,
                saving: _saving,
                blocked: _blocked,
                onReview: _lines == 0 ? null : () => _openReview(obligations),
                onRecord: _saving || _total <= 0 || _blocked
                    ? null
                    : () => _record(obligations),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _list(List<MemberObligation> obligations) {
    final visible = _visible(obligations);
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
                    ? 'Nothing is overdue'
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
        final obligation = visible[index];
        return _ObligationRow(
          obligation: obligation,
          allocated: _allocated[obligation.accountCode] ?? 0,
          overdue: _isOverdue(obligation),
          onTap: _blocked ? null : () => _editAmount(obligation),
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
    required this.obligations,
    required this.stale,
    required this.member,
    required this.postsOnCollection,
    required this.onFillOwed,
    required this.onClear,
  });

  final List<MemberObligation> obligations;
  final bool stale;
  final CollectorMember member;
  final bool postsOnCollection;
  final VoidCallback? onFillOwed;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final owed = obligations.fold<int>(0, (sum, o) => sum + o.outstanding);
    final owing = obligations.where((o) => o.outstanding > 0).length;
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
                      '${obligations.length} '
                      '${obligations.length == 1 ? 'account' : 'accounts'}'
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

/// One obligation on one line: what it is, what stands against it, and what the
/// collector has put against it so far.
class _ObligationRow extends StatelessWidget {
  const _ObligationRow({
    required this.obligation,
    required this.allocated,
    required this.overdue,
    required this.onTap,
  });

  final MemberObligation obligation;
  final int allocated;
  final bool overdue;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final outstanding = obligation.outstanding;
    final filled = allocated > 0;
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
                    Text(
                      obligation.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    // One line rather than a row of two: an account name and a
                    // five-figure balance already fill a phone's width, and a row
                    // of unflexed texts has nowhere to go when they do.
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: outstanding > 0
                                ? '${Money.formatWhole(outstanding)} outstanding'
                                : 'Settled',
                            style: TextStyle(
                              color: outstanding > 0
                                  ? AppColors.muted
                                  : AppColors.success,
                            ),
                          ),
                          if (obligation.nextDueDate != null)
                            TextSpan(
                              text:
                                  '  · ${overdue ? 'due' : 'by'} ${Dates.day(obligation.nextDueDate)}',
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
}

/// The amount for one obligation, on its own.
///
/// A sheet rather than a field on the row: with a real chart of accounts there are
/// too many rows for a field each, and the amount is worth the collector's whole
/// attention for the moment they are entering it.
class _AmountSheet extends StatefulWidget {
  const _AmountSheet({
    required this.obligation,
    required this.initial,
    required this.overdue,
  });

  final MemberObligation obligation;
  final int initial;
  final bool overdue;

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
    final obligation = widget.obligation;
    final outstanding = obligation.outstanding;
    final entered = moneyFieldMinor(_amount);
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
            obligation.title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            [
              outstanding > 0
                  ? '${Money.format(outstanding)} outstanding of ${Money.format(obligation.amount)}'
                  : 'Nothing outstanding on this account',
              if (obligation.nextDueDate != null)
                '${widget.overdue ? 'was due' : 'due'} ${Dates.day(obligation.nextDueDate)}',
            ].join(' · '),
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
              if (outstanding > 0)
                ActionChip(
                  label: Text('Pay all ${Money.formatWhole(outstanding)}'),
                  onPressed: () => _set(outstanding),
                ),
              if (obligation.amount > 0 && obligation.amount != outstanding)
                ActionChip(
                  label: Text('Standing ${Money.formatWhole(obligation.amount)}'),
                  onPressed: () => _set(obligation.amount),
                ),
              if (widget.initial > 0)
                ActionChip(
                  avatar: const Icon(Iconsax.trash, size: 15, color: AppColors.danger),
                  label: const Text('Remove'),
                  onPressed: () => Navigator.of(context).pop(0),
                ),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: entered <= 0 && widget.initial <= 0
                  ? null
                  : () => Navigator.of(context).pop(entered),
              child: Text(entered <= 0
                  ? 'Leave this account'
                  : '${widget.initial > 0 ? 'Update' : 'Add'} ${Money.format(entered)}'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewLine {
  const _ReviewLine({
    required this.code,
    required this.title,
    required this.amount,
  });

  final String code;
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
                        onTap: () => Navigator.of(context).pop(line.code),
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
                        widget.onRemove(line.code);
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
