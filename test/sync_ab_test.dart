import 'package:fieldwise_sync/fieldwise_sync.dart';
import '../example/pdv.dart';
import 'package:test/test.dart';

// Cenário "Vendedor A/B": dois SyncClient (dois dispositivos) sincronizando
// contra um mesmo servidor em memória. É a base reproduzível do capítulo
// Resultados — cada teste é um experimento de concorrência.

Product cafe({
  required String name,
  required double price,
  required DateTime updatedAt,
}) => Product(
  id: 'p1',
  name: name,
  price: price,
  version: 0,
  updatedAt: updatedAt,
);

void main() {
  final t0 = DateTime.utc(2026, 1, 1, 8, 0);
  final t1 = DateTime.utc(2026, 1, 1, 9, 0); // mais cedo
  final t2 = DateTime.utc(2026, 1, 1, 10, 0); // mais tarde

  group('LWW de registro inteiro', () {
    late FakeServer server;
    late SyncClient a;
    late SyncClient b;

    setUp(() {
      server = FakeServer(); // LWW por padrão
      a = SyncClient(server);
      b = SyncClient(server);
    });

    test('o cano fecha: A cria, sincroniza e B puxa o registro', () async {
      a.edit(productEntity, cafe(name: 'Café', price: 10, updatedAt: t0));
      expect(a.pending, 1); // mutação retida no Outbox enquanto offline

      await a.sync();
      expect(a.pending, 0);
      expect(a.get(productEntity, 'p1')!.version, 1); // servidor numerou v1

      await b.sync(); // B só puxa
      expect(b.get(productEntity, 'p1')!.name, 'Café');
      expect(b.get(productEntity, 'p1')!.version, 1);
    });

    test('conflito LWW: vence a escrita mais recente (A)', () async {
      a.edit(productEntity, cafe(name: 'Café', price: 10, updatedAt: t0));
      await a.sync();
      await b.sync();

      // Editam offline o mesmo registro, baseados na v1.
      final pa = a.get(productEntity, 'p1')!;
      final pb = b.get(productEntity, 'p1')!;
      a.edit(productEntity, pa.copyWith(name: 'Café A', updatedAt: t2));
      b.edit(productEntity, pb.copyWith(name: 'Café B', updatedAt: t1));

      await a.sync(); // aplica sem conflito -> v2 "Café A"
      await b.sync(); // conflito: base(v1) != v2 -> LWW -> A vence (t2 > t1)

      expect(b.get(productEntity, 'p1')!.name, 'Café A');
    });

    test('conflito LWW: vence a escrita mais recente (B)', () async {
      a.edit(productEntity, cafe(name: 'Café', price: 10, updatedAt: t0));
      await a.sync();
      await b.sync();

      final pa = a.get(productEntity, 'p1')!;
      final pb = b.get(productEntity, 'p1')!;
      a.edit(productEntity, pa.copyWith(name: 'Café A', updatedAt: t1));
      b.edit(productEntity, pb.copyWith(name: 'Café B', updatedAt: t2));

      await a.sync();
      await b.sync(); // conflito -> LWW -> B vence (t2 > t1)

      expect(b.get(productEntity, 'p1')!.name, 'Café B');
    });

    test('convergência: após todos sincronizarem, estados idênticos', () async {
      a.edit(productEntity, cafe(name: 'Café', price: 10, updatedAt: t0));
      await a.sync();
      await b.sync();

      final pa = a.get(productEntity, 'p1')!;
      final pb = b.get(productEntity, 'p1')!;
      a.edit(productEntity, pa.copyWith(name: 'Café A', updatedAt: t2));
      b.edit(productEntity, pb.copyWith(name: 'Café B', updatedAt: t1));
      await a.sync();
      await b.sync();
      await a.sync(); // rodada final: A puxa o estado resolvido

      final ra = a.get(productEntity, 'p1')!;
      final rb = b.get(productEntity, 'p1')!;
      expect(ra.name, rb.name);
      expect(ra.version, rb.version);
      expect(ra.name, 'Café A'); // convergiram no vencedor
    });
  });

  group('política gerada (fieldMerge por entidade)', () {
    late FakeServer server;
    late SyncClient a;
    late SyncClient b;

    setUp(() {
      server = FakeServer.withPolicy([
        productEntity,
        customerEntity,
        orderEntity,
      ]);
      a = SyncClient(server);
      b = SyncClient(server);
    });

    test('Customer: A muda o telefone, B muda o nome, nada se perde', () async {
      a.edit(
        customerEntity,
        Customer(
          id: 'c1',
          name: 'Maria',
          phone: '1111',
          creditLimit: 500,
          version: 0,
          updatedAt: t0,
        ),
      );
      await a.sync();
      await b.sync();

      final ca = a.get(customerEntity, 'c1')!;
      final cb = b.get(customerEntity, 'c1')!;
      a.edit(customerEntity, ca.copyWith(phone: '2222', updatedAt: t2));
      b.edit(customerEntity, cb.copyWith(name: 'Maria Souza', updatedAt: t1));
      await a.sync();
      await b.sync(); // conflito de registro, mas não de campo
      await a.sync();

      for (final c in [a, b]) {
        final r = c.get(customerEntity, 'c1')!;
        expect(r.phone, '2222');
        expect(r.name, 'Maria Souza');
        expect(r.version, 3);
      }
    });

    test('Order: pedido feito offline chega, e reenvio não duplica', () async {
      final order = Order(
        id: 'o1',
        customerId: 'c1',
        seller: 'a',
        items: const [OrderItem(productId: 'p1', quantity: 2, unitPrice: 10)],
        version: 0,
        updatedAt: t0,
      );
      a.edit(orderEntity, order);

      // A confirmação do 1º envio "se perde": o pedido chegou ao servidor,
      // mas continua no Outbox e é reenviado com a mesma base.
      final m = Mutation('Order', order.toJson(), 0);
      await server.push(m);
      await a.sync();

      final orders = (await server.pull())['Order']!;
      expect(orders, hasLength(1)); // id do cliente: o reenvio caiu no mesmo
      expect(Order.fromJson(orders.single).total, 20);
      expect(a.pending, 0);
    });
  });
}
