# Integración gruppe6.es ↔ os_security (propuesta, sin implementar)

Estado: **propuesta para revisión**. No se ha modificado código de GruppeNGRP ni de os_security.
Revisado: GruppeNGRP `87e228a` (D:\OTROS\ROL\BOTS\GruppeNGRP) y os_security 0.12.1.

## 1. Qué se reutiliza de GruppeNGRP

| Necesidad | Ya existe | Uso |
|---|---|---|
| Cuentas de cliente y login | `extranet_accounts` (+ Discord login, 2FA en `two-factor.php`) | El cliente vincula su personaje desde su cuenta Extranet. |
| Vínculos de cuenta | `extranet_account_links` solo cubre cuentas Extranet; los empleados están en `users` | Tabla propia `fivem_character_links` para Extranet **e** Intranet (§4). |
| Auditoría | `extranet_audit_logs`, `audit_logs` (Intranet) y `public_ticket_audit_logs` | `fivem.link.*` en el registro de cada tipo de cuenta; `commercial.*` / `fivem.*` en la solicitud. |
| Solicitudes | `CommercialRequests` sobre `public_tickets` (código `GS-año-ID`, `submission_key`, estados, mensajes, notificación a gestores) | Una solicitud web es un `public_ticket` comercial; no se crea otra tabla de solicitudes. |
| Puentes firmados | `web/intranet/api/*-bridge.php` (HMAC del cuerpo + `ts` ±300 s) | Mismo patrón de archivo, endurecido (nonce, firma de cabeceras, idempotencia). |
| Idempotencia | `intersecurity_api_receipts` (clave + hash del cuerpo → 409 si cambia) | Mismo esquema de recibos para los eventos de FiveM. |
| Límites | `IntersecurityStore::limit()` | Límites por cliente/acción (no por IP: tras Cloudflare Tunnel `REMOTE_ADDR` es el túnel). |
| Tareas en segundo plano | `worker` (`gruppe-scheduler`, `task.php`) | Purga de nonces/códigos caducados y aviso de FiveM sin sincronizar. |
| Ubicaciones | `gta_locations` + alias (`map_x/map_y` 0–1536 del mapa web) | Zonas del sistema; se añaden coordenadas de juego (ver §6). |

Lo único nuevo en la web: tablas de soporte del puente (§4), el endpoint `fivem-bridge.php`, la pantalla de
vinculación en Extranet → Cuenta y la vista de seguimiento en Extranet → Solicitudes.

## 2. Topología: FiveM siempre llama, la web nunca llama a FiveM

```
os_security (FiveM) ──HTTPS saliente──► Cloudflare Tunnel ──► gruppe6.es/intranet/api/fivem-bridge.php ──► MariaDB
        ▲                                                                                    │
        └────────────── respuestas firmadas + comandos pendientes (pull cada 5 s) ◄──────────┘
```

Motivos:
- **No se expone nada nuevo de FiveM**: ni MariaDB ni un endpoint HTTP en 30120. La IP dinámica/DDNS solo
  afecta a los jugadores, no a la integración.
- **TLS real** gracias a Cloudflare (FiveM a 30120 sería HTTP plano).
- La política de webhooks de Intersecurity ya prohíbe destinos que no sean 443/públicos; esto la respeta.
- **Tolerancia a caídas** natural: cada lado guarda una cola durable y el otro la vacía cuando vuelve (§8).
- Latencia: FiveM→web inmediata (se envía al ocurrir); web→FiveM ≤5 s (pull). Casi tiempo real en ambos
  sentidos sin long-polling que ocupe workers de Apache.

## 3. Seguridad del puente

**Credencial por servicio y entorno.** Cada cliente del puente (`fivem-prod`, `fivem-dev`) tiene su id,
secreto de 32 bytes aleatorios y versión de clave. En la web: variables de entorno (`.env`, fuera del repo),
p. ej. `FIVEM_BRIDGE_PROD_SECRET`, `FIVEM_BRIDGE_PROD_SECRET_PREVIOUS` (rotación sin corte). En FiveM:
`set ossecurity_web_secret "…"` en un `secrets.cfg` aparte cargado con `exec` (no `setr`/`sets`: así nunca
se replica a los clientes ni aparece en NUI/JS). El secreto nunca se registra; los logs solo muestran
cliente, acción, resultado y los 8 primeros caracteres del nonce.

**Firma de cada petición** (cabeceras):

```
X-G6-Client:      fivem-prod
X-G6-Key-Version: 1
X-G6-Timestamp:   1762862400            (segundos UTC, ventana ±90 s)
X-G6-Nonce:       32 hex aleatorios      (único por cliente durante 10 min)
Idempotency-Key:  64 hex                 (operaciones que cambian datos)
X-G6-Signature:   v1=<hex HMAC-SHA256(secreto, canónico)>

canónico = "v1\n" + cliente + "\n" + versión + "\n" + timestamp + "\n" + nonce + "\n"
         + método + "\n" + ruta + "\n" + Idempotency-Key + "\n" + sha256_hex(cuerpo)
```

Verificación en este orden y en tiempo constante (`hash_equals`), **antes** de decodificar el JSON:
cliente activo → versión de clave → ventana temporal → firma → nonce no usado (`INSERT` con clave única;
duplicado = 401 replay) → tamaño ≤64 KiB → JSON estricto → permiso del cliente para la acción →
límite de frecuencia → validación del payload por acción (lista blanca de campos, tipos y longitudes).

**La web también firma sus respuestas** (mismo esquema con el nonce de la petición), así FiveM rechaza
respuestas manipuladas o de otro servidor aunque falle el DNS.

**Permisos por acción**: cada cliente tiene una lista de acciones permitidas (`fivem-dev` sin acceso a
datos reales, por ejemplo). Las acciones de usuarios web (vincular, pedir, cancelar) usan la sesión de
Extranet, su CSRF y sus permisos existentes; el puente no acepta cookies.

**Límites**: por cliente y acción (p. ej. `pull` 30/min, `events` 120/min); vinculación 5 intentos por
cuenta cada 15 min y bloqueo progresivo; 1 código `/g6web` por personaje cada 60 s.

**Registro de seguridad**: firma inválida, replay, ventana vencida, permiso denegado y límite alcanzado se
guardan con cliente, acción, motivo y hora (tabla `fivem_bridge_security_log`), y se avisa a gestores tras
N fallos seguidos reutilizando `StaffNotifications`.

**En FiveM** (Lua 5.4): SHA-256/HMAC en Lua puro (verificado con los vectores RFC 4231 en los tests);
aleatoriedad para nonces y códigos a partir de `GetPasswordHash` (bcrypt con sal aleatoria del servidor),
como ya hace la sesión de tablets. `PerformHttpRequest` solo hacia `ossecurity_web_url` (https obligatorio).

## 4. Modelo de datos (web, migración aditiva `097_fivem_bridge.sql`)

| Tabla | Contenido |
|---|---|
| `fivem_bridge_nonces` | `client`, `nonce` (único), `expires_at`. Purga en el worker. |
| `fivem_bridge_receipts` | `client`, `idempotency_key` (único), `request_hash`, `response_json`, `created_at`. Misma clave y cuerpo → misma respuesta; otro cuerpo → 409. |
| `fivem_bridge_commands` | Cola web→FiveM: `id` (cursor), `type`, `payload_json`, `created_at`, `acked_at`, `result_json`. |
| `fivem_link_codes` | `code_hmac` (HMAC con pepper, nunca el código), `character_id`, `character_label`, `expires_at`, `consumed_at`, `consumed_by_type` (`extranet`/`intranet`), `consumed_by_id`. |
| `fivem_character_links` | `subject_type` (`extranet`/`intranet`), `subject_id`, `character_id`, `character_label`, `origin`, `linked_at`, `revoked_at`, `revoked_reason`, `revoked_by`. Un vínculo activo por cuenta y por personaje. |
| `fivem_order_links` | `ticket_id` (FK `public_tickets`, único), `order_id` (`ot_…`, único), `character_id`, `game_status`, `technician_label`, `price`, `payment_state`, `paid_at`, `last_event_at`. |
| `fivem_character_cache` | Caché, no fuente de verdad: `character_id`, nombre visible, propiedades (id, etiqueta), `updated_at`. Permite mostrar el formulario aunque FiveM esté caído. |
| `fivem_bridge_security_log` | Eventos de seguridad del §3. |

Vínculo activo: fila de `fivem_character_links` sin `revoked_at`. Pueden vincular **todas** las cuentas:
Extranet (clientes y justicia) e Intranet (empleados). Un personaje solo puede estar vinculado a una cuenta y
una cuenta a un personaje (columnas generadas `active_subject`/`active_character`, NULL al revocar, con índice
único). Las filas revocadas quedan como historial. Auditoría en el registro de cada tipo de cuenta
(`extranet_audit_logs` o `audit_logs`): `fivem.link.created`, `fivem.link.revoked`, `fivem.link.replaced`, con
personaje, origen web/juego y motivo. La licencia de Rockstar **no se envía a la web**; el
propietario se identifica por el `characterId` estable de os_devtools.

En os_security (JSON propio, sin MariaDB): `orders` gana `webRef` (`GS-…`) y `origin` (`game`/`web`); nuevo
`data/web_outbox.json` con los eventos pendientes de enviar y el último cursor de comandos aplicado.

## 5. Vinculación `/g6web`

1. En el juego, `/g6web` con un personaje activo. os_security genera un código de 8 caracteres
   (alfabeto sin ambiguos `ABCDEFGHJKMNPQRSTUVWXYZ23456789`, ~8·10¹¹ combinaciones), caduca en 10 min,
   y lo envía a la web (`link.offer` con `character_id` y nombre visible). Uno nuevo invalida el anterior.
   Si la web no responde: «Servicio web no disponible, inténtalo más tarde» (no se da un código inútil).
2. El jugador lo ve solo él (aviso privado, nunca en el chat global ni en logs).
3. En Extranet → Cuenta → Personaje FiveM (empleados: Intranet → Perfil), con sesión iniciada (y 2FA si la cuenta lo tiene), introduce el
   código. La web hace en una transacción:
   `UPDATE fivem_link_codes SET consumed_at=NOW(), consumed_by_account_id=? WHERE code_hmac=? AND consumed_at IS NULL AND expires_at>NOW()`
   → si afecta a 1 fila, crea/reemplaza el vínculo, audita y encola `link.created` para FiveM. Un código
   consumido o caducado nunca vuelve a servir, tampoco para otra cuenta.
4. FiveM recibe `link.created` en el siguiente pull y avisa al jugador: «Personaje vinculado a tu cuenta
   Gruppe6». La tablet G6 Client muestra «Cuenta web: vinculada».
- **Desvincular**: desde la web (Extranet) o desde el juego (`/g6web desvincular`). Ambos auditan.
- **Cambiar de personaje**: usar un código nuevo desde otro personaje; reemplaza el vínculo y lo audita.
- **Consultar**: Extranet muestra personaje, fecha y origen; en el juego `/g6web estado`.

## 6. Solicitudes desde la web

Formulario en Extranet → Solicitudes (solo con personaje vinculado):
- **Tipo de servicio**: mismos tipos que la tablet (`cctv`, `alarm`, `repair`, `lock`, `car`, `other`),
  ampliables. Se añaden al catálogo de `CommercialRequests` como servicio de tipo `city` (en la ciudad,
  sin franja horaria ni disponibilidad de personal real: no aplica a un servicio dentro del juego).
- **Ubicación**: una propiedad o negocio del personaje (de la caché que envía FiveM) o una zona del sistema
  (`gta_locations` con coordenadas de juego). Para las zonas se añaden `game_x/game_y/game_z` nulables a
  `gta_locations`; un administrador las rellena desde el F10 del juego («Guardar este punto para la web»).
  Zonas sin coordenadas de juego no se ofrecen.
- **Descripción**, **observaciones** y **prioridad** (normal/urgente; urgente avisa con prioridad a los
  técnicos de servicio).

Al enviar: `CommercialRequests::create` con `submission_key` (doble clic = misma solicitud), auditoría y
notificación a gestores y **canal de ticket en Discord** (`create_ticket_channel`) como hoy, y se encola
`request.create` para FiveM. FiveM la crea como orden
`origin=web`, responde con el `ot_…` y desde ahí sigue el flujo normal de la tablet. Las solicitudes que el
personaje vinculado cree desde la tablet **también se reflejan en la web** (`order.created`, `origin=game`):
se crea su `public_ticket` (con canal de Discord) enlazado en `fivem_order_links`.

## 7. Estados

Estados de la orden en os_security (los que no existen hoy se añaden a la tablet):

| os_security | Web (cliente) | Quién / cómo |
|---|---|---|
| `open` | Pendiente | Al crearse. |
| `assigned` | Asignada | Un supervisor la asigna a un técnico desde G6 Operations (nuevo); el técnico la acepta o la rechaza. Un técnico también puede aceptar directamente una pendiente. |
| `accepted` | Aceptada | El técnico la acepta (ya existe). |
| `en_route` | En camino | Automático al aceptar con GPS, o botón. |
| `on_site` | En el lugar | Automático al llegar a 30 m del punto. |
| `in_progress` | Trabajo en curso | Botón «Empezar», o al usar una herramienta G6 en el sitio. |
| `billed` | Pendiente de pago | Al facturar (ya existe). |
| `paid` | Pagada | Al pagar el cliente en la tablet (banco del juego). |
| `completed` | Finalizada | El técnico cierra tras el pago (o automático a las 24 h). |
| `cancelled` | Cancelada | El cliente (web o tablet) antes de facturar, o el supervisor. |

En `public_tickets.commercial_state` solo se reflejan los estados generales (`PENDING`, `ACCEPTED`,
`CANCELLED`, y uno de cierre), y el detalle va en `fivem_order_links.game_status`. El cliente ve en la web
técnico (nombre del personaje), estado, fechas de cada cambio, importe, método (banco del juego) y estado de
pago, y las observaciones marcadas como visibles; lo interno queda como `is_internal` en los mensajes.
El cobro sigue siendo dentro del juego; la web solo lo refleja.

## 8. Contrato del puente

Un único endpoint, como los otros puentes: `POST https://gruppe6.es/intranet/api/fivem-bridge.php`,
cuerpo `{ "action": "…", "data": { … } }`. Respuesta `{ "ok": true, "data": … }` o
`{ "ok": false, "error": "codigo_estable" }` con 400/401/403/409/413/422/429/503; nunca SQL ni trazas.

| Acción | Dirección | Datos | Respuesta |
|---|---|---|---|
| `hello` | FiveM→web | versión, `cursor` | estado del puente, comandos pendientes |
| `pull` | FiveM→web | `cursor` (último comando aplicado) | hasta 50 comandos con `id > cursor` |
| `ack` | FiveM→web | `[{id, result}]` | ok (idempotente) |
| `events` | FiveM→web | hasta 50 eventos `{event_id, type, at, data}` | recibo por evento |

Eventos FiveM→web: `link.offer`, `link.revoke`, `character.snapshot` (nombre visible y propiedades, al
vincular y cuando cambien), `order.created`, `order.status`, `order.assigned`, `order.billed`,
`order.paid`, `order.cancelled`, `order.completed`.
Comandos web→FiveM: `link.created`, `link.revoked`, `request.create`, `request.cancel`.

**Idempotencia**: cada evento lleva `event_id` = `sha256(cliente:id local del evento)`; un reenvío tras un
corte devuelve el mismo recibo. Cada comando tiene `id` creciente; FiveM guarda el último aplicado y
aplica cada uno una sola vez (`request.create` con el mismo `GS-…` devuelve el `ot_…` ya creado).

## 9. Caídas y reconciliación

- **Web caída**: FiveM sigue igual. Los eventos quedan en `web_outbox.json` (persistente, acotado) y se
  reintentan con espera creciente (5 s → 5 min). `/g6web` avisa de que no está disponible.
- **FiveM caído**: la web acepta solicitudes y las deja en `fivem_bridge_commands` como «Pendiente de
  sincronizar» (visible para el cliente). Al arrancar, `hello` + `pull` las recoge todas.
- **Reconciliación al arrancar**: `hello` envía el cursor; la web devuelve lo pendiente; FiveM reenvía su
  cola. El worker avisa a gestores si FiveM lleva más de X min sin sincronizar.

## 10. Activación opcional

Sin `ossecurity_web_url` y `ossecurity_web_secret`, os_security no carga el puente, `/g6web` responde «no
disponible» y todo lo demás funciona igual (sigue siendo un script independiente). En la web, sin
`FIVEM_BRIDGE_*` el endpoint responde 503 y la Extranet oculta la sección.

## 11. Plan por fases

1. **Puente y seguridad** — hecho (os_security 0.13.0; web: rama `claude/fivem-bridge-fase1`).
2. **Vinculación** `/g6web` — hecho (os_security 0.14.0; web: rama `claude/fivem-link-fase2`). La sección
   está en Configuración (página común de Extranet e Intranet), con su CSRF y la sesión ya verificada con 2FA.
3. **Solicitudes web → tablet** y reflejo de las del juego.
4. **Estados ampliados** en la tablet (asignada, en camino, en el lugar, en curso, finalizada) y
   seguimiento en la web.
5. **Zonas del sistema** con coordenadas de juego desde el F10.

## 12. Decisiones tomadas (11/11/2026)

1. Cada solicitud de FiveM abre también un canal de ticket en Discord, como las comerciales.
2. Las solicitudes creadas desde la tablet por un personaje vinculado aparecen en la web.
3. Existe el estado «Asignada»: un supervisor reparte las órdenes.
4. Pueden vincular personaje todas las cuentas: Extranet (cualquier tipo) e Intranet (empleados).
