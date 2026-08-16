import 'model/product.dart';
import 'outbox/outbox.dart';
import 'transport/sync_transport.dart';

/// O cliente de sincronização que roda em cada dispositivo (cada "vendedor").
///
/// Fluxo Offline-First:
/// - [edit] grava no store local e enfileira no Outbox — funciona sem rede.
/// - [sync] drena o Outbox para o servidor, aplica o estado resolvido e
///   puxa de volta a fonte da verdade. O servidor é a autoridade após o sync.
class SyncClient {
  final SyncTransport _transport;

  // ponytail: store local em memória; vira adapter ILocalDatabase (SQLite)
  // na Fase 3, sem mexer nesta classe.
  final _local = <String, Product>{};
  final _outbox = Outbox();

  SyncClient(this._transport);

  Product? get(String id) => _local[id];
  List<Product> get all => _local.values.toList();
  int get pending => _outbox.length;

  /// Edição offline. [desired] carrega os novos valores (name/price/updatedAt);
  /// a versão base é a que o cliente conhece hoje (0 se o registro é novo).
  void edit(Product desired) {
    final base = _local[desired.id]?.version ?? 0;
    _local[desired.id] = desired;
    _outbox.enqueue(Mutation(desired, base));
  }

  /// Sincroniza com o servidor: envia pendências, aplica o que voltou
  /// resolvido e puxa o estado atual.
  Future<void> sync() async {
    for (final m in _outbox.drain()) {
      final resolved = await _transport.push(m);
      _local[resolved.id] = resolved;
    }
    for (final p in await _transport.pull()) {
      _local[p.id] = p;
    }
  }
}
