/// Regra de resolução para **um** campo, no Field-Level Merge.
///
/// Fica em arquivo próprio (sem dependências) para poder ser importado tanto
/// pelo motor ([fieldMerge]) quanto pelo `Product` — que passa a ter um `part`
/// gerado a partir das anotações. Sem isso haveria import circular.
enum FieldRule {
  /// Vence o campo de quem tem o `updatedAt` mais recente.
  lww,

  /// O valor do servidor prevalece neste campo.
  serverWins,

  /// O valor que chega (cliente) prevalece neste campo.
  clientWins,
}
