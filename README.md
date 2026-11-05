# OS Security — Fase 0.1

Recurso base standalone para comprobar el entorno local de FiveM con GTA V Legacy,
FXServer y txAdmin. Versión inicial: `0.1.0`.

Esta fase contiene únicamente configuración, comandos de prueba y registros de
inicio y detención. No incluye cámaras, alarmas, cerraduras, bodycams,
localizadores, minijuegos ni NUI propia.

## Estructura

```text
os_security/
├── fxmanifest.lua
├── config/
│   └── config.lua
├── client/
│   └── main.lua
├── server/
│   └── main.lua
├── shared/
│   └── constants.lua
├── README.md
└── .gitignore
```

| Archivo | Función |
| --- | --- |
| `fxmanifest.lua` | Declara `cerulean`, `gta5` y las rutas de los scripts. Carga constantes y configuración antes de los scripts de cada contexto. |
| `config/config.lua` | Centraliza `Version` y `Debug` en `OSSecurity.Config`. |
| `shared/constants.lua` | Define el prefijo de registros y el título del chat en `OSSecurity.Constants`. |
| `client/main.lua` | Registra `/oshello` y muestra un saludo en el chat local. |
| `server/main.lua` | Registra `/osstatus` y los mensajes de inicio y detención del recurso. |
| `.gitignore` | Excluye archivos locales de editores, registros, temporales y archivos `.env`. |
| `README.md` | Describe configuración, instalación y comprobaciones manuales. |

## Configuración

Editar `config/config.lua` y reiniciar el recurso para aplicar los cambios:

```lua
OSSecurity.Config = {
    Version = '0.1.0',
    Debug = false
}
```

`Version` es la fuente de la versión mostrada en registros y en `/osstatus`.
`Debug = true` añade un registro con el nombre del recurso al iniciarlo.
La configuración compartida se envía a los clientes: no debe contener secretos.

## Requisitos

- FXServer con soporte para `cerulean` y GTA V (`gta5`).
- Cliente FiveM para GTA V Legacy.
- Sin frameworks ni librerías externas.
- Para ver los mensajes en el juego, debe estar iniciado el recurso `chat`
  estándar incluido con FXServer, que atiende el evento `chat:addMessage`.
  La consulta y los registros de consola funcionan sin el chat.

## Instalación y prueba manual

La carpeta de desarrollo por sí sola no hace que FXServer descubra el recurso.
Cuando se quiera probar, colocar una copia de `os_security` dentro de la carpeta
`resources` del perfil activo de txAdmin, conservando el nombre `os_security`.
Este proyecto no modifica `server.cfg` ni instala archivos en el servidor.

1. En la consola del servidor o en la consola en vivo de txAdmin, ejecutar:

   ```text
   refresh
   ensure os_security
   osstatus
   ```

2. Comprobar estos mensajes en la consola (FiveM puede añadir su propio prefijo):

   ```text
   [OS SECURITY] Recurso iniciado. Version: 0.1.0
   [OS SECURITY] Estado: started | Version: 0.1.0
   ```

3. Conectarse al servidor y escribir `/oshello` en el chat del juego. Debe mostrar
   `OS SECURITY` seguido de `Hola. OS Security esta funcionando.`
4. Escribir `/osstatus` en el chat. Debe mostrar el estado y la versión al jugador
   que ejecuta el comando y registrar la consulta en la consola del servidor.
5. Ejecutar `restart os_security` desde la consola. Deben aparecer los registros
   de detención e inicio con el prefijo `[OS SECURITY]`.
6. Ejecutar `stop os_security`. Debe aparecer el registro de detención y los
   comandos dejarán de estar disponibles. Ejecutar `ensure os_security` para
   volver a iniciarlo.
7. Para comprobar depuración, cambiar `Debug` a `true`, reiniciar y verificar
   `[OS SECURITY] [DEBUG] Nombre del recurso: os_security`. Restaurar `false`
   y reiniciar al terminar.

## Comandos

| Comando | Dónde ejecutarlo | Resultado |
| --- | --- | --- |
| `/oshello` | Chat del juego | Saludo local de comprobación. |
| `/osstatus` | Chat del juego | Estado y versión; responde al solicitante y registra la consulta en el servidor. |
| `osstatus` | Consola del servidor o txAdmin | Estado y versión en la consola, sin barra inicial. |

Los comandos son de diagnóstico y no requieren permisos ACE. Solo están
disponibles mientras el recurso está iniciado. Los registros de ciclo de vida
pertenecen al servidor y filtran los eventos de otros recursos.

## Validación y límites

Comprobaciones realizadas durante la creación:

- Sintaxis de los cinco archivos Lua validada con `luaparse` 0.3.1 en modo
  Lua 5.3; el código utiliza sintaxis común compatible con Lua 5.4. No se
  dispone de `lua`/`luac` local para una comprobación con el compilador nativo.
- Rutas del manifiesto y orden de carga de los scripts compartidos verificados.
- Declaraciones `cerulean` y `gta5`, ausencia de NUI y de dependencias declaradas
  verificadas.
- Reglas de `.gitignore` comprobadas para configuración de editor, registros
  y archivos `.env`; los scripts del recurso no quedan excluidos.

Las pruebas manuales anteriores describen el resultado esperado. La ejecución
real en FXServer y en el cliente FiveM queda pendiente; crear o revisar estos
archivos no equivale a haber probado el recurso en el juego.

Si no aparece el saludo, comprobar que `chat` está iniciado y que la consola F8
no muestra errores. Si FXServer no encuentra el recurso, revisar la ubicación
de la copia dentro de `resources` y ejecutar `refresh`.

El repositorio Git es local a esta carpeta; no se configura ningún remoto ni se
modifican otros repositorios.
