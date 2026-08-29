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
                const _LogoCircle(),
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

/// The member app's splash mark, at the member app's proportions: its circle is
/// 200 of a 430-wide design and the mark inside is 140 of it, so both are taken
/// off the real width rather than pinned to a number that only suits one phone.
class _LogoCircle extends StatelessWidget {
  const _LogoCircle();

  @override
  Widget build(BuildContext context) {
    final diameter = (MediaQuery.sizeOf(context).width * 200 / 430).clamp(
      140.0,
      220.0,
    );

    return Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Center(
        child: Image.asset(
          'assets/images/icon-02.png',
          width: diameter * 0.7,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}

/// The member app's loader, actually moving.
///
/// There it is a static bar whose gradient stop is animated, which only slides a
/// colour boundary — so the same three colours are used here, on a segment that
/// travels the track. A repeating controller read straight would jump at the seam;
/// folding it into a triangle wave sends the segment out and back instead.
class _Loading extends StatefulWidget {
  const _Loading();

  @override
  State<_Loading> createState() => _LoadingState();
}

class _LoadingState extends State<_Loading>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 120,
      height: 4,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white24,
          borderRadius: BorderRadius.circular(2),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final t = _controller.value <= 0.5
                  ? _controller.value * 2
                  : (1 - _controller.value) * 2;
              return Align(
                alignment: Alignment(Curves.easeInOut.transform(t) * 2 - 1, 0),
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(2),
                    gradient: const LinearGradient(
                      colors: [
                        Color(0xFF00D9FF),
                        Color(0xFF00A8E8),
                        Color(0xFFFFC107),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
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
