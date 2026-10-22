import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

class ApiException implements Exception {
  const ApiException(this.status, this.message);
  final int? status;
  final String message;
  @override
  String toString() => message;
}

/// How the app talks to a controller (tests use an in-memory one).
abstract class Backend {
  /// Controller clock minus device clock, from `X-Rigdeck-Time`: freshness is judged on the
  /// controller's clock, as in the web console.
  int get serverOffsetMs;

  /// Raw response body; JSON decoding of large bodies happens off the UI isolate.
  Future<String> raw(String method, String path, {Map<String, String>? query, Object? body});

  void close() {}
}

extension BackendJson on Backend {
  int get nowMs => DateTime.now().millisecondsSinceEpoch + serverOffsetMs;
  Future<dynamic> getJson(String path, {Map<String, String>? query}) async =>
      jsonDecode(await raw('GET', path, query: query));
  Future<dynamic> send(String method, String path, [Object? body]) async {
    final text = await raw(method, path, body: body);
    return text.isEmpty ? null : jsonDecode(text);
  }
}

/// Saved login: a session (cookie + CSRF token, 12 h) or a revocable API token.
class Credentials {
  const Credentials({required this.server, required this.user, this.token, this.cookie, this.csrf});
  final String server;
  final String user;
  final String? token;
  final String? cookie;
  final String? csrf;

  Map<String, dynamic> toJson() =>
      {'server': server, 'user': user, 'token': token, 'cookie': cookie, 'csrf': csrf};
  static Credentials? fromJson(Map<String, dynamic> j) {
    final server = j['server'];
    if (server is! String || server.isEmpty) return null;
    return Credentials(
      server: server,
      user: (j['user'] as String?) ?? '',
      token: j['token'] as String?,
      cookie: j['cookie'] as String?,
      csrf: j['csrf'] as String?,
    );
  }
}

/// The controller address as typed, made usable: Chinese keyboards in full-width mode turn
/// `http://10.0.0.1:8080` into `ＨＴＴＰ：／／10。0。0。1：8080`, which no URL parser accepts.
String normalizeServer(String input) {
  final half = StringBuffer();
  for (final c in input.trim().runes) {
    if (c >= 0xFF01 && c <= 0xFF5E) {
      half.writeCharCode(c - 0xFEE0); // full-width ASCII block
    } else if (c == 0x3002) {
      half.write('.'); // ideographic full stop 。
    } else if (c == 0x3000) {
      half.write(' ');
    } else {
      half.writeCharCode(c);
    }
  }
  var s = half.toString().replaceAll(' ', '');
  final scheme = RegExp(r'^[a-zA-Z]+://').firstMatch(s);
  if (scheme == null) {
    s = 'https://$s';
  } else {
    s = s.substring(0, scheme.end).toLowerCase() + s.substring(scheme.end);
  }
  while (s.endsWith('/')) {
    s = s.substring(0, s.length - 1);
  }
  final uri = Uri.tryParse(s);
  if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https') || uri.host.isEmpty) {
    throw ApiException(null, '主控地址格式不对，例如 http://192.168.1.10:8080');
  }
  return s;
}

Uri _uri(String server, String path, Map<String, String>? query) {
  final base = Uri.parse(server);
  return base.replace(
    path: '${base.path}$path',
    queryParameters: (query == null || query.isEmpty) ? null : query,
  );
}

String _errorText(http.Response res) {
  try {
    final body = jsonDecode(utf8.decode(res.bodyBytes));
    if (body is Map && body['error'] is String) return body['error'] as String;
  } catch (_) {
    // Gateways answer with HTML; the status code is all there is.
  }
  return 'HTTP ${res.statusCode}';
}

const _timeout = Duration(seconds: 20);

class HttpBackend extends Backend {
  HttpBackend(this.credentials, {this.onUnauthorized});
  final Credentials credentials;
  final void Function()? onUnauthorized;
  final http.Client _client = http.Client();
  int _offset = 0;

  @override
  int get serverOffsetMs => _offset;

  static Future<Credentials> login(String server, String user, String password) async {
    final http.Response res;
    try {
      res = await http
          .post(
            _uri(server, '/api/v1/login', null),
            headers: {'content-type': 'application/json'},
            body: jsonEncode({'username': user, 'password': password}),
          )
          .timeout(_timeout);
    } on TimeoutException {
      throw const ApiException(null, '连接主控超时');
    } on Exception catch (e) {
      throw ApiException(null, '无法连接主控：$e');
    }
    if (res.statusCode != 200) throw ApiException(res.statusCode, _errorText(res));
    final cookie = RegExp(r'rigdeck_session=([^;,\s]+)').firstMatch(res.headers['set-cookie'] ?? '');
    final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    if (cookie == null) throw const ApiException(null, '主控没有返回会话');
    return Credentials(
      server: server,
      user: ((body['actor'] as Map?)?['name'] as String?) ?? user,
      cookie: cookie.group(1),
      csrf: body['csrf'] as String?,
    );
  }

  static Future<Credentials> withToken(String server, String token) async {
    final probe = HttpBackend(Credentials(server: server, user: '', token: token));
    try {
      final me = await probe.getJson('/api/v1/me') as Map<String, dynamic>;
      return Credentials(
        server: server,
        user: ((me['actor'] as Map?)?['name'] as String?) ?? '令牌',
        token: token,
      );
    } finally {
      probe.close();
    }
  }

  @override
  Future<String> raw(String method, String path, {Map<String, String>? query, Object? body}) async {
    final request = http.Request(method, _uri(credentials.server, path, query));
    final token = credentials.token;
    if (token != null) {
      request.headers['authorization'] = 'Bearer $token';
    } else {
      if (credentials.cookie != null) request.headers['cookie'] = 'rigdeck_session=${credentials.cookie}';
      if (method != 'GET' && credentials.csrf != null) request.headers['x-csrf-token'] = credentials.csrf!;
    }
    if (body != null) {
      request.headers['content-type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    final http.Response res;
    try {
      res = await http.Response.fromStream(await _client.send(request).timeout(_timeout));
    } on TimeoutException {
      throw const ApiException(null, '主控响应超时');
    } on http.ClientException catch (e) {
      throw ApiException(null, '无法连接主控：${e.message}');
    }
    final time = int.tryParse(res.headers['x-rigdeck-time'] ?? '');
    if (time != null) _offset = time - DateTime.now().millisecondsSinceEpoch;
    if (res.statusCode == 401) {
      onUnauthorized?.call();
      throw const ApiException(401, '登录已失效，请重新登录');
    }
    if (res.statusCode >= 400) throw ApiException(res.statusCode, _errorText(res));
    return utf8.decode(res.bodyBytes);
  }

  @override
  void close() => _client.close();
}

String newIdempotencyKey() {
  final r = Random.secure();
  return List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
}

/// Queue a job; returns its id. `action` uses the controller's tagged form, e.g.
/// `{'kind': 'miner', 'operation': 'restart', 'instances': ['xmr']}`.
Future<String> submitJob(Backend backend, List<String> machineIds, Map<String, dynamic> action) async {
  final result = await backend.send('POST', '/api/v1/jobs', {
    'machine_ids': machineIds,
    'action': action,
    'idempotency_key': newIdempotencyKey(),
    'include_controller': false,
  });
  return (result as Map)['job_id'] as String;
}
