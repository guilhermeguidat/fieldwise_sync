import '../engine/conflict.dart';
import '../outbox/outbox.dart';
import 'sync_transport.dart';

/// Servidor em memória, para testar sem rede. É a especificação executável do
/// protocolo: um servidor HTTP compatível deve se comportar como ele.
///
/// [strategies] define a estratégia por entidade; as demais usam [fallback].
class FakeServer implements SyncTransport {
  final _store = <String, Map<String, Json>>{};
  final Map<String, ConflictStrategy> strategies;
  final ConflictStrategy fallback;

  FakeServer({this.strategies = const {}, this.fallback = lww});

  /// `fieldMerge` com as regras geradas de cada entidade.
  FakeServer.withPolicy(List<EntityType> entities)
    : this(strategies: {for (final e in entities) e.name: fieldMerge(e.rules)});

  @override
  Future<Json> push(Mutation m) async {
    final table = _store[m.entity] ??= {};
    final current = table[m.id];

    // Registro novo nasce na versão 1.
    if (current == null) return table[m.id] = {...m.record, 'version': 1};

    final version = current['version'] as int;

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
