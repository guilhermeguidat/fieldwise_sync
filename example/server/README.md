# Servidor de referência (Spring Boot)

Implementação do protocolo da `fieldwise_sync` em Spring Boot 4 + JPA. Espelha o `FakeServer`, a
especificação executável: detecção por versão e mesclagem de três vias com a política por campo
lida do `sync_config.json` gerado pelo `build_runner`.

| Arquivo | Papel |
|---|---|
| `SyncController.java` | `POST /sync/push` (detecta e resolve) e `GET /sync/pull` |
| `SyncPolicy.java` | lê `sync_config.json` do classpath |
| `FieldRule.java` | as regras (`LWW`, `SERVER_WINS`, `CLIENT_WINS`) |
| `SyncRecord.java`, `SyncRecordRepository.java` | tabela `sync_records (entity, id, json)` |

Para usar no seu projeto:

1. Copie os cinco arquivos (pacote `fieldwise.server`) e registre o pacote na aplicação:

   ```java
   @SpringBootApplication(scanBasePackages = {"com.suaempresa", "fieldwise.server"})
   @AutoConfigurationPackage(basePackages = "fieldwise.server")
   public class Application { ... }
   ```

2. Copie o `lib/sync_config.json` gerado no pacote Dart que declara as entidades para
   `src/main/resources/`. Mudou uma anotação: rode o `build_runner`, copie de novo e reinicie.

3. Proteja `/sync/**` com a autenticação da sua aplicação. O `HttpTransport` envia
   `Authorization: Bearer <token>`.

Dependências: `spring-boot-starter-webmvc`, `spring-boot-starter-data-jpa` e o driver do banco.

Outra persistência (tabelas por entidade, outro banco) serve, desde que a leitura do registro atual
trave a linha dentro da transação do push, como faz `findForUpdate`. Sem a trava, dois pushes
simultâneos leem a mesma versão e o segundo sobrescreve o primeiro sem passar pela detecção.
