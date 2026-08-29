import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'core/config.dart';
import 'core/theme.dart';
import 'data/api_client.dart';
import 'data/outbox.dart';
import 'data/repository.dart';
import 'data/session_store.dart';
import 'screens/home_shell.dart';
import 'screens/login_screen.dart';
import 'screens/splash_screen.dart';
import 'state/connectivity_cubit.dart';
import 'state/outbox_cubit.dart';
import 'state/session_cubit.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
  runApp(const CollectorApp());
}

class CollectorApp extends StatefulWidget {
  const CollectorApp({super.key});

  @override
  State<CollectorApp> createState() => _CollectorAppState();
}

class _CollectorAppState extends State<CollectorApp> {
  late final SessionStore _store;
  late final ApiClient _api;
  late final AuthRepository _auth;
  late final CollectorRepository _repository;
  late final SessionCubit _session;
  late final OutboxCubit _outbox;
  late final ConnectivityCubit _connectivity;

  @override
  void initState() {
    super.initState();
    _store = SessionStore();
    _connectivity = ConnectivityCubit();
    // The client can end the session on its own — a refused refresh is the end of
    // it — so it needs a way back to the cubit that owns that state.
    _api = ApiClient(
      _store,
      onSessionExpired: () async {
        await _session.signOut(
          notice: 'Your session ended. Please sign in again.',
        );
      },
      offlineCheck: () => _connectivity.state.isOffline,
      onReachability: _connectivity.markReachability,
    );
    _auth = AuthRepository(_api);
    _repository = CollectorRepository(_api);
    _session = SessionCubit(store: _store, repository: _repository);
    _outbox = OutboxCubit(outbox: Outbox(), repository: _repository);
    _session.bootstrap();
    _outbox.load();
  }

  @override
  void dispose() {
    _session.close();
    _outbox.close();
    _connectivity.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider.value(value: _auth),
        RepositoryProvider.value(value: _repository),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider.value(value: _session),
          BlocProvider.value(value: _outbox),
          BlocProvider.value(value: _connectivity),
        ],
        child: MaterialApp(
          title: AppConfig.appName,
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(),
          home: const _Entry(),
        ),
      ),
    );
  }
}

/// What the app opens on, decided by the session and — for a signed-out collector
/// only — by whether the platform can be reached.
///
/// A signed-in collector goes straight to the round no matter what the network is
/// doing. That is the whole point of the app: the roster and the standing are
/// cached, a receipt is written to the phone first, and blocking the door would
/// leave somebody standing in front of a collector who cannot write their receipt.
/// Sign-in is the exception, because only the cooperative can send the code.
class _Entry extends StatefulWidget {
  const _Entry();

  @override
  State<_Entry> createState() => _EntryState();
}

class _EntryState extends State<_Entry> {
  /// The splash is held for a moment even when the session resolves instantly, so
  /// the app opens rather than flickering through a purple frame.
  static const _brandingHold = Duration(milliseconds: 1100);

  bool _held = true;
  Timer? _holdTimer;

  /// Once the sign-in form has been shown, losing signal must not snatch it away —
  /// a collector halfway through typing a phone number would lose it, and the form
  /// blocks its own submit anyway. The door is only closed on the way in.
  bool _loginShown = false;

  @override
  void initState() {
    super.initState();
    _holdTimer = Timer(_brandingHold, () {
      if (mounted) setState(() => _held = false);
    });
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = context.select((SessionCubit c) => c.state.status);
    final network = context.watch<ConnectivityCubit>().state;

    if (_held || status == SessionStatus.unknown) {
      return const SplashScreen();
    }
    if (status == SessionStatus.signedIn) {
      return const HomeShell();
    }
    if (network.isOffline && !_loginShown) {
      return SplashScreen(
        blocked: true,
        hasTransport: network.hasTransport,
        checking: network.checking,
        onRetry: () => context.read<ConnectivityCubit>().recheck(),
      );
    }
    _loginShown = true;
    return const LoginScreen();
  }
}
