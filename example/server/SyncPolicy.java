package fieldwise.server;

import tools.jackson.core.type.TypeReference;
import tools.jackson.databind.ObjectMapper;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.io.Resource;
import org.springframework.stereotype.Component;

import java.io.IOException;
import java.util.Map;

/// Política de resolução de conflitos, lida de `sync_config.json` — o arquivo
/// que o codegen da fieldwise_sync gera a partir das anotações do modelo Dart
/// (ADR 0002). O servidor não escreve política nenhuma à mão: só obedece.
///
/// O arquivo precisa estar no classpath (ex.: `src/main/resources/`). Mudou a
/// anotação: `build_runner`, copiar o JSON e reiniciar o servidor.
@Component
public class SyncPolicy {

    /// Espelha o formato do JSON: `{ "default": ..., "entities": { E: { campo: regra } } }`.
    private record Config(FieldRule defaultRule, Map<String, Map<String, FieldRule>> entities) {}

    private final Config config;

    public SyncPolicy(@Value("classpath:sync_config.json") Resource file, ObjectMapper json)
            throws IOException {
        var tree = json.readTree(file.getInputStream());
        this.config = new Config(
                FieldRule.valueOf(tree.get("default").asText()),
                json.convertValue(tree.get("entities"), new TypeReference<>() {}));
    }

    /// A entidade está na política? Só entidades `@SyncEntity` da lib são
    /// aceitas pelo `/sync/push`.
    public boolean knows(String entity) {
        return config.entities().containsKey(entity);
    }

    /// Regra do campo. A política gerada já vem resolvida (anotação do campo
    /// ou `defaultRule` da entidade); o `default` global só cobre os campos de
    /// protocolo, como `updatedAt` (mesmo fallback do `fieldMerge` na lib).
    public FieldRule ruleFor(String entity, String field) {
        return config.entities()
                .getOrDefault(entity, Map.of())
                .getOrDefault(field, config.defaultRule());
    }
}
