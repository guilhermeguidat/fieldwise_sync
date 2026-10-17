/// Quem vence um campo que cliente e servidor alteraram, no `fieldMerge`.
enum FieldRule {
  /// Vence o `updatedAt` mais recente.
  lww,

  /// Vence o servidor.
  serverWins,

  /// Vence o cliente.
  clientWins,
}
