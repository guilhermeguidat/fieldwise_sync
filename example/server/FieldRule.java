package fieldwise.server;

/// Regra de resolução por campo — espelha `FieldRule` da fieldwise_sync. Os nomes
/// são os que o codegen da lib emite em `sync_config.json`.
public enum FieldRule { LWW, SERVER_WINS, CLIENT_WINS }
