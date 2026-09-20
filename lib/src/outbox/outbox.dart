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
/// Esta é a fila em memória, usada por [InMemoryDatabase]. A persistência
/// (sobreviver a fechar o app) é responsabilidade do adapter concreto —
/// ver [ILocalDatabase].
class Outbox {
  final _pending = <Mutation>[];

  void enqueue(Mutation m) => _pending.add(m);

  /// Próxima mutação a enviar, sem retirá-la: só sai da fila com [pop],
  /// depois que o servidor confirmou. Se o envio falhar, ela continua aqui
  /// e é reenviada no próximo sync (entrega ao menos uma vez).
  Mutation? peek() => _pending.isEmpty ? null : _pending.first;

  void pop() => _pending.removeAt(0);

  bool get isEmpty => _pending.isEmpty;
  int get length => _pending.length;
}
