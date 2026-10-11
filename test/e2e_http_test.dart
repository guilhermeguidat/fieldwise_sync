@Tags(['e2e'])
library;

import 'dart:io';

import 'package:fieldwise_sync/fieldwise_sync.dart';
import '../example/pdv.dart';
import 'package:test/test.dart';

// Integração real: dois SyncClient via HttpTransport contra o backend Spring
// (Postgres), cada um autenticado como um vendedor. É o "punhado" de testes de
// integração que prova o cano ponta-a-ponta de verdade (o resto da prova roda
// em Dart puro com FakeServer). Também é o teste de conformidade do backend
// com a especificação executável (FakeServer).
//
// Requer backend rodando. Rode com:
//   docker compose up -d
//   (cd backend && ./mvnw spring-boot:run)   # em outro terminal
//   RUN_E2E=1 dart test -t e2e
//
// Sem RUN_E2E=1 o arquivo é pulado (mantém `dart test` verde offline).

void main() {
  final run = Platform.environment['RUN_E2E'] == '1';
  final skip = run ? null : 'defina RUN_E2E=1 com o backend no ar';
  final baseUrl =
      Platform.environment['BACKEND_URL'] ?? 'http://localhost:8080';

  final t0 = DateTime.utc(2026, 1, 1, 8);
  final t1 = DateTime.utc(2026, 1, 1, 9);
  final t2 = DateTime.utc(2026, 1, 1, 10);

  late HttpTransport ta;
  late HttpTransport tb;
  late SyncClient a;
  late SyncClient b;

  setUp(() async {
    if (!run) return;
    ta = await HttpTransport.login(baseUrl, 'vendedor_a', 'senha');
    tb = await HttpTransport.login(baseUrl, 'vendedor_b', 'senha');
    a = SyncClient(ta);
    b = SyncClient(tb);
  });
  tearDown(() {
    if (!run) return;
    ta.close();
    tb.close();
  });

  String uid(String p) => '$p-${DateTime.now().microsecondsSinceEpoch}';

  test('sem token o servidor recusa', () async {
    final anon = HttpTransport(baseUrl, 'invalido');
    await expectLater(anon.pull(), throwsA(isA<SyncTransportException>()));
    anon.close();
  }, skip: skip);

  test('Product: name por LWW, price por Server Wins', () async {
    final id = uid('p');
    a.edit(
      productEntity,
      Product(id: id, name: 'Café', price: 10, version: 0, updatedAt: t0),
    );
    await a.sync();
    await b.sync();

    final pa = a.get(productEntity, id)!;
    final pb = b.get(productEntity, id)!;
    a.edit(
      productEntity,
      pa.copyWith(name: 'Café A', price: 50, updatedAt: t1),
    );
    await a.sync(); // sem conflito -> v2 (name 'Café A', price 50)
    b.edit(
      productEntity,
      pb.copyWith(name: 'Café B', price: 88, updatedAt: t2),
    );
    await b.sync(); // colisão nos dois campos

    final r = b.get(productEntity, id)!;
    expect(r.name, 'Café B'); // LWW -> B é mais recente
    expect(r.price, 50); // Server Wins -> servidor
    expect(r.version, 3);
  }, skip: skip);

  test('Customer: edições em campos diferentes se somam', () async {
    final id = uid('c');
    a.edit(
      customerEntity,
      Customer(
        id: id,
        name: 'Maria',
        phone: '1111',
        creditLimit: 500,
        version: 0,
        updatedAt: t0,
      ),
    );
    await a.sync();
    await b.sync();

    final ca = a.get(customerEntity, id)!;
    final cb = b.get(customerEntity, id)!;
    a.edit(customerEntity, ca.copyWith(phone: '2222', updatedAt: t2));
    b.edit(customerEntity, cb.copyWith(name: 'Maria Souza', updatedAt: t1));
    await a.sync();
    await b.sync();

    final r = b.get(customerEntity, id)!;
    expect(r.phone, '2222');
    expect(r.name, 'Maria Souza');
  }, skip: skip);

  test('Order: reenvio do mesmo pedido não duplica', () async {
    final order = Order(
      id: uid('o'),
      customerId: 'c1',
      seller: 'vendedor_a',
      items: const [OrderItem(productId: 'p1', quantity: 3, unitPrice: 2.5)],
      version: 0,
      updatedAt: t0,
    );
    final m = Mutation('Order', order.toJson(), 0);
    await ta.push(m); // chegou, mas a confirmação "se perdeu"
    final again = await ta.push(m); // o Outbox reenvia

    final orders = (await ta.pull())['Order']!.where(
      (o) => o['id'] == order.id,
    );
    expect(orders, hasLength(1));
    expect(Order.fromJson(again).total, 7.5);
  }, skip: skip);
}
