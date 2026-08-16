import '../model/product.dart';

/// Uma mutação local pendente de envio: o estado que o cliente quer gravar
/// mais a versão em que ele se baseou (a "base" da detecção de conflito).
class Mutation {
  final Product product;
  final int baseVersion;

  const Mutation(this.product, this.baseVersion);
}

/// Outbox Pattern: fila local que retém as mutações feitas offline até o
/// dispositivo conseguir sincronizar. Garante que nenhuma alteração se perca
/// entre "usuário salvou" e "servidor recebeu".
///
/// ponytail: fila em memória por enquanto; na Fase 3 o Outbox passa a
/// persistir no store local (SQLite) para sobreviver a fechar o app.
class Outbox {
  final _pending = <Mutation>[];

  void enqueue(Mutation m) => _pending.add(m);

  /// Retira tudo que está pendente para envio (esvazia a fila).
  List<Mutation> drain() {
    final copy = List<Mutation>.from(_pending);
    _pending.clear();
    return copy;
  }

  bool get isEmpty => _pending.isEmpty;
  int get length => _pending.length;
}
