import '../engine/entity.dart';

/// Edição local pendente: o registro desejado, a versão em que se baseou e
/// [base], o valor anterior de cada campo alterado.
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

/// Fila FIFO de [Mutation]s em memória, usada pelo `InMemoryDatabase`.
class Outbox {
  final _pending = <Mutation>[];

  void enqueue(Mutation m) => _pending.add(m);

  /// Próxima mutação, sem retirá-la (ver `ILocalDatabase.peekOutbox`).
  Mutation? peek() => _pending.isEmpty ? null : _pending.first;

  void pop() => _pending.removeAt(0);

  bool get isEmpty => _pending.isEmpty;
  int get length => _pending.length;
}
