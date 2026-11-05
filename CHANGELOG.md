# Changelog

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
