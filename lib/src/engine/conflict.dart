import '../model/product.dart';

/// O motor de conflitos — o núcleo acadêmico da biblioteca.
///
/// Duas responsabilidades separadas de propósito:
/// 1. **Detecção** ([hasConflict]): puramente por número de versão.
/// 2. **Resolução** ([ConflictStrategy]): decide o vencedor. Na Fase 1 só
///    existe LWW; a Fase 2 acrescenta Server Wins e Field-Level Merge sem
///    tocar na detecção nem no orquestrador — por isso a estratégia é um
///    ponto de extensão (função injetável, padrão Strategy).

/// Houve conflito? Sim quando a versão em que o cliente baseou a edição
/// diverge da versão atual no servidor (alguém alterou no meio do caminho).
bool hasConflict(int clientBaseVersion, int serverVersion) =>
    clientBaseVersion != serverVersion;

/// Uma estratégia recebe a mutação que chega e o estado atual do servidor,
/// e devolve o registro vencedor (ainda sem renumerar a versão — isso é
/// responsabilidade de quem persiste).
typedef ConflictStrategy = Product Function(Product incoming, Product current);

/// Last Write Wins: vence quem tem o [updatedAt] mais recente.
/// Empate de timestamp resolve a favor do estado já no servidor (estável).
Product lww(Product incoming, Product current) =>
    incoming.updatedAt.isAfter(current.updatedAt) ? incoming : current;

/// Server Wins: o estado no servidor sempre prevalece; a edição que chega é
/// descartada quando há conflito. Útil para dados "autoridade do servidor"
/// (preço tabelado, estoque central) onde a cópia local não deve sobrescrever.
Product serverWins(Product incoming, Product current) => current;

/// Regra de resolução para **um** campo, no merge granular.
enum FieldRule {
  /// Vence o campo de quem tem o [Product.updatedAt] mais recente.
  lww,

  /// O valor do servidor prevalece neste campo.
  serverWins,

  /// O valor que chega (cliente) prevalece neste campo.
  clientWins,
}

/// Field-Level Merge: resolve **campo a campo**, cada um pela sua [FieldRule].
/// É a granularidade que dá nome ao OE3 — na mesma entidade, `name` pode seguir
/// LWW enquanto `price` segue Server Wins.
///
/// Genérico via JSON: opera sobre `toJson()`/`fromJson` do [Product], sem
/// reflection nem codegen. Campos sem regra explícita usam [fallback].
///
/// ponytail: o LWW por campo compara o `updatedAt` do *registro* (não temos
/// timestamp por campo). Se granularidade temporal por campo virar requisito,
/// o passo é carregar um `updatedAt` por campo — a assinatura da regra não muda.
ConflictStrategy fieldMerge(
  Map<String, FieldRule> rules, {
  FieldRule fallback = FieldRule.lww,
}) {
  return (Product incoming, Product current) {
    final inc = incoming.toJson();
    final cur = current.toJson();
    final incomingIsNewer = incoming.updatedAt.isAfter(current.updatedAt);

    final merged = <String, dynamic>{};
    for (final field in cur.keys) {
      final rule = rules[field] ?? fallback;
      merged[field] = switch (rule) {
        FieldRule.serverWins => cur[field],
        FieldRule.clientWins => inc[field],
        FieldRule.lww => incomingIsNewer ? inc[field] : cur[field],
      };
    }
    return Product.fromJson(merged);
  };
}
