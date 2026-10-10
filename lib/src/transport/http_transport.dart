import 'dart:convert';

import 'package:http/http.dart' as http;

import '../engine/entity.dart';
import '../outbox/outbox.dart';
import 'sync_transport.dart';

/// Implementação real do transporte: fala HTTP/JSON com o backend Spring.
/// Mesma interface do FakeServer — o SyncClient não muda ao trocar um pelo
/// outro. O payload é o `Mutation.toJson()` (ver ADR 0001 e 0003).
///
/// Os endpoints de sync exigem o token JWT obtido em [login].
class HttpTransport implements SyncTransport {
  /// ex.: http://10.0.2.2:8080 (host da máquina no emulador Android)
  final String baseUrl;
  final String token;
  final http.Client _client;

  HttpTransport(this.baseUrl, this.token, {http.Client? client})
    : _client = client ?? http.Client();

  /// Autentica o vendedor e devolve um transporte já com o token.
  static Future<HttpTransport> login(
    String baseUrl,
    String username,
    String password, {
    http.Client? client,
  }) async {
    final c = client ?? http.Client();
    final res = await c.post(
      Uri.parse('$baseUrl/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password}),
    );
    _ensureOk(res, 'login');
    final token = (jsonDecode(res.body) as Json)['token'] as String;
    return HttpTransport(baseUrl, token, client: c);
  }

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $token',
  };

  @override
  Future<Json> push(Mutation m) async {
    final res = await _client.post(
      Uri.parse('$baseUrl/sync/push'),
      headers: _headers,
      body: jsonEncode(m.toJson()),
    );
    _ensureOk(res, 'push');
    return jsonDecode(res.body) as Json;
  }

  @override
  Future<Map<String, List<Json>>> pull() async {
    final res = await _client.get(
      Uri.parse('$baseUrl/sync/pull'),
      headers: _headers,
    );
    _ensureOk(res, 'pull');
    return {
      for (final e in (jsonDecode(res.body) as Json).entries)
        e.key: [for (final r in e.value as List) r as Json],
    };
  }

  static void _ensureOk(http.Response res, String op) {
    if (res.statusCode != 200) {
      throw SyncTransportException(op, res.statusCode, res.body);
    }
  }

  void close() => _client.close();
}

class SyncTransportException implements Exception {
  final String operation;
  final int statusCode;
  final String body;

  SyncTransportException(this.operation, this.statusCode, this.body);

  @override
  String toString() =>
      'SyncTransportException($operation: HTTP $statusCode) $body';
}
