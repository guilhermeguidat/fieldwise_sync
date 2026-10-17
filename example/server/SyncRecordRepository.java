package fieldwise.server;

import jakarta.persistence.LockModeType;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;

public interface SyncRecordRepository extends JpaRepository<SyncRecord, SyncRecord.Key> {

    /// Lê o registro travando a linha até o fim da transação (SELECT ... FOR
    /// UPDATE). Sem a trava, dois pushes simultâneos do mesmo registro leriam a
    /// mesma versão e o segundo sobrescreveria o primeiro sem passar pela
    /// detecção de conflito: exatamente a perda que o motor existe para evitar.
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select r from SyncRecord r where r.entity = :entity and r.id = :id")
    Optional<SyncRecord> findForUpdate(String entity, String id);
}
