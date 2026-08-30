import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:iconsax/iconsax.dart';

import '../core/config.dart';
import '../core/theme.dart';

/// The ground this screen is painted on, and the same value as the launch window's
/// `launch_ground` in `res/values/colors.xml`. It has to be the same: Android paints that
/// window before any Dart runs, so a different colour here is a flash on every cold
/// start — which is exactly what the purple version of this screen did.
const splashGround = Color(0xFF000000);

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
        statusBarColor: splashGround,
        systemNavigationBarColor: splashGround,
      ),
      child: Scaffold(
        backgroundColor: splashGround,
        body: Stack(
          children: [
            const SplashGlows(),
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SplashMark(),
                  SizedBox(height: 40.h),
                  Text(
                    AppConfig.appName,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 34.sp,
                      height: 1.15,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                  SizedBox(height: 12.h),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 40.w),
                    child: Text(
                      'Collections on the round, signal or not',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 15.sp,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                  if (!AppConfig.isProduction) ...[
                    SizedBox(height: 14.h),
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 10.w,
                        vertical: 4.h,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        AppConfig.environment.toUpperCase(),
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10.sp,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                  ],
                  SizedBox(height: 40.h),
                  const SplashLoader(),
                ],
              ),
            ),
            if (blocked)
              Positioned.fill(
                child: SplashBlocked(
                  hasTransport: hasTransport,
                  checking: checking,
                  onRetry: onRetry,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The mark, drawn the way the launch window draws it: white, straight onto the black,
/// with no plate behind it.
///
/// It used to be the purple mark inside a 200 white circle, which was right when this
/// screen was purple and wrong the moment the ground went black — the launch window
/// Android paints already shows a bare white mark, so the plate appeared out of nowhere
/// on the first Dart frame. The mark keeps its own size; only the plate is gone.
///
/// Public, like the other sized pieces of this screen, because ScreenUtilInit skips
/// any widget whose type name begins with an underscore when it re-marks the tree
/// after the real screen size arrives — a private one keeps whatever it measured on
/// the first frame, which on this device is nothing at all.
class SplashMark extends StatelessWidget {
  const SplashMark({super.key});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/mark_white.png',
      width: 150.w,
      fit: BoxFit.contain,
    );
  }
}

/// The member app's three colour washes behind the mark, at its positions. Its
/// own version blurs them with a BackdropFilter; that layer took the mark and the
/// loader off this device's screen entirely, so the softness comes from the
/// gradient stops instead.
///
/// The alphas are a little higher than the member app's because black absorbs a wash
/// that purple carried.
class SplashGlows extends StatelessWidget {
  const SplashGlows({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 400.w,
        height: 650.h,
        child: Stack(
          children: [
            Positioned(
              top: 20.h,
              right: 10.w,
              child: SplashGlow(
                size: 200.w,
                inner: Colors.orange.withValues(alpha: 0.34),
                outer: Colors.orange.withValues(alpha: 0.18),
              ),
            ),
            Positioned(
              top: 180.h,
              left: 0,
              child: SplashGlow(
                size: 180.w,
                inner: const Color(0xFFE0B0FF).withValues(alpha: 0.34),
                outer: const Color(0xFFB09FFF).withValues(alpha: 0.18),
              ),
            ),
            Positioned(
              bottom: 50.h,
              right: 20.w,
              child: SplashGlow(
                size: 190.w,
                inner: Colors.cyan.withValues(alpha: 0.34),
                outer: Colors.blue.withValues(alpha: 0.18),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SplashGlow extends StatelessWidget {
  const SplashGlow({
    super.key,
    required this.size,
    required this.inner,
    required this.outer,
  });

  final double size;
  final Color inner;
  final Color outer;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [inner, outer, Colors.transparent],
          stops: const [0.0, 0.45, 1.0],
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
class SplashLoader extends StatefulWidget {
  const SplashLoader({super.key});

  @override
  State<SplashLoader> createState() => _SplashLoaderState();
}

class _SplashLoaderState extends State<SplashLoader>
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
      width: 120.w,
      height: 4.h,
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
                  width: 44.w,
                  height: 4.h,
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
/// press rather than one they must. It covers the splash the way the member app's
/// does, centred, rather than sitting under it.
class SplashBlocked extends StatelessWidget {
  const SplashBlocked({
    super.key,
    required this.hasTransport,
    required this.checking,
    this.onRetry,
  });

  final bool hasTransport;
  final bool checking;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: splashGround.withValues(alpha: 0.97),
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 28.w),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(18.w),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    Icon(
                      hasTransport
                          ? Iconsax.cloud_cross
                          : Iconsax.wifi_square,
                      color: AppColors.primary,
                      size: 30.sp,
                    ),
                    SizedBox(height: 12.h),
                    Text(
                      hasTransport
                          ? 'Cannot reach Communal'
                          : 'No network on this phone',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16.sp,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                      ),
                    ),
                    SizedBox(height: 8.h),
                    Text(
                      hasTransport
                          ? 'You are connected to something, but it is not carrying us. '
                                'Signing in needs your code sent and checked, so it has to '
                                'wait. We keep trying.'
                          : 'Turn on mobile data or wifi. Signing in needs your code sent '
                                'and checked — once you are in, the app works without '
                                'signal.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13.sp,
                        height: 1.45,
                        color: AppColors.muted,
                      ),
                    ),
                    SizedBox(height: 16.h),
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
              SizedBox(height: 14.h),
              Text(
                'Receipts you already wrote are safe on this phone.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 12.sp),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
