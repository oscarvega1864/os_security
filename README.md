# OS Security — Device Core 0.2.0

Recurso standalone para FiveM y GTA V Legacy. Esta fase añade un registro lógico
persistente de dispositivos, exclusivamente en el servidor. Conserva `/oshello`,
`osstatus` y los registros `[OS SECURITY]`.

No incluye modelos 3D, instalación física, CCTV funcional, alarmas, cerraduras,
NUI, minijuegos, cálculos de desgaste ni temporizadores. FXServer no requiere
frameworks, oxmysql ni librerías externas.

## Archivos y arquitectura

| Archivo | Responsabilidad |
| --- | --- |
| `fxmanifest.lua` | `cerulean`, `gta5` y carga explícita por contexto. |
| `config/config.lua` | Versión `0.2.0` y depuración compartidas; nunca guardar secretos aquí. |
| `config/server.lua` | ACE, almacenamiento y límites, solo en servidor. |
| `shared/constants.lua` | Prefijos del chat y los registros. |
| `client/main.lua` | Saludo local `/oshello`. |
| `server/main.lua` | Adaptadores FiveM, carga inicial, `osstatus` y ciclo de vida. |
| `server/core/util.lua` | Copia de datos, comparación y comprobaciones de tipos. |
| `server/devices/catalog.lua` | Tipos, modelo lógico predeterminado y esquemas de metadatos. |
| `server/devices/states.lua` | Máquina de estados y transiciones. |
| `server/devices/validation.lua` | Contratos de creación, dispositivos, historial y snapshots. |
| `server/devices/registry.lua` | Creación, consultas paginadas, transiciones y retirada. |
| `server/storage/codec.lua` | Adaptación al JSON FiveM; rechaza errores y contenido adicional. |
| `server/storage/json.lua` | Snapshots alternos y verificación de escritura. |
| `server/security/permissions.lua` | Autorización ACE y límites de solicitudes. |
| `server/commands/devices.lua` | Subcomandos `osdev` y respuestas al solicitante. |
| `data/.gitkeep` | Conserva vacío el directorio de almacenamiento en Git. |
| `tests/core_spec.lua`, `tests/storage_json_spec.lua`, `tests/run.cjs` | Pruebas Lua 5.4, regresiones JSON y APIs FiveM simuladas. |
| `package.json`, `package-lock.json` | Wasmoon, dependencia solo de desarrollo para pruebas. |
| `.npmrc` | Mantiene la cache de npm dentro del repositorio. |
| `AGENTS.md`, `.gitignore`, `CHANGELOG.md` | Reglas, exclusiones e historial de versiones. |

Los scripts del servidor y los datos JSON no se declaran como archivos de
cliente. No se registran eventos de red ni exports administrativos.

## Catálogo y contratos de datos

Tipos admitidos: `cctv_camera`, `alarm_panel`, `alarm_sensor`, `smart_lock`,
`vehicle_tracker`, `bodycam`, `security_monitor`. Son definiciones de datos;
no implementan todavía los módulos correspondientes.

Cada dispositivo contiene:

- `id`: formato `osd_0000000001`, secuencia persistente sin reutilización normal tras reinicios.
- `type`, `model`, `state`, `schemaVersion` (actualmente `1`).
- `createdAt`, `updatedAt`: segundos Unix. Una actualización no retrocede si cambia el reloj.
- `owner`, `propertyId` o `vehicleId`: opcionales, textos de hasta 128 bytes.
  Propiedad y vehículo son mutuamente excluyentes.
- `position`, `rotation`: opcionales, objetos `{ x, y, z }` numéricos finitos;
  posición dentro de ±1.000.000 y rotación en grados dentro de ±360.
- `metadata`: objeto plano de hasta 32 propiedades admitidas por su esquema.
- `history`: eventos `{ from?, to, at }` desde la creación; se conservan al retirar.
- `installation`: contrato separado con `quality` opcional entre 0 y 100.
- `condition.components`: hasta 32 componentes por identificador, con `health`
  y `wear` opcionales entre 0 y 100, `expectedLifetimeHours` entre 0 y 1.000.000,
  y hasta 16 códigos de avería `faults` de 64 bytes.
- `maintenance.events`: contrato reservado para hasta 128 eventos `fault`,
  `repair` o `replacement`, con `componentId`, `at`, `notes?` y `replacementId?`.
  `replacementId` solo se admite para `replacement` y referencia una pieza
  lógica; no reactiva un dispositivo retirado.

Los contratos de mantenimiento se crean vacíos; no hay operaciones ni cálculos
que los rellenen. La salud nunca se modifica implícitamente al cambiar el estado.
El modelo predeterminado `generic` es lógico, no un modelo GTA. No se inventan
propietarios ni coordenadas al crear desde consola.

Los siete tipos admiten inicialmente metadatos vacíos: se rechaza cualquier clave
desconocida. Los futuros módulos podrán añadir en su entrada del catálogo
descriptores `string` (`maxLength`, máximo 256 bytes), `number` (`min`/`max`,
finitos), `boolean` y `required`, sin modificar la validación genérica.

La creación rechaza campos reservados como `id`, `state` e `history`. Las
consultas devuelven copias; no existe una API para sustituir libremente un
registro completo. Solo se implementan creaciones y transiciones.

API interna para scripts de servidor del mismo recurso, cargados después de
`server/main.lua`: `OSSecurity.Registry.create(source, input)`, `get(source, id)`,
`list(source, offset?, limit?)`, `setState(source, id, target)` y `retire(source, id)`.
Se llaman con punto; devuelven datos o `nil, error`. Todas comprueban permisos y
rechazan operaciones antes de la carga inicial. `source = 0` se reserva a trabajo
de servidor de confianza; nunca debe derivarse de un argumento enviado por cliente.

## Máquina de estados

| Origen | Destinos permitidos |
| --- | --- |
| `registered` | `installing`, `retired` |
| `installing` | `installed`, `registered`, `retired` |
| `installed` | `active`, `maintenance`, `fault`, `retired` |
| `active` | `maintenance`, `fault`, `retired` |
| `maintenance` | `installed`, `active`, `fault`, `retired` |
| `fault` | `maintenance`, `retired` |
| `retired` | Ninguno. |

Repetir el estado actual es un error. `remove` aplica `retired` sin borrar el ID,
el registro ni el historial. No hay sustitución ni reactivación. `fault` es una
excepción del ciclo operativo; `condition` describe la salud de los componentes
como un contrato independiente.

## Permisos, límites y comandos

La consola (`source == 0`) puede administrar. Para jugadores se comprueba el ACE
`ossecurity.admin` en cada operación, incluidas las consultas. Pertenecer a
`group.admin` no concede automáticamente ese permiso. El comando valida este
ACE internamente, en lugar del objeto diferente `command.osdev`.

Un administrador puede concederlo explícitamente a un grupo ya configurado,
ejecutando en la consola del servidor:

```text
add_ace group.admin ossecurity.admin allow
```

Este proyecto no ejecuta esa concesión ni modifica `server.cfg`. Para conservarla
tras reiniciar el servidor hay que guardarla mediante su administración habitual.
Las respuestas dentro del juego requieren el recurso `chat` estándar y se envían
solo al solicitante. Las consultas en consola no necesitan `chat`.

| Comando en consola | Resultado |
| --- | --- |
| `osstatus` | Estado, versión y disponibilidad del Device Core. |
| `osdev list [offset] [limit]` | Lista por ID, total y paginación desde offset 0. |
| `osdev create <type>` | Crea y persiste un dispositivo `registered`. |
| `osdev info <id>` | Tipo, modelo, estado, fechas, vínculos y metadatos, sin volcar el historial completo. |
| `osdev state <id> <state>` | Aplica y persiste una transición válida. |
| `osdev remove <id>` | Retira y persiste sin borrar el registro. |

En el chat usar `/osdev ...` con ACE explícito. `/oshello` y `/osstatus` se
conservan sin permiso administrativo.

Límites predeterminados en `config/server.lua`: 1.000 dispositivos incluyendo
retirados, páginas de 20 con máximo 100, 256 eventos de estado, 128 de mantenimiento
y 8 MiB por snapshot. El último evento de estado se reserva para retirar.
Cada jugador autorizado dispone de 30 consultas y 5 mutaciones por ventana de
10 segundos; también cuentan intentos inválidos que llegan al registro. La consola
está exenta del límite temporal y respeta los demás. No hay guardados por frame.

## Persistencia y errores

La interfaz `store.load()`, `store.save(snapshot)` y `store.isBlocked()` permite
cambiar el adaptador en una futura fase. No se implementa MySQL.

`data/devices.a.json` y `data/devices.b.json` están excluidos de Git. Cada snapshot
contiene `schemaVersion`, `revision`, `nextId` y `devices` indexados por ID.
Si se comprueba que ambos archivos están ausentes, se inicia un registro vacío
sin escribir hasta la primera mutación. Un fallo de acceso no se trata como ausencia.

Al iniciar se validan todos los archivos presentes y se selecciona la mayor
revisión. Si existen ambos, deben ser consecutivos y representar una sola creación
o transición, conservando datos anteriores. JSON corrupto, esquemas desconocidos,
IDs inconsistentes o historial alterado bloquean el registro. Incluso si el otro
snapshot es válido, no se sobrescribe ni se recupera silenciosamente el corrupto.

Cada mutación prepara una copia, valida y serializa, comprueba que los archivos
no hayan cambiado externamente, escribe en el slot alterno con `SaveResourceFile`
y verifica los bytes con `LoadResourceFile`. Solo entonces publica el nuevo estado
en memoria y responde `Persistido`. La revisión confirmada anterior permanece en
el otro slot. No hay yields entre escritura y comprobación.

Los errores de IO producen registros `[OS SECURITY] [ERROR]`; un fallo de escritura
o verificación devuelve error y bloquea consultas y mutaciones para evitar exponer
un estado ambiguo. `osstatus` sigue funcionando. Un fallo de serialización anterior
a la escritura conserva disponible el estado confirmado.

Ante corrupción o bloqueo:

1. Detener el recurso y conservar copias de **ambos** archivos para diagnóstico.
2. Revisar consola, permisos, espacio y contenido de los archivos.
3. Restaurar un conjunto verificado con intervención del administrador, conservando
   historial y la secuencia máxima de IDs utilizados.
4. Reiniciar, consultar `osstatus`, `osdev list` y los IDs conocidos.

No borrar archivos para desbloquear ni restaurar un contador obsoleto sin revisar
los IDs ya usados. La eliminación de ambos archivos o una restauración antigua
pueden perder datos y reutilizar IDs; no hay recuperación que adivine datos perdidos.

Riesgos del adaptador: no ofrece aquí una transacción con `fsync` ni garantiza
protección ante cualquier fallo físico. Un guardado que devuelve error podría haber
escrito datos completos: al reiniciar puede recuperarse una operación que antes
no se confirmó. Consultar el registro antes de reintentar creaciones tras un fallo.
Debe existir un único escritor; no editar los archivos con el recurso iniciado.
Se copia y serializa el conjunto completo por mutación: este adaptador se dirige
a esta fase acotada y no a alta frecuencia o gran volumen.

Las rutas de montaje y APIs utilizadas corresponden al
[sandbox documentado de Cfx.re](https://docs.fivem.net/docs/developers/sandbox/).

## Pruebas automatizadas

Node.js 22 o posterior y npm son necesarios **solo en desarrollo**. Instalar la
herramienta y su caché dentro del repositorio:

```powershell
npm.cmd ci --cache .tools/npm-cache --ignore-scripts --no-audit --no-fund
npm.cmd test
```

Wasmoon ejecuta Lua 5.4 compilado a WebAssembly. El ejecutor monta el código en
memoria, valida sintaxis con `loadfile` y ejecuta lógica, persistencia y conexión
simulada de las APIs FiveM. No escribe fixtures reales ni inicia FXServer.

Por defecto usa un puente `JSON.stringify`/`JSON.parse`. También puede leerse
la biblioteca **heredada dkjson** del archivo `json.lua` de una instalación
local, sin modificarla. Ese archivo no es el JSON nativo RapidJSON del runtime:

```powershell
node tests/run.cjs --codec 'E:\Fivem-DEV\server\citizen\scripting\lua\json.lua'
```

Esa ruta opcional se ajusta en otros equipos; no se distribuye una copia de la
biblioteca. La suite cubre creación, tipos, IDs persistentes, estados, serialización,
recarga, corrupción, metadatos, ACE, límites, fallos de IO, cambios externos y retirada.
Incluye un doble del contrato RapidJSON que reproduce sus metatablas de
decodificación, también cuando se pasan `nil`, y la regresión de creación del
snapshot. La corrección normaliza solo los marcadores propios del códec,
incluidos contenedores vacíos, sin relajar los contratos del dominio.
Las pruebas con dobles no ejecutan el módulo C++ ni equivalen a probar FXServer.

## Validación manual pendiente en FiveM

Según la confirmación del proyecto, la fase 0.1.0 ya funciona en FiveM. La fase
0.2.0 requiere todavía pruebas en FXServer y en el cliente real.

Colocar una copia en `resources` del perfil local de txAdmin con el directorio
`data` incluido. Al actualizar no sobrescribir los datos de una instalación previa.
Este trabajo no instala nada fuera del repositorio ni cambia el servidor.

En la consola del servidor o la consola en vivo de txAdmin:

```text
refresh
ensure os_security
osstatus
osdev create cctv_camera
osdev list
osdev info osd_0000000001
osdev state osd_0000000001 installing
osdev state osd_0000000001 installed
osdev state osd_0000000001 active
restart os_security
osdev info osd_0000000001
osdev create bodycam
osdev remove osd_0000000001
osdev state osd_0000000001 active
```

Si ya existen datos, usar los IDs realmente devueltos. Comprobar que el primer
dispositivo sigue `active` tras reiniciar, que el segundo tiene otro ID, que
`remove` conserva el registro `retired` y que la última transición se rechaza.
Comprobar también:

- `/oshello` y `/osstatus` con `chat` iniciado.
- `/osdev list` denegado sin el ACE, incluso para un grupo administrativo que no
  tenga concedido `ossecurity.admin`; con ACE, respuestas solo al solicitante.
- Tipo inexistente, salto `registered -> active` y páginas fuera de límites rechazados.
- `Debug = true` añade el nombre del recurso al inicio; restaurar después `false`.
- `stop os_security` y `ensure os_security` registran el ciclo de vida y recargan IDs.

Las comprobaciones de corrupción y errores de disco reales deben realizarse solo
sobre una copia de prueba con respaldo. La suite ya inyecta esos errores en memoria.
No se afirma haber superado estas pruebas reales de la fase 0.2.0 en FiveM.
