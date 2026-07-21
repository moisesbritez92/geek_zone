# geek_zone

Bot de ventas por WhatsApp para Ciudad del Este, Paraguay. Orquestado enteramente en **n8n**:
atiende clientes por WhatsApp vía **Evolution API**, responde con un agente de IA
(**Gemini Flash Lite**) que consulta un catálogo en **Postgres**, y avisa al vendedor humano
cuando se cierra una venta.

El catálogo se mantiene solo, con scraping periódico de vendedores de eBay (API oficial) y
de tiendas locales de CDE.

Este repo contiene la **definición** del sistema: los workflows de n8n listos para importar,
el esquema de la base y la documentación de setup. No incluye infraestructura — n8n,
Evolution API y Postgres ya corren en el VPS.

---

## Cómo funciona

```
Cliente WhatsApp
      │
      ▼
Evolution API ──webhook──►  01 - Agente de Ventas
                                   │
                                   ├─ search_products ──────┐
                                   ├─ get_product_details ──┤
                                   │                        ▼
                                   │                   ┌──────────┐
                                   │                   │ Postgres │
                                   │                   └──────────┘
                                   │                        ▲
                                   └─ register_purchase_alert│
                                            │               │
                                            ▼               │
                                   04 - Alerta de Compra ────┘
                                            │
                                            ▼
                                   WhatsApp del vendedor

02 - Scraping eBay (cada 6 h) ──────────────► Postgres
03 - Scraping Sitios CDE (diario 03:00) ────► Postgres
     └─► 03a - Worker genérico (1 sitio)
```

El agente **decide por sí mismo** cuándo buscar en el catálogo y cuándo registrar una venta:
no hay detección de intención hecha con nodos. Lo que sí está blindado es que nunca inventa
productos (todo dato de catálogo sale de una tool) y que el número de teléfono de la alerta
sale del contexto real de la conversación, nunca del modelo.

---

## Contenido

| Ruta | Qué es |
|---|---|
| `workflows/01-conversation-agent.json` | Webhook + agente de ventas + respuesta al cliente |
| `workflows/02-scraping-ebay.json` | Scraping de vendedores de eBay vía Browse API |
| `workflows/03-scraping-local-sites.json` | Orquestador: recorre los sitios locales activos |
| `workflows/03a-scraping-local-site-worker.json` | Worker genérico que scrapea **un** sitio |
| `workflows/04-purchase-alert.json` | Registra la venta y avisa al vendedor |
| `sql/001` … `sql/004` | Extensiones, esquema, tabla de memoria del agente, fuentes de ejemplo |
| `config/local-sites.example.json` | Plantilla de selectores para agregar un sitio local |
| `docs/SETUP.md` | **Empezá por acá** para desplegar |
| `docs/CREDENTIALS.md` | Las 4 credenciales de n8n y las variables de entorno |

---

## Puesta en marcha

Guía completa en **[docs/SETUP.md](docs/SETUP.md)**. En resumen:

1. Correr `sql/001` → `004` contra Postgres.
2. Crear las 4 credenciales en n8n (ver [docs/CREDENTIALS.md](docs/CREDENTIALS.md)).
3. Setear las variables de entorno y reiniciar n8n.
4. Importar los workflows **empezando por los sub-workflows** (`03a` y `04`).
5. Re-vincular credenciales y referencias a sub-workflows — los IDs del JSON son placeholders.
6. Apuntar el webhook de Evolution API a la Production URL del workflow 01.
7. Cargar las fuentes reales en `sources` y probar antes de activar los schedules.

---

## Agregar fuentes al catálogo

**No hay que tocar ningún workflow.** Los scrapers releen la tabla `sources` en cada corrida.

Un vendedor de eBay:

```sql
INSERT INTO sources (name, platform, seller_username, config, active)
VALUES ('mi-vendedor', 'ebay', 'usuario_ebay',
        '{"q": "notebook", "marketplace_id": "EBAY_US", "limit": 200}'::jsonb, true);
```

Una tienda local (los selectores CSS salen de inspeccionar el sitio con F12 —
plantilla en [`config/local-sites.example.json`](config/local-sites.example.json)):

```sql
INSERT INTO sources (name, platform, base_url, config, active)
VALUES ('mi-tienda-cde', 'local_scrape', 'https://mitienda.com.py',
        '{"list_url": "/ofertas",
          "selectors": {"item": ".producto", "title": ".nombre",
                        "price": ".precio", "url": "a@href", "image": "img@src"},
          "currency_default": "PYG"}'::jsonb, true);
```

Las dos fuentes que trae el seed quedan con `active = false` a propósito: son placeholders.

---

## Estado

Primera etapa: definición completa y probada localmente, **sin desplegar todavía**.

Lo verificado hasta ahora:

- Los 5 JSON parsean y los scripts SQL corren limpio contra Postgres 16 (y son re-ejecutables).
- Las queries de los workflows probadas con datos reales: upserts sin duplicar, la tool de
  búsqueda del agente en sus 6 combinaciones de filtros, y el alta de alertas incluso cuando
  el modelo no aporta producto ni nombre.
- La lógica JS de los Code nodes: parser de precios (14 casos, formatos Gs. y USD), armado de
  URLs con paginación, y extracción de HTML con cheerio.

Lo que **no** está probado y solo se puede verificar en el VPS: la conexión real con Evolution
API, las llamadas a Gemini y a la Browse API de eBay. El checklist de pruebas de punta a punta
está en [docs/SETUP.md](docs/SETUP.md#8-probar-antes-de-dejarlo-en-producción).

Pendientes conocidos para v2 (paginación de eBay, expirado de productos viejos, manejo de
audios e imágenes, rate limiting) documentados al final de `docs/SETUP.md`.
