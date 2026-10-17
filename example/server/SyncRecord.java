package fieldwise.server;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.IdClass;
import jakarta.persistence.Table;
import java.io.Serializable;

/// Um registro sincronizado de qualquer entidade (Product, Customer, Order),
/// guardado como o JSON que a fieldwise_sync envia. Espelha o adapter local: o
/// servidor não tem uma classe por entidade, porque o protocolo e o merge
/// operam sobre o JSON (ADR 0003). Acrescentar entidade não toca no Java.
///
/// `version` vive dentro do JSON e é um número comum, NÃO o @Version do JPA:
/// o @Version faria lock otimista e lançaria exceção quando as versões
/// divergem, mas o objetivo aqui é justamente detectar essa divergência e
/// RESOLVER o conflito.
///
/// ponytail: JSON numa coluna text, não uma tabela por entidade. Basta para
/// sync; se a retaguarda precisar consultar por campo (relatórios), aí sim
/// vira esquema por coluna ou jsonb indexado.
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
