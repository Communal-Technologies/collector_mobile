import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:iconsax/iconsax.dart';

import '../core/theme.dart';
import '../data/api_client.dart';
import '../data/local_cache.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../widgets/common.dart';
import 'record_collection_screen.dart';

/// The round: who this collector may collect from, and the way in to writing a
/// receipt for one of them.
class MembersTab extends StatefulWidget {
  const MembersTab({
    super.key,
    required this.grant,
    required this.revision,
    required this.onChanged,
  });

  final CollectorGrant grant;
  final int revision;
  final VoidCallback onChanged;

  @override
  State<MembersTab> createState() => _MembersTabState();
}

class _MembersTabState extends State<MembersTab> {
  final _search = TextEditingController();
  Timer? _debounce;

  Future<Cached<CollectorMember>>? _future;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(MembersTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.revision != widget.revision ||
        oldWidget.grant.collectorId != widget.grant.collectorId) {
      _load();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _load() {
    setState(() {
      _future = context
          .read<CollectorRepository>()
          .members(widget.grant.cooperativeId, query: _query);
    });
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _query = value;
      _load();
    });
  }

  Future<void> _openMember(CollectorMember member) async {
    final recorded = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => RecordCollectionScreen(
          grant: widget.grant,
          member: member,
        ),
      ),
    );
    if (recorded == true) widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: TextField(
            controller: _search,
            onChanged: _onSearchChanged,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search by name, ledger number or phone',
              prefixIcon: const Icon(Iconsax.search_normal, size: 20),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Iconsax.close_circle, size: 18),
                      onPressed: () {
                        _search.clear();
                        _query = '';
                        _load();
                      },
                    ),
            ),
          ),
        ),
        if (!widget.grant.isActive)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Notice(
              text: 'Your collector account is ${widget.grant.status}. You cannot record '
                  'new collections until the cooperative reinstates you — but you can '
                  'still remit the cash you are holding.',
              tone: AppColors.danger,
              background: AppColors.dangerSoft,
              icon: Iconsax.slash,
            ),
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              _load();
              widget.onChanged();
            },
            child: FutureBuilder<Cached<CollectorMember>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const SkeletonRows(count: 7);
                }
                if (snapshot.hasError) {
                  final error = snapshot.error;
                  return ListView(
                    children: [
                      const SizedBox(height: 60),
                      EmptyState(
                        icon: Iconsax.cloud_cross,
                        title: 'Could not load your round',
                        message: error is ApiException
                            ? error.message
                            : 'Pull down to try again.',
                      ),
                    ],
                  );
                }
                final result = snapshot.data;
                final members = result?.items ?? const <CollectorMember>[];
                if (members.isEmpty) {
                  return ListView(
                    children: [
                      const SizedBox(height: 60),
                      EmptyState(
                        icon: Iconsax.profile_2user,
                        title: _query.isEmpty
                            ? 'No members on your round yet'
                            : 'Nobody matches "$_query"',
                        message: _query.isEmpty
                            ? 'The cooperative decides who a collector may collect from. '
                                'Ask them to add members to your round.'
                            : 'Check the spelling, or search by ledger number.',
                      ),
                    ],
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  itemCount: members.length + (result!.stale ? 1 : 0),
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    if (result.stale && index == 0) {
                      return const Padding(
                        padding: EdgeInsets.only(bottom: 8),
                        child: Notice(
                          text: 'No connection — this is the round as it was the last '
                              'time this phone reached the cooperative. You can still '
                              'record; receipts go up when you have signal.',
                          icon: Iconsax.cloud_cross,
                        ),
                      );
                    }
                    final member = members[result.stale ? index - 1 : index];
                    return _MemberTile(
                      member: member,
                      onTap: widget.grant.isActive && member.collectible
                          ? () => _openMember(member)
                          : null,
                    );
                  },
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({required this.member, this.onTap});

  final CollectorMember member;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final initials = member.fullName.isEmpty
        ? '#'
        : member.fullName
            .trim()
            .split(RegExp(r'\s+'))
            .take(2)
            .map((part) => part[0].toUpperCase())
            .join();
    return Card(
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: Container(
          height: 40,
          width: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.primarySoft,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            initials,
            style: const TextStyle(
              color: AppColors.primary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        title: Text(
          member.fullName.isEmpty ? member.ledgerNumber : member.fullName,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              [
                member.ledgerNumber,
                if (member.phone.isNotEmpty) member.phone,
              ].join(' · '),
              style: const TextStyle(fontSize: 12),
            ),
            if (!member.collectible) ...[
              const SizedBox(height: 4),
              Text(
                member.standingNote,
                style: const TextStyle(
                  fontSize: 11.5,
                  height: 1.35,
                  color: AppColors.danger,
                ),
              ),
            ],
          ],
        ),
        trailing: !member.collectible
            ? StatusChip(
                member.standing == 'suspended' ? 'declined' : 'pending',
                label: member.standingLabel,
              )
            : onTap == null
                ? null
                : const Icon(Iconsax.arrow_right_3, color: AppColors.muted),
      ),
    );
  }
}
