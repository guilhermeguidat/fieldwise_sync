import 'package:sync_lib/sync_lib.dart';
import 'package:test/test.dart';

// Testes de unidade das estratégias de resolução (o motor da Fase 2 / OE3).
// Aqui exercitamos as funções puras diretamente — sem SyncClient nem servidor —
// para provar o comportamento de cada estratégia de forma isolada.

Product p({
  required String name,
  required double price,
  required DateTime updatedAt,
}) =>
    Product(id: 'p1', name: name, price: price, version: 1, updatedAt: updatedAt);

void main() {
  final t1 = DateTime.utc(2026, 1, 1, 9, 0); // mais cedo
  final t2 = DateTime.utc(2026, 1, 1, 10, 0); // mais tarde

  group('LWW', () {
    test('vence quem tem updatedAt mais recente', () {
      final incoming = p(name: 'A', price: 10, updatedAt: t2);
      final current = p(name: 'B', price: 20, updatedAt: t1);
      expect(lww(incoming, current).name, 'A');
    });

    test('empate de timestamp mantém o servidor', () {
      final incoming = p(name: 'A', price: 10, updatedAt: t1);
      final current = p(name: 'B', price: 20, updatedAt: t1);
      expect(lww(incoming, current).name, 'B');
    });
  });

  group('Server Wins', () {
    test('servidor sempre prevalece, mesmo com edição mais recente', () {
      final incoming = p(name: 'A', price: 10, updatedAt: t2); // mais novo
      final current = p(name: 'B', price: 20, updatedAt: t1);
      expect(serverWins(incoming, current).name, 'B');
      expect(serverWins(incoming, current).price, 20);
    });
  });

  group('Field-Level Merge (granularidade por campo — o OE3)', () {
    test('na MESMA entidade, campos diferentes têm vencedores diferentes', () {
      // Cliente (incoming) é mais recente. Regras: name segue LWW (cliente vence),
      // price segue Server Wins (servidor mantém).
      final incoming = p(name: 'Café Cliente', price: 99, updatedAt: t2);
      final current = p(name: 'Café Servidor', price: 20, updatedAt: t1);

      final strategy = fieldMerge({
        'name': FieldRule.lww,
        'price': FieldRule.serverWins,
      });
      final merged = strategy(incoming, current);

      expect(merged.name, 'Café Cliente'); // LWW -> cliente (t2 > t1)
      expect(merged.price, 20); // Server Wins -> servidor
    });

    test('clientWins força o valor que chega mesmo sendo mais antigo', () {
      final incoming = p(name: 'novo', price: 5, updatedAt: t1); // mais antigo
      final current = p(name: 'velho', price: 50, updatedAt: t2);

      final strategy = fieldMerge({'price': FieldRule.clientWins});
      final merged = strategy(incoming, current);

      expect(merged.price, 5); // clientWins -> incoming
      expect(merged.name, 'velho'); // fallback lww -> current (t2 > t1)
    });

    test('fallback aplica-se a campos sem regra', () {
      final incoming = p(name: 'X', price: 1, updatedAt: t2);
      final current = p(name: 'Y', price: 2, updatedAt: t1);

      // Sem regras; fallback serverWins -> tudo do servidor.
      final strategy = fieldMerge(const {}, fallback: FieldRule.serverWins);
      final merged = strategy(incoming, current);

      expect(merged.name, 'Y');
      expect(merged.price, 2);
    });
  });
}
