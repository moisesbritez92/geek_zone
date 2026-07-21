-- Extensiones requeridas por el esquema de geek_zone
CREATE EXTENSION IF NOT EXISTS pgcrypto;   -- gen_random_uuid()
CREATE EXTENSION IF NOT EXISTS pg_trgm;    -- búsqueda ILIKE eficiente sobre products.name/description
