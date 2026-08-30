/// Build-time configuration.
///
/// Same contract as the member app: values arrive through `--dart-define`, never
/// from a bundled asset, and `BASE_URL` is only consulted in development.
///
///     flutter run --dart-define-from-file=tool/dart_defines.json
///
/// The development URL has to be reachable *from the handset*, so it is the
/// zrok share that fronts the local gateway — the same one the member app uses.
/// Neither 127.0.0.1 (which needs an `adb reverse` tunnel that dies with every adb
/// disconnect) nor this machine's LAN address (which roams) survives a day of use.
class AppConfig {
  AppConfig._();

  static const String appName = 'Communal Collector';

  /// Backend issues 6-digit codes, and the PIN is the same 6 digits.
  static const int otpLength = 6;
  static const int pinLength = 6;

  /// Sent with the PIN reset calls so the surface is on the record. Every value
  /// except `admin_app` resolves the same member account, which is the one a
  /// collector has — Communal's own staff are the exception and are not collectors.
  static const String platform = 'collector_app';

  static const String stagingApiBaseUrl = 'https://api-staging.communalhq.com';
  static const String productionApiBaseUrl = 'https://api.communalhq.com';

  static const String _baseUrlDefine = String.fromEnvironment('BASE_URL');
  static const String _appEnvDefine =
      String.fromEnvironment('APP_ENV', defaultValue: 'development');

  static String get environment {
    final raw = _appEnvDefine.trim();
    return raw.isEmpty ? 'development' : raw.toLowerCase();
  }

  static bool get isProduction =>
      environment == 'production' || environment == 'prod';

  /// Resolved API origin — scheme and host only. Every path in [ApiPaths] carries
  /// its own service prefix, so the origin must not embed one.
  static String get baseUrl {
    switch (environment) {
      case 'development':
      case 'dev':
        final url = _strip(_baseUrlDefine.trim());
        if (url.isEmpty) {
          throw StateError(
            'BASE_URL must be passed via --dart-define when APP_ENV is development.',
          );
        }
        return url;
      case 'staging':
        return stagingApiBaseUrl;
      case 'production':
      case 'prod':
        return productionApiBaseUrl;
      default:
        throw StateError(
          'Unknown APP_ENV "$_appEnvDefine". Use development, staging or production.',
        );
    }
  }

  static String _strip(String value) {
    if (value.length >= 2) {
      final first = value[0];
      final last = value[value.length - 1];
      if ((first == "'" && last == "'") || (first == '"' && last == '"')) {
        return value.substring(1, value.length - 1);
      }
    }
    return value;
  }
}

/// Every route this app calls, with its service prefix.
///
/// A collector reaches three services and nothing else: authsvc to sign in,
/// obligations-svc for the round, cooperative-svc for the cash accounts and
/// remittance. Every other route on those services is closed to a collector
/// token, which is deliberate — a collector holds no dashboard permission.
class ApiPaths {
  ApiPaths._();

  static const String loginRequest = '/api/v1/collector/login-request';
  static const String loginResend = '/api/v1/collector/login-resend';
  static const String loginVerify = '/api/v1/collector/login-verify';
  static const String unlock = '/api/v1/collector/unlock';
  static const String refreshToken = '/api/v1/refresh-token';

  /// The PIN reset is the member app's own three calls, not a collector copy of
  /// them: it is one PIN on one account, so resetting it here resets it there.
  static const String pinResetRequest = '/api/v1/generate-password-reset-link';
  static const String pinResetVerify = '/api/v1/verify-password-reset-pin';
  static const String pinResetSet = '/api/v1/reset-password';

  static const String _obl = '/api/obligations/v2/collector';
  static const String collections = '$_obl/collections';
  static const String standing = '$_obl/standing';
  static const String earnings = '$_obl/earnings';
  static const String members = '$_obl/members';
  static String memberObligations(String ledgerNumber) =>
      '$_obl/members/$ledgerNumber/obligations';

  /// Only the fines raised against the member directly. The ones a missed cycle
  /// earned already ride inside their own obligation.
  static String memberFines(String ledgerNumber) =>
      '$_obl/members/$ledgerNumber/fines';

  static const String _coop = '/api/cooperative/v2/collector';
  static const String myCollectorAccounts = '$_coop/accounts';
  static const String remittanceAccounts = '$_coop/remittance-accounts';
  static const String remittances = '$_coop/remittances';
}
