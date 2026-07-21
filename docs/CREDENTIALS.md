# Credenciales y variables de entorno

Los JSON exportados de n8n **solo guardan la referencia** (nombre + tipo) a la credencial,
nunca el secreto. Por eso es seguro versionarlos en git, pero hay que crear las credenciales
a mano en la instancia de n8n del VPS.

Todos los nodos vienen con `"id": "REEMPLAZAR"`. Al importar, n8n va a mostrar la credencial
en rojo hasta que la selecciones del desplegable.

---

## 1. `Postgres - geek_zone`

**Tipo:** Postgres (built-in)
**Usado en:** los 5 workflows (nodos Postgres, Postgres Tool y Postgres Chat Memory)

| Campo | Valor |
|---|---|
| Host | host de tu Postgres (si n8n y Postgres corren en el mismo Docker network, el nombre del servicio) |
| Database | la base donde corriste los scripts de `sql/` |
| User / Password | los del rol de la app |
| Port | 5432 |
| SSL | según tu setup |

**Hardening recomendado (post-MVP):** el agente de ventas solo necesita `SELECT` sobre
`products`. Conviene un rol separado con permisos mínimos para las tools del agente y otro
con `INSERT`/`UPDATE` para los workflows de scraping y logging:

```sql
CREATE ROLE n8n_bot LOGIN PASSWORD '...';
GRANT SELECT ON products TO n8n_bot;
GRANT SELECT, INSERT, UPDATE ON conversations, messages, purchase_alerts TO n8n_bot;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO n8n_bot;
```

Para el MVP alcanza con una sola credencial con permisos sobre todo el esquema.

---

## 2. `Evolution API - Header Auth`

**Tipo:** Header Auth (genérico)
**Usado en:** `01-conversation-agent` (responder al cliente), `04-purchase-alert` (avisar al admin)

| Campo | Valor |
|---|---|
| Name | `apikey` |
| Value | la `AUTHENTICATION_API_KEY` global de tu Evolution API, o la apikey de la instancia |

---

## 3. `Google Gemini API`

**Tipo:** `Google Gemini(PaLM) Api` (`googlePalmApi`)
**Usado en:** `01-conversation-agent` (Chat Model del agente)

| Campo | Valor |
|---|---|
| Host | `https://generativelanguage.googleapis.com` |
| API Key | la key de [Google AI Studio](https://aistudio.google.com/apikey) |

> El nodo trae `models/gemini-flash-lite-latest`. Los identificadores de modelo de Google
> cambian seguido: si el nodo da error de modelo inexistente, abrí el desplegable **Model**
> y elegí el Flash Lite que liste tu API key.

---

## 4. `eBay Browse API - OAuth2`

**Tipo:** OAuth2 API (genérico)
**Usado en:** `02-scraping-ebay`

Primero creá una app en el [eBay Developer Program](https://developer.ebay.com/my/keys)
y sacá el **App ID (Client ID)** y el **Cert ID (Client Secret)** de producción.

| Campo | Valor |
|---|---|
| Grant Type | `Client Credentials` |
| Access Token URL | `https://api.ebay.com/identity/v1/oauth2/token` |
| Client ID | tu App ID |
| Client Secret | tu Cert ID |
| Scope | `https://api.ebay.com/oauth/api_scope` |
| Authentication | `Send as Basic Auth header` |

Para probar contra el sandbox, cambiá el host por `api.sandbox.ebay.com` y usá las keys de sandbox.

---

## Variables de entorno de n8n

No son credenciales, pero tampoco deben quedar hardcodeadas en los nodos. Se setean en el
`docker-compose.yml` / `.env` de n8n en el VPS y requieren **reiniciar n8n** para tomar efecto.

| Variable | Ejemplo | Para qué |
|---|---|---|
| `EVOLUTION_BASE_URL` | `http://evolution-api:8080` | Base de la Evolution API. **Sin barra final.** |
| `EVOLUTION_INSTANCE_NAME` | `geekzone` | Nombre de la instancia de WhatsApp |
| `ADMIN_WHATSAPP_NUMBER` | `595981123456` | Número que recibe las alertas de compra. Formato internacional, **sin `+` ni espacios ni guiones** |
| `NODE_FUNCTION_ALLOW_EXTERNAL` | `cheerio` | Habilita `require('cheerio')` en el Code node del scraper local. **Sin esto el workflow 03a falla.** |

> `$env` solo está disponible en las expresiones si n8n no tiene bloqueado el acceso a
> variables de entorno. Si tu instancia corre con `N8N_BLOCK_ENV_ACCESS_IN_NODE=true`,
> ponelo en `false` o reemplazá los `$env.X` de los nodos por los valores literales.
