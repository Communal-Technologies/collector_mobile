import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/models.dart';
import '../data/repository.dart';
import '../data/session_store.dart';

enum SessionStatus { unknown, signedOut, signedIn }

class SessionState extends Equatable {
  const SessionState({
    this.status = SessionStatus.unknown,
    this.grant,
    this.grants = const [],
    this.profile,
    this.notice = '',
  });

  final SessionStatus status;

  /// The grant the app is currently acting under. A person can collect for more
  /// than one cooperative, and nothing in this app is meaningful without knowing
  /// which one — the members, the float, the terms and the commission are all
  /// per-cooperative.
  final CollectorGrant? grant;

  final List<CollectorGrant> grants;
  final CollectorProfile? profile;

  /// Why the collector was signed out, when it was not their own doing.
  final String notice;

  SessionState copyWith({
    SessionStatus? status,
    CollectorGrant? grant,
    List<CollectorGrant>? grants,
    CollectorProfile? profile,
    String? notice,
  }) =>
      SessionState(
        status: status ?? this.status,
        grant: grant ?? this.grant,
        grants: grants ?? this.grants,
        profile: profile ?? this.profile,
        notice: notice ?? this.notice,
      );

  @override
  List<Object?> get props => [status, grant?.collectorId, grants.length, profile?.id, notice];
}

class SessionCubit extends Cubit<SessionState> {
  SessionCubit({
    required SessionStore store,
    required CollectorRepository repository,
  })  : _store = store,
        _repository = repository,
        super(const SessionState());

  final SessionStore _store;
  final CollectorRepository _repository;

  /// Decides what the app opens on. A stored token with a stored grant is enough to
  /// go straight in; the grants are then re-read from the server, because terms and
  /// suspensions change while the app is closed.
  Future<void> bootstrap() async {
    await _store.load();
    if (!_store.hasSession) {
      emit(state.copyWith(status: SessionStatus.signedOut));
      return;
    }
    final grant = await _store.readActiveGrant();
    final grants = await _store.readGrants();
    final profile = await _store.readProfile();
    if (grant == null) {
      emit(state.copyWith(status: SessionStatus.signedOut));
      return;
    }
    emit(SessionState(
      status: SessionStatus.signedIn,
      grant: grant,
      grants: grants.isEmpty ? [grant] : grants,
      profile: profile,
    ));
    refreshGrants();
  }

  Future<void> completeLogin(LoginResult result) async {
    await _store.saveTokens(access: result.token, refresh: result.refreshToken);
    await _store.saveActiveGrant(result.grant);
    await _store.saveProfile(result.profile);
    await _store.saveGrants([result.grant]);
    emit(SessionState(
      status: SessionStatus.signedIn,
      grant: result.grant,
      grants: [result.grant],
      profile: result.profile,
    ));
    refreshGrants();
  }

  /// Re-reads the grants. A grant the cooperative revoked disappears; if it was the
  /// active one, the app falls back to another rather than sitting on a dead one.
  Future<void> refreshGrants() async {
    if (state.status != SessionStatus.signedIn) return;
    try {
      final grants = await _repository.myGrants();
      if (grants.isEmpty) return;
      await _store.saveGrants(grants);
      final current = state.grant;
      final match = grants.firstWhere(
        (g) => g.collectorId == current?.collectorId,
        orElse: () => grants.first,
      );
      await _store.saveActiveGrant(match);
      emit(state.copyWith(grants: grants, grant: match));
    } catch (_) {
      // Offline, or the server is down. The stored grant is what the collector
      // keeps working under until it can be checked again.
    }
  }

  Future<void> switchGrant(CollectorGrant grant) async {
    await _store.saveActiveGrant(grant);
    emit(state.copyWith(grant: grant));
  }

  Future<void> signOut({String notice = ''}) async {
    await _store.clear();
    emit(SessionState(status: SessionStatus.signedOut, notice: notice));
  }
}
