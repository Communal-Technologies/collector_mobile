import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'theme.dart';

/// What the last store check concluded, and therefore what the UI owes the user.
enum AppUpdateOutcome {
  /// Nothing to do: already current, the platform has no answer, or the build
  /// was not installed from a store so Play refuses to talk to us.
  none,

  /// Play is downloading the new version in the background. Nothing to show.
  downloading,

  /// The new version is on the device and applies on the next relaunch.
  readyToInstall,

  /// A newer version exists but we cannot install it ourselves — the user has
  /// to be sent to the store.
  storeUpdateAvailable,
}

/// Bridges the two stores' very different answers to "is there a newer build".
///
/// Android gets the real thing: Play's in-app updates API knows what is live on
/// the track this device installed from, downloads it in the background, and
/// applies it on relaunch. There is no silent path — Play always asks the user
/// once — so "auto update" here means one tap and no trip to the Play listing.
///
/// iOS has no equivalent API. The only public source is the iTunes lookup
/// endpoint, which reports the version on the storefront; acting on it means
/// opening the App Store page and letting the user press Update.
///
/// Every failure is swallowed. A debug build, a sideloaded APK, an app that is
/// not on the store yet and a flat network all raise here, and a collector
/// halfway through a round is the last person who should see any of it.
class AppUpdateService {
  const AppUpdateService._();

  /// Play's own priority scale is 0-5, carried on the release itself and only
  /// settable through the Play Developer API — the Console has no field for it. At
  /// or above this we stop asking and let Play take the screen, which is how a
  /// fix reaches a phone that keeps declining.
  static const int _forceFromPriority = 4;

  /// A device whose Play Store has known about the update for this long has had
  /// every chance to take it voluntarily.
  static const int _forceAfterStaleDays = 14;

  static const String _lastPromptAtKey = 'app_update_last_prompt_at';
  static const String _lastPromptVersionKey = 'app_update_last_prompt_version';
  static const Duration _promptInterval = Duration(hours: 24);

  static String? _storeUrl;

  /// The store listing for the newer build, once a check has found one.
  static String? get storeUrl => _storeUrl;

  /// Asks the store what is live and goes as far towards installing it as the
  /// platform allows.
  ///
  /// [userInitiated] skips the throttle and lets the caller report "you are up
  /// to date", which is only honest when the user asked the question.
  static Future<AppUpdateOutcome> check({bool userInitiated = false}) async {
    try {
      if (Platform.isAndroid) {
        return await _checkPlay(userInitiated: userInitiated);
      }
      if (Platform.isIOS) {
        return await _checkAppStore(userInitiated: userInitiated);
      }
    } catch (e) {
      debugPrint('AppUpdateService: store check skipped: $e');
    }
    return AppUpdateOutcome.none;
  }

  /// Applies a build already downloaded by the flexible flow. Play relaunches
  /// the app, so nothing after this call runs.
  static Future<void> installDownloaded() async {
    if (!Platform.isAndroid) return;
    try {
      await InAppUpdate.completeFlexibleUpdate();
    } catch (e) {
      debugPrint('AppUpdateService: completing the update failed: $e');
    }
  }

  /// Opens the store listing for whoever has to update by hand.
  static Future<bool> openStore() async {
    final url = _storeUrl;
    if (url == null) return false;
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('AppUpdateService: could not open the store: $e');
      return false;
    }
  }

  static Future<AppUpdateOutcome> _checkPlay({
    required bool userInitiated,
  }) async {
    final info = await InAppUpdate.checkForUpdate();

    if (info.updateAvailability ==
        UpdateAvailability.developerTriggeredUpdateInProgress) {
      return info.installStatus == InstallStatus.downloaded
          ? AppUpdateOutcome.readyToInstall
          : AppUpdateOutcome.downloading;
    }
    if (info.updateAvailability != UpdateAvailability.updateAvailable) {
      return AppUpdateOutcome.none;
    }

    _storeUrl =
        'https://play.google.com/store/apps/details?id=${info.packageName}';

    final stale = info.clientVersionStalenessDays ?? 0;
    final mandatory = info.updatePriority >= _forceFromPriority ||
        stale >= _forceAfterStaleDays;

    if (mandatory && info.immediateUpdateAllowed) {
      // Play owns the screen from here and relaunches the app itself, so a
      // userDeniedUpdate is the only branch that ever comes back.
      final result = await InAppUpdate.performImmediateUpdate();
      return result == AppUpdateResult.success
          ? AppUpdateOutcome.none
          : AppUpdateOutcome.storeUpdateAvailable;
    }

    final version = info.availableVersionCode?.toString();

    if (!info.flexibleUpdateAllowed) {
      return await _shouldPrompt(version, userInitiated: userInitiated)
          ? AppUpdateOutcome.storeUpdateAvailable
          : AppUpdateOutcome.none;
    }

    // Play shows its own consent sheet here, so this has to be throttled the
    // same way an in-app dialog would be.
    if (!await _shouldPrompt(version, userInitiated: userInitiated)) {
      return AppUpdateOutcome.none;
    }

    final started = await InAppUpdate.startFlexibleUpdate();
    if (started != AppUpdateResult.success) return AppUpdateOutcome.none;
    return AppUpdateOutcome.readyToInstall;
  }

  static Future<AppUpdateOutcome> _checkAppStore({
    required bool userInitiated,
  }) async {
    final packageInfo = await PackageInfo.fromPlatform();
    final bundleId = packageInfo.packageName;
    if (bundleId.isEmpty) return AppUpdateOutcome.none;

    final listing = await _lookUpAppStore(bundleId);
    if (listing == null) return AppUpdateOutcome.none;

    final storeVersion = listing['version'] as String?;
    if (storeVersion == null || storeVersion.isEmpty) {
      return AppUpdateOutcome.none;
    }
    if (!_isNewer(storeVersion, packageInfo.version)) {
      return AppUpdateOutcome.none;
    }

    _storeUrl = listing['trackViewUrl'] as String? ??
        'https://apps.apple.com/app/id${listing['trackId']}';

    return await _shouldPrompt(storeVersion, userInitiated: userInitiated)
        ? AppUpdateOutcome.storeUpdateAvailable
        : AppUpdateOutcome.none;
  }

  /// The storefront matters: a lookup without a country searches the US store,
  /// which answers with nothing for an app released only in Nigeria.
  static Future<Map<String, dynamic>?> _lookUpAppStore(String bundleId) async {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 8),
      responseType: ResponseType.json,
    ));

    for (final country in const ['ng', null]) {
      try {
        final response = await dio.get<dynamic>(
          'https://itunes.apple.com/lookup',
          queryParameters: {
            'bundleId': bundleId,
            'country': ?country,
          },
        );
        final body = response.data;
        final results = body is Map ? body['results'] : null;
        if (results is List && results.isNotEmpty && results.first is Map) {
          return Map<String, dynamic>.from(results.first as Map);
        }
      } catch (e) {
        debugPrint('AppUpdateService: App Store lookup failed: $e');
      }
    }
    return null;
  }

  /// Compares dot-separated numeric versions. A segment that is not a number
  /// makes the comparison unsafe, so we answer "not newer" and stay quiet
  /// rather than nag on a build tagged `1.0.0-rc1`.
  static bool _isNewer(String store, String installed) {
    final storeParts = store.split('.');
    final installedParts = installed.split('.');
    final length = storeParts.length > installedParts.length
        ? storeParts.length
        : installedParts.length;

    for (var i = 0; i < length; i++) {
      final left = i < storeParts.length ? int.tryParse(storeParts[i]) : 0;
      final right =
          i < installedParts.length ? int.tryParse(installedParts[i]) : 0;
      if (left == null || right == null) return false;
      if (left != right) return left > right;
    }
    return false;
  }

  /// True when the user has not already been asked about this version inside
  /// the throttle window. Recorded on the way out, so a "not now" is honoured
  /// on the next resume instead of being asked again immediately.
  static Future<bool> _shouldPrompt(
    String? version, {
    required bool userInitiated,
  }) async {
    if (userInitiated) return true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final lastVersion = prefs.getString(_lastPromptVersionKey);
      final lastAt = prefs.getInt(_lastPromptAtKey);

      if (version != null && lastVersion == version && lastAt != null) {
        final since = DateTime.now().millisecondsSinceEpoch - lastAt;
        if (since < _promptInterval.inMilliseconds) return false;
      }

      await prefs.setInt(
        _lastPromptAtKey,
        DateTime.now().millisecondsSinceEpoch,
      );
      if (version != null) {
        await prefs.setString(_lastPromptVersionKey, version);
      }
    } catch (e) {
      debugPrint('AppUpdateService: throttle unavailable: $e');
    }
    return true;
  }
}

/// Runs the store check once the round is on screen, and again on resume.
///
/// Wrapped around [HomeShell] rather than the whole app on purpose: the splash,
/// the sign-in form and the PIN screen are all places where Play's consent
/// sheet would land on top of something the collector is in the middle of.
class AppUpdateWatcher extends StatefulWidget {
  const AppUpdateWatcher({super.key, required this.child});

  final Widget child;

  @override
  State<AppUpdateWatcher> createState() => _AppUpdateWatcherState();
}

class _AppUpdateWatcherState extends State<AppUpdateWatcher>
    with WidgetsBindingObserver {
  /// The roster and the standing are still loading when the shell mounts; the
  /// store can wait until that has settled.
  static const Duration _startupDelay = Duration(seconds: 4);
  static const Duration _resumeCooldown = Duration(minutes: 30);

  DateTime? _lastCheck;
  bool _running = false;
  bool _noticeShowing = false;
  Timer? _startupTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startupTimer = Timer(_startupDelay, _check);
  }

  @override
  void dispose() {
    _startupTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final last = _lastCheck;
    if (last != null && DateTime.now().difference(last) < _resumeCooldown) {
      return;
    }
    _check();
  }

  Future<void> _check() async {
    if (_running || _noticeShowing) return;
    _running = true;
    _lastCheck = DateTime.now();
    try {
      final outcome = await AppUpdateService.check();
      if (!mounted) return;
      switch (outcome) {
        case AppUpdateOutcome.readyToInstall:
          _showRelaunchPrompt();
        case AppUpdateOutcome.storeUpdateAvailable:
          await _showStorePrompt();
        case AppUpdateOutcome.downloading:
        case AppUpdateOutcome.none:
          break;
      }
    } finally {
      _running = false;
    }
  }

  void _showRelaunchPrompt() {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.showSnackBar(
      SnackBar(
        content: const Text(
          'A new version of Collector is ready. Relaunch to finish updating.',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: AppColors.primary,
        duration: const Duration(seconds: 12),
        action: SnackBarAction(
          label: 'Relaunch',
          textColor: Colors.white,
          onPressed: AppUpdateService.installDownloaded,
        ),
      ),
    );
  }

  Future<void> _showStorePrompt() async {
    _noticeShowing = true;
    try {
      final update = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Update available'),
          content: const Text(
            'A newer version of Collector is on the store. Updating keeps '
            'receipts and remittances working with the platform.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Not now'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(foregroundColor: AppColors.primary),
              child: const Text('Update'),
            ),
          ],
        ),
      );
      if (update == true) await AppUpdateService.openStore();
    } finally {
      _noticeShowing = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
