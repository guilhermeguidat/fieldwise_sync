import 'package:sync_lib/sync_lib.dart';
import 'package:test/test.dart';

// Prova que a configuração por ANOTAÇÃO chega até o comportamento: o mapa
// `productFieldRules` é gerado (source_gen) a partir de @Lww/@ServerWins no
// Product, e é ele que alimenta o fieldMerge. Fecha o OE3 ponta a ponta:
// anotação -> código gerado -> resolução.

void main() {
  final t1 = DateTime.utc(2026, 1, 1, 9);
  final t2 = DateTime.utc(2026, 1, 1, 10);

  test('o mapa gerado reflete as anotações do Product', () {
    expect(productFieldRules, {
      'name': FieldRule.lww,
      'price': FieldRule.serverWins,
    });
  });

  test('fieldMerge dirigido pelo mapa GERADO resolve por campo', () {
    // Cliente mais recente: vence o name (LWW); perde o price (Server Wins).
    final incoming = Product(
        id: 'p1', name: 'Cliente', price: 99, version: 1, updatedAt: t2);
    final current = Product(
        id: 'p1', name: 'Servidor', price: 20, version: 1, updatedAt: t1);

    final merged = fieldMerge(productFieldRules)(incoming, current);

    expect(merged.name, 'Cliente'); // @Lww -> cliente (t2 > t1)
    expect(merged.price, 20); // @ServerWins -> servidor
  });
}
