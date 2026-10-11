## 0.1.0

- Primeira versão publicada.
- Detecção de conflito por número de versão; `updatedAt` só desempata no LWW.
- Estratégias `lww`, `serverWins` e `fieldMerge` (três vias, regra por campo).
- Política declarada por anotação (`@SyncEntity`, `@Lww`, `@ServerWins`, `@ClientWins`) e gerada
  por `build_runner`, incluindo `lib/sync_config.json` para o servidor no pacote que declara as
  entidades.
- Domínio de demonstração (PDV) em `example/`, fora da API publicada.
- Outbox com remoção só após confirmação; gravação e enfileiramento na mesma transação.
- Adapters `InMemoryDatabase` e `SqliteDatabase`; transportes `HttpTransport` e `FakeServer`.
