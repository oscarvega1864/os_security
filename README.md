# Gruppe Sechs — OS Security 0.4.1

Recurso standalone para FiveM y GTA V Legacy. La experiencia comercial pertenece
a Gruppe Sechs; el nombre técnico sigue siendo `os_security`. Incluye Device Core,
componentes, mantenimiento, inventario persistente, dos tablets y colocación física
CCTV. No requiere frameworks ni MySQL. Conserva los comandos anteriores.

`g6_client_tablet` abre G6 Client; `g6_operations_tablet` abre G6 Operations. Cada
tablet exige su propio ítem y autorización del servidor. El catálogo CCTV y los
props colocados son funcionales; **no hay transmisión de vídeo remoto**. Alarmas,
cerraduras, GPS, bodycams, contratos y demás servicios futuros aparecen pendientes.
No se implementan minijuegos. Las piezas siguen siendo referencias lógicas.

Consultar [arquitectura, permisos y prueba completa de las tablets y colocación](docs/g6-tablets.md).

La administración admite además el export opcional `HasOscarPermission` de
`os_devtools`, exclusivamente para `ossecurity.admin`. Debe existir una delegación
explícita y vigente verificada por ese servicio. Los ACE siguen funcionando por sí
solos; desactivar con `AdminAuthorizationResource = false`. Este adaptador no
concede tablets, empleos, roles G6 ni acceso de cliente a dispositivos. Los errores,
parada o revocación del proveedor deniegan la delegación en la siguiente consulta.

## Proveedor de objetos

Por defecto (`standalone`) las tablets, kits, herramientas y materiales viven en el registro propio
de OS Security, por cuenta (`license`). Es el modo portable y no requiere otros recursos.

En el entorno OSCAR pueden vivir en `os_inventory`, por **personaje activo** de `os_devtools`:

```cfg
set ossecurity_items os_inventory        # antes de ensure os_security
# Opcionales: set ossecurity_items_resource os_inventory / set ossecurity_identity_resource os_devtools
```

- Requiere que `os_inventory` autorice a `os_security` en su `ResourceAccess` y que `os_devtools` lo incluya en `IdentityReaders`.
- Montajes, instalaciones y concesiones por dispositivo siguen en el registro local; solo cambian los objetos.
- Abrir una tablet comprueba el objeto en el personaje activo. "Usar" la tablet en el inventario la abre (con la autorización completa del servidor). Un cambio de personaje cierra las sesiones G6.
- "Usar" el kit CCTV en el inventario inicia directamente la colocación: el cliente abre una sesión de inventario oculta y pide el mismo `use` que la tablet, así que el servidor exige tablet G6 Operations, permiso de instalación, herramientas, materiales y un montaje libre cercano. Nada se cobra hasta confirmar la colocación.
- Instalar una cámara registra la reserva con el personaje (`holder`) y después cobra kit y batería con identificadores de operación fijos (`g6i_…:take:<item>`). Si falla la creación, o al recuperar una reserva huérfana, se devuelven (`g6i_…:refund:<item>`) liquidando antes cada cobro: repetir nunca cobra ni devuelve dos veces. Las herramientas no se consumen.
- Si el proveedor no está disponible al arrancar, las reservas externas pendientes se dejan pendientes (sin bloquear) y se resuelven en un arranque posterior. Una devolución no confirmada bloquea la recuperación en lugar de perder objetos.
- `osg6 give` e `osg6 inventory` usan el proveedor. `osg6 migrate <jugador>` pasa los objetos locales de la cuenta al personaje activo; la clave de operación incluye el total migrado por objeto, así que repetirlo tras una interrupción no duplica.
- No reutilizar identificadores de instalación borrando los datos de OS Security: los recibos del proveedor quedarían asociados a IDs antiguos.

## Perfiles G6 por empleo

Además de los ACE, la tablet Operations se puede autorizar por el empleo del personaje
activo. Por defecto se lee de `ossecurity_identity_resource` (os_devtools) mediante
`GetActiveEmployment`; `set ossecurity_employment_resource none` lo desactiva.

| Empleo (`GameplayConfig.Employment`) | Perfil |
| --- | --- |
| `gruppe6` / `tecnico`, de servicio | Técnico |
| `gruppe6` / `supervisor`, de servicio | Supervisor |
| Cualquier otro, o fuera de servicio | Ninguno (solo ACE) |

```text
/setjob <idJugador|alias> gruppe6 tecnico
/setduty <idJugador|alias> on
```

Sigue haciendo falta poseer `g6_operations_tablet`. El perfil se revalida en cada
petición: salir de servicio o cambiar de empleo cierra la sesión en la siguiente acción.
Con objetos por personaje, el empleo debe ser del mismo personaje que tiene la tablet.
El empleo nunca concede `admin` ni la tablet Client. Los ACE tienen prioridad, y si el
proveedor falla o no está iniciado no se concede nada por empleo.

## Propiedades y negocios

Un dispositivo se puede vincular a una propiedad o negocio de os_devtools. El titular, con
ese personaje activo, lo ve en su tablet Client (solo consulta) sin concesión manual:

```text
osg6 site <dispositivo> propiedad <id>
osg6 site <dispositivo> negocio <id>
osg6 site <dispositivo> none
```

El servidor comprueba que la propiedad o negocio existe. La titularidad se consulta en cada
petición (`GetAsset` y `GetActiveCharacter`): si cambia el propietario o el personaje
activo, deja de verse. La tarjeta muestra "Propiedad 200" o "Negocio 3 · Nombre". El vínculo
no da acceso a Operations ni a mantenimiento. `set ossecurity_sites_resource none` lo
desactiva. Sigue haciendo falta la tablet Client y el ACE `ossecurity.g6.client`.

## Mensajes al jugador

Los avisos de la tablet y de la instalación (errores, "cargando", CCTV registrado o colocación cancelada)
usan `os_notify` si está iniciado, con su tipo (error, aviso, éxito o información); si no, el chat
estándar, como antes. No es una dependencia: OS Security sigue siendo portable. Las respuestas de los
comandos administrativos (`osdev`, `osmaint`, `osg6`, `osstatus`) y `/oshello` siguen en el chat porque
incluyen listados.

## Arquitectura

| Archivo o directorio | Responsabilidad |
| --- | --- |
| `fxmanifest.lua` | `cerulean`, `gta5` y orden explícito de scripts por contexto. |
| `config/config.lua` | Versión y depuración compartidas; no introducir secretos. |
| `config/brand.lua`, `shared/items.lua` | Marca, temas, textos, módulos e ítems distintos de cada tablet. |
| `config/gameplay.lua` | Perfiles, sesiones, materiales, colocación e inventario; solo servidor. |
| `config/server.lua` | ACE, límites y ubicación del almacenamiento, solo servidor. |
| `config/components.lua` | Catálogo de piezas, modelos, slots compatibles y políticas de mantenimiento. |
| `shared/constants.lua`, `client/main.lua` | Prefijos y saludo local `/oshello`. |
| `server/core/util.lua` | Validación de tipos, comparación y copia de datos. |
| `server/devices/catalog.lua`, `states.lua` | Tipos de dispositivo y máquina administrativa. |
| `server/devices/validation.lua` | Contratos de dispositivo/snapshot y reproducción de cambios entre revisiones. |
| `server/devices/registry.lua` | API de dispositivos, servicio, paginación y confirmación de persistencia. |
| `server/components/catalog.lua` | Resuelve kits y modelos compatibles con cada slot. |
| `server/components/wear.lua` | Fórmula pura, umbrales de salud y evaluación temporal. |
| `server/components/migration.lua` | Promoción explícita de dispositivo v1 a v2, conservando datos heredados. |
| `server/components/lifecycle.lua` | Inspección, reparación, sustitución, simulación y resultados de intervención. |
| `server/components/validation.lua` | Contratos de piezas, políticas, operaciones y referencias de historial. |
| `server/storage/codec.lua` | Compatibilidad RapidJSON/dkjson y control de JSON completo. |
| `server/storage/resource_files.lua` | APIs FiveM, longitudes en bytes y retornos `true`/`1`. |
| `server/storage/json.lua` | Snapshots alternos, integridad y diagnósticos por etapa. |
| `server/security/permissions.lua` | ACE y límites temporales de solicitudes. |
| `server/commands/devices.lua`, `maintenance.lua` | Subcomandos `osdev` y `osmaint`. |
| `server/main.lua` | Conexión con FiveM, arranque, detención y `osstatus`. |
| `server/inventory/` | Dominio validado y adaptador standalone con snapshots propios. |
| `server/security/identity.lua`, `server/tablet/` | Identidad estable, autorización, sesiones, DTO y controlador compartido. |
| `server/installation/`, `server/gameplay.lua` | Reserva persistente, instalación CCTV y recuperación entre almacenes. |
| `server/integrations/contracts.lua` | Contratos y capacidades explícitas de futuras integraciones. |
| `server/commands/gameplay.lua` | Administración ACE de ítems, accesos y montajes. |
| `client/tablet.lua`, `view.lua`, `boot.lua` | Controlador, foco NUI, tablet en mano y conexión con FiveM. |
| `client/placement.lua`, `props.lua` | Previsualización por raycast y props locales cercanos. |
| `web/` | Interfaz original compartida con temas Client y Operations. |
| `tests/` | Núcleo, JSON, mantenimiento, inventario, permisos, sesiones, colocación y navegador. |
| `package.json`, `package-lock.json`, `.npmrc` | Herramientas de prueba y caché dentro del repositorio. |
| `data/.gitkeep`, `.gitignore` | Directorio vacío versionado y exclusión de datos locales. |
| `AGENTS.md`, `CHANGELOG.md` | Reglas de trabajo e historial de versiones. |

Todo el mantenimiento se ejecuta en el servidor. Un único evento de solicitud G6
centraliza la validación de origen, sesión, secuencia, ítem, ACE y alcance. Los
clientes reciben DTO filtrados; no pueden sustituir dispositivos ni enviar salud
arbitraria. No hay exports administrativos. Las consultas internas devuelven copias.

## Dispositivos y componentes

Tipos: `cctv_camera`, `alarm_panel`, `alarm_sensor`, `smart_lock`, `vehicle_tracker`,
`bodycam`, `security_monitor`.

Se conservan ID persistente `osd_0000000001`, tipo, modelo lógico, estado,
propietario opcional, `propertyId` o `vehicleId`, posición/rotación opcionales,
fechas Unix, metadatos validados e historial administrativo. Posición finita dentro
de ±1.000.000 y rotación dentro de ±360 grados. Los metadatos admiten solo las
propiedades declaradas por tipo. CCTV admite ahora el vínculo opcional
`installationId`; los demás contratos anteriores se conservan.

Los dispositivos nuevos usan `schemaVersion = 2` y reciben un kit lógico:

| Dispositivo | Slots y tipos de pieza |
| --- | --- |
| Cámara CCTV | `power`: `power_supply`; `optics`: `optical_module` |
| Panel de alarma | `power`: `power_supply`; `controller`: `control_board` |
| Sensor | `power`: `power_supply`; `sensor`: `signal_sensor` |
| Cerradura | `power`: `power_supply`; `actuator`: `lock_actuator` |
| Localizador | `power`: `power_supply`; `radio`: `radio_module` |
| Bodycam | `power`: `power_supply`; `optics`: `optical_module`; `storage`: `storage_module` |
| Monitor | `power`: `power_supply`; `display`: `display_panel` |

Cada pieza contiene `id`, `generation`, `type`, `model`, `state`, `health` (0–100),
`quality`, `installedAt`, `lastMaintenanceAt` opcional, `expectedLifetimeHours`,
parámetros `wear` e índices `history` de sus intervenciones. El ID incluye
`<deviceId>:<slot>:<generation>`; una sustitución incrementa la generación.
Las fechas describen el ciclo lógico del registro, sin afirmar instalación física.

`installation.quality` pertenece a la instalación. La salud de piezas está en
`condition.components`. Ningún cambio de salud cambia automáticamente el estado
administrativo del dispositivo; un `active` puede tener una pieza `failed`.
El diagnóstico global utiliza la salud mínima de las piezas.

Estados de salud:

| Salud | Estado |
| --- | --- |
| 80–100 | `healthy` |
| 60–menos de 80 | `worn` |
| 30–menos de 60 | `degraded` |
| Mayor que 0–menos de 30 | `critical` |
| 0 | `failed` |

## Configuración y desgaste

La versión es `0.4.1`. `Debug = true` activa trazas técnicas de almacenamiento;
reiniciar el recurso para aplicar cambios de configuración.

Valores iniciales de `config/components.lua`:

| Parámetro | Valor |
| --- | --- |
| Intervalo de evaluación | 60 segundos |
| Máximo de tiempo por evaluación | 72 horas |
| Máximo por simulación solicitada | 24 horas |
| Intensidad de uso / factor ambiental | 1 / 1 |
| Calidad de instalación predeterminada | 75 sobre 100 |
| Recuperación por reparación | Hasta 25 puntos |
| Techo de salud por reparación | 90 |
| Reparar una pieza `failed` | Desactivado; requiere sustitución |

El catálogo define calidad y vida nominal por modelo. La calidad de instalación
usa la del dispositivo si existe; en otro caso usa el valor predeterminado.
Todos estos parámetros se copian a la pieza al crearla o sustituirla: editar los
valores predeterminados no altera retroactivamente el desgaste de piezas existentes.
No eliminar ni reasignar modelos o slots que estén en uso sin una migración:
la compatibilidad forma parte del contrato validado de los datos.

La pérdida de salud es:

```text
horas × (100 / vidaNominalHoras) × intensidad × ambiente
      × (2 - calidadInstalacion / 100) × (2 - calidadPieza / 100)
```

Se aplica únicamente cuando el estado administrativo es `active`. La vida nominal
corresponde a calidades 100, intensidad 1 y ambiente 1. No hay azar. El diagnóstico
expone causas como tiempo de operación, intensidad alta, entorno, calidad y fin de
vida útil. La vida estimada no garantiza una fecha de avería.

La evaluación es **bajo demanda**: `inspect`/`diagnose`, intervenciones y cambios
de estado usan marcas persistidas, sin bucles por dispositivo ni dependencia del
FPS. `list` muestra la última condición confirmada y no recalcula. Las inspecciones
consumen intervalos completos; al cambiar de estado se liquida también la fracción
activa para no perder tiempo entre pausas. El tiempo inactivo queda excluido.

Un estado `active` persistido acumula tiempo entre evaluaciones, también durante
una parada del servidor. Se limita a 72 horas por defecto y el exceso se registra
en `discardedHours`, avanzando la marca para no volver a aplicarlo. No representa
una medición de uptime del proceso. El reloj no retrocede respecto al último cambio.

`simulate` añade horas controladas sin adelantar el reloj real ni su marca futura.
Es una herramienta administrativa deliberada y queda registrada. Los escalares
nuevos de mantenimiento se normalizan a 12 cifras significativas para permitir una
serialización exacta con los códecs de prueba. Se mantiene la comparación estricta
entre el candidato y el JSON recuperado.

## Mantenimiento, historial y migración

Reparar o sustituir exige el estado administrativo `maintenance`. La reparación
conserva identidad, horas y fecha de instalación; aumenta salud hasta los límites
configurados y actualiza la fecha de mantenimiento. Si no puede mejorar la salud,
se rechaza. La sustitución requiere un modelo compatible, crea otra generación con
salud 100 y horas 0, y conserva los resultados históricos de la pieza anterior.
No hay sustituciones automáticas.

`maintenance.events` conserva operación, parámetros y resultados antes/después,
con IDs, modelos, salud, estado y horas. `component.history` referencia las entradas
que afectan a esa identidad. Una pieza nueva empieza su propio historial; las
intervenciones de las anteriores siguen en el historial del dispositivo.
La evaluación temporal no llena ese historial: usa un contador de servicio y su
última operación reproducible. Una inspección sin cambios no escribe.

Los registros de esquema 1 de la fase 0.2 se leen sin escribir ni cambiar sus
componentes reservados. Para equiparlos explícitamente:

```text
osmaint provision <id>
```

Requiere `registered`, `installed` o `maintenance`. Si el dispositivo antiguo está
`active` o `fault`, pasarlo primero a `maintenance` con `osdev state`. `provision`
crea el kit lógico nuevo y conserva los componentes/eventos antiguos íntegros en
`maintenance.legacy`. No convierte automáticamente piezas sin tipo conocido ni
borra el historial administrativo. El comando no se puede repetir en un v2.

El contenedor JSON mantiene esquema 1 porque su estructura no cambia; pueden
convivir dispositivos v1 y v2. Cada promoción se guarda como una operación normal
y solo se publica tras verificar la escritura. Los fallos conservan la revisión
confirmada. El historial paginado incluye primero los eventos heredados.

## Permisos y comandos

La consola (`source == 0`) puede administrar. Los jugadores requieren el ACE
`ossecurity.admin` en consultas y mutaciones; `group.admin` no lo concede por sí
solo. Un administrador puede concederlo explícitamente en su consola:

```text
add_ace group.admin ossecurity.admin allow
```

Este recurso no ejecuta esa concesión ni modifica `server.cfg`. Las respuestas del
juego se envían solo al solicitante mediante el `chat` estándar. En el chat se
antepone `/` a los comandos; `/oshello` y `/osstatus` conservan su comportamiento.

| Comando de consola | Resultado |
| --- | --- |
| `osstatus` | Estado, versión y disponibilidad del núcleo. |
| `osdev list [offset] [limit]` | Dispositivos ordenados por ID. |
| `osdev create <type>` | Dispositivo nuevo v2 con kit lógico compatible. |
| `osdev info <id>` | Resumen del dispositivo. |
| `osdev state <id> <state>` | Transición administrativa válida. |
| `osdev remove <id>` | `retired` conservando datos e historial. |
| `osmaint list <id>` | Componentes y condición guardada. |
| `osmaint inspect <id>` | Evalúa intervalos pendientes y persiste si hay cambios. |
| `osmaint diagnose <id>` | Inspección con estados y causas; mismo cálculo. |
| `osmaint simulate <id> <horas>` | Horas adicionales controladas; exige `active`. |
| `osmaint repair <id> <slot>` | Recuperación limitada; exige `maintenance`. |
| `osmaint replace <id> <slot> [modelo]` | Sustitución compatible; exige `maintenance`. |
| `osmaint history <id> [offset] [limit]` | Intervenciones y resultados paginados. |
| `osmaint provision <id>` | Migración/equipamiento lógico explícito de un v1. |

Los estados administrativos conservan estas transiciones:

```text
registered  -> installing, retired
installing  -> installed, registered, retired
installed   -> active, maintenance, fault, retired
active      -> maintenance, fault, retired
maintenance -> installed, active, fault, retired
fault       -> maintenance, retired
retired     -> (ninguno)
```

La API interna usa punto en scripts del mismo recurso cargados después de `main`:
`OSSecurity.Registry.create/get/list/setState/retire`,
`service(source, id, kind, args)` y `serviceHistory(source, id, offset?, limit?)`.
Devuelve datos copiados o `nil, error`; `service` recibe argumentos específicos,
sin permitir objetos completos o salud arbitraria. `source = 0` solo debe originarse
en trabajo de servidor de confianza, nunca en argumentos del cliente.

## Persistencia, límites y recuperación

Se mantienen `data/devices.a.json` y `data/devices.b.json`, excluidos de Git. Cada
cambio escribe en el slot alterno con `SaveResourceFile`, enviando `#content` en
bytes y aceptando solo `true` o `1` del binding. Se verifica después con
`LoadResourceFile`. Cada revisión cambia un solo dispositivo mediante una creación,
transición o servicio reproducible desde la anterior. La revisión cuenta eventos
administrativos y operaciones de servicio; no se permiten sustituciones libres.

Se validan ambos snapshots al cargar. Un archivo corrupto, versiones incompatibles,
IDs inconsistentes, cambios externos o historial alterado bloquean el registro.
No hay recuperación silenciosa ni sobrescritura de datos corruptos. Un fallo de
escritura o relectura impide confirmar la operación y bloquea el núcleo. Un fallo
de serialización previo a escribir conserva disponible el estado confirmado.

Los diagnósticos `[storage:<etapa>]` distinguen validación, serialización, corrupción,
permisos detectados, escritura, lectura e integridad. No registran datos sensibles
ni textos de excepciones. `Debug` muestra revisión, slot, bytes y retorno nativo.
Un fallo nativo sin errno se informa como escritura de causa indeterminada; no se
supone que sea un error del Junction o de permisos.

Límites: 1.000 dispositivos incluyendo retirados, páginas de 20/máximo 100,
256 eventos administrativos, 128 intervenciones nuevas y hasta 128 heredadas,
32 piezas y 8 MiB por snapshot. Los jugadores autorizados tienen 30 consultas y
5 mutaciones por ventana de 10 segundos; la consola no tiene límite temporal.
Inspecciones y diagnósticos usan el cupo de mutaciones porque pueden guardar.
El último evento administrativo se reserva para retirar. Un historial de servicio
lleno impide nuevas intervenciones sin truncarlo; permite evaluar desgaste y retirar.

Ante corrupción: detener, conservar ambos archivos, revisar el error y restaurar
un conjunto verificado manteniendo el historial y la secuencia máxima de IDs. No
borrar archivos ni restaurar contadores obsoletos para desbloquear. Eliminar ambos
snapshots o restaurar datos antiguos puede perder registros y reutilizar IDs.

Riesgos: el adaptador serializa el conjunto completo y no ofrece transacciones
`fsync` frente a cualquier fallo físico. Una operación que devolvió error podría
aparecer tras reiniciar si la escritura se completó: consultar antes de reintentar.
Los archivos deben tener un solo escritor. Las capacidades son intencionadamente
acotadas; un límite de tamaño alcanzado rechazará cambios sin confirmarlos.
Los datos v2 no son legibles por el código 0.2: respaldar antes de probar y no
revertir código sobre snapshots convertidos sin planificar recuperación.

## Pruebas automatizadas

Node.js 22+ y npm se utilizan solo en desarrollo. Wasmoon ejecuta Lua 5.4 en
WebAssembly, con fixtures en memoria y caché dentro del repositorio:

```powershell
npm.cmd ci --cache .tools/npm-cache --ignore-scripts --no-audit --no-fund
npm.cmd test
node tests/run.cjs --codec 'E:\Fivem-DEV\server\citizen\scripting\lua\json.lua'
npm.cmd run test:ui
```

El segundo modo lee dkjson heredado, sin modificarlo; ese archivo no es el módulo
RapidJSON nativo de FXServer. La suite incluye dobles de sus metatablas y de los
retornos de archivos, además de regresiones de precisión, desgaste, reinicio,
reparación, sustitución, historial, migración, permisos y fallos de persistencia.
Las suites Lua pasan 101/101 con cada códec de desarrollo. La prueba de interfaz
pasa 6/6 en Chromium local y deja capturas en `.tools/g6-browser/`. Requiere
Chrome/Edge o `G6_BROWSER_PATH`; utiliza respuestas de servidor simuladas. No se
añaden dependencias de navegador al recurso. Los scripts JavaScript se comprueban
también con `node --check`. Ninguna prueba equivale a ejecutar servidor o cliente
FiveM, ni el códec RapidJSON nativo.

## Comprobación pendiente en FiveM

Esta fase no se ha ejecutado en FiveM. No se modifican el perfil txAdmin ni sus
credenciales, configuración o recursos externos. Para probar, usar una instalación
local de prueba con respaldo y un único recurso que escriba en estos datos.

Para inventario, permisos, montaje físico, reinicio y limpieza de las tablets,
seguir la [secuencia de validación 0.4.1](docs/g6-tablets.md#comprobación-pendiente-en-fivem).
Requiere OneSync y puntos de montaje reales registrados por un administrador.

Con un ID nuevo realmente devuelto por `create`:

```text
refresh
ensure os_security
osstatus
osdev create cctv_camera
osmaint list <id>
osdev state <id> installing
osdev state <id> installed
osdev state <id> active
osmaint simulate <id> 24
osmaint inspect <id>
osdev state <id> maintenance
osmaint repair <id> power
osmaint replace <id> power
osmaint history <id> 0 20
restart os_security
osmaint list <id>
```

Con valores predeterminados, una simulación de 24 horas puede dejar la salud por
encima del techo 90 de reparación: en ese caso reparar debe rechazarse, sin reducir
salud. Para probar recuperación, usar un modelo de vida nominal menor configurado
en una copia de prueba. Comprobar también migración de un registro v1 respaldado,
denegación sin ACE, respuestas privadas, retirada terminal, conservación de IDs,
`/oshello`, `/osstatus` y registros de inicio/detención. Los fallos de disco y
corrupción reales deben probarse solo en una copia con respaldo; ya se inyectan
en las pruebas automatizadas.
