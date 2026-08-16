import 'dart:convert';

import 'package:http/http.dart' as http;

import '../model/product.dart';
import '../outbox/outbox.dart';
import 'sync_transport.dart';

/// Implementação real do transporte: fala HTTP/JSON com o backend Spring.
/// Mesma interface do FakeServer — o SyncClient não muda ao trocar um pelo
/// outro. O payload espelha os DTOs do backend (ver ADR 0001).
class HttpTransport implements SyncTransport {
  final String baseUrl; // ex.: http://10.0.2.2:8080 (host da máquina no emulador Android)
  final http.Client _client;

  HttpTransport(this.baseUrl, {http.Client? client})
      : _client = client ?? http.Client();

  @override
  Future<Product> push(Mutation m) async {
    final res = await _client.post(
      Uri.parse('$baseUrl/sync/push'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'product': m.product.toJson(),
        'baseVersion': m.baseVersion,
      }),
    );
    _ensureOk(res, 'push');
    return Product.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  @override
  Future<List<Product>> pull() async {
    final res = await _client.get(Uri.parse('$baseUrl/sync/pull'));
    _ensureOk(res, 'pull');
    final list = jsonDecode(res.body) as List<dynamic>;
    return list
        .map((e) => Product.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  void _ensureOk(http.Response res, String op) {
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
