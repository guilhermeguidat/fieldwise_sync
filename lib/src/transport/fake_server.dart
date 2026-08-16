import '../engine/conflict.dart';
import '../model/product.dart';
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
class FakeServer implements SyncTransport {
  final _store = <String, Product>{};
  final ConflictStrategy _strategy;

  FakeServer({ConflictStrategy strategy = lww}) : _strategy = strategy;

  @override
  Future<Product> push(Mutation m) async {
    final current = _store[m.product.id];

    // Registro novo: aceita e nasce na versão 1.
    if (current == null) {
      final saved = m.product.copyWith(version: 1);
      _store[saved.id] = saved;
      return saved;
    }

    // Base do cliente == versão atual: sem conflito, aplica e incrementa.
    if (!hasConflict(m.baseVersion, current.version)) {
      final saved = m.product.copyWith(version: current.version + 1);
      _store[saved.id] = saved;
      return saved;
    }

    // Conflito: alguém alterou no meio. Resolve pela estratégia e incrementa.
    final winner = _strategy(m.product, current);
    final saved = winner.copyWith(version: current.version + 1);
    _store[saved.id] = saved;
    return saved;
  }

  @override
  Future<List<Product>> pull() async => _store.values.toList();
}
