-- =============================================================================
-- geek_zone - Esquema principal
-- Requiere: 001_extensions.sql
-- =============================================================================

-- -----------------------------------------------------------------------------
-- sources: fuentes de datos del catálogo (vendedores de eBay + sitios locales)
-- Agregar un sitio nuevo = insertar una fila acá. No se tocan los workflows.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS sources (
  id              SERIAL PRIMARY KEY,
  name            TEXT UNIQUE NOT NULL,
  platform        TEXT NOT NULL CHECK (platform IN ('ebay', 'local_scrape')),
  base_url        TEXT,                 -- solo local_scrape
  seller_username TEXT,                 -- solo ebay
  config          JSONB,                -- solo local_scrape: selectores, paginación, defaults
  active          BOOLEAN NOT NULL DEFAULT true,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_sources_platform_active ON sources (platform, active);

-- -----------------------------------------------------------------------------
-- products: catálogo unificado que consulta el agente de ventas
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS products (
  id              SERIAL PRIMARY KEY,
  source_id       INTEGER REFERENCES sources(id) ON DELETE CASCADE,
  source_platform TEXT NOT NULL CHECK (source_platform IN ('ebay', 'local')),
  external_id     TEXT NOT NULL,              -- id/hash del producto en el sitio origen
  sku             TEXT,
  name            TEXT NOT NULL,
  description     TEXT,
  category        TEXT,
  subcategory     TEXT,
  price           NUMERIC(12,2),
  currency        TEXT NOT NULL DEFAULT 'PYG' CHECK (currency IN ('PYG', 'USD')),
  availability    BOOLEAN NOT NULL DEFAULT true,
  stock_quantity  INTEGER,
  image_url       TEXT,
  product_url     TEXT,
  seller_name     TEXT,
  location        TEXT,                       -- ej. 'Ciudad del Este'
  scraped_at      TIMESTAMPTZ,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT products_source_external_uniq UNIQUE (source_id, external_id)
);

CREATE INDEX IF NOT EXISTS idx_products_category     ON products (category);
CREATE INDEX IF NOT EXISTS idx_products_price        ON products (price);
CREATE INDEX IF NOT EXISTS idx_products_availability ON products (availability);
CREATE INDEX IF NOT EXISTS idx_products_name_trgm    ON products USING gin (name gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_products_desc_trgm    ON products USING gin (description gin_trgm_ops);

-- -----------------------------------------------------------------------------
-- conversations: un registro por número de WhatsApp
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS conversations (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  phone_number    TEXT UNIQUE NOT NULL,
  contact_name    TEXT,
  status          TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'closed')),
  last_message_at TIMESTAMPTZ,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- -----------------------------------------------------------------------------
-- messages: log de negocio de la conversación.
-- Independiente de n8n_chat_histories (que es el formato interno de LangChain).
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS messages (
  id                   BIGSERIAL PRIMARY KEY,
  conversation_id      UUID REFERENCES conversations(id) ON DELETE CASCADE,
  phone_number         TEXT NOT NULL,
  direction            TEXT NOT NULL CHECK (direction IN ('inbound', 'outbound')),
  message_type         TEXT NOT NULL DEFAULT 'text',
  content              TEXT,
  evolution_message_id TEXT,
  created_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_messages_conversation ON messages (conversation_id, created_at);
CREATE INDEX IF NOT EXISTS idx_messages_phone        ON messages (phone_number, created_at);

-- -----------------------------------------------------------------------------
-- purchase_alerts: se genera cuando el agente detecta una compra confirmada
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS purchase_alerts (
  id                    BIGSERIAL PRIMARY KEY,
  conversation_id       UUID REFERENCES conversations(id) ON DELETE SET NULL,
  phone_number          TEXT NOT NULL,
  customer_name         TEXT,
  product_id            INTEGER REFERENCES products(id) ON DELETE SET NULL,
  product_name_snapshot TEXT,          -- snapshot: el producto puede desaparecer del scraping
  price_snapshot        NUMERIC(12,2),
  currency_snapshot     TEXT,
  notes                 TEXT,
  status                TEXT NOT NULL DEFAULT 'pending'
                        CHECK (status IN ('pending', 'contacted', 'confirmed', 'cancelled')),
  notified_admin        BOOLEAN NOT NULL DEFAULT false,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_purchase_alerts_status ON purchase_alerts (status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_purchase_alerts_phone  ON purchase_alerts (phone_number);

-- -----------------------------------------------------------------------------
-- scrape_runs: auditoría de cada corrida de scraping
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS scrape_runs (
  id             BIGSERIAL PRIMARY KEY,
  source_id      INTEGER REFERENCES sources(id) ON DELETE SET NULL,
  source_type    TEXT NOT NULL,
  status         TEXT NOT NULL CHECK (status IN ('success', 'partial', 'error')),
  items_found    INTEGER DEFAULT 0,
  items_upserted INTEGER DEFAULT 0,
  error_message  TEXT,
  started_at     TIMESTAMPTZ,
  finished_at    TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_scrape_runs_source ON scrape_runs (source_id, finished_at DESC);
