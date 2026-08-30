import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'core/app_update.dart';
import 'core/config.dart';
import 'core/theme.dart';
import 'data/api_client.dart';
import 'data/outbox.dart';
import 'data/pin_lock.dart';
import 'data/repository.dart';
import 'data/session_store.dart';
import 'screens/home_shell.dart';
import 'screens/lock_screen.dart';
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
    _session = SessionCubit(
      store: _store,
      repository: _repository,
      auth: _auth,
      lock: PinLock(),
    );
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
        // The member app's design size, so a number written here means the same
        // fraction of the screen in both apps.
        child: ScreenUtilInit(
          designSize: const Size(430, 932),
          minTextAdapt: true,
          // The first frame on this hardware arrives with a zero-sized view, and
          // whatever is measured off it stays measured off it. Holding the frame
          // until the view has a size is cheap — the launch window is still up.
          ensureScreenSize: true,
          builder: (context, child) => MaterialApp(
            title: AppConfig.appName,
            debugShowCheckedModeBanner: false,
            theme: buildAppTheme(),
            home: const _Entry(),
          ),
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
/// Sign-in is the exception, because only Communal can send the code.
class _Entry extends StatefulWidget {
  const _Entry();

  @override
  State<_Entry> createState() => _EntryState();
}

class _EntryState extends State<_Entry> with WidgetsBindingObserver {
  /// The splash is held for a moment even when the session resolves instantly, so
  /// the app opens rather than flickering through a purple frame.
  static const _brandingHold = Duration(milliseconds: 1100);

  /// How long the app may sit in the background before the PIN is asked for again.
  ///
  /// A launch always asks — that is [SessionCubit.bootstrap]. This is the other
  /// half: closing the app is what locks it, and the phone cannot tell "closed" from
  /// "the collector opened the camera to photograph a receipt, or answered the SMS
  /// with the code in it". Locking on every glance elsewhere would make the app
  /// unusable on a round; never locking would leave a round's takings open on a
  /// phone in someone's pocket.
  static const _backgroundGrace = Duration(minutes: 3);

  bool _held = true;
  Timer? _holdTimer;
  DateTime? _leftAt;

  /// Once the sign-in form has been shown, losing signal must not snatch it away —
  /// a collector halfway through typing a phone number would lose it, and the form
  /// blocks its own submit anyway. The door is only closed on the way in.
  bool _loginShown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _holdTimer = Timer(_brandingHold, () {
      if (mounted) setState(() => _held = false);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _holdTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        // Not `inactive`: that also fires for the notification shade and for a
        // permission dialog, neither of which is leaving the app.
        _leftAt ??= DateTime.now();
      case AppLifecycleState.resumed:
        final left = _leftAt;
        _leftAt = null;
        if (left != null &&
            DateTime.now().difference(left) >= _backgroundGrace) {
          context.read<SessionCubit>().lockNow();
        }
      case AppLifecycleState.inactive:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionCubit>().state;
    final status = session.status;
    final network = context.watch<ConnectivityCubit>().state;

    if (_held || status == SessionStatus.unknown) {
      return const SplashScreen();
    }
    if (status == SessionStatus.signedIn) {
      // The token says which account this is. The PIN is what says the phone is in
      // the right hands, and it is asked for on every launch.
      return session.locked
          ? const LockScreen()
          : const AppUpdateWatcher(child: HomeShell());
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
