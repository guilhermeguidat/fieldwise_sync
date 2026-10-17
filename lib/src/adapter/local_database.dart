import '../engine/entity.dart';
import '../outbox/outbox.dart';

/// Persistência local: a réplica dos registros, por (entidade, id), e o
/// Outbox. Implemente-a para usar outro banco. A API é síncrona.
abstract interface class ILocalDatabase {
  Json? get(String entity, String id);
  List<Json> all(String entity);
  void put(String entity, Json record);

  /// Grava `m.record` e enfileira [m] atomicamente: edição gravada sem
  /// enfileirar nunca seria enviada.
  void saveAndEnqueue(Mutation m);

  /// Próxima mutação a enviar, sem retirá-la. [popOutbox] só depois da
  /// resposta do servidor: entrega ao menos uma vez.
  Mutation? peekOutbox();
  void popOutbox();
  int get pendingCount;
}

/// [ILocalDatabase] em memória, sem persistência. Útil em testes.
class InMemoryDatabase implements ILocalDatabase {
  final _records = <String, Map<String, Json>>{};
  final _outbox = Outbox();

  @override
  Json? get(String entity, String id) => _records[entity]?[id];

  @override
  List<Json> all(String entity) => [...?_records[entity]?.values];

  @override
  void put(String entity, Json record) =>
      (_records[entity] ??= {})[record['id'] as String] = record;

  @override
  void saveAndEnqueue(Mutation m) {
    put(m.entity, m.record);
    _outbox.enqueue(m);
  }

  @override
  Mutation? peekOutbox() => _outbox.peek();

  @override
  void popOutbox() => _outbox.pop();

  @override
  int get pendingCount => _outbox.length;
}
