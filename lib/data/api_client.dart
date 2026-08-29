import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

import '../core/config.dart';
import 'session_store.dart';

/// A failure the screens can put in front of the collector.
///
/// [message] is the backend's own wording where it sent one. Those messages were
/// written for the person holding the phone — "this collection would take you past
/// the cash limit your cooperative set" — and rewording them here would only make
/// them vaguer.
class ApiException implements Exception {
  ApiException(this.message, {this.statusCode, this.offline = false});

  final String message;
  final int? statusCode;
  final bool offline;

  /// True when the request never reached the server. The outbox exists for exactly
  /// this case: a collection recorded here is kept and sent when there is signal.
  bool get isTransport => offline;

  @override
  String toString() => message;
}

/// The HTTP client. One dio instance, one refresh in flight at a time.
class ApiClient {
  ApiClient(
    this.session, {
    Dio? dio,
    Future<void> Function()? onSessionExpired,
    bool Function()? offlineCheck,
    void Function(bool reachable)? onReachability,
  }) : _onSessionExpired = onSessionExpired,
       _offlineCheck = offlineCheck,
       _onReachability = onReachability,
       _dio = dio ?? Dio() {
    _dio.options
      ..baseUrl = AppConfig.baseUrl
      ..connectTimeout = const Duration(seconds: 20)
      ..receiveTimeout = const Duration(seconds: 30)
      ..headers['Accept'] = 'application/json'
      ..validateStatus = (status) => status != null && status < 500;
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final token = session.accessToken;
          if ((token ?? '').isNotEmpty && options.extra['anonymous'] != true) {
            options.headers[HttpHeaders.authorizationHeader] = 'Bearer $token';
          }
          handler.next(options);
        },
      ),
    );
  }

  final SessionStore session;
  final Dio _dio;
  final Future<void> Function()? _onSessionExpired;

  /// Asked before every request so a known-dead network fails at once instead of
  /// after a 20-second connect timeout. It changes no outcome — the failure is the
  /// same transport failure, so the outbox still keeps the receipt and the cached
  /// reads still fall back — it only stops a collector watching a spinner for
  /// something the app already knows cannot work.
  final bool Function()? _offlineCheck;

  /// Told what each request learned. A reply proves the platform is reachable and a
  /// transport failure proves it is not, which is better evidence than any probe.
  final void Function(bool reachable)? _onReachability;

  /// Shared by every request that meets a 401 at the same moment, so a signal
  /// coming back after a long walk does not fire six refreshes at once.
  Future<bool>? _refreshing;

  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, dynamic>? query,
    bool anonymous = false,
  }) => _send(
    () => _dio.get(
      path,
      queryParameters: query,
      options: Options(extra: {'anonymous': anonymous}),
    ),
  );

  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? body,
    bool anonymous = false,
  }) => _send(
    () => _dio.post(
      path,
      data: body,
      options: Options(extra: {'anonymous': anonymous}),
    ),
  );

  Future<Map<String, dynamic>> _send(
    Future<Response<dynamic>> Function() call, {
    bool retried = false,
  }) async {
    if (_offlineCheck?.call() ?? false) {
      throw ApiException('No connection. Nothing was sent.', offline: true);
    }

    Response<dynamic> response;
    try {
      response = await call();
    } on DioException catch (e) {
      final failure = _transportFailure(e);
      if (failure.isTransport) _onReachability?.call(false);
      throw failure;
    }
    _onReachability?.call(true);

    final status = response.statusCode ?? 0;
    if (status == 401 && !retried) {
      final refreshed = await _ensureRefreshed();
      if (refreshed) return _send(call, retried: true);
      await _endSession();
      throw ApiException(
        'Your session has ended. Please sign in again.',
        statusCode: 401,
      );
    }
    if (status == 401) {
      await _endSession();
      throw ApiException(
        'Your session has ended. Please sign in again.',
        statusCode: 401,
      );
    }
    final data = response.data;
    final map = data is Map<String, dynamic> ? data : <String, dynamic>{};
    if (status >= 400) {
      throw ApiException(_messageFrom(map, status), statusCode: status);
    }
    return map;
  }

  /// Refreshes once, shared. Returns false when the refresh token is gone or
  /// refused, which is the only honest end for the session.
  Future<bool> _ensureRefreshed() {
    final inFlight = _refreshing;
    if (inFlight != null) return inFlight;
    final future = _refresh();
    _refreshing = future;
    return future.whenComplete(() => _refreshing = null);
  }

  Future<bool> _refresh() async {
    final token = session.refreshToken;
    if ((token ?? '').isEmpty) return false;
    try {
      // A bare client: the refresh must not recurse through the 401 handling above.
      final bare = Dio(
        BaseOptions(
          baseUrl: AppConfig.baseUrl,
          headers: const {'Accept': 'application/json'},
          validateStatus: (status) => status != null && status < 500,
        ),
      );
      final response = await bare.post(
        ApiPaths.refreshToken,
        data: {'refresh_token': token},
      );
      final data = response.data;
      if (response.statusCode != 200 || data is! Map<String, dynamic>) {
        return false;
      }
      final access = (data['token'] ?? '').toString();
      final next = (data['refresh_token'] ?? '').toString();
      if (access.isEmpty || next.isEmpty) return false;
      await session.saveTokens(access: access, refresh: next);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _endSession() async {
    await session.clear();
    await _onSessionExpired?.call();
  }

  ApiException _transportFailure(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return ApiException(
          'The network is too slow to finish that. Try again when you have signal.',
          offline: true,
        );
      case DioExceptionType.connectionError:
      case DioExceptionType.unknown:
        return ApiException('No connection. Nothing was sent.', offline: true);
      case DioExceptionType.badResponse:
        final data = e.response?.data;
        final map = data is Map<String, dynamic> ? data : <String, dynamic>{};
        return ApiException(
          _messageFrom(map, e.response?.statusCode ?? 0),
          statusCode: e.response?.statusCode,
        );
      default:
        return ApiException('Something went wrong. Please try again.');
    }
  }

  /// Both message shapes on the platform: Laravel's `{message, errors}` and the Go
  /// services' `{message}`. A validation error is more useful than the summary
  /// above it, so the first field error wins where there is one.
  String _messageFrom(Map<String, dynamic> map, int status) {
    final errors = map['errors'];
    if (errors is Map && errors.isNotEmpty) {
      final first = errors.values.first;
      if (first is List && first.isNotEmpty) return first.first.toString();
      if (first is String) return first;
    }
    final message = map['message'];
    if (message is String && message.trim().isNotEmpty) return message;
    if (status == 403) return 'You are not allowed to do that.';
    if (status == 404) return 'That could not be found.';
    return 'Something went wrong. Please try again.';
  }
}
