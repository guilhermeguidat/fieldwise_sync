import 'adapter/local_database.dart';
import 'engine/conflict.dart';
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
/// falar). Trocar banco ou servidor não toca nesta classe. Também não conhece
/// nenhuma entidade: recebe o [EntityType] gerado de cada uma.
class SyncClient {
  final SyncTransport _transport;
  final ILocalDatabase _db;

  SyncClient(this._transport, {ILocalDatabase? db})
    : _db = db ?? InMemoryDatabase();

  T? get<T extends Syncable>(EntityType<T> type, String id) {
    final json = _db.get(type.name, id);
    return json == null ? null : type.fromJson(json);
  }

  List<T> all<T extends Syncable>(EntityType<T> type) =>
      _db.all(type.name).map(type.fromJson).toList();

  int get pending => _db.pendingCount;

  /// Edição (ou criação) offline. A versão base é a que o cliente conhece
  /// hoje (0 se o registro é novo); o `base` da mutação guarda o valor
  /// anterior de cada campo alterado, para o servidor separar edição
  /// concorrente de colisão real.
  void edit<T extends Syncable>(EntityType<T> type, T desired) {
    final before = _db.get(type.name, desired.id);
    final record = desired.toJson();
    _db.put(type.name, record);
    _db.enqueue(
      Mutation(
        type.name,
        record,
        before?['version'] as int? ?? 0,
        changedFields(before, record),
      ),
    );
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
      _db.put(m.entity, resolved);
      _db.popOutbox();
    }
    for (final e in (await _transport.pull()).entries) {
      for (final r in e.value) {
        _db.put(e.key, r);
      }
    }
  }
}
