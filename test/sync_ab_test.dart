import 'package:sync_lib/sync_lib.dart';
import 'package:test/test.dart';

// Cenário "Vendedor A/B": dois SyncClient (dois dispositivos) sincronizando
// contra um mesmo servidor em memória. É a base reproduzível do capítulo
// Resultados — cada teste é um experimento de concorrência.

Product cafe({
  required String name,
  required double price,
  required int version,
  required DateTime updatedAt,
}) => Product(
  id: 'p1',
  name: name,
  price: price,
  version: version,
  updatedAt: updatedAt,
);

void main() {
  final t0 = DateTime.utc(2026, 1, 1, 8, 0);
  final t1 = DateTime.utc(2026, 1, 1, 9, 0); // mais cedo
  final t2 = DateTime.utc(2026, 1, 1, 10, 0); // mais tarde

  late FakeServer server;
  late SyncClient a;
  late SyncClient b;

  setUp(() {
    server = FakeServer(); // LWW por padrão
    a = SyncClient(server);
    b = SyncClient(server);
  });

  test('o cano fecha: A cria, sincroniza e B puxa o registro', () async {
    a.edit(cafe(name: 'Café', price: 10, version: 0, updatedAt: t0));
    expect(a.pending, 1); // mutação retida no Outbox enquanto offline

    await a.sync();
    expect(a.pending, 0);
    expect(a.get('p1')!.version, 1); // servidor numerou como v1

    await b.sync(); // B só puxa
    expect(b.get('p1')!.name, 'Café');
    expect(b.get('p1')!.version, 1);
  });

  test('conflito LWW: vence a escrita mais recente (A)', () async {
    // Ambos partem da v1.
    a.edit(cafe(name: 'Café', price: 10, version: 0, updatedAt: t0));
    await a.sync();
    await b.sync();

    // Editam offline o mesmo registro, baseados na v1.
    a.edit(
      a.get('p1')!.copyWith(name: 'Café A', updatedAt: t2),
    ); // mais recente
    b.edit(b.get('p1')!.copyWith(name: 'Café B', updatedAt: t1)); // mais antiga

    await a.sync(); // aplica sem conflito -> v2 "Café A"
    await b.sync(); // conflito: base(v1) != v2 -> LWW -> A vence (t2 > t1)

    expect(b.get('p1')!.name, 'Café A');
  });

  test('conflito LWW: vence a escrita mais recente (B)', () async {
    a.edit(cafe(name: 'Café', price: 10, version: 0, updatedAt: t0));
    await a.sync();
    await b.sync();

    a.edit(a.get('p1')!.copyWith(name: 'Café A', updatedAt: t1)); // mais antiga
    b.edit(
      b.get('p1')!.copyWith(name: 'Café B', updatedAt: t2),
    ); // mais recente

    await a.sync();
    await b.sync(); // conflito -> LWW -> B vence (t2 > t1)

    expect(b.get('p1')!.name, 'Café B');
  });

  test('convergência: após todos sincronizarem, estados idênticos', () async {
    a.edit(cafe(name: 'Café', price: 10, version: 0, updatedAt: t0));
    await a.sync();
    await b.sync();

    a.edit(a.get('p1')!.copyWith(name: 'Café A', updatedAt: t2));
    b.edit(b.get('p1')!.copyWith(name: 'Café B', updatedAt: t1));
    await a.sync();
    await b.sync();

    // Rodada final: A puxa o estado resolvido.
    await a.sync();

    final pa = a.get('p1')!;
    final pb = b.get('p1')!;
    expect(pa.name, pb.name);
    expect(pa.version, pb.version);
    expect(pa.name, 'Café A'); // sem perda: convergiram no vencedor
  });
}
