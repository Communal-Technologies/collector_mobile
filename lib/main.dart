import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'core/config.dart';
import 'core/theme.dart';
import 'data/api_client.dart';
import 'data/outbox.dart';
import 'data/repository.dart';
import 'data/session_store.dart';
import 'screens/home_shell.dart';
import 'screens/login_screen.dart';
import 'state/outbox_cubit.dart';
import 'state/session_cubit.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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

  @override
  void initState() {
    super.initState();
    _store = SessionStore();
    // The client can end the session on its own — a refused refresh is the end of
    // it — so it needs a way back to the cubit that owns that state.
    _api = ApiClient(_store, onSessionExpired: () async {
      await _session.signOut(notice: 'Your session ended. Please sign in again.');
    });
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

/// What the app opens on, decided by the session and nothing else.
class _Entry extends StatelessWidget {
  const _Entry();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SessionCubit, SessionState>(
      buildWhen: (a, b) => a.status != b.status,
      builder: (context, state) {
        switch (state.status) {
          case SessionStatus.unknown:
            return const _Splash();
          case SessionStatus.signedOut:
            return const LoginScreen();
          case SessionStatus.signedIn:
            return const HomeShell();
        }
      },
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.primary,
      body: Center(
        child: CircularProgressIndicator(color: Colors.white),
      ),
    );
  }
}
