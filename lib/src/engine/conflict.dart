import '../model/product.dart';

/// O motor de conflitos — o núcleo acadêmico da biblioteca.
///
/// Duas responsabilidades separadas de propósito:
/// 1. **Detecção** ([hasConflict]): puramente por número de versão.
/// 2. **Resolução** ([ConflictStrategy]): decide o vencedor. Na Fase 1 só
///    existe LWW; a Fase 2 acrescenta Server Wins e Field-Level Merge sem
///    tocar na detecção nem no orquestrador — por isso a estratégia é um
///    ponto de extensão (função injetável, padrão Strategy).

/// Houve conflito? Sim quando a versão em que o cliente baseou a edição
/// diverge da versão atual no servidor (alguém alterou no meio do caminho).
bool hasConflict(int clientBaseVersion, int serverVersion) =>
    clientBaseVersion != serverVersion;

/// Uma estratégia recebe a mutação que chega e o estado atual do servidor,
/// e devolve o registro vencedor (ainda sem renumerar a versão — isso é
/// responsabilidade de quem persiste).
typedef ConflictStrategy = Product Function(Product incoming, Product current);

/// Last Write Wins: vence quem tem o [updatedAt] mais recente.
/// Empate de timestamp resolve a favor do estado já no servidor (estável).
Product lww(Product incoming, Product current) =>
    incoming.updatedAt.isAfter(current.updatedAt) ? incoming : current;
