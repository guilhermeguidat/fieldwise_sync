// Experimentos da Fase 5 (OE4): medem perda e recuperação de registros sob
// rede instável e edição concorrente. São a base do capítulo de Resultados.
//
//   dart run tool/experimentos.dart            # contra o FakeServer (Dart puro)
//   dart run tool/experimentos.dart --http     # contra o backend real (Spring +
//                                              # Postgres no ar, ver CLAUDE.md)
//
// Semente fixa: os números são reproduzíveis no modo FakeServer. A latência é
// real (Future.delayed), então a ordem exata de chegada pode variar entre
// execuções; as métricas de perda e convergência não dependem dela.

import 'dart:io';
import 'dart:math';

import 'package:fieldwise_sync/fieldwise_sync.dart';
import '../example/pdv.dart';

const _seed = 42;

Future<void> main(List<String> args) async {
  final http = args.contains('--http');
  final baseUrl =
      Platform.environment['BACKEND_URL'] ?? 'http://localhost:8080';

  // Prefixo dos ids: o banco do backend persiste entre execuções, e um id
  // repetido cairia em registro de uma execução anterior.
  final execucao = DateTime.now().millisecondsSinceEpoch.toRadixString(36);

  // Cada experimento recebe uma fábrica de "servidor": dois transportes (um por
  // vendedor) que enxergam o mesmo estado.
  Future<(SyncTransport, SyncTransport)> servidor(
    Map<String, ConflictStrategy> strategies,
  ) async {
    if (http) {
      // O backend sempre aplica a política gerada (fieldMerge por entidade).
      return (
        await HttpTransport.login(baseUrl, 'vendedor_a', 'senha'),
        await HttpTransport.login(baseUrl, 'vendedor_b', 'senha'),
      );
    }
    final s = FakeServer(strategies: strategies);
    return (s, s);
  }

  print(
    '# Experimentos (${http ? 'backend Spring + Postgres' : 'FakeServer em memória'})\n',
  );
  print(
    'Semente: $_seed. Gerado em ${DateTime.now().toUtc().toIso8601String()}.\n',
  );

  print('## E1. Pedidos sob rede instável\n');
  print(
    '| Falha por chamada | Fila | Pedidos criados | No servidor | Perdidos '
    '| Duplicados | Tentativas de sync (média) |',
  );
  print('|---|---|---|---|---|---|---|');
  for (final p in [0.0, 0.1, 0.3, 0.5]) {
    for (final confirmado in [true, false]) {
      final r = await pedidosSobFalha(
        await servidor({'Order': fieldMerge(orderFieldRules)}),
        falha: p,
        pedidosPorVendedor: 100,
        confirmaAntesDeRemover: confirmado,
        rodada: '$execucao-e1-${(p * 100).round()}-$confirmado',
      );
      print(
        '| ${(p * 100).round()}% | ${confirmado ? 'Outbox (remove após confirmar)' : 'ingênua (remove antes de enviar)'} '
        '| ${r.criados} | ${r.noServidor} | ${r.perdidos} | ${r.duplicados} '
        '| ${r.tentativasMedia.toStringAsFixed(1)} |',
      );
    }
  }

  print('\n## E2. Edição concorrente do mesmo cliente por dois vendedores\n');
  print(
    '| Estratégia | Edições sem colisão | Perdidas | Colisões | '
    'Colisões LWW resolvidas pelo mais recente | Registros convergentes |',
  );
  print('|---|---|---|---|---|---|');
  final estrategias = http
      ? {'fieldMerge (política gerada)': const <String, ConflictStrategy>{}}
      : {
          'LWW (registro inteiro)': {'Customer': lww},
          'Server Wins (registro inteiro)': {'Customer': serverWins},
          'fieldMerge (política gerada)': {
            'Customer': fieldMerge(customerFieldRules),
          },
        };
  // Última linha: a política gerada sob latência alta (até 100 ms por
  // chamada), que embaralha mais a ordem de chegada dos dois vendedores.
  final linhas = [
    for (final e in estrategias.entries) (e.key, e.value, 3),
    ('fieldMerge, latência até 100 ms', estrategias.values.last, 100),
  ];
  for (final (nome, estrategia, latencia) in linhas) {
    final r = await edicaoConcorrente(
      await servidor(estrategia),
      clientes: 200,
      rodada: '$execucao-e2-${nome.hashCode}',
      latenciaMaxMs: latencia,
    );
    print(
      '| $nome | ${r.semColisao} | ${r.perdidas} '
      '(${(100 * r.perdidas / r.semColisao).toStringAsFixed(1)}%) | ${r.colisoes} '
      '| ${r.lwwCorretas}/${r.colisoesLww} | ${r.convergentes}/${r.clientes} |',
    );
  }
}

// ---------------------------------------------------------------------------
// E1: dois vendedores fecham pedidos offline e sincronizam por uma rede que
// falha com probabilidade [falha] em cada chamada. Metade das falhas perde a
// requisição; a outra metade perde só a confirmação (o servidor gravou, o
// cliente não soube). Sincroniza até esvaziar a fila.
//
// [confirmaAntesDeRemover] = false é a linha de base sem Outbox confirmado:
// tira a mutação da fila antes de enviar, como um "fire and forget".

typedef ResultadoE1 = ({
  int criados,
  int noServidor,
  int perdidos,
  int duplicados,
  double tentativasMedia,
});

Future<ResultadoE1> pedidosSobFalha(
  (SyncTransport, SyncTransport) servidor, {
  required double falha,
  required int pedidosPorVendedor,
  required bool confirmaAntesDeRemover,
  required String rodada,
}) async {
  final rnd = Random(_seed);
  final ids = <String>{};
  var tentativas = 0;

  for (final (v, transporte) in [('a', servidor.$1), ('b', servidor.$2)]) {
    final db = InMemoryDatabase();
    final rede = RedeInstavel(transporte, rnd, falha: falha);
    final cliente = SyncClient(rede, db: db);

    for (var i = 0; i < pedidosPorVendedor; i++) {
      final id = '$rodada-$v-$i';
      ids.add(id);
      cliente.edit(
        orderEntity,
        Order(
          id: id,
          customerId: 'c${rnd.nextInt(10)}',
          seller: 'vendedor_$v',
          items: [
            OrderItem(
              productId: 'p${rnd.nextInt(20)}',
              quantity: 1 + rnd.nextInt(5),
              unitPrice: 1 + rnd.nextInt(100).toDouble(),
            ),
          ],
          version: 0,
          updatedAt: DateTime.utc(2026, 1, 1).add(Duration(minutes: i)),
        ),
      );
    }

    // ponytail: teto de tentativas só para o experimento terminar; o app
    // real tenta de novo a cada vez que a rede volta.
    for (var t = 0; db.pendingCount > 0 && t < 1000; t++) {
      tentativas++;
      try {
        if (confirmaAntesDeRemover) {
          await cliente.sync();
        } else {
          await _syncIngenuo(db, rede);
        }
      } on SocketException {
        // rede caiu no meio; tenta de novo
      }
    }
  }

  final pull = await servidor.$1.pull();
  final noServidor = [
    for (final o in pull['Order'] ?? const <Json>[])
      if (ids.contains(o['id'])) o['id'] as String,
  ];
  return (
    criados: ids.length,
    noServidor: noServidor.toSet().length,
    perdidos: ids.difference(noServidor.toSet()).length,
    duplicados: noServidor.length - noServidor.toSet().length,
    tentativasMedia: tentativas / 2,
  );
}

/// Linha de base: remove da fila ANTES de enviar. Se o envio falha, a mutação
/// já saiu da fila e se perde.
Future<void> _syncIngenuo(ILocalDatabase db, SyncTransport rede) async {
  for (var m = db.peekOutbox(); m != null; m = db.peekOutbox()) {
    db.popOutbox();
    await rede.push(m);
  }
}

// ---------------------------------------------------------------------------
// E2: [clientes] cadastros, conhecidos pelos dois vendedores. Offline, cada
// vendedor altera um subconjunto aleatório dos campos de cada cadastro, com
// valores distintos e horários aleatórios. Os dois sincronizam ao mesmo tempo
// (com latência), e depois mais uma vez para puxar o estado final.
//
// Métricas por campo:
// - edição sem colisão: só um vendedor alterou o campo. Perdida se o valor
//   final não é o dele (nada a disputar, então nada deveria se perder);
// - colisão: os dois alteraram. Nos campos LWW, verifica se venceu o mais
//   recente; nos Server Wins, qualquer um dos dois que chegou primeiro é válido.
// - convergência: A, B e servidor terminam com o mesmo registro.

typedef ResultadoE2 = ({
  int clientes,
  int semColisao,
  int perdidas,
  int colisoes,
  int colisoesLww,
  int lwwCorretas,
  int convergentes,
});

Future<ResultadoE2> edicaoConcorrente(
  (SyncTransport, SyncTransport) servidor, {
  required int clientes,
  required String rodada,
  int latenciaMaxMs = 3,
}) async {
  final rnd = Random(_seed);
  final a = SyncClient(
    RedeInstavel(servidor.$1, rnd, latenciaMaxMs: latenciaMaxMs),
  );
  final b = SyncClient(
    RedeInstavel(servidor.$2, rnd, latenciaMaxMs: latenciaMaxMs),
  );
  final t0 = DateTime.utc(2026, 1, 1);
  String id(int i) => '$rodada-c$i';

  for (var i = 0; i < clientes; i++) {
    a.edit(
      customerEntity,
      Customer(
        id: id(i),
        name: 'Cliente $i',
        phone: '0000-$i',
        creditLimit: 100,
        version: 0,
        updatedAt: t0,
      ),
    );
  }
  await a.sync();
  await b.sync();

  // Edições offline. Guarda, por cliente, o que cada vendedor fez.
  final feitas = <String, Map<String, Map<String, Object>>>{};
  final horario = <String, Map<String, DateTime>>{};
  for (var i = 0; i < clientes; i++) {
    for (final (v, c) in [('a', a), ('b', b)]) {
      final atual = c.get(customerEntity, id(i))!;
      final campos = <String, Object>{};
      while (campos.isEmpty) {
        if (rnd.nextBool()) campos['name'] = 'Nome $v$i';
        if (rnd.nextBool()) campos['phone'] = '9999-$v$i';
        if (rnd.nextBool()) campos['creditLimit'] = v == 'a' ? 300.0 : 500.0;
      }
      final quando = t0.add(Duration(minutes: 1 + rnd.nextInt(600)));
      (feitas[id(i)] ??= {})[v] = campos;
      (horario[id(i)] ??= {})[v] = quando;
      c.edit(
        customerEntity,
        atual.copyWith(
          name: campos['name'] as String?,
          phone: campos['phone'] as String?,
          creditLimit: campos['creditLimit'] as double?,
          updatedAt: quando,
        ),
      );
    }
  }

  await Future.wait([a.sync(), b.sync()]);
  await Future.wait([a.sync(), b.sync()]);

  final servidorFinal = {
    for (final r in (await servidor.$1.pull())['Customer']!) r['id']: r,
  };
  var semColisao = 0, perdidas = 0, colisoes = 0;
  var colisoesLww = 0, lwwCorretas = 0, convergentes = 0;

  for (var i = 0; i < clientes; i++) {
    final final_ = servidorFinal[id(i)]!;
    final fa = feitas[id(i)]!['a']!, fb = feitas[id(i)]!['b']!;
    for (final campo in {...fa.keys, ...fb.keys}) {
      if (fa.containsKey(campo) && fb.containsKey(campo)) {
        colisoes++;
        if (customerFieldRules[campo] == FieldRule.lww) {
          colisoesLww++;
          final ta = horario[id(i)]!['a']!, tb = horario[id(i)]!['b']!;
          if (ta == tb) continue; // empate: qualquer um é aceitável
          final esperado = ta.isAfter(tb) ? fa[campo] : fb[campo];
          if (sameValue(final_[campo], esperado)) lwwCorretas++;
        }
      } else {
        semColisao++;
        final valor = fa[campo] ?? fb[campo];
        if (!sameValue(final_[campo], valor)) perdidas++;
      }
    }
    final ra = a.get(customerEntity, id(i))!.toJson();
    final rb = b.get(customerEntity, id(i))!.toJson();
    if (sameValue(ra, rb) && sameValue(ra, final_)) convergentes++;
  }

  return (
    clientes: clientes,
    semColisao: semColisao,
    perdidas: perdidas,
    colisoes: colisoes,
    colisoesLww: colisoesLww,
    lwwCorretas: lwwCorretas,
    convergentes: convergentes,
  );
}

// ---------------------------------------------------------------------------

/// Rede simulada entre o vendedor e o servidor: latência aleatória de até
/// [latenciaMaxMs] em cada chamada e, com probabilidade [falha], uma queda.
/// Metade das quedas acontece antes de a requisição chegar; a outra metade
/// depois de o servidor gravar, perdendo só a confirmação.
class RedeInstavel implements SyncTransport {
  final SyncTransport _servidor;
  final Random _rnd;
  final double falha;
  final int latenciaMaxMs;

  RedeInstavel(
    this._servidor,
    this._rnd, {
    this.falha = 0,
    this.latenciaMaxMs = 3,
  });

  Future<void> _latencia() =>
      Future.delayed(Duration(milliseconds: _rnd.nextInt(latenciaMaxMs + 1)));

  @override
  Future<Json> push(Mutation m) async {
    await _latencia();
    final cai = _rnd.nextDouble() < falha;
    final antes = _rnd.nextBool();
    if (cai && antes) throw const SocketException('requisição perdida');
    final r = await _servidor.push(m);
    await _latencia();
    if (cai) throw const SocketException('confirmação perdida');
    return r;
  }

  @override
  Future<Map<String, List<Json>>> pull() async {
    await _latencia();
    return _servidor.pull();
  }
}
