-- =============================================================================
-- Tabla requerida por el nodo "Postgres Chat Memory" (LangChain) del AI Agent.
-- El session_id es el número de WhatsApp normalizado (ver 01-conversation-agent).
-- Formato de columnas impuesto por LangChain: no cambiar nombres ni tipos.
-- =============================================================================
CREATE TABLE IF NOT EXISTS n8n_chat_histories (
  id         SERIAL PRIMARY KEY,
  session_id VARCHAR(255) NOT NULL,
  message    JSONB NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_chat_histories_session ON n8n_chat_histories (session_id);
