/// Anotações que configuram a resolução de conflitos de forma **declarativa**,
/// direto na entidade. São lidas em tempo de build por um gerador (source_gen)
/// que produz o mapa `{campo: FieldRule}` consumido por `fieldMerge`.
///
/// É a ergonomia do OE3: o desenvolvedor descreve a política de conflito onde
/// o dado é declarado, sem escrever o mapa à mão.
///
/// ```dart
/// @SyncEntity()
/// class Product {
///   @Lww() final String name;        // campo segue Last-Write-Wins
///   @ServerWins() final double price; // servidor é autoridade neste campo
/// }
/// ```
library;

/// Marca uma classe como entidade sincronizável. O gerador emite o mapa de
/// regras (`<nome>FieldRules`) a partir das anotações de campo dela.
class SyncEntity {
  const SyncEntity();
}

/// Campo resolvido por Last-Write-Wins (vence o `updatedAt` mais recente).
class Lww {
  const Lww();
}

/// Campo em que o valor do servidor sempre prevalece.
class ServerWins {
  const ServerWins();
}

/// Campo em que o valor que chega (cliente) sempre prevalece.
class ClientWins {
  const ClientWins();
}
