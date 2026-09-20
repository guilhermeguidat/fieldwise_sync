import 'adapter/local_database.dart';
import 'model/product.dart';
import 'outbox/outbox.dart';
import 'transport/sync_transport.dart';

/// O cliente de sincronização que roda em cada dispositivo (cada "vendedor").
///
/// Fluxo Offline-First:
/// - [edit] grava no banco local e enfileira no Outbox — funciona sem rede.
/// - [sync] drena o Outbox para o servidor, aplica o estado resolvido e
///   puxa de volta a fonte da verdade. O servidor é a autoridade após o sync.
///
/// Só conhece [ILocalDatabase] (onde persistir) e [SyncTransport] (com quem
/// falar). Trocar banco ou servidor não toca nesta classe.
class SyncClient {
  final SyncTransport _transport;
  final ILocalDatabase _db;

  SyncClient(this._transport, {ILocalDatabase? db})
    : _db = db ?? InMemoryDatabase();

  Product? get(String id) => _db.get(id);
  List<Product> get all => _db.all();
  int get pending => _db.pendingCount;

  /// Edição offline. [desired] carrega os novos valores (name/price/updatedAt);
  /// a versão base é a que o cliente conhece hoje (0 se o registro é novo).
  void edit(Product desired) {
    final base = _db.get(desired.id)?.version ?? 0;
    _db.put(desired);
    _db.enqueue(Mutation(desired, base));
  }

  /// Sincroniza com o servidor: envia pendências, aplica o que voltou
  /// resolvido e puxa o estado atual.
  ///
  /// Cada mutação só sai do Outbox depois que o servidor a confirmou. Se o
  /// envio falhar no meio, o que não foi confirmado fica na fila e é
  /// reenviado no próximo [sync] — nada se perde (OE2).
  Future<void> sync() async {
    for (var m = _db.peekOutbox(); m != null; m = _db.peekOutbox()) {
      final resolved = await _transport.push(m);
      _db.put(resolved);
      _db.popOutbox();
    }
    for (final p in await _transport.pull()) {
      _db.put(p);
    }
  }
}
