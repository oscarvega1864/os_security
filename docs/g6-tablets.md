# Gruppe Sechs — Tablets e instalación CCTV 0.4.1

Esta entrega incluye inventario y colocación CCTV, según el alcance autorizado.
La marca comercial cambia; `os_security`, `OSSecurity`, los IDs `osd_*`, los tipos
del Device Core y los archivos `data/devices.a/b.json` conservan su identidad.
No se modifica ningún archivo de otros recursos ni la configuración del servidor.

## Arquitectura

| Capa | Implementación y responsabilidad |
| --- | --- |
| Marca | `config/brand.lua`: nombres, colores, perfiles visibles, textos, servicios y módulos. |
| Ítems | `shared/items.lua`: catálogo, cantidades gestionadas por servidor y contrato de metadatos vacío. |
| Configuración servidor | `config/gameplay.lua`: ACE, capacidades, límites, materiales, herramientas y modelo autorizado. |
| Identidad | `server/security/identity.lua`: origen real conectado e identificador `license:` validado. |
| Inventario | `server/inventory/state.lua` y `standalone.lua`: operaciones tipadas, reservas, compensación y snapshots. |
| Autorización | `server/tablet/authorization.lua`: intersección de perfil profesional y acceso al dispositivo. |
| Sesiones | `server/tablet/sessions.lua`: origen, identidad, tablet, perfil, nonce, secuencia y caducidad. |
| Datos de tablet | `server/tablet/service.lua`: DTO filtrados y paginación del conjunto autorizado. |
| Controlador servidor | `server/tablet/controller.lua`: único enrutador de solicitudes; ningún inventario o estado completo aceptado del cliente. |
| Instalación | `server/installation/service.lua`: validación geométrica autorizada y recuperación de operaciones pendientes. |
| Composición | `server/gameplay.lua` y `server/main.lua`: almacenes, nativos, arranque, RPC privado y desconexión. |
| Cliente | `client/tablet.lua`: un controlador para ambas tablets e inventario. `view.lua`: foco/animación. `placement.lua`: preview. `props.lua`: objetos cercanos. `boot.lua`: conexión a FiveM. |
| Interfaz | `web/index.html`, `style.css`, `app.js`: una implementación con dos temas y navegación diferenciada. |
| Extensión | `server/integrations/contracts.lua`: contratos explícitos y estado real de cada integración. |

El evento `os_security:g6:request` obtiene el jugador del `source` del servidor.
Cada respuesta se envía exclusivamente al mismo origen. La sesión pertenece a un
solo origen/perfil/tablet; cambiar de tablet invalida la anterior. Se comprueban
identidad, vida, posesión, ACE y secuencia en cada solicitud. El nonce permanece
en Lua y no se entrega al navegador. Las solicitudes se limitan a 25 por 10 s y
las aperturas a 3 por 10 s; la sesión caduca tras 90 s sin solicitudes válidas.

La NUI solo presenta los datos autorizados; no decide permisos. Usa recursos
locales, texto DOM, CSP y callbacks estrictos. Escape, error de red, muerte,
timeout de NUI o detención liberan foco y objetos temporales. Los mensajes de
auditoría contienen acción, origen e ID técnico validado, sin payload, licencia,
nonce ni excepciones sensibles. `G6-E-*` es una acreditación visual; nunca una
clave de autorización ni un nombre tomado del jugador.

## Tablets y perfiles

| Acceso | Ítem obligatorio | ACE obligatorio | Alcance y operaciones |
| --- | --- | --- | --- |
| G6 Client | `g6_client_tablet` | `ossecurity.g6.client` | Consultar dispositivos propios o concedidos; sin mutaciones. |
| Técnico Operations | `g6_operations_tablet` | `ossecurity.g6.operations` + `ossecurity.g6.technician` | Inspeccionar, reparar, sustituir y equipar registros dentro de su alcance. Instalar en montajes asignados. |
| Supervisor Operations | `g6_operations_tablet` | `ossecurity.g6.operations` + `ossecurity.g6.supervisor` | Consultar e inspeccionar su alcance y pasar a mantenimiento; sin instalación/reparación/sustitución. |
| Administrador Operations | `g6_operations_tablet` | `ossecurity.g6.operations` + `ossecurity.admin` | Acceso global explícito y operaciones implementadas. La instalación sigue exigiendo montaje asignado. |

La prioridad profesional es administrador, supervisor, técnico. Si se conceden
varios roles se usa el de mayor prioridad, sin sumar capacidades. Un técnico no
puede declararse supervisor desde la NUI. Un permiso por dispositivo tampoco
concede un rol profesional. Propiedad y concesiones se resuelven mediante licencia
del servidor, nunca mediante el nombre visible. Los registros antiguos con otro
formato de propietario conservan sus datos: conceder acceso explícito con `osg6`.

Las concesiones `client`, `technician`, `supervisor` habilitan respectivamente
consulta, servicio técnico o supervisión, siempre intersectadas con el perfil.
`none` elimina la concesión adicional; no anula la propiedad del dispositivo.
`ossecurity.admin` por sí solo no abre Operations: también hacen falta su ítem y
el ACE específico de Operations. La consola puede ejecutar `osg6` sin tablet.

Reparar y sustituir siguen exigiendo estado administrativo `maintenance`. El
supervisor puede iniciarlo; un administrador usa el comando existente
`osdev state <id> active` para volver al servicio cuando corresponda. Los límites
y rechazos del Core permanecen vigentes. La sustitución usa el modelo compatible
predeterminado, sin permitir salud/modelos arbitrarios desde la interfaz. Esta
fase reutiliza el servicio lógico; no consume repuestos de inventario al reparar.

Client ofrece dispositivos y registro CCTV autorizado. Operations ofrece
dispositivos, instalaciones vinculadas, inventario, mantenimiento y registro CCTV.
Alarmas residenciales/comerciales, cerraduras, GPS, emergencias, contratos,
solicitudes e incidencias, órdenes, bodycams, rondas, central y transporte de fondos
se muestran deshabilitados. No se crean tickets, contratos o vídeo ficticios.
El historial mostrado en el detalle es la última intervención de componentes;
el historial paginado completo sigue disponible en `osmaint history`.

## Inventario standalone y persistencia

Ítems distintos de tablet: `g6_client_tablet`, `g6_operations_tablet`.
Equipo: `os_cctv_kit`, `os_alarm_kit`, `os_lock_kit`, `os_tracker_kit`, `os_drill`,
`os_screwdriver`, `os_battery`. Solo tablets y kit CCTV tienen uso implementado.
No existe una tablet genérica que sustituya a las dos. No se añade un framework.

El adaptador interno ofrece `load`, `get`, `has`, `grant`, `reserve`, `finish`,
`cancel`, `status`. Una integración futura debe mantener reservas persistentes y
compensación idempotente, además de identidad y posesión verificadas en servidor.
ESX, QBCore, Qbox y ox_inventory solo tienen contrato; no hay adaptadores funcionales.
Propiedades, vehículos y contratos de seguridad también siguen pendientes.

`data/inventory.a.json` y `data/inventory.b.json` guardan cuentas, concesiones,
montajes e instalaciones. Se reutiliza el journal de snapshots alternos con
validador y estado inicial inyectables. No cambia el comportamiento de almacenamiento
de dispositivos. Los datos locales continúan excluidos de Git.

Límites predeterminados: 256 cuentas, 100 unidades por ítem, 500 unidades por
cuenta, 1.000 concesiones por cuenta, 128 montajes, 1.000 instalaciones y 8 MiB
por snapshot. No hay truncado automático. Las unidades reservadas cuentan para
la capacidad, de modo que una devolución nunca depende de espacio liberado después.
No eliminar ítems/modelos en uso del catálogo sin una migración explícita.

La instalación cruza dos almacenes; usa una operación recuperable, sin afirmar
una transacción ACID entre archivos:

1. Persistir una reserva `pending` con materiales descontados y herramientas comprobadas.
2. Crear el dispositivo Core con el vínculo `metadata.installationId`.
3. Aplicar `registered → installing → installed → active` mediante el Core.
4. Persistir `committed` y conceder alcance técnico al instalador, dentro de una misma revisión de inventario.

El consumo predeterminado es un kit CCTV y una batería; taladro y destornillador
se comprueban y conservan. Cada reserva congela los materiales/herramientas usados
para que un cambio posterior de configuración no altere su compensación.
Al reiniciar, una reserva con dispositivo coincidente continúa sobre el mismo ID;
si se comprueba que no existe, se cancela y devuelve materiales una vez. Un
dispositivo retirado pendiente se compensa. Datos contradictorios o vínculos
duplicados bloquean el flujo. No se crea otra cámara para resolver una ambigüedad.

Ante retorno de escritura fallido, incluso si el archivo llegó a escribirse,
el almacén se bloquea. No se devuelve material a ciegas: se reconcilia al cargar
un conjunto validado. Ambos snapshots se verifican antes de sobrescribir y tras
escribir. Mantener un único escritor; conservar archivos y revisar diagnósticos
antes de reiniciar. Nunca borrar JSON para desbloquear. El almacenamiento sigue
sin prometer `fsync` o inmunidad a fallos físicos del disco.

## Colocación física y límites de OneSync

No hay coordenadas de ejemplo activadas. Un administrador debe registrar un punto
de montaje **medido sobre una superficie real**: centro, normal hacia fuera,
radio, propietario, instalador y routing bucket del instalador. Un montaje
pendiente no se puede reasignar. Un montaje ocupado no admite otra instalación;
retirar la cámara conserva su reserva histórica y no libera ese montaje.

El cliente realiza un raycast de geometría del mundo para mostrar un prop local
translúcido sobre un montaje compatible. La rueda gira la cámara, E confirma y
Retroceso/Escape cancela. Morir, entrar en vehículo, alejarse o superar 90 s cancela.
La previsualización se elimina antes de confirmar; nunca se persiste un handle de entidad.

El servidor exige perfil técnico/administrador Operations, ítem y equipo, sesión
válida y contexto de colocación de un solo uso. Verifica posición OneSync, bucket,
distancia de 4 m, movimiento máximo de 6 m, asignación del montaje, radio de
0,25–2 m, plano con tolerancia de 0,08 m, rotación y modelo permitido. Proyecta
al plano autorizado y aplica separación de 0,02 m. Recomprueba materiales al reservar.

**No existe un raycast de colisión del mapa en servidor.** La política autoritativa
es el plano de montaje levantado por un administrador; no demuestra por sí misma
la existencia de una pared, línea de visión o accesibilidad física. Las coordenadas
replicadas de OneSync no sustituyen un sistema contra teletransporte. Hay que validar
superficies y orientación en juego. La previsualización solo detecta geometría del
mundo; instalaciones sobre objetos móviles o interiores especiales quedan fuera.

Los props confirmados son locales, congelados y sin red. Cada cliente pide cada
5 s hasta 40 props a 80 m y en su bucket, reconstruidos desde instalaciones
confirmadas y dispositivos no retirados. La geometría visible se comparte con
jugadores cercanos; no requiere tablet. Ese paquete solo contiene ID, modelo,
posición y rotación. Consulta y mantenimiento permanecen sujetos a autorización.
Salir de zona/bucket o detener el recurso elimina los objetos locales.

No hay tick permanente por cámara. La preview usa un bucle por frame solo durante
la colocación; el servidor supervisa contextos activos cada 500 ms. Falta medir
`resmon` y profiler en FiveM con carga real; no se declara un coste medido.

Registro, autorización y sesiones CCTV están implementados. Representación de
imagen y transporte de señal están marcados `false`; no hay retransmisión remota.
La creación de un prop y el streaming de entidades de OneSync no implican que el
cliente pueda visualizar una cámara lejana. Bodycams sigue en registro lógico.

## Comandos

Los comandos de jugador se usan con `/` en el chat. Todos reciben validación real
del servidor; conocer el comando no evita el requisito de ítem/permisos.

| Comando | Función |
| --- | --- |
| `/g6inventory` | Consultar equipo propio y usar ítems con función implementada. |
| `/g6client` | Solicitar G6 Client con su ítem y ACE. |
| `/g6operations` | Solicitar G6 Operations con su ítem, ACE y perfil profesional. |
| `osg6 give <jugador> <item> <cantidad>` | Conceder ítems a una identidad conectada. |
| `osg6 inventory <jugador>` | Consultar cantidades del jugador indicado. |
| `osg6 access <jugador> <dispositivo> <client|technician|supervisor|none>` | Conceder o retirar alcance adicional sobre un dispositivo existente. |
| `osg6 anchor <id> <cliente> <instalador> <x> <y> <z> <nx> <ny> <nz> [radio]` | Registrar/actualizar un montaje autorizado; normaliza la normal. |
| `osg6 installations` | Consultar estado de instalaciones y vínculo Core. |
| `osg6 diagnose` | Ver disponibilidad del Core, inventario y flujo G6. |

Todos los subcomandos `osg6` requieren consola o `ossecurity.admin`. Los IDs de
jugador solo resuelven la identidad conectada en ese momento; no son claves
persistentes. Se conservan `osdev`, `osmaint`, `/oshello` y `osstatus`.

## Comprobación pendiente en FiveM

Ejecutar en un servidor de desarrollo con respaldo y OneSync disponible. No se ha
ejecutado esta entrega en FXServer/cliente FiveM. Los siguientes pasos son manuales;
el desarrollo no cambia `server.cfg`, ACL, licencias ni el perfil de txAdmin.

1. Iniciar `os_security` y ejecutar `osstatus` y `osg6 diagnose`. Revisar consola.
2. Autorizar expresamente perfiles de prueba. Ejemplo de grupos a introducir por
   el administrador en la consola; sustituir los marcadores por identidades de
   prueba reales mediante `add_principal identifier.license:<hex> <grupo>`:

   ```text
   add_ace group.g6_client ossecurity.g6.client allow
   add_ace group.g6_technician ossecurity.g6.operations allow
   add_ace group.g6_technician ossecurity.g6.technician allow
   add_ace group.g6_supervisor ossecurity.g6.operations allow
   add_ace group.g6_supervisor ossecurity.g6.supervisor allow
   ```

3. Con instalador conectado `1` y cliente `2` (sustituir por sus IDs actuales):

   ```text
   osg6 give 1 g6_operations_tablet 1
   osg6 give 1 os_cctv_kit 1
   osg6 give 1 os_battery 1
   osg6 give 1 os_drill 1
   osg6 give 1 os_screwdriver 1
   osg6 give 2 g6_client_tablet 1
   osg6 inventory 1
   osg6 anchor wall_01 2 1 <x> <y> <z> <nx> <ny> <nz> 0.75
   ```

   Medir la superficie y normal reales antes del último comando; no usar
   literalmente los marcadores. Situar al instalador a menos de 4 m del montaje
   y en el bucket correcto. No se proporciona un montaje ficticio que permita
   instalar sin comprobar la geometría del mapa.

4. Abrir `/g6inventory`, usar el kit, apuntar al montaje, orientar y confirmar.
   Comprobar retirada del kit/batería y conservación de herramientas. Consultar
   `osg6 installations` y `osdev info <id_real>`. Abrir ambas tablets con sus
   usuarios: el cliente ve su cámara; el instalador tiene alcance técnico.
5. Comprobar rechazo sin tablet, sin ACE, con ítem equivocado, sin materiales,
   sobre otro montaje, fuera de distancia o bucket. Un tercero sin concesión no
   debe ver la ficha aunque vea el prop cercano. Para registros previos usar
   `osg6 access <jugador> <id_real> client` o la concesión profesional apropiada.
6. Consultar componentes, pasar a mantenimiento con supervisor autorizado y probar
   inspección/reparación/sustitución respetando límites del Core. La salud cercana
   a 100 puede impedir reparar; debe rechazarse sin reducirla. No existe vídeo.
7. Reiniciar el recurso y reconectar: comprobar ítems, mismo ID/prop, concesiones
   y ausencia de duplicados. Acercarse/alejarse y cambiar bucket para verificar
   reconstrucción. Probar muerte, cancelación, timeout, desconexión, Escape,
   cambio rápido de tablet y parada: sin foco retenido ni objetos huérfanos.
8. En copia aislada respaldada, validar recuperación de instalaciones interrumpidas
   y fallos de IO. No corromper los datos habituales. Medir resmon/profiler en reposo,
   con colocación activa y varios clientes/cámaras; anotar resultados reales.

Las suites automatizadas usan Lua 5.4 Wasmoon, nativos simulados y archivos en
memoria. La prueba Chromium abre los assets reales y verifica visibilidad,
identidad, temas, controles, DOM seguro, cierre y errores con RPC simulado.
No verifica CEF de FiveM, animaciones GTA, colisiones, buckets ni vídeo remoto.
Referencias oficiales: [NUI](https://docs.fivem.net/docs/scripting-manual/nui-development/full-screen-nui/),
[callbacks y modo estricto](https://docs.fivem.net/docs/scripting-manual/nui-development/nui-callbacks/),
[OneSync](https://docs.fivem.net/docs/scripting-reference/onesync/).
