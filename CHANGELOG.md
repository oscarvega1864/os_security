# Changelog

## 0.16.1 — Montaje del arco con herramientas y minijuego

- Montar y desmontar el arco detector exige **taladro y destornillador** (se conservan), como alarmas y cámaras.
- Minijuego propio del arco: **montar** = anclar las dos bases al suelo (taladrar), atornillar los postes y conectar
  la unidad de control (sensores izquierdo y derecho, zumbador); **desmontar** = desconectar la unidad y soltar los
  pernos. Cancelar o fallar no gasta el arco ni lo retira.
- `/arco recoger` pasa a ser del cliente: el servidor comprueba empresa, arco y herramientas antes del minijuego y
  vuelve a comprobarlo al retirarlo.

## 0.16.0 — Arco detector de metales y cacheo

- Objeto **Arco detector de metales** (tienda G6, 4.800 $). Lo coloca cualquier empleado de servicio de una empresa
  (os_devtools): fantasma delante, rueda para girar, E para colocar. El arco es de su empresa y solo ella lo recoge
  (`/arco recoger`). Se usa el modelo de arco del juego si existe; si no, se dibuja con marcadores (`/arcomodelo` lo dice).
- Al cruzarlo pita (tres pitidos y luz roja) si se lleva metal: objetos de metal del inventario o armas con metal
  (lista en `shared/weapons.lua`); si no, un pitido y luz verde. Avisa a los empleados de esa empresa cercanos.
- **Cacheo** (`/cacheo` a quien tienes delante): lo pide un empleado de servicio de cualquier empresa o personal G6;
  el cacheado acepta o rechaza y, si acepta, pone las manos en alto. El vigilante palpa 8 zonas del cuerpo y ve lo que
  hay en cada una; puede retener armas y objetos peligrosos (herramienta, ganzúa, taladro, destornillador).
- Lo retenido queda en **custodia** de su empresa; el dueño lo recoge en el mismo sitio con `/custodia` (mismo
  personaje). Las armas del ped se quitan y se devuelven con su munición.
- Limitación: las armas las informa el cliente del jugador (no hay inventario de armas en el servidor todavía).

## 0.15.0 — Central de operaciones y Emergencias

- Avisos guardados de la central: salto de alarma, manipulación de un teclado (bloqueo por códigos fallidos) y
  botón de pánico. Un salto repetido de la misma central con su aviso abierto suma al mismo aviso (x2, x3…).
  Los cerrados se borran pasados 7 días.
- G6 Client → **Emergencias**: botón de pánico donde estás o en una de tus propiedades, con nota opcional. Llega al
  momento a todo el personal G6 de servicio, con punto en el mapa. Un aviso activo por cliente y 60 s entre avisos;
  el cliente ve quién acude y la resolución, y puede cancelarlo si fue una falsa alarma.
- G6 Operations → **Central de operaciones**: avisos por prioridad (pánico, alarma, manipulación). El técnico se
  asigna un aviso (GPS) o lo devuelve; el supervisor lo asigna a un compañero de servicio; se cierra con una nota
  obligatoria que le llega al cliente.
- Al saltar una alarma, el titular recibe su aviso de siempre y el personal G6 solo el de la central (sin duplicados).

## 0.14.0 — Vincular el personaje con gruppe6.es (fase 2)

- `/g6web`: código de un solo uso (8 caracteres, 10 minutos) que solo ve el jugador, para vincular su
  personaje con su cuenta de gruppe6.es (Extranet o Intranet) desde Configuración → Personaje de FiveM.
  Solo se muestra si la web lo ha recibido; no se guarda en disco ni en los registros; uno por minuto.
- `/g6web estado` y `/g6web desvincular` (avisa a la web). La web confirma cada vínculo o desvinculación y
  el jugador recibe un aviso si está conectado.
- Puente web: envío inmediato de eventos que no deben esperar en la cola y generador de valores aleatorios
  para códigos.

## 0.13.0 — Puente con la web de Gruppe Sechs (fase 1)

- Conexión opcional y firmada con gruppe6.es (`ossecurity_web_url`, `ossecurity_web_secret`): sin configurar
  no cambia nada. OS Security inicia siempre la conexión por HTTPS; la web nunca llama al servidor de juego.
- Seguridad: HMAC-SHA256 sobre cliente, versión de clave, fecha (±90 s), nonce de un solo uso, ruta, clave de
  idempotencia y hash del cuerpo; las respuestas de la web también van firmadas y se descartan si no
  verifican. SHA-256/HMAC en Lua puro, comprobados con los vectores oficiales y con el de la web.
- Tolerante a caídas: eventos en cola persistente (`data/web_bridge.json`) reenviados con el mismo cuerpo y
  clave; comandos de la web aplicados una sola vez y confirmados. Consola: `g6bridge`.
- Base para las fases siguientes (vinculación `/g6web`, solicitudes web ↔ tablet, estados ampliados).

## 0.12.1 — Cada personaje con lo suyo

- Corregido: con objetos por personaje (`ossecurity_items os_inventory`), los dispositivos, zonas, concesiones
  y solicitudes eran de la cuenta, así que otro personaje de la misma cuenta veía cámaras, alarmas y
  solicitudes que no eran suyas. Ahora el titular es el personaje activo.
- Al arrancar, los datos antiguos de cada cuenta pasan al único personaje que hizo sus instalaciones. Si los
  hicieron varios personajes no se adivina: se avisa en consola y quedan sin mostrarse.
- `set ossecurity_ownership account` mantiene el comportamiento anterior (compartido por cuenta).

## 0.12.0 — Solicitudes y órdenes de trabajo

- G6 Client → Solicitudes de mantenimiento: pedir a Gruppe Sechs un trabajo (cámaras, alarma, reparación,
  bombín, vehículo u otro) con una descripción, donde estás o en una de tus propiedades. Máximo 3 en curso;
  se pueden cancelar hasta que estén facturadas y se pagan desde la tablet (banco).
- G6 Operations → Órdenes de trabajo (técnicos con perfil de instalación): las órdenes abiertas con su lugar
  y distancia; aceptar (queda a tu nombre y se marca en el GPS), soltar o facturar con un importe (máx.
  $25.000). Los técnicos de servicio reciben un aviso con cada solicitud nueva y el cliente, al aceptarse y
  al facturarse.
- Al pagar el cliente, el técnico cobra el 60 % al momento o, si no está conectado, la próxima vez que abra
  las órdenes. Las órdenes cerradas se borran a los 30 días. Configuración en `Orders` de
  `config/gameplay.lua`.

## 0.11.1 — Vista de cámaras sin solaparse con el HUD

- El HUD de la vista en directo va centrado (REC, hora y cámara arriba; ayuda abajo) y deja libres las
  esquinas, donde están el chat y los HUD de otros mods.
- Al entrar y salir de la vista se emite el evento local `os_security:cameraView` (true/false) para que otros
  HUD se oculten; os_devtools ya oculta su ID y dinero con él.

## 0.11.0 — Cámaras en directo

- Cámaras CCTV en directo desde la tablet (Client y Operations): botón "Ver en directo" en las cámaras con
  señal. La pantalla pasa a la cámara instalada con filtro de videovigilancia y HUD (REC, fecha y hora,
  cámara y sitio); ratón o flechas para girar, rueda o + / - para zoom, Q / E para cambiar de cámara y
  Retroceso para volver a la tablet. Solo con acceso al dispositivo; sin señal si no está instalada, está en
  mantenimiento o avería, o falla la alimentación o la óptica; una óptica gastada mete ruido en la imagen.
  El personaje queda quieto mientras mira y recibir daño corta la vista.
- Tienda: F10 → Gruppe Sechs → "Tienda: en la calle de Union Depository" (la carretera más cercana, donde
  salía el furgón de las misiones) y "Tienda: mover a mi posición", para sacar el mostrador a un sitio
  accesible. Se guarda en `data/shop.json` y llega al momento a todos los jugadores.

## 0.10.0 — Tienda Gruppe Sechs

- Tienda en el mostrador de Union Depository (blip, marcador y E): catálogo por categorías, cantidades,
  carrito y pago con banco o efectivo del personaje activo.
- Al público: tablet Client, bombines, kits de cierre y alarma de vehículo, destornillador y baterías.
  Solo personal G6 de servicio (o ACE técnico, supervisor o admin): kits CCTV y de alarma, taladro y tablet
  Operations. La ganzúa no se vende.
- Todo validado en el servidor: cerca del mostrador, catálogo, cantidades (máx. 10 por producto), total y
  saldo. Se cobra una vez y se entrega cada producto con su identificador de operación; lo que no cabe en el
  inventario se devuelve al momento.
- Dinero con `ossecurity_money_resource` (por defecto `os_devtools`: `ChargeCharacter`, `PayCharacter`,
  `GetCharacterBalance`); `none` cierra la tienda. Precios y ubicaciones en `config/shop.lua`.
- Instalaciones: la zona más cercana sale primero y se marca como "Aquí"; en las lejanas el botón dice a
  cuántos metros están. Enlace fijo de descarga de la última versión en el README.

## 0.9.0 — Instalaciones desde la tablet

- G6 Operations → Instalaciones: eliges el cliente (tú o un jugador a tu lado), marcas la zona con un visor
  de cámara (E fija la superficie, flechas mueven, + y − cambian el tamaño, E hace la foto) y la zona aparece
  como una ficha tipo foto con lugar, cliente, superficie, tamaño y estado. Desde la ficha se instala la
  cámara o la alarma con el kit elegido (a menos de 4 m) y se borran las zonas sin usar.
- Las zonas quedan vinculadas a la propiedad o negocio del cliente si está cerca.
- G6 Client: Cerraduras (puertas de tus propiedades), Localizadores (tus vehículos con equipo G6 y marca en
  el GPS) e Historial de incidencias (sucesos de tus alarmas).
- Las secciones aún no programadas ya no aparecen en el menú de las tablets.
- Releases en GitHub: zip del recurso con su versión y changelog al publicar una etiqueta `vX.Y.Z`.

## 0.8.0 — Puente

- Arrancar sin llave un vehículo OS con destornillador: segunda pulsación de Y, minijuego del vehículo en modo
  puente (tapa de la columna, +12V con Llave, arranque en la franja verde con fusibles). Dificultad según el
  equipo del vehículo; con alarma salta y avisa al dueño. El dueño recibe aviso y su llave lo revoca.

## 0.7.0 — Ganzúa

- `os_lockpick` para forzar puertas cerradas (dificultad según el bombín: 3, 5 o 7 pines y zona verde
  menor) y vehículos cerrados (3 pines sin cierre, 5 con cierre centralizado), con minijuego de pines.
- Validación en el servidor: objetivo elegido por el servidor, distancia, objeto y tiempo mínimo por pin.
  Éxito: abre, avisa al dueño y la alarma del vehículo salta. Fallo: la ganzúa puede romperse.
- Editor de zonas con + y −; paso de cables del vehículo con nombres claros.

## 0.6.0 — Vehículos: cierre centralizado y alarma

- Kits `os_car_lock_kit` y `os_car_alarm_kit` para vehículos de os_devtools, instalados al volante con el
  motor apagado por el dueño, un técnico G6 de servicio o un admin, con minijuego propio (grapas del
  embellecedor, multímetro y empalmes, prueba del mando). Cobro idempotente al terminar.
- Mando (tecla L): abrir y cerrar con destellos y pitido; estado persistente reaplicado a las entidades.
- Alarma armada al cerrar: un intento de entrar de otra persona la hace sonar y avisa al dueño.
- `osg6 cars` y entrada en el panel F10.
- Llave en todos los vehículos con matrícula OS: abrir/cerrar a mano (L, 3,5 m) sin kit y motor con la tecla
  Y solo para el dueño; el juego deja de arrancarlos solo al subirse.

## 0.5.1 — Montajes y puertas desde el panel F10

- F10 → Gruppe Sechs: crear zona de montaje (abre el editor de apuntar, nombre automático y propiedad
  opcional), añadir la puerta apuntada y dar de baja la puerta más cercana, sin comandos.
- Un montaje creado para una propiedad o negocio vincula a ella el dispositivo que se instale.

## 0.5.0 — Cerraduras de puertas

- Puertas reales (GTA o MLO) de cada propiedad o negocio con titular, detectadas automáticamente por el
  primer jugador cercano y validadas en el servidor (titular, distancia, radio, duplicados y límites).
- Llave (E) para el titular actual o un administrador; puertas dobles a la vez; propiedades cerradas y
  negocios abiertos por defecto; sin titular quedan libres. Estado aplicado con el sistema de puertas de GTA.
- Bombines por niveles: de serie, `os_lock_kit` (seguridad) y `os_lock_kit_high` (alta seguridad), con
  minijuego propio de cambio (tornillo de fijación, leva alineada, bombín nuevo) y devolución del retirado.
- Export `GetDoorSecurity`, `osg6 doors`, `osg6 door remove`, `/g6puerta` y entradas en el panel F10.

## Sin publicar — Proveedor externo de objetos

- `ossecurity_items=os_inventory`: tablets, kits, herramientas y materiales por personaje activo en
  `os_inventory`; `standalone` sigue siendo el valor por defecto.
- Instalación CCTV con reserva local con titular y cobro/devolución externos idempotentes; recuperación
  que liquida cobros sin perder ni duplicar objetos, y espera si el proveedor no está disponible.
- "Usar" el kit CCTV desde el inventario inicia la colocación con la autorización completa.
- Perfiles Técnico/Supervisor de la tablet Operations por empleo `gruppe6` de servicio
  (`GetActiveEmployment` de os_devtools), además de los ACE; revocación en la siguiente
  petición al salir de servicio y desactivable con `ossecurity_employment_resource none`.
- Desmontaje de cualquier dispositivo instalado desde la tablet (técnico con acceso o propietario), junto al
  dispositivo y con herramientas, con minijuego inverso (desconectar y desatornillar): retira el dispositivo,
  libera el montaje y devuelve el kit. Teclado de alarma con cuenta atrás en vivo y resincronización.
- Alarmas: sirena propia generada en la NUI (Web Audio) con volumen por distancia, en lugar de un sonido de
  GTA inexistente; pitidos del teclado y del retardo de entrada. Chapa directa: tecla G junto al teclado o
  Usar la chapa desde el inventario. Corrección: VerifyPasswordHash devuelve 1 en el binding de Lua y el
  código correcto se daba por incorrecto y bloqueaba el teclado.
- Alarmas de propiedades y negocios: kit de alarma instalable (productos genéricos de instalación), teclado
  en la pared con pinpad y lector de chapa, modos total y parcial, retardos de salida y entrada, bloqueo
  por códigos incorrectos, sirena, avisos al titular y a G6 de servicio, historial y control desde la
  tablet Client (código con hash, chapas programables y revocables). Sección Alarmas habilitada.
- Minijuegos de instalación interactivos con ratón: taladrar cuatro anclajes (mantener sobre la marca,
  temperatura de la broca y resbalones), atornillar girando el ratón en sentido horario (fuerza y roscas
  pasadas) y enlazar los cables arrastrándolos hasta su borne. Prueba de navegador que los completa.
- Minijuego de instalación con herramienta en la mano y animación por fase: taladro
  (`hei_prop_heist_drill`, `anim@heists@fleeca_bank@drilling`) con sonido mientras se mantiene pulsado,
  destornillador y cableado, más sonidos de acierto y error. Cada modelo, animación y banco de sonido se
  comprueba en el juego y, si falta, esa parte se omite.
- Sección **Gruppe Sechs** en el panel y la consola de `os_admin` (opcional): dispositivos, mantenimiento,
  equipo, accesos, vínculos e instalaciones mediante los comandos existentes y su mismo ACE.
- `osmaint fault <id> <slot> <salud>`: avería controlada de una pieza para pruebas y demostraciones;
  solo baja la salud, se registra en el historial y se reproduce al validar el almacenamiento.
- Profundidad de la cámara ajustable con Q/Z en el editor (−0,15 a +0,30 m respecto a la superficie),
  guardada tal cual por el servidor; `/g6anchor` fija la superficie y permite mover la zona con las
  flechas. Se descarta el asentado automático por dimensiones del modelo, que la hundía en la pared.
- Zonas de montaje cuadradas con editor `/g6anchor` (vista en vivo, tamaño con la rueda) en paredes,
  techos o suelos; colocación con inclinación de hasta 90° y montaje invertido (R). Minijuego de
  instalación en tres fases (taladrar, atornillar y cablear); fallar o salir cancela sin consumir.
- Corrección: montajes y colocaciones guardan coordenadas a 0,1 mm, normales a 9 decimales y ángulos a
  0,01°. Los residuos del raycast (p. ej. 2e-17) no se releían exactos con el JSON del runtime y el
  guardado se bloqueaba por integridad. El error de integridad indica ahora la ruta y los valores.
- Editor de colocación CCTV: la vista previa se ancla al montaje (sin seguir la mira) y se ajusta
  con flechas sobre los ejes X/Y de la pared, Mayús+flechas para girar e inclinar, Ctrl fino, Tab
  para cambiar de montaje y E/Intro para colocar, limitado al radio e inclinación del servidor.
- `/g6anchor`: alta de montajes apuntando a la pared en el juego, revalidada en el servidor (ACE,
  distancia real, datos y bucket); `osg6 anchor` comparte la misma lógica.
- Vínculo de dispositivos con propiedades y negocios de os_devtools (`osg6 site`): el titular del
  personaje activo los consulta en la tablet Client; titularidad revalidada en cada petición.
- La tablet Operations muestra el perfil (Técnico, Supervisor, Administrador) con su color, sus
  funciones y oculta los módulos que el perfil no puede usar (Instalaciones sin `install`).
- Avisos de tablet e instalación con tipo a través de `os_notify` (opcional) y vuelta al chat estándar.
- "Usar" las tablets desde el inventario, cierre de sesiones al cambiar de personaje, `osg6 migrate`
  idempotente y `osg6 give/inventory` sobre el proveedor.

## 0.4.1 — Gruppe Sechs, doble tablet e instalación CCTV

- Adaptador administrativo OSCAR opcional, tras verificar el contrato existente:
  consulta `os_devtools:HasOscarPermission` solo para `ossecurity.admin` y conserva
  ACE directo. No añade dependencia ni modifica roles G6, ítems, alcance por
  dispositivo o datos. Cinco regresiones de revocación, proveedor ausente, errores
  y separación de permisos; 101 pruebas Lua pasan con ambos códecs de desarrollo.
- Marca centralizada Gruppe Sechs: nombres, identificación visual de empleados y
  dispositivos, temas, textos y denominaciones. El recurso sigue siendo
  `os_security`; se conservan IDs, tablas, snapshots y contratos anteriores.
- Dos ítems independientes: `g6_client_tablet` y `g6_operations_tablet`. NUI local
  original con tema claro Client y oscuro Operations, controlador común, tablet
  en mano, callbacks acotados y limpieza de foco/props al cancelar o detener.
- Autorización del servidor mediante identidad `license`, ítem, ACE profesional
  y alcance por dispositivo. Sesiones ligadas al origen con caducidad, secuencia,
  límites de solicitudes y revalidación en cada operación. Ningún rol del cliente
  ni nombre visible concede permisos. Salt nativo de sesión calculado una vez,
  evitando repetir bcrypt en cada apertura. Los nonces no llegan a la NUI.
- Inventario standalone con catálogo y metadatos vacíos validados, cantidades
  acotadas y almacenamiento alterno independiente `data/inventory.a/b.json`.
  Reutiliza el journal existente mediante validación/estado inicial inyectables;
  conserva relectura, rechazo de corrupción y bloqueo por fallos de escritura.
- Colocación CCTV con previsualización local, orientación, cancelación y montaje
  autorizado. El servidor comprueba asignación, posición OneSync, bucket, radio,
  plano, materiales y herramientas; el raycast del cliente es solo visual. No
  hay raycast del mundo ejecutado por el servidor ni montajes ficticios iniciales.
- Reserva persistente antes de crear el dispositivo, vínculo opcional
  `metadata.installationId`, transiciones reales del Core y confirmación del
  consumo. Recuperación de reservas tras interrupciones, compensación comprobada
  y rechazo de duplicados/resultados ambiguos. No se borran datos existentes.
- Props CCTV locales reconstruidos por proximidad y bucket, separados de la
  autorización de consulta. Nunca se emite el registro completo a clientes.
- Mantenimiento existente accesible según perfil y alcance, conservando intactos
  los cálculos de desgaste y las validaciones de las fases 0.2/0.3. Comandos
  `osg6` administrativos y `/g6inventory`, `/g6client`, `/g6operations`.
- Módulos futuros y adaptadores ESX/QBCore/Qbox/ox_inventory identificados como
  no disponibles. Contratos para propiedades, vehículos, personal, servicios,
  instalaciones, mantenimiento, CCTV y bodycams. Vídeo remoto expresamente no
  implementado: separados registro, permisos, sesión, representación y señal.
- 96 pruebas Lua pasan con ambos códecs de desarrollo y 6 pruebas NUI pasan en
  Chromium con APIs simuladas. Incluyen sesiones, acceso, reservas, consumo,
  compensación, reinicios, corrupción, IO ambiguo, limpieza y seguridad DOM.
  Validación real de FiveM/CEF, animación, geometría, OneSync y rendimiento pendiente.

## 0.3.0 — Componentes y mantenimiento

- Catálogo configurable de piezas y modelos compatibles por slot y tipo de
  dispositivo. Identidades por generación y contratos completos de componente.
- Desgaste determinista en servidor, calculado bajo demanda por intervalos
  persistentes. Incluye horas, intensidad, calidad de instalación y de pieza,
  entorno, límites de tiempo acumulado y registro de horas descartadas.
- Estados de salud `healthy`, `worn`, `degraded`, `critical`, `failed`, con causas
  derivadas del uso y parámetros. Independientes del estado administrativo.
- Inspección, diagnóstico, simulación controlada, reparación limitada y sustitución
  explícita. Historial con parámetros y resultados antes/después; sin reemplazos
  aleatorios, bucles por dispositivo, objetos físicos, NUI ni minijuegos.
- Comando servidor `osmaint`, protegido por `ossecurity.admin`, con consultas e
  historial paginado; se conservan los comandos anteriores y sus permisos.
- Dispositivos nuevos con esquema 2 y kit lógico. Migración explícita de registros
  de esquema 1 mediante `osmaint provision`, conservando datos e intervenciones
  heredados. El contenedor de snapshots sigue en esquema 1 y admite convivencia.
- Cada servicio persistido se reproduce desde el snapshot anterior antes de
  aceptarlo, incluidas las migraciones. Se mantienen snapshots alternos, rechazo
  de corrupción, comprobación por relectura y normalización de retornos nativos.
- Escalares de mantenimiento normalizados a 12 cifras significativas para evitar
  pérdida de precisión con dkjson, manteniendo la comparación exacta de integridad.
- Pruebas automatizadas de compatibilidad, desgaste, reinicio, límites, averías,
  reparación, sustitución, historial, permisos, migración y fallos de persistencia.
  La ejecución real de esta fase en FiveM queda pendiente.

## 0.2.0 — Device Core

### Corrección del resultado de SaveResourceFile y diagnóstico de persistencia

- El adaptador propagaba el resultado nativo sin normalizar. El almacen exigia
  `true` literal y rechazaba el entero `1` del binding Lua aun cuando el archivo
  ya estaba escrito. La regresion de arranque/comandos reprodujo ese bloqueo.
  La inspeccion de solo lectura encontro revisiones consecutivas 1 y 2, con
  uno y dos dispositivos, en los snapshots del recurso enlazado por Junction.
- Nuevo adaptador `resource_files.lua`: convierte exclusivamente `true` y `1`
  a exito booleano. Conserva la longitud `#content` en bytes. No hay escrituras
  alternativas con `io`, cambios de rutas, extensiones, esquema o sandbox.
- Se conservan snapshots alternos y verificacion integra por relectura antes de
  confirmar. Un resultado falso o ambiguo no se convierte en exito por encontrar
  bytes escritos; sigue bloqueando el registro para su revision.
- Diagnosticos por etapa: `validation`, `serialization`, `corruption`, `permission`,
  `write`, `read` e `integrity`. Incluyen revision, slot, tamanos y tipo/resultado
  nativo; las trazas de exito requieren `Debug`. No incluyen JSON ni excepciones.
  Se identifica permiso denegado por errno 13 o una excepcion explicita de acceso;
  un retorno fallido sin errno se informa como escritura de causa no determinada.
- 44 pruebas pasan con cada codec de desarrollo. Cubren enteros/booleanos,
  longitud UTF-8, persistencia, corrupcion y diagnosticos. Los datos reales se
  inspeccionan sin modificarlos; no se borran ni reinicializan archivos.
- Se intento arrancar una copia aislada del FXServer local con un recurso de
  prueba enlazado mediante Junction, sin configuracion ni credenciales del perfil
  habitual. El binario exigio licencia antes de ejecutar el recurso: la prueba
  nativa queda pendiente. No se atribuye el fallo al Junction ni se cambian ACL.
- Referencias: [native de escritura](https://github.com/citizenfx/fivem/blob/master/code/components/citizen-scripting-core/src/MetadataScriptFunctions.cpp)
  y [control de escritura por recurso](https://github.com/citizenfx/fivem/blob/master/code/components/citizen-scripting-core/src/FilesystemPermissions.cpp).

### Corrección de compatibilidad JSON de FXServer

- Causa: `store.save()` comprobaba el JSON generado con `codec.decode()` y
  `DeviceValidation.snapshot()`. El runtime usa RapidJSON; pasar `nil` como
  `objectmeta`/`arraymeta` conserva las metatablas JSON predeterminadas. Por eso
  `Util.object()` rechazaba el snapshot legítimo y devolvía
  `Serializacion invalida: Formato o version de almacenamiento incompatible.`
  Las pruebas anteriores usaban dkjson heredado, donde esos `nil` sí eliminan
  las metatablas, y no reproducían el comportamiento del runtime.
- Solución: proporcionar metatablas marcadoras explícitas y retirar solo esas
  marcas del resultado decodificado, recursivamente, antes de validar. Los
  marcadores `null` y las metatablas desconocidas conservan su rechazo. No se
  relajan validadores ni se cambian esquema, IDs o snapshots alternos.
- Las tablas vacías pueden codificarse como `[]` con la configuración de FiveM.
  Se mantiene la aceptación de contenedores vacíos según su contrato, tanto
  `{}` como `[]`, sin alterar las opciones globales del JSON ni reescribir datos.
- Regresión: el doble del contrato RapidJSON reproduce el error antes del
  arreglo. Después pasan 37 pruebas con el puente JSON y con dkjson heredado,
  incluyendo creación, recarga, tablas vacías, `null`, corrupción y fallos de IO.
  No se ejecutó el módulo nativo C++ ni un FXServer real durante esta corrección.
- Referencias: [decodificador Cfx RapidJSON](https://github.com/citizenfx/lua-rapidjson/blob/60f4dd4e3f04c64e04d74b69c1ff41397fc01e53/src/lua_rapidjson.cpp)
  y [opciones del runtime FiveM](https://github.com/citizenfx/fivem/blob/master/data/shared/citizen/scripting/lua/scheduler.lua).

### Implementación inicial

- Registro exclusivamente en servidor con IDs persistentes y consultas paginadas.
- Catálogo central de siete tipos y validación extensible de metadatos.
- Máquina de estados con historial, retirada irreversible y límites explícitos.
- JSON con snapshots alternos, validación de carga, comprobación de escritura
  y bloqueo ante corrupción, errores de IO o cambios externos.
- Interfaz de almacenamiento preparada para un adaptador futuro, sin MySQL.
- Permiso ACE `ossecurity.admin`, autorización por operación y límites por jugador.
- Comando `osdev` con `list`, `create`, `info`, `state` y `remove`.
- Contratos separados para instalación, componentes, salud y mantenimiento;
  sin simulación, reparaciones ni sustituciones funcionales.
- Pruebas automatizadas en Lua 5.4 y documentación de validación real pendiente.
- Conservados `/oshello`, `osstatus` y los registros `[OS SECURITY]`.

## 0.1.0 — Recurso base

- Manifiesto `cerulean`/`gta5`, configuración y separación cliente/servidor.
- Comandos de diagnóstico y registros de inicio y detención.
