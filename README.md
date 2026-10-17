# fieldwise_sync

Sincronização Offline-First em Dart puro, com resolução de conflitos declarada **por entidade e
por campo**. O aplicativo grava localmente, enfileira as alterações e sincroniza quando houver rede.
Quando dois dispositivos alteram o mesmo registro, o conflito é detectado pelo número de versão e
resolvido pela política que você anotou no modelo.

Desenvolvida como Trabalho de Conclusão de Curso em Ciência da Computação (UNIFOR-MG, 2026).

## Instalação

```yaml
dependencies:
  fieldwise_sync: ^0.1.0

dev_dependencies:
  build_runner: ^2.15.1
```

O núcleo não depende de Flutter. Para usar o `SqliteDatabase` num app Flutter, acrescente
`sqlite3_flutter_libs` ao app (traz o binário nativo do SQLite).

## Uso

Declare a política na própria entidade:

```dart
import 'package:fieldwise_sync/fieldwise_sync.dart';

part 'customer.g.dart';

@SyncEntity()
class Customer implements Syncable {
  @Lww() final String name;               // colisão: vence a edição mais recente
  @Lww() final String phone;
  @ServerWins() final double creditLimit; // colisão: o servidor mantém
  // id, version, updatedAt, toJson/fromJson ...
}

@SyncEntity(defaultRule: FieldRule.serverWins) // regra da entidade para campos sem anotação
class Order implements Syncable { ... }
```

Gere a configuração (`customerEntity`, `customerFieldRules` e `lib/sync_config.json`, a mesma
política em JSON para o servidor ler):

```bash
dart run build_runner build
```

E sincronize:

```dart
final transport = await HttpTransport.login(url, usuario, senha);
final client = SyncClient(transport, db: SqliteDatabase('local.db'));

client.edit(customerEntity, maria.copyWith(phone: '2222', updatedAt: DateTime.now().toUtc()));
await client.sync(); // envia a fila (remove só após confirmação) e puxa o estado do servidor
```

O `example/` roda dois clientes contra o servidor em memória e mostra a mesclagem por campo. O
domínio de demonstração (`Product`, `Customer`, `Order`) está em `example/pdv/` e serve de modelo
para declarar as próprias entidades: o pacote em si não traz entidade nenhuma.

## Como funciona

- **Detecção** por número de versão (`hasConflict`), nunca por relógio: o relógio de um celular
  não ordena eventos entre dispositivos. `updatedAt` só desempata dentro do LWW.
- **Resolução** por estratégia injetável: `lww`, `serverWins` (registro inteiro) ou `fieldMerge`
  (por campo, três vias: campo que só um lado alterou passa sem disputa; a regra só arbitra quando
  os dois alteraram o mesmo campo).
- **Outbox**: `edit` grava e enfileira na mesma transação; `sync` só retira da fila depois da
  confirmação do servidor, então uma falha no meio do envio não perde a alteração.
- **Adapter**: `ILocalDatabase`, com `InMemoryDatabase` e `SqliteDatabase` (pacote `sqlite3`, FFI).
- **Transporte**: `SyncTransport`, com `HttpTransport` e `FakeServer`. O `FakeServer` é a
  especificação executável do protocolo: um servidor em outra linguagem deve se comportar como ele.

## Protocolo do servidor

`HttpTransport` fala com dois endpoints autenticados por JWT (`POST /auth/login`):

- `POST /sync/push`: recebe mutações `{entity, record, baseVersion, base}` e aplica a política.
- `GET /sync/pull`: devolve o estado atual de cada entidade, com a versão de cada registro.

A implementação de referência, em Spring Boot, está em [`example/server/`](example/server/) e lê a
política direto do `sync_config.json` gerado, de modo que cliente e servidor nunca divergem nas
regras.

## Testes

```bash
dart test                                # suíte rápida, sem rede
RUN_E2E=1 dart test -t e2e               # contra um servidor real no ar
dart run tool/experimentos.dart [--http] # perda e convergência sob falha de rede
```

## Licença

MIT
