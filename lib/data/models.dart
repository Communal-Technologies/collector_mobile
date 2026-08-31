import '../core/money.dart';

int _asInt(dynamic value) {
  if (value == null) return 0;
  if (value is int) return value;
  if (value is double) return value.round();
  return int.tryParse(value.toString()) ?? 0;
}

int? _asNullableInt(dynamic value) {
  if (value == null) return null;
  return _asInt(value);
}

String _asString(dynamic value) => value == null ? '' : value.toString();

/// One cooperative the signed-in account collects for, on the terms that
/// cooperative set. A person can collect for more than one, which is why the app
/// always knows which grant it is acting under.
class CollectorGrant {
  const CollectorGrant({
    required this.collectorId,
    required this.collectorCode,
    required this.cooperativeId,
    required this.cooperativeName,
    required this.fullName,
    required this.settlementMode,
    required this.commissionType,
    required this.commissionValue,
    required this.cashLimitMinor,
    required this.status,
  });

  final String collectorId;
  final String collectorCode;
  final String cooperativeId;
  final String cooperativeName;
  final String fullName;
  final String settlementMode;
  final String commissionType;
  final int commissionValue;
  final int? cashLimitMinor;
  final String status;

  bool get isActive => status == 'active';
  bool get postsOnCollection => settlementMode == 'on_collection';

  /// What the cooperative pays this person, in words. Percentage is basis points
  /// and flat is kobo per collection, so neither is shown raw.
  String get commissionLabel {
    switch (commissionType) {
      case 'percentage':
        final percent = commissionValue / 100;
        final text = percent == percent.roundToDouble()
            ? percent.toStringAsFixed(0)
            : percent.toStringAsFixed(2);
        return '$text% of what you collect';
      case 'flat':
        return '${Money.format(commissionValue)} per collection';
      default:
        return 'No commission';
    }
  }

  factory CollectorGrant.fromJson(Map<String, dynamic> json) {
    return CollectorGrant(
      collectorId: _asString(json['collector_id'] ?? json['id']),
      collectorCode: _asString(json['collector_code']),
      cooperativeId: _asString(json['cooperative_id']),
      cooperativeName: _asString(
        json['cooperative_name'] ?? json['cooperative_id'],
      ),
      fullName: _asString(json['full_name']),
      settlementMode: _asString(json['settlement_mode']),
      commissionType: _asString(json['commission_type']),
      commissionValue: _asInt(json['commission_value']),
      cashLimitMinor: _asNullableInt(json['cash_limit_minor']),
      status: _asString(json['status']),
    );
  }

  Map<String, dynamic> toJson() => {
        'collector_id': collectorId,
        'collector_code': collectorCode,
        'cooperative_id': cooperativeId,
        'cooperative_name': cooperativeName,
        'full_name': fullName,
        'settlement_mode': settlementMode,
        'commission_type': commissionType,
        'commission_value': commissionValue,
        'cash_limit_minor': cashLimitMinor,
        'status': status,
      };
}

/// How much of the cooperative's money is in this collector's hands right now —
/// what is already countersigned into their float plus what they have declared and
/// not yet had approved. This is the number the whole app opens on.
class CollectorStanding {
  const CollectorStanding({
    required this.floatBalance,
    required this.pendingTotal,
    required this.pendingCount,
    required this.cashInHand,
    required this.cashLimitMinor,
    required this.headroom,
    required this.collectorCode,
    required this.fullName,
    required this.status,
  });

  final int floatBalance;
  final int pendingTotal;
  final int pendingCount;
  final int cashInHand;
  final int? cashLimitMinor;
  final int? headroom;
  final String collectorCode;
  final String fullName;
  final String status;

  factory CollectorStanding.fromJson(Map<String, dynamic> json) {
    final collector = (json['collector'] as Map<String, dynamic>?) ?? const {};
    return CollectorStanding(
      floatBalance: _asInt(json['float_balance']),
      pendingTotal: _asInt(json['pending_total']),
      pendingCount: _asInt(json['pending_count']),
      cashInHand: _asInt(json['cash_in_hand']),
      cashLimitMinor: _asNullableInt(json['cash_limit_minor']),
      headroom: _asNullableInt(json['headroom']),
      collectorCode: _asString(collector['collector_code']),
      fullName: _asString(collector['full_name']),
      status: _asString(collector['status']),
    );
  }
}

/// A name on the collector's round. Deliberately the least they need to find the
/// right person: a collector is not an administrator, so nothing else about the
/// member is theirs to read.
class CollectorMember {
  const CollectorMember({
    required this.ledgerNumber,
    required this.fullName,
    required this.phone,
    required this.deactivated,
    required this.collectible,
    required this.standing,
  });

  final String ledgerNumber;
  final String fullName;
  final String phone;
  final bool deactivated;

  /// Whether the cooperative's membership for this person is active. False closes
  /// the door on a receipt: the cooperative pays Communal per active member, so
  /// collecting against a membership it has stopped paying for would make the
  /// collector the way round the subscription. The server refuses it too — this only
  /// saves the collector from being told at the member's door.
  final bool collectible;

  /// `active`, `suspended` (the cooperative closed it) or `lapsed` (the subscription
  /// ran out). Two different sentences at the door, and two different things for the
  /// cooperative to fix.
  final String standing;

  /// The one word the tile carries.
  String get standingLabel =>
      standing == 'suspended' ? 'suspended' : 'inactive';

  /// What the collector says at the door, and who has to fix it. Neither is the
  /// member's doing, so neither is worded as though it were.
  String get standingNote => standing == 'suspended'
      ? 'The cooperative has suspended this account. No collection can be recorded '
          'against it until they reinstate it.'
      : 'This membership is not active — the cooperative has to renew it before a '
          'collection can be recorded against it.';

  factory CollectorMember.fromJson(Map<String, dynamic> json) {
    final standing = _asString(json['standing']);
    final deactivated = json['deactivated'] == true;
    return CollectorMember(
      ledgerNumber: _asString(json['ledger_number']),
      fullName: _asString(json['full_name']),
      phone: _asString(json['phone']),
      deactivated: deactivated,
      // An older service that does not send the field must not lock the whole round
      // out; it has its own refusal at the point the receipt is sent.
      collectible: json.containsKey('collectible')
          ? json['collectible'] == true
          : !deactivated,
      standing: standing.isEmpty
          ? (deactivated ? 'suspended' : 'active')
          : standing,
    );
  }
}

/// One obligation the cash could settle, and what stands against it.
class MemberObligation {
  const MemberObligation({
    required this.id,
    required this.accountCode,
    required this.accountName,
    required this.amount,
    required this.amountPaid,
    required this.category,
    required this.recurring,
    required this.frequency,
    required this.nextDueDate,
    required this.pendingAmount,
    required this.fines,
  });

  final String id;
  final String accountCode;
  final String accountName;
  final int amount;
  final int amountPaid;

  /// What receipts already written are holding against this account and nobody has
  /// countersigned yet. [amountPaid] does not move until one is posted, so on a
  /// capped account it says there is room a receipt in the collector's own bag has
  /// already taken.
  final int pendingAmount;

  /// The cooperative's chart-of-accounts type: equity, patronage or custom.
  final String category;

  /// Whether the account falls due again. Equity does not — it is one commitment
  /// paid in instalments until it is complete, so it has no cycle, no due date and
  /// nothing to be overdue on. Only patronage and custom recur, on their frequency.
  final bool recurring;
  final String frequency;
  final DateTime? nextDueDate;

  /// The fines raised against this account's missed cycles.
  final List<MemberFine> fines;

  /// The name where the cooperative gave one, the code where it did not. The code
  /// is machine-minted and means nothing to the member, so it is the last resort.
  String get title => accountName.isNotEmpty ? accountName : accountCode;

  int get outstanding {
    final left = amount - amountPaid;
    return left > 0 ? left : 0;
  }

  factory MemberObligation.fromJson(Map<String, dynamic> json) {
    final rawFines = (json['fines'] as List<dynamic>?) ?? const [];
    return MemberObligation(
      id: _asString(json['id']),
      accountCode: _asString(json['account_code']),
      accountName: _asString(json['account_name']),
      amount: _asInt(json['amount']),
      amountPaid: _asInt(json['amount_paid']),
      category: _asString(json['category']),
      // Absent on a server that predates the distinction, where every account was
      // drawn as though it recurred. A due date is the honest signal there: the
      // server only ever computed one for an account with a cycle.
      recurring: json.containsKey('recurring')
          ? json['recurring'] == true
          : json['next_due_date'] != null,
      frequency: _asString(json['frequency']),
      nextDueDate: Dates.tryParse(json['next_due_date']),
      // Absent on a server that predates the figure. Zero is the honest reading of
      // that: it leaves the ceiling where it used to be rather than inventing a
      // claim, and the recorder still refuses the receipt one screen later.
      pendingAmount: _asInt(json['pending_amount']),
      fines: rawFines
          .whereType<Map<String, dynamic>>()
          .map(MemberFine.fromJson)
          .toList(),
    );
  }
}

/// A penalty standing against the member — either against one account's missed
/// cycle, or raised against them directly.
class MemberFine {
  const MemberFine({
    required this.id,
    required this.obligationId,
    required this.amount,
    required this.amountPaid,
    required this.status,
    required this.description,
    required this.dueDate,
  });

  final String id;

  /// The obligation whose missed cycle earned it, empty where an administrator
  /// raised it against the member directly.
  final String obligationId;
  final int amount;
  final int amountPaid;
  final String status;
  final String description;
  final DateTime? dueDate;

  int get outstanding {
    final left = amount - amountPaid;
    return left > 0 ? left : 0;
  }

  /// Whether a collector may take it. A waived fine is forgiven and a paid one is
  /// settled; taking cash against either would be taking money the member no
  /// longer owes.
  bool get collectible => status == 'pending' && outstanding > 0;

  factory MemberFine.fromJson(Map<String, dynamic> json) {
    return MemberFine(
      id: _asString(json['id']),
      obligationId: _asString(json['obligation_id']),
      amount: _asInt(json['amount']),
      amountPaid: _asInt(json['amount_paid']),
      status: _asString(json['status']),
      description: _asString(json['description']),
      dueDate: Dates.tryParse(json['due_date']),
    );
  }
}

/// One thing at the member's door that the cash can be put against.
///
/// An obligation account and a fine are the same decision to a collector — a name,
/// a figure and an amount to write beside it — but they are different rows in
/// different tables settled by different postings. So the screen works over this,
/// and `key` is what the receipt is keyed on.
class CollectionTarget {
  const CollectionTarget({
    required this.key,
    required this.obligationCode,
    required this.fineId,
    required this.title,
    required this.amount,
    required this.amountPaid,
    required this.recurring,
    required this.nextDueDate,
    this.pendingAmount = 0,
  });

  /// Unique within one receipt: an account code, or the fine's id namespaced so a
  /// fine and an account can never collide.
  final String key;
  final String obligationCode;
  final String fineId;
  final String title;

  /// What the whole thing comes to: one cycle for a recurring account, the entire
  /// commitment for a one-off, the penalty for a fine.
  final int amount;
  final int amountPaid;
  final bool recurring;
  final DateTime? nextDueDate;

  /// What receipts already written are holding here, unsettled. Only ever non-zero
  /// on a capped account, where it is part of the ceiling.
  final int pendingAmount;

  bool get isFine => fineId.isNotEmpty;

  int get outstanding {
    final left = amount - amountPaid;
    return left > 0 ? left : 0;
  }

  /// Whether there is a figure this one cannot be taken past.
  ///
  /// A fine is a fixed penalty with nowhere for an excess to go. A one-off account is
  /// the member's share capital — total shares × cost per share — and is complete
  /// when it is met, so the cooperative's own rules cap it. A recurring account has
  /// no ceiling: paying next month's contribution early is a thing collectors do.
  bool get capped => isFine || (!recurring && amount > 0);

  /// The most this one can still take, or null where nothing caps it.
  ///
  /// Receipts awaiting a countersignature are subtracted because they are cash the
  /// member has already handed over: the room they hold is gone whether or not it
  /// has reached [amountPaid] yet.
  int? get ceiling {
    if (!capped) return null;
    final left = amount - amountPaid - pendingAmount;
    return left > 0 ? left : 0;
  }

  factory CollectionTarget.obligation(MemberObligation obligation) {
    return CollectionTarget(
      key: obligation.accountCode,
      obligationCode: obligation.accountCode,
      fineId: '',
      title: obligation.title,
      amount: obligation.amount,
      amountPaid: obligation.amountPaid,
      recurring: obligation.recurring,
      nextDueDate: obligation.nextDueDate,
      pendingAmount: obligation.pendingAmount,
    );
  }

  /// A fine reads as a penalty rather than an account: it is settled once, in full
  /// or in part, and never falls due again — so it carries no frequency and its own
  /// due date is only what it was raised against.
  factory CollectionTarget.fine(MemberFine fine, {String against = ''}) {
    final what = fine.description.isNotEmpty ? fine.description : 'late payment';
    return CollectionTarget(
      key: 'fine:${fine.id}',
      obligationCode: '',
      fineId: fine.id,
      title: against.isEmpty ? 'Fine — $what' : 'Fine — $against',
      amount: fine.amount,
      amountPaid: fine.amountPaid,
      recurring: false,
      nextDueDate: fine.dueDate,
    );
  }

  /// The obligation accounts with the fines that ride on them, and the fines that
  /// stand on their own — each fine directly beneath what it was raised against, so
  /// a collector reads the account and its penalty together.
  static List<CollectionTarget> spread(
    List<MemberObligation> obligations,
    List<MemberFine> standaloneFines,
  ) {
    final targets = <CollectionTarget>[];
    for (final obligation in obligations) {
      targets.add(CollectionTarget.obligation(obligation));
      for (final fine in obligation.fines) {
        if (!fine.collectible) continue;
        targets.add(CollectionTarget.fine(fine, against: obligation.title));
      }
    }
    for (final fine in standaloneFines) {
      if (!fine.collectible) continue;
      targets.add(CollectionTarget.fine(fine));
    }
    return targets;
  }
}

/// Everything at the member's door, and what could not be read.
class MemberCollectibles {
  const MemberCollectibles({
    required this.targets,
    this.stale = false,
    this.finesError = '',
  });

  final List<CollectionTarget> targets;
  final bool stale;

  /// Why the fines raised against the member directly could not be read, where
  /// they could not. Their contributions are still collectable without them, so
  /// this is a notice on the screen rather than a failure of it.
  final String finesError;
}

/// One thing a collection settles and how much of the cash goes there.
class CollectionAllocation {
  const CollectionAllocation({
    required this.obligationCode,
    required this.title,
    required this.amount,
    this.fineId = '',
  });

  final String obligationCode;
  final String title;
  final int amount;

  /// Set where the cash settles a fine rather than an obligation account.
  final String fineId;

  bool get isFine => fineId.isNotEmpty;

  factory CollectionAllocation.fromJson(Map<String, dynamic> json) {
    return CollectionAllocation(
      obligationCode: _asString(json['obligation'] ?? json['obligation_code']),
      title: _asString(json['account_name'] ?? json['title']),
      amount: _asInt(json['amount']),
      fineId: _asString(json['fine_id']),
    );
  }

  Map<String, dynamic> toJson() => {
        'obligation': obligationCode,
        'title': title,
        'amount': amount,
        if (fineId.isNotEmpty) 'fine_id': fineId,
      };

  /// The wire shape obligations-svc accepts. `title` is the app's own label and has
  /// no place in the request. An obligation line carries no `target_type` at all:
  /// the service reads its absence as an obligation, and a receipt queued by an
  /// older build has to keep sending exactly what it always sent.
  Map<String, dynamic> toRequestJson() => isFine
      ? {
          'target_type': 'fine',
          'fine_id': fineId,
          'amount': amount,
        }
      : {
          'obligation': obligationCode,
          'amount': amount,
        };
}

/// A receipt. `pending` is a record waiting for an administrator to countersign the
/// cash; `posted` has already moved the member's obligations.
class Collection {
  const Collection({
    required this.id,
    required this.reference,
    required this.ledgerNumber,
    required this.memberName,
    required this.totalAmount,
    required this.status,
    required this.note,
    required this.collectedAt,
    required this.createdAt,
    required this.declineReason,
    required this.allocations,
  });

  final String id;
  final String reference;
  final String ledgerNumber;
  final String memberName;
  final int totalAmount;
  final String status;
  final String note;
  final DateTime? collectedAt;
  final DateTime? createdAt;
  final String declineReason;
  final List<CollectionAllocation> allocations;

  bool get isPending => status == 'pending';
  bool get isDeclined => status == 'declined';

  factory Collection.fromJson(Map<String, dynamic> json) {
    final raw = (json['allocations'] as List<dynamic>?) ?? const [];
    return Collection(
      id: _asString(json['id']),
      reference: _asString(json['reference']),
      ledgerNumber: _asString(json['ledger_number']),
      memberName: _asString(json['member_name']),
      totalAmount: _asInt(json['total_amount']),
      status: _asString(json['status']),
      note: _asString(json['note']),
      collectedAt: Dates.tryParse(json['collected_at']),
      createdAt: Dates.tryParse(json['created_at']),
      declineReason: _asString(json['decline_reason']),
      allocations: raw
          .whereType<Map<String, dynamic>>()
          .map(CollectionAllocation.fromJson)
          .toList(),
    );
  }
}

/// An account the collector may hand the cash to. The cooperative's own accounts
/// only — never another collector's float.
class RemittanceAccount {
  const RemittanceAccount({
    required this.id,
    required this.accountName,
    required this.bank,
    required this.accountNumber,
    required this.accountType,
  });

  final String id;
  final String accountName;
  final String bank;
  final String accountNumber;
  final String accountType;

  /// The name and the bank, never the account number. Showing a full account
  /// number on a screen a collector carries around adds nothing they need.
  String get label => bank.isEmpty ? accountName : '$accountName · $bank';

  factory RemittanceAccount.fromJson(Map<String, dynamic> json) {
    return RemittanceAccount(
      id: _asString(json['id']),
      accountName: _asString(json['account_name']),
      bank: _asString(json['bank']),
      accountNumber: _asString(json['account_number']),
      accountType: _asString(json['account_type']),
    );
  }
}

/// A hand-in the collector declared. It comes off their float only once an
/// administrator confirms the cash, so `pending` here means "claimed, not counted".
class Remittance {
  const Remittance({
    required this.id,
    required this.amount,
    required this.reference,
    required this.status,
    required this.narration,
    required this.toAccountName,
    required this.failureReason,
    required this.createdAt,
  });

  final int amount;
  final String id;
  final String reference;
  final String status;
  final String narration;
  final String toAccountName;
  final String failureReason;
  final DateTime? createdAt;

  factory Remittance.fromJson(Map<String, dynamic> json) {
    final to = (json['to_repository'] as Map<String, dynamic>?) ?? const {};
    return Remittance(
      id: _asString(json['id']),
      amount: _asInt(json['amount']),
      reference: _asString(json['reference']),
      status: _asString(json['status']),
      narration: _asString(json['narration']),
      toAccountName: _asString(to['account_name']),
      failureReason: _asString(json['failure_reason']),
      createdAt: Dates.tryParse(json['created_at']),
    );
  }
}

/// What the collector has earned and what of it is still owed. `claimed` is money
/// on a payout an administrator has raised and a second one has not yet approved —
/// its own figure, because "on its way" is not the same answer as "still to raise".
class EarningsSummary {
  const EarningsSummary({
    required this.collections,
    required this.earned,
    required this.outstanding,
    required this.claimed,
    required this.paid,
  });

  final int collections;
  final int earned;
  final int outstanding;
  final int claimed;
  final int paid;

  factory EarningsSummary.fromJson(Map<String, dynamic> json) {
    return EarningsSummary(
      collections: _asInt(json['collections']),
      earned: _asInt(json['earned']),
      outstanding: _asInt(json['outstanding']),
      claimed: _asInt(json['claimed']),
      paid: _asInt(json['paid']),
    );
  }
}

/// One collection's commission, priced on the terms in force when it posted.
class CommissionEntry {
  const CommissionEntry({
    required this.id,
    required this.collectionReference,
    required this.basisAmount,
    required this.amount,
    required this.status,
    required this.paidAt,
    required this.createdAt,
  });

  final String id;
  final String collectionReference;
  final int basisAmount;
  final int amount;
  final String status;
  final DateTime? paidAt;
  final DateTime? createdAt;

  factory CommissionEntry.fromJson(Map<String, dynamic> json) {
    return CommissionEntry(
      id: _asString(json['id']),
      collectionReference: _asString(json['collection_reference']),
      basisAmount: _asInt(json['basis_amount']),
      amount: _asInt(json['amount']),
      status: _asString(json['status']),
      paidAt: Dates.tryParse(json['paid_at']),
      createdAt: Dates.tryParse(json['created_at']),
    );
  }
}

/// The challenge the login request opened: which channel the code went to, and the
/// grants this account could sign in under once it is verified.
class LoginChallenge {
  const LoginChallenge({
    required this.challengeId,
    required this.channel,
    required this.maskedDestination,
    required this.requiresPinSetup,
    required this.grants,
    required this.message,
  });

  final String challengeId;
  final String channel;
  final String maskedDestination;
  final bool requiresPinSetup;
  final List<CollectorGrant> grants;
  final String message;

  factory LoginChallenge.fromJson(Map<String, dynamic> json) {
    final raw = (json['collectors'] as List<dynamic>?) ?? const [];
    return LoginChallenge(
      challengeId: _asString(json['challenge_id']),
      channel: _asString(json['channel']),
      maskedDestination: _asString(json['masked_destination']),
      requiresPinSetup: json['requires_pin_setup'] == true,
      grants: raw
          .whereType<Map<String, dynamic>>()
          .map(CollectorGrant.fromJson)
          .toList(),
      message: _asString(json['message']),
    );
  }
}

/// The account behind the session. A collector signs in with their ordinary
/// Communal account, so this is the same person a member screen would show.
class CollectorProfile {
  const CollectorProfile({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.phone,
    required this.email,
  });

  final String id;
  final String firstName;
  final String lastName;
  final String phone;
  final String email;

  String get displayName {
    final name = '$firstName $lastName'.trim();
    return name.isEmpty ? phone : name;
  }

  factory CollectorProfile.fromJson(Map<String, dynamic> json) {
    return CollectorProfile(
      id: _asString(json['id']),
      firstName: _asString(json['first_name']),
      lastName: _asString(json['last_name']),
      phone: _asString(json['phone']),
      email: _asString(json['email']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'first_name': firstName,
        'last_name': lastName,
        'phone': phone,
        'email': email,
      };
}
