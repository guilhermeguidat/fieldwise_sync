import '../engine/entity.dart';
import '../outbox/outbox.dart';

/// Abstração de persistência local (padrão Adapter — OE1).
///
/// O motor de sincronização (`SyncClient`) fala só com esta interface: não
/// sabe se está sobre memória, SQLite, Hive ou qualquer outro banco. Trocar a
/// tecnologia de armazenamento é trocar a implementação, sem tocar na lógica
/// de sync.
///
/// Cobre as duas coisas que precisam sobreviver no dispositivo: a réplica
/// local dos registros e o Outbox (mutações pendentes de envio). O Outbox
/// persistido é o que garante "venda registrada sem sinal não se perde" mesmo
/// se o app for fechado antes de sincronizar.
///
/// Registros são guardados como [Json] e endereçados por (entidade, id): o
/// adapter não conhece nenhuma classe de modelo.
///
/// ponytail: API síncrona, porque o binding `sqlite3` é síncrono. Se um
/// adapter assíncrono (ex.: sqflite) for necessário, promover para Future.
abstract interface class ILocalDatabase {
  // --- réplica local ---
  Json? get(String entity, String id);
  List<Json> all(String entity);
  void put(String entity, Json record);

  // --- outbox (FIFO) ---

  /// Grava `m.record` na réplica e enfileira [m] **atomicamente** (padrão
  /// Outbox): se o app morrer no meio, ou ficam os dois ou nenhum. Gravar sem
  /// enfileirar deixaria uma edição no aparelho que nunca seria enviada.
  void saveAndEnqueue(Mutation m);

  /// Próxima mutação a enviar, sem retirá-la. Só sai com [popOutbox], após o
  /// servidor confirmar — se o envio falhar, permanece para a próxima
  /// tentativa. É o que dá a garantia "ao menos uma vez" do Outbox.
  Mutation? peekOutbox();
  void popOutbox();
  int get pendingCount;
}

/// Implementação em memória: a mais simples possível e a usada nos testes
/// rápidos. Também serve de referência de comportamento para os adapters
/// concretos — o mesmo cenário deve produzir o mesmo resultado em qualquer um.
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
