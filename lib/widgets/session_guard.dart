import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../state/outbox_cubit.dart';
import '../state/session_cubit.dart';

/// When the PIN is asked for again.
///
/// The member app locks on four things and this app has to lock on the same four,
/// because it is the same PIN on the same account and this one is carrying a
/// cooperative's cash. A launch is [SessionCubit.bootstrap]'s doing. The other
/// three are here: leaving the app, the process detaching, and the phone being sat
/// in front of untouched — asked about at three minutes, locked at five.
///
/// Deliberately not `inactive`: that also fires for the notification shade and for
/// a permission dialog, neither of which is leaving the app.
class SessionGuard extends StatefulWidget {
  const SessionGuard({super.key, required this.child});

  final Widget child;

  @override
  State<SessionGuard> createState() => _SessionGuardState();
}

class _SessionGuardState extends State<SessionGuard>
    with WidgetsBindingObserver {
  /// The prompt is a route, so it has to be taken down when the state that raised
  /// it goes away — including by the lock it was warning about.
  bool _promptOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        context.read<SessionCubit>().lockNow();
      case AppLifecycleState.resumed:
        // A collector puts the phone in their pocket between doors, so coming back
        // is the likeliest moment for signal to have returned. Both of these are
        // owed to the cooperative whether or not the PIN has been typed yet, which
        // is why they live above the lock rather than inside the round.
        context.read<OutboxCubit>().flush();
        context.read<SessionCubit>().refreshGrants();
      case AppLifecycleState.inactive:
        break;
    }
  }

  void _onIdlePromptChanged(SessionState session) {
    if (session.idlePrompt && !_promptOpen) {
      _showIdlePrompt();
    } else if (!session.idlePrompt && _promptOpen) {
      _promptOpen = false;
      Navigator.of(context).pop();
    }
  }

  Future<void> _showIdlePrompt() async {
    _promptOpen = true;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Are you still there?'),
        content: const Text(
          'This has been sitting untouched for a while. Stay to carry on with the '
          'round, or lock it now and open it again with your PIN.',
        ),
        actions: [
          TextButton(
            onPressed: () => context.read<SessionCubit>().lockNow(),
            child: const Text('Lock now'),
          ),
          FilledButton(
            onPressed: () => context.read<SessionCubit>().dismissIdlePrompt(),
            child: const Text('Stay'),
          ),
        ],
      ),
    );
    _promptOpen = false;
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<SessionCubit, SessionState>(
      listenWhen: (before, after) => before.idlePrompt != after.idlePrompt,
      listener: (context, session) => _onIdlePromptChanged(session),
      child: widget.child,
    );
  }
}
