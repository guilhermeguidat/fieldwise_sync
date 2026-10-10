import '../engine/entity.dart';

/// Uma mutação local pendente de envio: o estado que o cliente quer gravar,
/// a versão em que ele se baseou (detecção de conflito) e [base], os valores
/// anteriores dos campos que ele alterou (resolução por campo, ver
/// `fieldMerge`).
class Mutation {
  final String entity;
  final Json record;
  final int baseVersion;
  final Json base;

  const Mutation(
    this.entity,
    this.record,
    this.baseVersion, [
    this.base = const {},
  ]);

  String get id => record['id'] as String;

  Json toJson() => {
    'entity': entity,
    'record': record,
    'baseVersion': baseVersion,
    'base': base,
  };

  factory Mutation.fromJson(Json j) => Mutation(
    j['entity'] as String,
    j['record'] as Json,
    j['baseVersion'] as int,
    j['base'] as Json,
  );
}

/// Outbox Pattern: fila local que retém as mutações feitas offline até o
/// dispositivo conseguir sincronizar. Garante que nenhuma alteração se perca
/// entre "usuário salvou" e "servidor recebeu".
///
/// Esta é a fila em memória, usada por `InMemoryDatabase`. A persistência
/// (sobreviver a fechar o app) é responsabilidade do adapter concreto —
/// ver `ILocalDatabase`.
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
