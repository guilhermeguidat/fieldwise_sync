import '../engine/conflict.dart';
import '../outbox/outbox.dart';
import 'sync_transport.dart';

/// Servidor de sincronização em memória.
///
/// Duplo papel:
/// - **Nos testes**, é o servidor contra o qual os dois "vendedores" sincronizam
///   (permite o cenário A/B em Dart puro, sem backend nem rede).
/// - **Como especificação executável**: implementa exatamente a lógica de
///   detecção + resolução que o backend Spring deve espelhar. É o algoritmo
///   descrito na monografia, rodando.
///
/// [strategies] escolhe a estratégia por entidade; entidade sem entrada usa
/// [fallback]. A configuração equivalente ao backend é `fieldMerge` com as
/// regras geradas de cada entidade (ver [FakeServer.withPolicy]).
class FakeServer implements SyncTransport {
  final _store = <String, Map<String, Json>>{};
  final Map<String, ConflictStrategy> strategies;
  final ConflictStrategy fallback;

  FakeServer({this.strategies = const {}, this.fallback = lww});

  /// A política gerada das anotações: `fieldMerge(regras)` em cada entidade.
  FakeServer.withPolicy(List<EntityType> entities)
    : this(strategies: {for (final e in entities) e.name: fieldMerge(e.rules)});

  @override
  Future<Json> push(Mutation m) async {
    final table = _store[m.entity] ??= {};
    final current = table[m.id];

    // Registro novo: aceita e nasce na versão 1.
    if (current == null) return table[m.id] = {...m.record, 'version': 1};

    final version = current['version'] as int;

    // Base do cliente == versão atual: sem conflito, aplica e incrementa.
    // Conflito: alguém alterou no meio. Resolve pela estratégia e incrementa.
    final winner = !hasConflict(m.baseVersion, version)
        ? m.record
        : (strategies[m.entity] ?? fallback)(m.record, current, m.base);

    return table[m.id] = {...winner, 'version': version + 1};
  }

  @override
  Future<Map<String, List<Json>>> pull() async => {
    for (final e in _store.entries) e.key: [...e.value.values],
  };
}
