@Tags(['e2e'])
library;

import 'dart:io';

import 'package:sync_lib/sync_lib.dart';
import 'package:test/test.dart';

// Integração real: dois SyncClient via HttpTransport contra o backend Spring
// (Postgres). É o "punhado" de testes de integração que prova o cano
// ponta-a-ponta de verdade (o resto da prova roda em Dart puro com FakeServer).
//
// Requer backend rodando. Rode com:
//   docker compose up -d
//   (cd backend && ./mvnw spring-boot:run)   # em outro terminal
//   RUN_E2E=1 dart test -t e2e
//
// Sem RUN_E2E=1 o arquivo é pulado (mantém `dart test` verde offline).

void main() {
  final run = Platform.environment['RUN_E2E'] == '1';
  final baseUrl =
      Platform.environment['BACKEND_URL'] ?? 'http://localhost:8080';

  test('conflito LWW ponta-a-ponta contra o backend real', () async {
    final id = 'e2e-${DateTime.now().microsecondsSinceEpoch}';
    final transport = HttpTransport(baseUrl);
    final a = SyncClient(transport);
    final b = SyncClient(transport);

    final t1 = DateTime.utc(2026, 1, 1, 9);
    final t2 = DateTime.utc(2026, 1, 1, 10);

    // A cria o registro e sincroniza; B puxa.
    a.edit(Product(
        id: id, name: 'Café', price: 10, version: 0, updatedAt: t1));
    await a.sync();
    await b.sync();
    expect(b.get(id)!.name, 'Café');

    // Ambos editam offline; A é mais recente e deve vencer o conflito.
    a.edit(a.get(id)!.copyWith(name: 'Café A', updatedAt: t2));
    b.edit(b.get(id)!.copyWith(name: 'Café B', updatedAt: t1));
    await a.sync();
    await b.sync();

    expect(b.get(id)!.name, 'Café A'); // LWW resolvido no servidor

    transport.close();
  }, skip: run ? null : 'defina RUN_E2E=1 com o backend no ar');

  test('Field-Level Merge ponta-a-ponta: name por LWW, price por Server Wins',
      () async {
    // Prova a granularidade por campo contra o backend real: numa mesma
    // entidade, o cliente vence `name` (regra LWW) mas perde `price` (regra
    // Server Wins), simultaneamente. Config do servidor: name=LWW, price=SW.
    final id = 'e2e-fm-${DateTime.now().microsecondsSinceEpoch}';
    final transport = HttpTransport(baseUrl);
    final a = SyncClient(transport);
    final b = SyncClient(transport);

    final t0 = DateTime.utc(2026, 1, 1, 8);
    final t1 = DateTime.utc(2026, 1, 1, 9);
    final t2 = DateTime.utc(2026, 1, 1, 10);

    // A cria (price 10) e sincroniza; B puxa a v1.
    a.edit(Product(id: id, name: 'Café', price: 10, version: 0, updatedAt: t0));
    await a.sync();
    await b.sync();

    // A edita mais cedo (t1): price 50 vira a autoridade do servidor.
    a.edit(a.get(id)!.copyWith(name: 'Café A', price: 50, updatedAt: t1));
    await a.sync(); // sem conflito -> v2 (name 'Café A', price 50)

    // B edita mais tarde (t2) baseado ainda na v1: conflito -> merge por campo.
    b.edit(b.get(id)!.copyWith(name: 'Café B', price: 88, updatedAt: t2));
    await b.sync();

    final resolved = b.get(id)!;
    expect(resolved.name, 'Café B'); // LWW -> B é mais recente, vence o name
    expect(resolved.price, 50); // Server Wins -> price do servidor prevalece

    transport.close();
  }, skip: run ? null : 'defina RUN_E2E=1 com o backend no ar');
}
