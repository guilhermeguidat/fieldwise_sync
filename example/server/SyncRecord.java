package fieldwise.server;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.IdClass;
import jakarta.persistence.Table;
import java.io.Serializable;

/// Registro de qualquer entidade, guardado como o JSON que a fieldwise_sync
/// envia, numa coluna `text`. Entidade nova não exige código Java.
///
/// `version` fica dentro do JSON e não é o `@Version` do JPA: este lançaria
/// exceção na divergência, que aqui precisa ser detectada e resolvida.
@Entity
@Table(name = "sync_records")
@IdClass(SyncRecord.Key.class)
public class SyncRecord {

    public record Key(String entity, String id) implements Serializable {
    }

    @Id
    private String entity;
    @Id
    private String id;
    @Column(columnDefinition = "text", nullable = false)
    private String json;

    protected SyncRecord() {
        // exigido pelo JPA
    }

    public SyncRecord(String entity, String id, String json) {
        this.entity = entity;
        this.id = id;
        this.json = json;
    }

    public String getEntity() {
        return entity;
    }

    public String getJson() {
        return json;
    }
}
