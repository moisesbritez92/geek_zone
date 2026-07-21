# Setup en el VPS

Guía para dejar el bot andando. Asume que ya tenés corriendo en el VPS:
**n8n**, **Evolution API** (con el número vinculado por QR) y **Postgres**.

---

## 1. Crear el esquema en Postgres

Los scripts son idempotentes (`IF NOT EXISTS`), se pueden volver a correr sin romper nada.
Ejecutalos **en orden**:

```bash
psql "$DATABASE_URL" -f sql/001_extensions.sql
psql "$DATABASE_URL" -f sql/002_schema.sql
psql "$DATABASE_URL" -f sql/003_chat_memory.sql
psql "$DATABASE_URL" -f sql/004_seed_sources.sql
```

Si Postgres corre en Docker:

```bash
docker exec -i <contenedor-postgres> psql -U <usuario> -d <base> < sql/001_extensions.sql
# ...y así con el resto
```

`001_extensions.sql` necesita permisos de superusuario para `CREATE EXTENSION`.
En un Postgres gestionado puede que las extensiones `pgcrypto` y `pg_trgm` ya vengan activas.

Verificá que quedaron las 7 tablas:

```sql
\dt
-- conversations, messages, n8n_chat_histories, products, purchase_alerts, scrape_runs, sources
```

---

## 2. Crear las credenciales en n8n

Ver **[CREDENTIALS.md](CREDENTIALS.md)**. Son 4:

- `Postgres - geek_zone`
- `Evolution API - Header Auth`
- `Google Gemini API`
- `eBay Browse API - OAuth2`

Creá las 4 **antes** de importar, así al abrir cada nodo ya aparecen en el desplegable.

---

## 3. Setear las variables de entorno de n8n

En el `docker-compose.yml` (o `.env`) de n8n:

```yaml
environment:
  - EVOLUTION_BASE_URL=http://evolution-api:8080
  - EVOLUTION_INSTANCE_NAME=geekzone
  - ADMIN_WHATSAPP_NUMBER=595981123456
  - NODE_FUNCTION_ALLOW_EXTERNAL=cheerio
```

**Reiniciá n8n** para que las tome: `docker compose up -d --force-recreate n8n`

---

## 4. Importar los workflows — el orden importa

n8n resuelve los sub-workflows por **ID interno**, y ese ID se genera al importar.
Por eso van primero los sub-workflows:

| # | Archivo | Tipo |
|---|---|---|
| 1 | `workflows/03a-scraping-local-site-worker.json` | sub-workflow |
| 2 | `workflows/04-purchase-alert.json` | sub-workflow |
| 3 | `workflows/01-conversation-agent.json` | principal |
| 4 | `workflows/02-scraping-ebay.json` | principal |
| 5 | `workflows/03-scraping-local-sites.json` | principal |

Importar: **Workflows → ⋯ → Import from File**.

---

## 5. ⚠️ Re-vincular referencias después de importar

Este es el paso que más se olvida y hace que todo falle en silencio.

**a) Credenciales.** Todos los nodos tienen `"id": "REEMPLAZAR"`. Abrí cada nodo con ícono
rojo y elegí la credencial correcta del desplegable.

**b) Referencias a sub-workflows.** Los IDs del JSON son placeholders y **no existen** en tu
instancia:

| Workflow | Nodo | Hay que apuntarlo a |
|---|---|---|
| `01-conversation-agent` | tool `register_purchase_alert` | `04 - Alerta de Compra` |
| `03-scraping-local-sites` | `Ejecutar Scraper del Sitio` | `03a - Scraper Sitio Local` |

Abrí cada uno y seleccioná el workflow destino de la lista.

**c) Modelo de Gemini.** Si el nodo `Gemini Flash Lite` marca error de modelo inexistente,
abrí el desplegable **Model** y elegí el Flash Lite que liste tu API key.

---

## 6. Conectar Evolution API al webhook

Activá primero el workflow `01 - Agente de Ventas WhatsApp` (toggle arriba a la derecha):
la **Production URL** solo existe con el workflow activo.

Copiá la Production URL del nodo `Webhook - Evolution Inbound`. Se ve así:

```
https://tu-n8n.com/webhook/evolution-inbound
```

Registrala en Evolution API:

```bash
curl -X POST "$EVOLUTION_BASE_URL/webhook/set/$EVOLUTION_INSTANCE_NAME" \
  -H "apikey: $EVOLUTION_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "webhook": {
      "enabled": true,
      "url": "https://tu-n8n.com/webhook/evolution-inbound",
      "byEvents": false,
      "base64": false,
      "events": ["MESSAGES_UPSERT"]
    }
  }'
```

> El formato del body cambió entre versiones de Evolution API. En v1 los campos van en la
> raíz (`{"enabled": true, "url": "...", "events": [...]}`) en vez de anidados bajo `webhook`.
> Verificá con `GET /webhook/find/$EVOLUTION_INSTANCE_NAME` que quedó guardado.

---

## 7. Cargar las fuentes reales

El seed deja dos fuentes de ejemplo con `active=false`. Hasta que las completes,
el catálogo queda vacío y el bot va a responder honestamente que no encuentra nada.

**eBay** — reemplazá el username y ajustá la búsqueda:

```sql
UPDATE sources
SET seller_username = 'usuario_real_de_ebay',
    config = '{"q": "notebook gamer", "marketplace_id": "EBAY_US", "limit": 200}'::jsonb,
    active = true
WHERE name = 'ebay-seller-ejemplo';
```

La Browse API **exige** `q` o `category_ids` además del filtro de vendedor: con el filtro
`sellers:` solo, devuelve error 12001.

**Sitios locales de CDE** — un `INSERT` por sitio, con sus selectores CSS.
Plantilla completa en [`config/local-sites.example.json`](../config/local-sites.example.json):

```sql
INSERT INTO sources (name, platform, base_url, config, active)
VALUES ('mi-tienda-cde', 'local_scrape', 'https://mitienda.com.py',
  '{
    "list_url": "/ofertas",
    "pagination": {"enabled": true, "param": "page", "max_pages": 3},
    "selectors": {
      "item": ".producto",
      "title": ".producto .nombre",
      "price": ".producto .precio",
      "url": ".producto a@href",
      "image": ".producto img@src"
    },
    "currency_default": "PYG",
    "location": "Ciudad del Este"
  }'::jsonb, true);
```

Para sacar los selectores: abrí el sitio, F12, inspeccioná una tarjeta de producto.
`item` es el contenedor que se repite; el resto son selectores **relativos a ese contenedor**.
Con `@atributo` extraés un atributo (`a@href`), sin `@` extraés el texto.

**Agregar un sitio nuevo no requiere tocar ningún workflow**: los scrapers releen `sources`
en cada corrida.

---

## 8. Probar antes de dejarlo en producción

### 8.1 Simular un mensaje entrante

Sin usar WhatsApp, con el workflow 01 activo:

```bash
curl -X POST https://tu-n8n.com/webhook/evolution-inbound \
  -H "Content-Type: application/json" \
  -d '{
    "event": "messages.upsert",
    "instance": "geekzone",
    "data": {
      "key": {"remoteJid": "595981999888@s.whatsapp.net", "fromMe": false, "id": "TEST001"},
      "pushName": "Cliente Prueba",
      "message": {"conversation": "hola, tenes notebooks?"},
      "messageTimestamp": 1700000000
    }
  }'
```

Verificá:

```sql
SELECT * FROM conversations WHERE phone_number = '595981999888';
SELECT direction, content FROM messages ORDER BY created_at DESC LIMIT 4;
SELECT session_id, jsonb_array_length('[]'::jsonb) FROM n8n_chat_histories LIMIT 1;
```

Tenés que ver la conversación creada, un mensaje `inbound` y uno `outbound`, y filas en
`n8n_chat_histories`. En n8n, **Executions** muestra el detalle si algo falló.

### 8.2 Probar el scraping

Abrí `02 - Scraping eBay` y dale **Execute Workflow** a mano (con al menos una fuente
`active=true`). Después:

```sql
SELECT source_type, status, items_found, items_upserted, error_message, finished_at
FROM scrape_runs ORDER BY finished_at DESC LIMIT 5;

SELECT count(*), source_platform FROM products GROUP BY source_platform;
```

Lo mismo con `03 - Scraping Sitios Locales`.

### 8.3 Probar el cierre de venta

Escribile al bot (o simulá con curl) hasta confirmar explícitamente una compra
("dale, lo llevo"). Después:

```sql
SELECT id, phone_number, product_name_snapshot, price_snapshot, status, notified_admin
FROM purchase_alerts ORDER BY created_at DESC LIMIT 5;
```

Tiene que haber una fila con `notified_admin = true`, y el número admin debe haber recibido
el mensaje por WhatsApp.

### 8.4 Activar los schedules

Recién cuando 8.1–8.3 pasen, activá `02` y `03` (corren cada 6 h y todos los días a las 03:00).

---

## Problemas frecuentes

| Síntoma | Causa |
|---|---|
| El webhook responde 200 pero no pasa nada | El `Filter` descartó el mensaje: era de un grupo, un eco del bot (`fromMe`), o un audio/imagen sin texto. Mirá el output del nodo en Executions. |
| `require is not defined` / `Cannot find module 'cheerio'` | Falta `NODE_FUNCTION_ALLOW_EXTERNAL=cheerio` y reiniciar n8n. |
| eBay devuelve error 12001 | La fuente no tiene `q` ni `category_ids` en su `config`. |
| El agente inventa productos | El nodo `search_products` está fallando (credencial mal vinculada) y el modelo responde sin datos. Revisá Executions. |
| La alerta de compra llega con el número equivocado | Alguien cambió `phone_number` en la tool para que lo genere el LLM. Tiene que salir de `$('Normalizar Payload')`. |
| El scraper local no saca nada | Los selectores no matchean. Probalos primero en la consola del navegador con `document.querySelectorAll('.tu-selector')`. |
| `$env is not defined` | n8n corre con `N8N_BLOCK_ENV_ACCESS_IN_NODE=true`. Ponelo en `false` o hardcodeá los valores. |

---

## Pendientes conocidos (v2)

- **Paginación de eBay**: el MVP trae solo la primera página (hasta 200 items por vendedor).
  Falta seguir el link `next` de la respuesta.
- **Productos vencidos**: nada marca `availability = false` cuando un producto desaparece de
  la fuente. Conviene un job que haga `UPDATE products SET availability = false WHERE
  scraped_at < now() - interval '7 days'`.
- **Mensajes no-texto**: audios, imágenes y stickers se descartan en el `Filter`.
  El cliente no recibe ninguna respuesta.
- **Rate limiting**: no hay control de cuántos mensajes procesa por número. Un cliente que
  escribe 20 veces seguidas dispara 20 llamadas al modelo.
