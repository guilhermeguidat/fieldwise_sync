package fieldwise.server;

import tools.jackson.core.type.TypeReference;
import tools.jackson.databind.ObjectMapper;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.io.Resource;
import org.springframework.stereotype.Component;

import java.io.IOException;
import java.util.Map;

/// Política de conflito lida de `sync_config.json`, gerado pelo `build_runner`
/// a partir das anotações. O arquivo precisa estar no classpath (ex.:
/// `src/main/resources/`).
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

    /// Se a entidade está na política; o `/sync/push` rejeita as demais.
    public boolean knows(String entity) {
        return config.entities().containsKey(entity);
    }

    /// Regra do campo. O `default` só cobre os campos de protocolo, como
    /// `updatedAt`.
    public FieldRule ruleFor(String entity, String field) {
        return config.entities()
                .getOrDefault(entity, Map.of())
                .getOrDefault(field, config.defaultRule());
    }
}
