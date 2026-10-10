import 'entity.dart';
import 'field_rule.dart';

export 'entity.dart';
export 'field_rule.dart';

/// O motor de conflitos — o núcleo acadêmico da biblioteca.
///
/// Duas responsabilidades separadas de propósito:
/// 1. **Detecção** ([hasConflict]): puramente por número de versão.
/// 2. **Resolução** ([ConflictStrategy]): decide o vencedor. Acrescentar uma
///    estratégia não toca na detecção nem no orquestrador — por isso a
///    estratégia é um ponto de extensão (função injetável, padrão Strategy).
///
/// Tudo opera sobre o JSON do registro ([Json]), então o mesmo motor serve a
/// qualquer entidade.

/// Houve conflito? Sim quando a versão em que o cliente baseou a edição
/// diverge da versão atual no servidor (alguém alterou no meio do caminho).
bool hasConflict(int clientBaseVersion, int serverVersion) =>
    clientBaseVersion != serverVersion;

/// Uma estratégia recebe o registro que chega, o estado atual do servidor e
/// [base]: os valores que o cliente via, antes de editar, **nos campos que ele
/// alterou** (as chaves de [base] são o conjunto de campos alterados). Devolve
/// o registro vencedor, ainda sem renumerar a versão (isso é de quem persiste).
///
/// As estratégias de registro inteiro ([lww], [serverWins]) ignoram [base]; o
/// [fieldMerge] precisa dele para separar edição concorrente de colisão real.
typedef ConflictStrategy =
    Json Function(Json incoming, Json current, Json base);

/// Last Write Wins: vence o registro inteiro com o `updatedAt` mais recente.
/// Empate de timestamp resolve a favor do estado já no servidor (estável).
Json lww(Json incoming, Json current, Json base) =>
    _isNewer(incoming, current) ? incoming : current;

/// Server Wins: o estado no servidor sempre prevalece; a edição que chega é
/// descartada quando há conflito. Útil para dados "autoridade do servidor"
/// (preço tabelado, estoque central) onde a cópia local não deve sobrescrever.
Json serverWins(Json incoming, Json current, Json base) => current;

/// Field-Level Merge (mesclagem de três vias, por campo). Para cada campo:
///
/// 1. o cliente não alterou → fica o valor do servidor;
/// 2. o cliente alterou e o servidor não (o valor atual ainda é o que o cliente
///    via em [base]) → fica o do cliente. Edições concorrentes em campos
///    diferentes **se somam**, nenhuma se perde;
/// 3. os dois alteraram o mesmo campo → **colisão real**, decidida pela
///    [FieldRule] daquele campo.
///
/// É a granularidade do OE3: na mesma entidade, `name` pode seguir LWW enquanto
/// `price` segue Server Wins. Campos sem regra explícita usam [fallback].
///
/// ponytail: o LWW por campo compara o `updatedAt` do *registro* (não temos
/// timestamp por campo). Só pesa no caso 3; se granularidade temporal por campo
/// virar requisito, o passo é carregar um `updatedAt` por campo.
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

/// Campos que [edited] mudou em relação a [before], com o valor anterior: o
/// `base` de uma mutação. `version` é do servidor e não entra. Registro novo
/// ([before] nulo) não tem base.
Json changedFields(Json? before, Json edited) => {
  if (before != null)
    for (final f in edited.keys)
      if (f != 'version' && !sameValue(before[f], edited[f])) f: before[f],
};

/// Igualdade de valores JSON. `50 == 50.0` (o mesmo preço pode voltar do
/// servidor como double), listas e mapas comparados por conteúdo.
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
