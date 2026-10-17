package fieldwise.server;

import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;
import org.springframework.http.HttpStatus;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.ObjectMapper;
import tools.jackson.databind.node.ObjectNode;

/// Endpoints de sincronização. Espelha exatamente a lógica do FakeServer da
/// fieldwise_sync (que é a especificação executável do protocolo — ver ADR 0001 e
/// 0003): detecção por versão + resolução configurável por campo
/// (Field-Level Merge de três vias). Não conhece nenhuma entidade: a política
/// de cada uma vem de `sync_config.json`.
@RestController
@RequestMapping("/sync")
public class SyncController {

    /// Uma mutação: o estado desejado, a versão em que o cliente baseou a
    /// edição (detecção) e `base`, o valor anterior de cada campo que ele
    /// alterou (resolução por campo). É o `Mutation.toJson()` da lib.
    public record PushRequest(String entity, ObjectNode record, long baseVersion, ObjectNode base) {
    }

    private final SyncRecordRepository repo;
    private final SyncPolicy policy;
    private final ObjectMapper json;

    public SyncController(SyncRecordRepository repo, SyncPolicy policy, ObjectMapper json) {
        this.repo = repo;
        this.policy = policy;
        this.json = json;
    }

    @PostMapping("/push")
    @Transactional
    public JsonNode push(@RequestBody PushRequest req) {
        if (!policy.knows(req.entity())) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "entidade desconhecida: " + req.entity());
        }
        String id = req.record().get("id").asText();
        // Registro novo disputado por dois pushes: os dois veem "não existe", o
        // segundo INSERT falha na chave primária e o cliente reenvia no próximo
        // sync, já como conflito. Nada se perde.
        ObjectNode current = repo.findForUpdate(req.entity(), id)
                .map(r -> (ObjectNode) json.readTree(r.getJson()))
                .orElse(null);

        ObjectNode saved;
        if (current == null) {
            // registro novo: nasce na versão 1
            saved = req.record().deepCopy().put("version", 1);
        } else {
            long version = current.get("version").asLong();
            ObjectNode winner = req.baseVersion() == version
                    ? req.record() // sem conflito: aplica
                    : merge(req.entity(), req.record(), current, // conflito: resolve campo a campo
                            req.base() == null ? json.createObjectNode() : req.base());
            saved = winner.deepCopy().put("version", version + 1);
        }

        repo.save(new SyncRecord(req.entity(), id, json.writeValueAsString(saved)));
        return saved;
    }

    @GetMapping("/pull")
    public Map<String, List<JsonNode>> pull() {
        return repo.findAll().stream().collect(Collectors.groupingBy(
                SyncRecord::getEntity,
                Collectors.mapping(r -> json.readTree(r.getJson()), Collectors.toList())));
    }

    /// Field-Level Merge de três vias, campo a campo (espelha `fieldMerge`):
    /// cliente não alterou -> servidor; só o cliente alterou -> cliente;
    /// os dois alteraram -> a regra que a política (gerada das anotações Dart)
    /// define para o campo. O LWW usa o updatedAt do registro (mesma limitação
    /// assumida na lib).
    private ObjectNode merge(String entity, ObjectNode incoming, ObjectNode current, ObjectNode base) {
        boolean incomingNewer = updatedAt(incoming).isAfter(updatedAt(current));
        ObjectNode merged = current.deepCopy();
        for (var field : current.properties()) {
            String name = field.getKey();
            if (!base.has(name)) {
                continue; // cliente não mexeu
            }
            boolean onlyClientChanged = same(field.getValue(), base.get(name));
            if (onlyClientChanged || useIncoming(policy.ruleFor(entity, name), incomingNewer)) {
                merged.set(name, incoming.get(name));
            }
        }
        return merged;
    }

    private static boolean useIncoming(FieldRule rule, boolean incomingNewer) {
        return switch (rule) {
            case SERVER_WINS -> false;
            case CLIENT_WINS -> true;
            case LWW -> incomingNewer;
        };
    }

    /// Igualdade de valores JSON com 50 == 50.0 (o mesmo preço pode chegar
    /// como inteiro ou decimal). Espelha `sameValue` da lib.
    private static boolean same(JsonNode a, JsonNode b) {
        return a.equals((x, y) -> x.equals(y)
                || x.isNumber() && y.isNumber() && x.decimalValue().compareTo(y.decimalValue()) == 0
                ? 0 : 1, b);
    }

    private static Instant updatedAt(JsonNode record) {
        return Instant.parse(record.get("updatedAt").asText());
    }
}
