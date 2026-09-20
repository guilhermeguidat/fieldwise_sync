import 'dart:io';

import 'package:sync_lib/sync_lib.dart';
import 'package:test/test.dart';

// OE1 — o motor não depende do banco local: o MESMO cenário Vendedor A/B
// (com merge por campo) roda sobre memória e sobre SQLite e produz o mesmo
// resultado. Trocar o adapter não toca no SyncClient nem no servidor.
//
// OE2 — o Outbox persistido sobrevive a fechar o app e a falha de rede no
// meio do envio: nada se perde.

Product cafe(String name, double price, DateTime at) =>
    Product(id: 'p1', name: name, price: price, version: 0, updatedAt: at);

void main() {
  final t0 = DateTime.utc(2026, 1, 1, 8);
  final t1 = DateTime.utc(2026, 1, 1, 9);
  final t2 = DateTime.utc(2026, 1, 1, 10);

  final adapters = <String, ILocalDatabase Function()>{
    'InMemoryDatabase': InMemoryDatabase.new,
    'SqliteDatabase': SqliteDatabase.inMemory,
  };

  for (final entry in adapters.entries) {
    group('OE1 sobre ${entry.key}', () {
      test('Vendedor A/B com merge por campo: mesmo resultado', () async {
        final server = FakeServer(strategy: fieldMerge(productFieldRules));
        final a = SyncClient(server, db: entry.value());
        final b = SyncClient(server, db: entry.value());

        a.edit(cafe('Café', 10, t0));
        await a.sync();
        await b.sync();

        a.edit(a.get('p1')!.copyWith(name: 'Café A', price: 50, updatedAt: t1));
        b.edit(b.get('p1')!.copyWith(name: 'Café B', price: 88, updatedAt: t2));
        await a.sync(); // sem conflito -> v2
        await b.sync(); // conflito -> name LWW (B), price ServerWins (50)
        await a.sync();

        for (final c in [a, b]) {
          expect(c.get('p1')!.name, 'Café B');
          expect(c.get('p1')!.price, 50);
          expect(c.get('p1')!.version, 3);
          expect(c.pending, 0);
        }
      });
    });
  }

  group('OE2 Outbox persistido (SQLite em arquivo)', () {
    late Directory tmp;
    late String path;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('sync_lib_');
      path = '${tmp.path}/local.db';
    });
    tearDown(() => tmp.deleteSync(recursive: true));

    test('edição offline sobrevive a fechar e reabrir o app', () async {
      // "Sessão 1": vende sem sinal e fecha o app antes de sincronizar.
      final db1 = SqliteDatabase(path);
      SyncClient(FakeServer(), db: db1).edit(cafe('Café', 10, t0));
      expect(db1.pendingCount, 1);
      db1.close();

      // "Sessão 2": reabre; a mutação ainda está na fila e é entregue.
      final server = FakeServer();
      final db2 = SqliteDatabase(path);
      final client = SyncClient(server, db: db2);
      expect(client.pending, 1);
      expect(client.get('p1')!.name, 'Café'); // réplica local também persistiu

      await client.sync();
      expect(client.pending, 0);
      expect((await server.pull()).single.name, 'Café');
      db2.close();
    });
  });

  group('OE2 falha de rede no meio do envio', () {
    test('mutação não confirmada fica na fila e é reenviada', () async {
      final server = FakeServer();
      final flaky = _FlakyTransport(server, failOnPush: 2);
      final client = SyncClient(flaky, db: SqliteDatabase.inMemory());

      client.edit(
        Product(id: 'p1', name: 'A', price: 1, version: 0, updatedAt: t0),
      );
      client.edit(
        Product(id: 'p2', name: 'B', price: 2, version: 0, updatedAt: t0),
      );
      expect(client.pending, 2);

      // 1º sync: p1 entra, p2 falha -> p2 continua pendente.
      await expectLater(client.sync(), throwsA(isA<SocketException>()));
      expect(client.pending, 1);
      expect((await server.pull()).map((p) => p.id), ['p1']);

      // 2º sync (rede voltou): p2 é entregue. Nada se perdeu.
      await client.sync();
      expect(client.pending, 0);
      expect((await server.pull()).map((p) => p.id), containsAll(['p1', 'p2']));
    });
  });
}

/// Transporte que falha no N-ésimo push, simulando queda de rede no meio
/// do envio da fila.
class _FlakyTransport implements SyncTransport {
  final SyncTransport _inner;
  final int failOnPush;
  int _pushes = 0;

  _FlakyTransport(this._inner, {required this.failOnPush});

  @override
  Future<Product> push(Mutation m) {
    if (++_pushes == failOnPush) {
      throw const SocketException('rede caiu');
    }
    return _inner.push(m);
  }

  @override
  Future<List<Product>> pull() => _inner.pull();
}
