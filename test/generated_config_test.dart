import 'dart:convert';
import 'dart:io';

import 'package:sync_lib/sync_lib.dart';
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

  test('o JSON do servidor é a mesma política (ADR 0002)', () {
    final json = jsonDecode(File('lib/sync_config.json').readAsStringSync());
    String snake(FieldRule r) => r.name
        .replaceAllMapped(RegExp('[A-Z]'), (m) => '_${m[0]}')
        .toUpperCase();
    for (final e in [productEntity, customerEntity, orderEntity]) {
      expect(
        json['entities'][e.name],
        e.rules.map((f, r) => MapEntry(f, snake(r))),
      );
    }
  });

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
