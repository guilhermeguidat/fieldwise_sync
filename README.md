# sync_lib

Biblioteca de sincronização Offline-First em Dart puro, com resolução de conflitos declarada por
entidade e por campo. Núcleo do TCC (ver `../PLANO.md` e `../docs/decisoes/`).

## Uso

Declare a política na própria entidade:

```dart
@SyncEntity()
class Customer implements Syncable {
  @Lww() final String name;            // colisão: vence a edição mais recente
  @Lww() final String phone;
  @ServerWins() final double creditLimit; // colisão: o servidor mantém
  // id, version, updatedAt ...
}

@SyncEntity(defaultRule: FieldRule.serverWins) // regra da entidade
class Order implements Syncable { ... }
```

Gere a configuração (`customerEntity`, `customerFieldRules` e `lib/sync_config.json` para o
servidor):

```bash
dart run build_runner build
```

E sincronize:

```dart
final transport = await HttpTransport.login(url, 'vendedor_a', 'senha');
final client = SyncClient(transport, db: SqliteDatabase('local.db'));

client.edit(customerEntity, maria.copyWith(phone: '2222', updatedAt: DateTime.now().toUtc()));
await client.sync(); // envia a fila (remove só após confirmação) e puxa o estado do servidor
```

## Como funciona

- **Detecção** por número de versão (`hasConflict`), nunca por relógio.
- **Resolução** por estratégia injetável: `lww`, `serverWins` (registro inteiro) ou `fieldMerge`
  (por campo, três vias: campo que só um lado alterou passa; a regra só arbitra colisão real).
- **Outbox**: `edit` grava e enfileira; `sync` só retira da fila depois do ack do servidor.
- **Adapter**: `ILocalDatabase` com `InMemoryDatabase` e `SqliteDatabase` (pacote `sqlite3`, FFI).
- **Transporte**: `SyncTransport` com `HttpTransport` e `FakeServer`, a especificação executável do
  protocolo que o backend espelha.

## Testes e experimentos

```bash
dart test                               # suíte rápida, sem rede
RUN_E2E=1 dart test -t e2e              # contra o backend real (Postgres + Spring no ar)
dart run tool/experimentos.dart [--http] # Fase 5: perda e convergência sob falha de rede
```
