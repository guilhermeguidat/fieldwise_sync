import '../model/product.dart';
import '../outbox/outbox.dart';

/// Abstração de persistência local (padrão Adapter — OE1).
///
/// O motor de sincronização ([SyncClient]) fala só com esta interface: não
/// sabe se está sobre memória, SQLite, Hive ou qualquer outro banco. Trocar a
/// tecnologia de armazenamento é trocar a implementação, sem tocar na lógica
/// de sync.
///
/// Cobre as duas coisas que precisam sobreviver no dispositivo: a réplica
/// local dos registros e o Outbox (mutações pendentes de envio). O Outbox
/// persistido é o que garante "venda registrada sem sinal não se perde" mesmo
/// se o app for fechado antes de sincronizar.
///
/// ponytail: API síncrona, porque o binding `sqlite3` é síncrono. Se um
/// adapter assíncrono (ex.: sqflite) for necessário, promover para Future.
abstract interface class ILocalDatabase {
  // --- réplica local ---
  Product? get(String id);
  List<Product> all();
  void put(Product p);

  // --- outbox (FIFO) ---
  void enqueue(Mutation m);

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
  final _records = <String, Product>{};
  final _outbox = Outbox();

  @override
  Product? get(String id) => _records[id];

  @override
  List<Product> all() => _records.values.toList();

  @override
  void put(Product p) => _records[p.id] = p;

  @override
  void enqueue(Mutation m) => _outbox.enqueue(m);

  @override
  Mutation? peekOutbox() => _outbox.peek();

  @override
  void popOutbox() => _outbox.pop();

  @override
  int get pendingCount => _outbox.length;
}
