-- =============================================================================
-- Fuentes de ejemplo. Ambas quedan active=false a propósito: activarlas recién
-- después de reemplazar los placeholders, si no el scraping corre contra nada.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- eBay: un registro por vendedor a seguir.
-- TODO: reemplazar 'REEMPLAZAR_USERNAME' por el username real del vendedor
--       (el que aparece en https://www.ebay.com/usr/<username>) y poner active=true.
--
-- Sobre config: la Browse API de eBay NO acepta el filtro sellers: por sí solo,
-- exige además al menos uno de q / category_ids / epid / gtin / charity_ids.
-- Por eso cada vendedor lleva su propio "q" (palabras clave) o "category_ids".
--   q             -> términos de búsqueda dentro del catálogo de ese vendedor
--   category_ids  -> alternativa a q; id de categoría de eBay (ej. 58058 = Computers)
--   marketplace_id-> EBAY_US por defecto. Ojo: el esquema solo acepta USD y PYG,
--                    los items en otra moneda se saltean en el mapeo.
--   limit         -> máximo 200 por página (el MVP trae solo la primera página)
-- -----------------------------------------------------------------------------
INSERT INTO sources (name, platform, seller_username, config, active)
VALUES (
  'ebay-seller-ejemplo',
  'ebay',
  'REEMPLAZAR_USERNAME',
  '{
    "q": "notebook",
    "category_ids": null,
    "marketplace_id": "EBAY_US",
    "limit": 200
  }'::jsonb,
  false
)
ON CONFLICT (name) DO NOTHING;

-- -----------------------------------------------------------------------------
-- Sitio local de Ciudad del Este.
-- TODO: reemplazar base_url y TODOS los selectores por los del sitio real.
--       Ver config/local-sites.example.json para la referencia del formato.
--       Convención: "selector@atributo" extrae un atributo; sin @ extrae el texto.
-- -----------------------------------------------------------------------------
INSERT INTO sources (name, platform, base_url, config, active)
VALUES (
  'TODO_ejemplo_sitio_local_cde',
  'local_scrape',
  'https://example.com',
  '{
    "list_url": "/ofertas",
    "pagination": { "enabled": true, "param": "page", "max_pages": 3 },
    "selectors": {
      "item":  ".product-card",
      "title": ".product-card__title",
      "price": ".product-card__price",
      "url":   "a.product-card__link@href",
      "image": "img.product-card__img@src"
    },
    "currency_default": "PYG",
    "category_default": "general",
    "location": "Ciudad del Este"
  }'::jsonb,
  false
)
ON CONFLICT (name) DO NOTHING;
