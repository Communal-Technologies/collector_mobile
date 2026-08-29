import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/config.dart';
import '../core/theme.dart';

/// What the app opens on.
///
/// It stays on screen for as long as the session is being worked out, and it also
/// doubles as the door: a collector who is signed out and has no connection cannot
/// get past it, because signing in is the one thing this app cannot do from the
/// device alone. Everything else — the roster, a receipt, the standing — is cached
/// or queued, so a *signed-in* collector never sees this screen for a connection.
class SplashScreen extends StatelessWidget {
  const SplashScreen({
    super.key,
    this.blocked = false,
    this.hasTransport = true,
    this.checking = false,
    this.onRetry,
  });

  /// Signed out with nothing to sign in through.
  final bool blocked;

  /// Whether the phone reports wifi or mobile data. Decides which of the two
  /// honest messages is shown: no signal at all, or signal that reaches nothing.
  final bool hasTransport;

  final bool checking;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: AppColors.primary,
        systemNavigationBarColor: AppColors.primary,
      ),
      child: Scaffold(
        backgroundColor: AppColors.primary,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              children: [
                const Spacer(),
                Container(
                  height: 76,
                  width: 76,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: const Icon(
                    Icons.account_balance_wallet_outlined,
                    color: AppColors.primary,
                    size: 38,
                  ),
                ),
                const SizedBox(height: 22),
                const Text(
                  AppConfig.appName,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Collections on the round, signal or not.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
                if (!AppConfig.isProduction) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      AppConfig.environment.toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                if (blocked)
                  _Blocked(
                    hasTransport: hasTransport,
                    checking: checking,
                    onRetry: onRetry,
                  )
                else
                  const _Loading(),
                const SizedBox(height: 36),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 3,
      width: 120,
      child: LinearProgressIndicator(
        backgroundColor: Colors.white24,
        color: Colors.white,
      ),
    );
  }
}

/// The hard stop. It says which of the two things is wrong, what the app is doing
/// about it, and — because the retry is automatic — it is a button a collector may
/// press rather than one they must.
class _Blocked extends StatelessWidget {
  const _Blocked({
    required this.hasTransport,
    required this.checking,
    this.onRetry,
  });

  final bool hasTransport;
  final bool checking;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              Icon(
                hasTransport ? Icons.cloud_off : Icons.signal_cellular_off,
                color: AppColors.primary,
                size: 30,
              ),
              const SizedBox(height: 12),
              Text(
                hasTransport
                    ? 'Cannot reach the cooperative'
                    : 'No network on this phone',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                hasTransport
                    ? 'You are connected to something, but it is not carrying us. '
                          'Signing in needs the cooperative to send your code, so it '
                          'has to wait. We keep trying.'
                    : 'Turn on mobile data or wifi. Signing in needs the cooperative '
                          'to send your code — once you are in, the app works without '
                          'signal.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  color: AppColors.muted,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: checking ? null : onRetry,
                  child: checking
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Try again'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          'Receipts you already wrote are safe on this phone.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ],
    );
  }
}
