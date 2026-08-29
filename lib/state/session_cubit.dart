import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/api_client.dart';
import '../data/models.dart';
import '../data/pin_lock.dart';
import '../data/repository.dart';
import '../data/session_store.dart';

enum SessionStatus { unknown, signedOut, signedIn }

/// What came of an attempt to unlock the app.
enum UnlockResult {
  unlocked,
  wrongPin,

  /// The account has no PIN. Nothing to check, so nothing to get wrong — the
  /// collector is sent to create one.
  needsPinSetup,

  /// Offline, and this phone has never completed an online unlock, so there is
  /// no verifier to check against.
  needsConnection,

  /// Too many wrong PINs offline. The session is gone; the receipts are not.
  signedOut,
}

class UnlockOutcome {
  const UnlockOutcome(this.result, {this.message = ''});

  final UnlockResult result;
  final String message;
}

class SessionState extends Equatable {
  const SessionState({
    this.status = SessionStatus.unknown,
    this.grant,
    this.grants = const [],
    this.profile,
    this.notice = '',
    this.locked = false,
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

  /// Signed in, but the PIN has not been presented since the app was last opened.
  /// Nothing behind the lock is shown while this is true.
  final bool locked;

  SessionState copyWith({
    SessionStatus? status,
    CollectorGrant? grant,
    List<CollectorGrant>? grants,
    CollectorProfile? profile,
    String? notice,
    bool? locked,
  }) =>
      SessionState(
        status: status ?? this.status,
        grant: grant ?? this.grant,
        grants: grants ?? this.grants,
        profile: profile ?? this.profile,
        notice: notice ?? this.notice,
        locked: locked ?? this.locked,
      );

  @override
  List<Object?> get props =>
      [status, grant?.collectorId, grants.length, profile?.id, notice, locked];
}

class SessionCubit extends Cubit<SessionState> {
  SessionCubit({
    required SessionStore store,
    required CollectorRepository repository,
    required AuthRepository auth,
    PinLock? lock,
  })  : _store = store,
        _repository = repository,
        _auth = auth,
        _lock = lock ?? PinLock(),
        super(const SessionState());

  final SessionStore _store;
  final CollectorRepository _repository;
  final AuthRepository _auth;
  final PinLock _lock;

  /// Decides what the app opens on. A stored token with a stored grant is enough to
  /// come back to, but not to walk straight in on: the PIN is asked for on every
  /// launch, so the session comes back locked and the grants are re-read behind the
  /// lock, because terms and suspensions change while the app is closed.
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
      locked: true,
    ));
    refreshGrants();
  }

  /// [pin] is what the collector just signed in with, and is remembered so the next
  /// launch can be unlocked with no signal. It is empty only where the sign-in did
  /// not involve one, which cannot happen today — the server requires either the
  /// existing PIN or a new one.
  Future<void> completeLogin(LoginResult result, {String pin = ''}) async {
    await _store.saveTokens(access: result.token, refresh: result.refreshToken);
    await _store.saveActiveGrant(result.grant);
    await _store.saveProfile(result.profile);
    await _store.saveGrants([result.grant]);
    if (pin.isNotEmpty) {
      await _lock.remember(pin);
    } else {
      await _lock.forget();
    }
    emit(SessionState(
      status: SessionStatus.signedIn,
      grant: result.grant,
      grants: [result.grant],
      profile: result.profile,
    ));
    refreshGrants();
  }

  /// Puts the lock back on. Called when the app is launched and when it comes back
  /// from a long spell in the background.
  void lockNow() {
    if (state.status != SessionStatus.signedIn || state.locked) return;
    emit(state.copyWith(locked: true));
  }

  /// Checks the PIN and, if it is right, opens the round.
  ///
  /// The server is asked first, because it is the authority: the PIN is one PIN on
  /// one account and the member app can change it. When there is no connection the
  /// verifier left behind by the last online unlock is what answers — a collector
  /// standing at a door out of signal is the case this app exists for, and a lock
  /// that only opens online would make it useless. Offline attempts are counted, and
  /// running out of them ends the session rather than the round: the receipts already
  /// written stay on the phone and go up when whoever signs in next has signal.
  Future<UnlockOutcome> unlock(String pin) async {
    try {
      final check = await _auth.unlock(pin);
      if (check == UnlockCheck.needsPinSetup) {
        return const UnlockOutcome(
          UnlockResult.needsPinSetup,
          message: 'This account has no PIN yet. Create one to carry on.',
        );
      }
      await _lock.remember(pin);
      emit(state.copyWith(locked: false));
      refreshGrants();
      return const UnlockOutcome(UnlockResult.unlocked);
    } on ApiException catch (e) {
      if (!e.isTransport) {
        // The server refused it — a wrong PIN, or a lockout. Its own wording is
        // more accurate than anything that could be written here.
        return UnlockOutcome(UnlockResult.wrongPin, message: e.message);
      }
      return _unlockOffline(pin);
    }
  }

  Future<UnlockOutcome> _unlockOffline(String pin) async {
    if (!await _lock.isSet) {
      return const UnlockOutcome(
        UnlockResult.needsConnection,
        message: 'Your PIN has to be checked with Communal the first time you '
            'unlock on this phone. Find signal once, and after that it works '
            'without any.',
      );
    }
    if (await _lock.matches(pin)) {
      await _lock.clearFailures();
      emit(state.copyWith(locked: false));
      return const UnlockOutcome(UnlockResult.unlocked);
    }
    final used = await _lock.recordFailure();
    final left = PinLock.maxOfflineAttempts - used;
    if (left <= 0) {
      await signOut(
        notice: 'Too many wrong PINs, so this phone signed you out. Sign in again '
            'to carry on — the receipts you have already written are still here '
            'and will go up with you.',
      );
      return const UnlockOutcome(UnlockResult.signedOut);
    }
    return UnlockOutcome(
      UnlockResult.wrongPin,
      message: 'That PIN is not right. $left ${left == 1 ? 'try' : 'tries'} left '
          'before this phone signs you out.',
    );
  }

  /// Re-reads the grants. A grant the cooperative revoked disappears; if it was the
  /// active one, the app falls back to another rather than sitting on a dead one.
  ///
  /// An empty list is the server saying every grant is gone. That is worth acting
  /// on: left signed in, the collector would keep writing receipts that are refused
  /// with a 403 they have no way to read. A transport failure is a different thing
  /// and lands in the catch, where the stored grant stands.
  Future<void> refreshGrants() async {
    if (state.status != SessionStatus.signedIn) return;
    try {
      final grants = await _repository.myGrants();
      if (grants.isEmpty) {
        await signOut(
          notice: 'Your cooperative has ended your collector account. Anything you '
              'still owe them is settled with an administrator directly.',
        );
        return;
      }
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
    await _lock.forget();
    emit(SessionState(status: SessionStatus.signedOut, notice: notice));
  }
}
