import 'package:sync_lib/sync_lib.dart';
import 'package:test/test.dart';

// Testes de unidade das estratégias de resolução (o motor / OE3). Aqui
// exercitamos as funções puras diretamente — sem SyncClient nem servidor —
// para provar o comportamento de cada estratégia de forma isolada.

Json p({
  required String name,
  required double price,
  required DateTime updatedAt,
}) => Product(
  id: 'p1',
  name: name,
  price: price,
  version: 1,
  updatedAt: updatedAt,
).toJson();

void main() {
  final t0 = DateTime.utc(2026, 1, 1, 8, 0); // base comum
  final t1 = DateTime.utc(2026, 1, 1, 9, 0); // mais cedo
  final t2 = DateTime.utc(2026, 1, 1, 10, 0); // mais tarde

  group('LWW', () {
    test('vence quem tem updatedAt mais recente', () {
      final incoming = p(name: 'A', price: 10, updatedAt: t2);
      final current = p(name: 'B', price: 20, updatedAt: t1);
      expect(lww(incoming, current, const {})['name'], 'A');
    });

    test('empate de timestamp mantém o servidor', () {
      final incoming = p(name: 'A', price: 10, updatedAt: t1);
      final current = p(name: 'B', price: 20, updatedAt: t1);
      expect(lww(incoming, current, const {})['name'], 'B');
    });
  });

  group('Server Wins', () {
    test('servidor sempre prevalece, mesmo com edição mais recente', () {
      final incoming = p(name: 'A', price: 10, updatedAt: t2); // mais novo
      final current = p(name: 'B', price: 20, updatedAt: t1);
      expect(serverWins(incoming, current, const {}), current);
    });
  });

  group('Field-Level Merge (granularidade por campo — o OE3)', () {
    // Os dois partiram de: name 'Café', price 10, updatedAt t0.
    final base = {
      'name': 'Café',
      'price': 10.0,
      'updatedAt': t0.toIso8601String(),
    };

    test(
      'colisão real: na MESMA entidade, campos com vencedores diferentes',
      () {
        // Servidor e cliente alteraram name e price. Regras: name LWW (cliente
        // é mais recente, vence), price Server Wins (servidor mantém).
        final incoming = p(name: 'Café Cliente', price: 99, updatedAt: t2);
        final current = p(name: 'Café Servidor', price: 20, updatedAt: t1);

        final merged = fieldMerge({
          'name': FieldRule.lww,
          'price': FieldRule.serverWins,
        })(incoming, current, base);

        expect(merged['name'], 'Café Cliente');
        expect(merged['price'], 20);
      },
    );

    test('edições em campos diferentes se somam, mesmo sob LWW', () {
      // Servidor mudou só o price; cliente (mais ANTIGO) mudou só o name.
      // Não há colisão: o resultado tem as duas alterações. Um LWW de
      // registro inteiro descartaria o name do cliente.
      final incoming = p(name: 'Café Cliente', price: 10, updatedAt: t1);
      final current = p(name: 'Café', price: 20, updatedAt: t2);
      final changed = {'name': 'Café', 'updatedAt': t0.toIso8601String()};

      final merged = fieldMerge(const {})(incoming, current, changed);

      expect(merged['name'], 'Café Cliente'); // só o cliente mexeu
      expect(merged['price'], 20); // só o servidor mexeu
      expect(
        lww(incoming, current, changed)['name'],
        'Café',
      ); // o que se perderia
    });

    test(
      'Server Wins só arbitra colisão: campo que só o cliente mudou entra',
      () {
        final incoming = p(name: 'Café', price: 99, updatedAt: t2);
        final current = p(name: 'Café Servidor', price: 10, updatedAt: t1);
        final changed = {'price': 10.0, 'updatedAt': t0.toIso8601String()};

        final merged = fieldMerge({'price': FieldRule.serverWins})(
          incoming,
          current,
          changed,
        );

        expect(merged['price'], 99); // servidor não tinha mudado o preço
        expect(merged['name'], 'Café Servidor'); // cliente não tocou no nome
      },
    );

    test('clientWins força o valor que chega mesmo sendo mais antigo', () {
      final incoming = p(name: 'novo', price: 5, updatedAt: t1); // mais antigo
      final current = p(name: 'velho', price: 50, updatedAt: t2);

      final merged = fieldMerge({'price': FieldRule.clientWins})(
        incoming,
        current,
        base,
      );

      expect(merged['price'], 5); // clientWins -> incoming
      expect(merged['name'], 'velho'); // fallback lww -> current (t2 > t1)
    });

    test('fallback aplica-se a campos sem regra', () {
      final incoming = p(name: 'X', price: 1, updatedAt: t2);
      final current = p(name: 'Y', price: 2, updatedAt: t1);

      // Sem regras; fallback serverWins -> tudo do servidor.
      final merged = fieldMerge(const {}, fallback: FieldRule.serverWins)(
        incoming,
        current,
        base,
      );

      expect(merged['name'], 'Y');
      expect(merged['price'], 2);
    });
  });

  test('changedFields: valor anterior só dos campos alterados', () {
    final before = p(name: 'Café', price: 10, updatedAt: t0);
    final after = p(name: 'Café', price: 12, updatedAt: t1);
    expect(changedFields(before, after), {
      'price': 10.0,
      'updatedAt': t0.toIso8601String(),
    });
    expect(changedFields(null, after), isEmpty); // registro novo
  });

  test('sameValue: 50 e 50.0 são o mesmo preço', () {
    expect(sameValue(50, 50.0), isTrue);
    expect(
      sameValue(
        [
          1,
          {'a': 2},
        ],
        [
          1.0,
          {'a': 2},
        ],
      ),
      isTrue,
    );
    expect(sameValue({'a': 1}, {'a': 2}), isFalse);
  });
}
