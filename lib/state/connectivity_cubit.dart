import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../core/config.dart';

/// Whether the cooperative can be reached, which is not the same question as
/// whether the phone has a bar of signal.
enum Reachability { unknown, online, offline }

class ConnectivityState extends Equatable {
  const ConnectivityState({
    this.reachability = Reachability.unknown,
    this.hasTransport = true,
    this.checking = false,
  });

  final Reachability reachability;

  /// What the operating system says about wifi/mobile/ethernet. Kept apart from
  /// [reachability] because the two disagree often enough to matter: a hotspot
  /// with no data left, a captive portal, or a carrier that resolves nothing
  /// all report a transport while the cooperative is unreachable — and the
  /// collector needs to be told which of the two is wrong.
  final bool hasTransport;

  final bool checking;

  bool get isOnline => reachability == Reachability.online;
  bool get isOffline => reachability == Reachability.offline;

  ConnectivityState copyWith({
    Reachability? reachability,
    bool? hasTransport,
    bool? checking,
  }) => ConnectivityState(
    reachability: reachability ?? this.reachability,
    hasTransport: hasTransport ?? this.hasTransport,
    checking: checking ?? this.checking,
  );

  @override
  List<Object?> get props => [reachability, hasTransport, checking];
}

/// Watches whether this phone can reach the platform.
///
/// The app is offline-first on purpose, so this exists to *tell the collector
/// what is true* — and to gate the two or three things that genuinely cannot be
/// done without a connection — never to stop them recording a collection. The
/// state is deliberately three-valued: [Reachability.unknown] is treated as
/// online by every caller, so nothing is blocked during the moment before the
/// first check finishes.
///
/// The reachability check is a TCP connect to the API host itself, not a ping to
/// a well-known address. On the round both failures are common and they need
/// different words: no signal at all, versus a connection that carries nothing.
/// Probing 1.1.1.1 cannot tell them apart.
class ConnectivityCubit extends Cubit<ConnectivityState> {
  ConnectivityCubit({
    Stream<List<ConnectivityResult>>? transportChanges,
    Future<List<ConnectivityResult>> Function()? checkTransport,
    Future<bool> Function()? probe,
    Duration retryInterval = const Duration(seconds: 15),
  }) : _checkTransport = checkTransport ?? Connectivity().checkConnectivity,
       _probe = probe ?? _probeApiHost,
       _retryInterval = retryInterval,
       super(const ConnectivityState()) {
    _transportSubscription =
        (transportChanges ?? Connectivity().onConnectivityChanged).listen(
          _onTransportChanged,
          onError: (_) => recheck(),
        );
    recheck();
  }

  final Future<List<ConnectivityResult>> Function() _checkTransport;
  final Future<bool> Function() _probe;
  final Duration _retryInterval;

  StreamSubscription<List<ConnectivityResult>>? _transportSubscription;
  Timer? _retryTimer;
  Future<void>? _inFlight;

  static bool _carries(List<ConnectivityResult> results) => results.any(
    (r) =>
        r == ConnectivityResult.mobile ||
        r == ConnectivityResult.wifi ||
        r == ConnectivityResult.ethernet ||
        r == ConnectivityResult.vpn,
  );

  void _onTransportChanged(List<ConnectivityResult> results) {
    final carries = _carries(results);
    if (!carries) {
      // Nothing to probe over. Said plainly rather than after a socket timeout,
      // because the collector is standing in front of somebody.
      _emitOffline(hasTransport: false);
      return;
    }
    emit(state.copyWith(hasTransport: true));
    recheck();
  }

  /// Checks now. Shared, so a burst of transport events on a bus ride does not
  /// open a socket per event.
  Future<void> recheck() {
    final inFlight = _inFlight;
    if (inFlight != null) return inFlight;
    final future = _evaluate();
    _inFlight = future;
    return future.whenComplete(() => _inFlight = null);
  }

  Future<void> _evaluate() async {
    if (isClosed) return;
    emit(state.copyWith(checking: true));
    var carries = true;
    try {
      carries = _carries(await _checkTransport());
    } catch (_) {
      // The platform channel can fail on some ROMs. Assume a transport and let
      // the probe be the judge — refusing to probe would strand the app offline.
    }
    if (isClosed) return;

    final reachable = await _probe();
    if (isClosed) return;

    if (reachable) {
      _retryTimer?.cancel();
      _retryTimer = null;
      emit(
        const ConnectivityState(
          reachability: Reachability.online,
          hasTransport: true,
          checking: false,
        ),
      );
      return;
    }
    _emitOffline(hasTransport: carries);
  }

  void _emitOffline({required bool hasTransport}) {
    if (isClosed) return;
    emit(
      ConnectivityState(
        reachability: Reachability.offline,
        hasTransport: hasTransport,
        checking: false,
      ),
    );
    _retryTimer ??= Timer.periodic(_retryInterval, (_) {
      if (state.isOffline) {
        recheck();
      } else {
        _retryTimer?.cancel();
        _retryTimer = null;
      }
    });
  }

  /// What real requests learned, which beats any probe: a request that came back
  /// proves the platform is reachable, and one that died in transport proves it
  /// is not. Called by [ApiClient] on every request.
  void markReachability(bool reachable) {
    if (isClosed) return;
    if (reachable) {
      if (state.isOnline) return;
      _retryTimer?.cancel();
      _retryTimer = null;
      emit(
        const ConnectivityState(
          reachability: Reachability.online,
          hasTransport: true,
        ),
      );
      return;
    }
    if (state.isOffline) return;
    _emitOffline(hasTransport: state.hasTransport);
  }

  /// Blocks until the platform answers. Used by the parts of the app that cannot
  /// be done from the device alone — signing in, above all — never by recording.
  Future<bool> waitUntilReachable({Duration? timeout}) async {
    if (!state.isOffline) return true;

    final completer = Completer<bool>();
    Timer? deadline;
    Timer? poll;
    StreamSubscription<ConnectivityState>? watch;

    void finish(bool value) {
      deadline?.cancel();
      poll?.cancel();
      watch?.cancel().ignore();
      if (!completer.isCompleted) completer.complete(value);
    }

    watch = stream.listen((next) {
      if (!next.isOffline) finish(true);
    });
    poll = Timer.periodic(const Duration(seconds: 3), (_) => recheck());
    if (timeout != null) deadline = Timer(timeout, () => finish(false));
    recheck();

    return completer.future;
  }

  @override
  Future<void> close() {
    _retryTimer?.cancel();
    _transportSubscription?.cancel();
    return super.close();
  }

  /// A TCP connect to the API host. Deliberately not an HTTP request: it needs no
  /// route to exist, no token, and it costs a collector on a metered line almost
  /// nothing.
  static Future<bool> _probeApiHost() async {
    Uri? uri;
    try {
      uri = Uri.tryParse(AppConfig.baseUrl);
    } catch (_) {
      // Development with no BASE_URL define. Nothing to probe.
      return false;
    }
    if (uri == null || uri.host.isEmpty) return false;
    final port = uri.hasPort ? uri.port : (uri.scheme == 'https' ? 443 : 80);
    try {
      final socket = await Socket.connect(
        uri.host,
        port,
        timeout: const Duration(seconds: 8),
      );
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }
}
