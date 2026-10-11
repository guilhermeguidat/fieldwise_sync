import 'dart:convert';
import 'dart:io';

import 'package:fieldwise_sync/fieldwise_sync.dart';
import '../example/pdv.dart';
import 'package:test/test.dart';

// Prova que a configuração por ANOTAÇÃO chega até o comportamento: os mapas
// `<entidade>FieldRules` são gerados (source_gen) a partir de @Lww/@ServerWins
// e da `defaultRule` de @SyncEntity, e são eles que alimentam o fieldMerge.
// Fecha o OE3 ponta a ponta: anotação -> código gerado -> resolução.

void main() {
  test('por campo: o mapa gerado reflete as anotações do Product', () {
    expect(productFieldRules, {
      'name': FieldRule.lww,
      'price': FieldRule.serverWins,
    });
    expect(customerFieldRules, {
      'name': FieldRule.lww,
      'phone': FieldRule.lww,
      'creditLimit': FieldRule.serverWins,
    });
  });

  test('por entidade: defaultRule vale para todo campo do Order', () {
    expect(orderFieldRules.values.toSet(), {FieldRule.serverWins});
    expect(orderFieldRules.keys, containsAll(['customerId', 'items']));
    expect(orderFieldRules, isNot(contains('total'))); // getter, não dado
  });

  // O JSON é gerado no app (o pacote que declara as entidades) e é o que o
  // servidor lê. Este teste prova a ADR 0002 e, de quebra, que o domínio do
  // example/ (usado pelos testes e experimentos) tem a mesma política do app.
  // Fora do monorepo (repo público) o app não existe e o teste é pulado.
  final appJson = File('../app_pdv/lib/sync_config.json');
  test(
    'o JSON do servidor é a mesma política (ADR 0002)',
    skip: appJson.existsSync() ? false : 'fora do monorepo',
    () {
      final json = jsonDecode(appJson.readAsStringSync());
      String snake(FieldRule r) => r.name
          .replaceAllMapped(RegExp('[A-Z]'), (m) => '_${m[0]}')
          .toUpperCase();
      final entities = [productEntity, customerEntity, orderEntity];
      expect((json['entities'] as Map).keys.toSet(), {
        for (final e in entities) e.name,
      });
      for (final e in entities) {
        expect(
          json['entities'][e.name],
          e.rules.map((f, r) => MapEntry(f, snake(r))),
        );
      }
    },
  );

  test('fieldMerge dirigido pelo mapa GERADO resolve por campo', () {
    final t0 = DateTime.utc(2026, 1, 1, 8).toIso8601String();
    final t1 = DateTime.utc(2026, 1, 1, 9);
    final t2 = DateTime.utc(2026, 1, 1, 10);
    Json prod(String name, double price, DateTime at) => Product(
      id: 'p1',
      name: name,
      price: price,
      version: 1,
      updatedAt: at,
    ).toJson();

    // Colisão nos dois campos. Cliente mais recente: vence o name (LWW);
    // perde o price (Server Wins).
    final merged = fieldMerge(productFieldRules)(
      prod('Cliente', 99, t2),
      prod('Servidor', 20, t1),
      {'name': 'Café', 'price': 10, 'updatedAt': t0},
    );

    expect(merged['name'], 'Cliente');
    expect(merged['price'], 20);
  });
}
