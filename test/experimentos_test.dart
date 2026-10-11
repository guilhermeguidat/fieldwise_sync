import 'package:fieldwise_sync/fieldwise_sync.dart';
import '../example/pdv.dart';
import 'package:test/test.dart';

import '../tool/experimentos.dart';

// Versão reduzida dos experimentos da Fase 5 (tool/experimentos.dart): trava
// as duas afirmações que o capítulo de Resultados faz. Se uma mudança no motor
// as quebrar, a suíte acusa.

void main() {
  test(
    'E1: com Outbox, nenhum pedido se perde mesmo com 50% de falha',
    () async {
      final s = FakeServer.withPolicy([orderEntity]);
      final r = await pedidosSobFalha(
        (s, s),
        falha: 0.5,
        pedidosPorVendedor: 20,
        confirmaAntesDeRemover: true,
        rodada: 't',
      );
      expect(r.perdidos, 0);
      expect(r.duplicados, 0);
      expect(r.noServidor, 40);
    },
  );

  test('E2: fieldMerge não perde edição sem colisão e converge', () async {
    final s = FakeServer.withPolicy([customerEntity]);
    final r = await edicaoConcorrente((s, s), clientes: 30, rodada: 't');
    expect(r.perdidas, 0);
    expect(r.lwwCorretas, r.colisoesLww);
    expect(r.convergentes, 30);
  });
}
