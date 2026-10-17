import 'entity.dart';
import 'field_rule.dart';

export 'entity.dart';
export 'field_rule.dart';

// Detecção (hasConflict) e resolução (ConflictStrategy) são separadas: uma
// estratégia nova não toca na detecção nem no SyncClient.

/// Há conflito quando a versão em que o cliente baseou a edição não é mais a
/// do servidor.
bool hasConflict(int clientBaseVersion, int serverVersion) =>
    clientBaseVersion != serverVersion;

/// Resolve um conflito a partir do registro que chega, do atual no servidor e
/// de `base` (valor anterior de cada campo que o cliente alterou). Devolve o
/// vencedor; renumerar a versão é de quem persiste.
typedef ConflictStrategy =
    Json Function(Json incoming, Json current, Json base);

/// Last Write Wins por registro: vence o `updatedAt` mais recente; no empate,
/// o servidor. Ignora `base`.
Json lww(Json incoming, Json current, Json base) =>
    _isNewer(incoming, current) ? incoming : current;

/// O servidor sempre vence. Ignora `base`.
Json serverWins(Json incoming, Json current, Json base) => current;

/// Mesclagem de três vias por campo: o campo que só um lado alterou fica com
/// esse lado; o que os dois alteraram é decidido por `rules[campo]` (ou
/// [fallback]).
/// O LWW por campo compara o `updatedAt` do registro inteiro.
ConflictStrategy fieldMerge(
  Map<String, FieldRule> rules, {
  FieldRule fallback = FieldRule.lww,
}) {
  return (Json incoming, Json current, Json base) {
    final incomingIsNewer = _isNewer(incoming, current);
    return {
      for (final field in current.keys)
        field: !base.containsKey(field)
            ? current[field]
            : sameValue(current[field], base[field])
            ? incoming[field]
            : switch (rules[field] ?? fallback) {
                FieldRule.serverWins => current[field],
                FieldRule.clientWins => incoming[field],
                FieldRule.lww =>
                  incomingIsNewer ? incoming[field] : current[field],
              },
    };
  };
}

/// Campos de [edited] que diferem de [before], com o valor anterior (o `base`
/// de uma `Mutation`). Ignora `version`; vazio se [before] é nulo.
Json changedFields(Json? before, Json edited) => {
  if (before != null)
    for (final f in edited.keys)
      if (f != 'version' && !sameValue(before[f], edited[f])) f: before[f],
};

/// Igualdade de valores JSON por conteúdo, com `50 == 50.0`.
bool sameValue(Object? a, Object? b) {
  if (a is num && b is num) return a == b;
  if (a is List && b is List) {
    return a.length == b.length &&
        Iterable.generate(a.length).every((i) => sameValue(a[i], b[i]));
  }
  if (a is Map && b is Map) {
    return a.length == b.length &&
        a.keys.every((k) => b.containsKey(k) && sameValue(a[k], b[k]));
  }
  return a == b;
}

bool _isNewer(Json a, Json b) => DateTime.parse(
  a['updatedAt'] as String,
).isAfter(DateTime.parse(b['updatedAt'] as String));
