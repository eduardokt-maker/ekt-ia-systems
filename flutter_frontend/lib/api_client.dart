import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

const Duration apiTimeout = Duration(seconds: 30);

class ApiFailure implements Exception {
  const ApiFailure(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient._();

  static final ApiClient instance = ApiClient._();

  final http.Client _http = http.Client();
  String _accessToken = '';
  String _refreshToken = '';
  Uri Function(String path)? _uriBuilder;
  Future<bool>? _refreshInProgress;
  Timer? _refreshTimer;
  void Function()? onSessionExpired;

  bool get isAuthenticated =>
      _accessToken.isNotEmpty && _refreshToken.isNotEmpty;

  void startSession({
    required String accessToken,
    required String refreshToken,
    required Uri Function(String path) uriBuilder,
  }) {
    _accessToken = accessToken;
    _refreshToken = refreshToken;
    _uriBuilder = uriBuilder;
    _scheduleRefresh();
  }

  void clearSession() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _accessToken = '';
    _refreshToken = '';
  }

  Future<http.Response> get(Uri uri, {Map<String, String>? headers}) =>
      _request('GET', uri, headers: headers);

  Future<http.Response> post(Uri uri,
          {Map<String, String>? headers,
          Object? body,
          bool authenticated = true}) =>
      _request('POST', uri,
          headers: headers, body: body, authenticated: authenticated);

  Future<http.Response> put(Uri uri,
          {Map<String, String>? headers, Object? body}) =>
      _request('PUT', uri, headers: headers, body: body);

  Future<http.Response> patch(Uri uri,
          {Map<String, String>? headers, Object? body}) =>
      _request('PATCH', uri, headers: headers, body: body);

  Future<http.Response> delete(Uri uri,
          {Map<String, String>? headers, Object? body}) =>
      _request('DELETE', uri, headers: headers, body: body);

  Future<http.Response> _request(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    bool authenticated = true,
    bool retryAfterRefresh = true,
  }) async {
    if (authenticated && _accessToken.isNotEmpty) {
      await _refreshIfExpiring();
    }
    final request = http.Request(method, uri)
      ..headers.addAll(headers ?? const <String, String>{});
    if (authenticated && _accessToken.isNotEmpty) {
      request.headers['authorization'] = 'Bearer $_accessToken';
    }
    if (body != null) {
      request.body = body is String ? body : jsonEncode(body);
    }

    try {
      final response = await (() async {
        final streamed = await _http.send(request);
        return http.Response.fromStream(streamed);
      })()
          .timeout(apiTimeout);
      if (authenticated &&
          response.statusCode == 401 &&
          retryAfterRefresh &&
          await _refresh()) {
        return _request(method, uri,
            headers: headers,
            body: body,
            authenticated: true,
            retryAfterRefresh: false);
      }
      if (authenticated && response.statusCode == 401) {
        _expireSession();
      }
      if (response.statusCode == 403) {
        throw const ApiFailure(
            'Voce nao tem permissao para realizar esta acao.',
            statusCode: 403);
      }
      if (response.statusCode == 408) {
        throw const ApiFailure('Tempo de resposta excedido. Tente novamente.',
            statusCode: 408);
      }
      if (<int>{500, 502, 503, 504}.contains(response.statusCode)) {
        throw ApiFailure(
            response.statusCode == 500
                ? 'Ocorreu um erro no servidor. Tente novamente.'
                : 'Servidor indisponivel. Tente novamente em instantes.',
            statusCode: response.statusCode);
      }
      return response;
    } on TimeoutException {
      throw const ApiFailure('Tempo de resposta excedido. Tente novamente.');
    } on http.ClientException {
      throw const ApiFailure(
          'Erro de conexao. Verifique sua internet e tente novamente.');
    }
  }

  Future<void> _refreshIfExpiring() async {
    final expiry = _tokenExpiry(_accessToken);
    if (expiry == null ||
        expiry.difference(DateTime.now()) <= const Duration(minutes: 2)) {
      await _refresh();
    }
  }

  Future<bool> _refresh() {
    final active = _refreshInProgress;
    if (active != null) return active;
    final future = _performRefresh();
    _refreshInProgress = future;
    return future.whenComplete(() => _refreshInProgress = null);
  }

  Future<bool> _performRefresh() async {
    final builder = _uriBuilder;
    if (builder == null || _refreshToken.isEmpty) return false;
    try {
      final response = await post(
        builder('/api/investments/refresh'),
        headers: const {'content-type': 'application/json; charset=utf-8'},
        body: jsonEncode(<String, String>{'refresh_token': _refreshToken}),
        authenticated: false,
      );
      if (response.statusCode != 200) {
        _expireSession();
        return false;
      }
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      _accessToken = body['session_token'] as String? ?? '';
      _refreshToken = body['refresh_token'] as String? ?? '';
      if (!isAuthenticated) {
        _expireSession();
        return false;
      }
      _scheduleRefresh();
      return true;
    } catch (_) {
      // A transient network failure must not log the user out. The next request
      // gets its own bounded attempt and presents the connection error.
      return false;
    }
  }

  void _scheduleRefresh() {
    _refreshTimer?.cancel();
    final expiry = _tokenExpiry(_accessToken);
    if (expiry == null) return;
    final delay =
        expiry.subtract(const Duration(minutes: 2)).difference(DateTime.now());
    _refreshTimer = Timer(delay.isNegative ? Duration.zero : delay, _refresh);
  }

  DateTime? _tokenExpiry(String token) {
    try {
      final encoded = token.split('.').first;
      final normalized = base64Url.normalize(encoded);
      final payload = jsonDecode(utf8.decode(base64Url.decode(normalized)))
          as Map<String, dynamic>;
      return DateTime.fromMillisecondsSinceEpoch(
          (payload['exp'] as num).toInt() * 1000);
    } catch (_) {
      return null;
    }
  }

  void _expireSession() {
    if (!isAuthenticated) return;
    clearSession();
    onSessionExpired?.call();
  }
}

final ApiClient apiClient = ApiClient.instance;
