# Changelog

## Sin publicar

- **Arco detector con interruptor**: `/arco encender`, `/arco apagar` (o `/arco interruptor` para cambiar) junto a un
  arco de tu empresa, de servicio. Apagado no detecta, no pita ni avisa (tampoco la vigilancia del servidor) y muestra
  el rótulo "ARCO APAGADO"; encendido tiene una luz verde tenue. El estado se guarda y sobrevive a reinicios.

## 0.27.5 — Arco detector vigilado por el servidor

- **Arco detector vigilado por el servidor**: antes solo sonaba si el cliente avisaba al cruzarlo, así que un cliente
  modificado podía pasar sin que pitara. Ahora el servidor comprueba 4 veces por segundo quién está bajo cada arco y,
  si lleva metal en el inventario (objetos metálicos o armas), lo hace sonar y avisa a la empresa aunque el cliente
  no diga nada. El paso limpio (luz verde) lo sigue dando el aviso del cliente.

## 0.27.4 — Tiempo mínimo en los minijuegos

- **Seguridad**: los minijuegos de instalar cierre o alarma en un coche, cambiar el bombín y sustituir piezas en una
  visita tienen un tiempo mínimo en el servidor (2, 2 y 3 s). Un "superado" instantáneo de un cliente modificado se
  rechaza sin gastar nada, como ya pasaba con la ganzúa y el puente.

## 0.27.3 — Arco detector y armas del inventario

- **Arreglado**: el arco detector no pitaba con un arma guardada en el inventario (os_inventory 0.2.0+) si no se
  llevaba en la mano: solo contaba los objetos de la lista de metal. Ahora pitan también las armas metálicas que son
  objetos del inventario, las informe o no el cliente.

## 0.27.2 — Aviones, helicópteros y barcos con llave

- **Arreglado**: los aviones, helicópteros y barcos de os_devtools no tienen matrícula en GTA y el servidor no los
  reconocía (los buscaba por matrícula): el motor quedaba bloqueado esperando la llave pero la llave no servía.
  Ahora se reconocen por la marca de os_devtools (state bag `osdev` con su ID, que solo pone el servidor), así que
  funcionan con su llave-tarjeta como los coches (Y para arrancar; sin ella, puente). Los coches se siguen
  reconociendo también por matrícula.

## 0.27.1 — Autotest accesible

- La última fase del cambio en el sitio ya no pide memorizar una secuencia: se enciende un piloto, parpadea y espera
  a que lo pulses; luego el siguiente (3, o 4 con el equipo completo). Sin tiempo y sin errores: pulsar otro solo
  recuerda cuál toca. Cada piloto lleva su número y el nombre del color, para quien distinga mal los colores.

## 0.27.0 — Minijuego propio para la sustitución en el sitio

- «Hacer el cambio» tiene su propio minijuego, distinto del de montar y del de calibrar, en cuatro fases:
  1. **Diagnóstico** con el polímetro: mantener en la toma de cada módulo para medirlo y marcar los que salen fuera
     de rango (marcar uno sano cuenta como error).
  2. **Extraer**: abrir el pestillo y tirar del módulo despacio; si tiras rápido, sube la tensión del conector y se
     doblan los pines.
  3. **Encajar** el módulo nuevo girándolo (rueda del ratón o ⟳) hasta que la muesca coincida con la de la ranura.
  4. **Autotest de arranque**: repetir la secuencia de pilotos que enciende el equipo.
- Con «Sustituir todo el equipo» todas las piezas salen averiadas en el diagnóstico y el autotest es más largo.
  Tres errores en una fase cancelan el cambio.

## 0.26.2 — La visita llega siempre al dueño

- «Sustituir» en un equipo montado crea siempre la visita y avisa a su dueño, también cuando el dueño es el propio
  técnico (antes, en ese caso, se cambiaba a distancia sin solicitud).

## 0.26.1 — Guardado bloqueado tras sustituir una pieza

- **Arreglado**: tras sustituir una pieza, al pasar el equipo a mantenimiento el guardado fallaba con
  `[storage:integrity] Serialización altera los datos` y el almacenamiento quedaba bloqueado hasta reiniciar. Las
  horas de uso de una pieza recién puesta (1 s = 0,000277… h) tenían una mantisa larga que el JSON del runtime no
  relee exacta. Los valores de desgaste se guardan ahora con como mucho 9 decimales.
- La comprobación de integridad (y la de cambios reproducibles al cargar) acepta diferencias de redondeo de coma
  flotante por debajo de una milmillonésima relativa; enteros, textos y estructura se siguen comparando exactos.

## 0.26.0 — Sustitución en el sitio con visita al cliente

- En G6 Operations, «Sustituir» una pieza (o el nuevo «Sustituir todo el equipo») de un equipo **montado con dueño** ya
  no la cambia a distancia: crea una **visita** (orden de trabajo «Sustitución en el sitio») a nombre del técnico y
  avisa al cliente, con el punto en el mapa, de que irá a su propiedad. El cliente la ve en sus solicitudes.
- En el sitio, **«Hacer el cambio»** (en la ficha del equipo o en la orden): junto al equipo y con taladro y
  destornillador, minijuego de instalación y se cambia la pieza o el equipo completo. El equipo vuelve solo a
  servicio, el cliente recibe el aviso y la orden queda lista para facturar (antes no se puede facturar).
- En equipos propios o sin montaje físico, sustituir sigue siendo inmediato; «Sustituir todo el equipo» cambia todas
  las piezas a la vez.

## 0.25.3 — Memoria del servidor

- Las esperas entre botones de pánico y entre solicitudes de trabajo se guardaban por personaje y no se borraban
  nunca; en un servidor encendido muchos días crecían sin límite. Ahora se borran al caducar (reconectar sigue sin
  saltarse la espera).

## 0.25.2 — Textos con ñ y tildes sin cortes rotos

- Las notas, nombres y textos que escribe un jugador (avisos, órdenes, contratos, rondas, zonas, bodycams, arco) se
  recortaban por bytes y podían partir una «ñ» o una letra con tilde por la mitad, dejando texto inválido. Ahora el
  recorte nunca parte una letra. Lo mismo con las etiquetas de objetos y el detalle que llega de la web.
- La limpieza de texto y los identificadores (`ct_`, `av_`, `ot_`, `rd_`, `md_`, `cu_`) se comparten en
  `server/core/util.lua` (`util.clean`, `util.cut`, `util.nextId`) en lugar de estar copiados en cada servicio.

## 0.25.1 — Ayuda de los comandos

- El chat sugiere con su descripción y parámetros `/g6client`, `/g6operations`, `/g6inventory`, `/bodycam`,
  `/bodycamajuste`, `/g6web`, `/g6puerta`, `/g6anchor` y `/arcomodelo` (antes solo `/arco`, `/cacheo`,
  `/custodia` y `/ronda`).
- `/ronda` sin argumentos ya no se queda en silencio: explica dónde se empiezan las rondas y cómo abandonarlas.

## 0.25.0 — Textos con tildes y eñes

- Todos los textos visibles (tablets, vista de cámaras, avisos, minijuegos, tienda, objetos, armas, mensajes del
  servidor y sección de administración) se escriben ya con tildes y eñes: «Cámara», «Sin señal: óptica averiada»,
  «Configuración», «Batería», «Ganzúa»... Los identificadores, claves, cabeceras y comentarios no cambian.
- El buscador de la tablet no distingue tildes: «camara» encuentra «Cámara».

## 0.24.2 — Nombres legibles

- La central, los contratos, las rondas y las bodycams muestran el personaje como nombre («Oscar Vega · jugador»)
  en lugar del alias interno (`oscar_vega`). La identidad interna no cambia.

## 0.24.1 — Registro más claro

- Los mensajes informativos («N puertas detectadas en…», «Datos de… asignados al personaje…») ya no salen con la
  etiqueta `[ERROR]` en la consola del servidor; esa etiqueta queda solo para fallos reales.

## 0.24.0 — Volver a servicio desde la tablet

- **Nuevo**: botón **Volver a servicio** en la ficha de un dispositivo en mantenimiento (G6 Operations). Hasta ahora
  la tablet podía abrir el mantenimiento pero no cerrarlo, y los dispositivos se quedaban en `maintenance` (sin
  imagen en directo) hasta que un administrador los cambiaba desde F10.
  - Lo pueden usar técnico, supervisor y administrador (con su alcance sobre el dispositivo).
  - Vuelve a `active` si está montado físicamente y a `installed` si es solo un registro.
  - Con alguna pieza averiada (salud 0) se niega: primero hay que sustituirla.

## 0.23.3 — Contratos y rondas más robustos

- Contratos: si se quita o renombra un plan en `config/gameplay.lua`, los contratos que ya lo tenían siguen
  apareciendo (sin ventajas) en lugar de romper la lista de contratos, la central y las rondas; un plan de
  `PlanOrder` sin definir simplemente no se ofrece.
- Rondas: lejos del siguiente punto de control el cliente ya no ejecuta un bucle en cada frame (comprueba cada
  medio segundo y solo dibuja el marcador a menos de 60 m).

## 0.23.2 — Chapa de alarma

- **Arreglado**: la chapa de alarma actuaba dos veces. El pase de chapa del teclado y el del objeto (sin teclado
  abierto) usaban el mismo evento, así que el servidor ejecutaba los dos: en el teclado la alarma se armaba y se
  volvía a desarmar en el mismo gesto, y con el objeto salía un error además del resultado. El pase sin teclado usa
  ahora su propio evento (`os_security:alarm:tagNearest`).
- Prueba que impide registrar dos veces el mismo evento de red en el servidor o en el cliente.
- Los fallos de alarmas y cerraduras indican el punto del código. Las tareas periódicas (alarmas, arcos, contratos y
  bodycams) ya no ocultan sus fallos: avisan como mucho una vez por minuto con el punto del código.

## 0.23.1 — Vista en directo de las cámaras

- **Arreglado**: «Ver en directo» no hacía nada en la tablet cuando, entre los dispositivos que ve el perfil, había
  alguno que no era una cámara (por ejemplo una central de alarma). Al montar la lista de cámaras para cambiar con
  Q / E el servidor daba una excepción y la petición fallaba. Ahora solo se tienen en cuenta las cámaras.
- El registro de fallos de solicitudes de la tablet indica la acción y el punto del código (sin payload ni texto de la
  excepción), para poder localizar un fallo así sin depurar.
- La lista de bienes con puertas ignora entradas sin datos válidos del proveedor en lugar de fallar.

## 0.23.0 — Vista de cámaras con la plantilla G6

- La vista en directo de las cámaras usa la plantilla de cámaras de Gruppe 6: logo arriba a la izquierda, etiqueta
  ● REC arriba a la derecha y el nombre de la cámara abajo (`CAMARA n - sitio`), con la hora abajo a la derecha.
  La ayuda de controles se desvanece a los pocos segundos. `Brand.Text.live.logo = false` usa la plantilla sin logo.
- Cámaras sin señal: al pasar de cámara con Q / E (o al revalidar) una cámara instalada sin señal ya no cierra la
  vista; muestra la pantalla **NO VIDEO** de la plantilla con el motivo y vuelve sola a la imagen si se repara
  (comprueba cada 5 s). La lista de cámaras incluye las instaladas sin señal (`live = false`).
- Las bodycams usan el mismo HUD con su propio título.
- **Cacheo de armas**: las armas que son objetos del inventario salen una sola vez (como objeto, en su zona del cuerpo)
  y, junto con la munición (`weapon_*`, `ammo_*`), se pueden retener y pasan a custodia como el resto de objetos.
- **Llaves como objetos** (os_devtools 0.1.8 + os_inventory 0.2.0): las puertas con cerradura de propiedades y negocios
  y el mando, el cierre y el arranque de los vehículos exigen llevar la llave válida del bien (`HasAssetAccess`),
  también al titular. Sin esos recursos se sigue usando el titular del personaje activo.
- **Lector de tarjetas** (`CardSwipe` de os_inventory, `CardSwipe` en `config/shared_gameplay.lua`): hay que arrastrar la llave-tarjeta al
  lector para abrir/cerrar (L) o arrancar (Y), la chapa para armar o desarmar la alarma y la tarjeta bancaria para pagar
  con tarjeta en la tienda G6, que además comprueba en el servidor que se lleva la tarjeta.
  Los vehículos clásicos (lista de os_devtools) usan llave física: no piden pasar la tarjeta.
- Identificadores que ve el jugador como números enteros: dispositivos `G6-D · 12` (antes `osd_0000000012`), órdenes,
  avisos y contratos `#7`. Los datos guardados no cambian.
- Matrículas aleatorias de os_devtools (p. ej. `8KDR472`): el cierre centralizado y la alarma encuentran el vehículo por
  su matrícula en el registro (`vehicles.byPlate`) y el cliente lo reconoce por su state bag `osdev`. Las matrículas
  antiguas `OS000012` siguen funcionando.
- Arco detector y cacheo: cuentan también las armas que el jugador lleva como objetos del inventario (os_inventory
  0.2.0+, export `GetCarriedWeapons`), además de las guardadas del sistema anterior y las que informa el cliente.
- Bodycam puesta: mientras está encendida se ve una camarita en el pecho del vigilante (objeto del juego, configurable
  en `BodycamWear` de `config/shared_gameplay.lua`; `/bodycamajuste` para ajustar la posición en el juego). Se quita al
  apagarla o al morir.
- Nuevo `config/shared_gameplay.lua` (cliente y servidor) con los ajustes de juego que necesita el cliente; corrige el
  `SCRIPT ERROR` de `client/boot.lua:80` al pasar la tarjeta y la camarita de la bodycam, que leían una configuración
  que solo existe en el servidor.

## 0.22.3

- Bodycams: la lista incluye también la propia (marcada «tú») y se puede ver en directo; antes quedaba fuera y, con
  una sola persona, parecía que no había ninguna encendida.

## 0.22.2 — Arco y cacheo con las armas guardadas del personaje

- El arco detector y el cacheo suman a las armas que informa el cliente las que el servidor tiene guardadas para el
  personaje activo (os_devtools 0.1.6+, export `GetCharacterWeapons`). Un cliente ya no puede esconder un arma que
  consta en su personaje. Sin ese export todo funciona como antes.

## 0.22.1 — Auditoría más limpia y tablet más ligera

- Las consultas de solo lectura de la tablet (inicio, buscador, listas de cada sección) ya no dejan una línea
  `access_allowed` en la auditoría cuando salen bien; las acciones y los rechazos se siguen registrando.
- El inicio, el mapa y el buscador guardan unos segundos las fichas de los dispositivos de cada perfil (se renuevan
  si cambia el inventario) en lugar de recorrer todo el registro en cada consulta.

## 0.22.0 — Rondas de vigilancia

- **G6 Operations → Rondas:** un supervisor o administrador crea rutas (opcionalmente para la propiedad de un cliente
  con contrato) y les añade puntos de control donde está (hasta 12, separados al menos 5 m).
- Cualquier perfil de Operations **empieza la ronda**: el siguiente punto sale con marca, punto en el mapa y ruta;
  junto a él, **E** ficha. El servidor comprueba que está a menos de 4 m y que va en orden. `/ronda cancelar` o el
  botón de la tablet la abandonan; caduca a la hora.
- Cada ronda completada queda en el registro de la ruta (últimas 20: vigilante, inicio y fin). El cliente con
  contrato ve en su tarjeta cuántas rondas se han hecho en su propiedad y la última.

## 0.21.0 — Transporte de fondos en la tablet

- **G6 Operations → Transporte de fondos:** pedir una misión de os_gruppesechs (tipo al azar o elegido), ver la
  propia con su paso, progreso, pago, vehículo y equipo, marcar la parada en el GPS y cancelarla (o salir del
  equipo); aceptar o rechazar la oferta de un compañero; y ver las misiones en curso de toda la empresa.
- Puente opcional y acotado: os_security solo llama a `TabletTransport` y `TabletTransportAction` de
  `ossecurity_transport_resource` (por defecto `os_gruppesechs`; `none` lo quita), que solo aceptan llamadas de
  os_security y aplican las mismas reglas que `/g6mision`. Sin ese recurso la sección dice que no está disponible.

## 0.20.0 — Bodycams

- Objeto **Bodycam** (`os_bodycam`, tienda G6 solo para personal, 650 $). El vigilante de servicio la enciende o
  apaga con «Usar» en el inventario o con `/bodycam`. Se apaga sola si deja el servicio, se queda sin ella o se
  desconecta.
- **G6 Operations → Bodycams** (supervisores y administradores): lista de bodycams encendidas con la distancia y
  **Ver en directo**: la cámara del juego va sujeta al pecho del vigilante y gira con él, con el filtro y el HUD de
  las cámaras CCTV. Ratón o flechas para mirar alrededor, Q / E para otra bodycam, Retroceso para volver a la tablet.
- Mientras se mira, el servidor amplía el radio de visibilidad de entidades de quien mira (`SetPlayerCullingRadius`,
  `Bodycams.CullingRadius`) para que el vigilante exista en su equipo, y lo restaura al salir. En otro mundo
  (routing bucket) no hay señal.
- Necesita os_inventory con el objeto `os_bodycam` (y su permiso de escritura y uso para os_security).

## 0.19.0 — Contratos de seguridad

- **G6 Client → Contratos:** el cliente contrata un plan para cada propiedad o negocio suyo (Básico, Alarma
  conectada, Vigilancia total). Paga la cuota al contratar y después cada periodo (24 h reales por defecto) desde
  su banco, cuando está conectado. Puede darlo de baja (con confirmación).
- **Ventajas** mientras está activo: con prioridad, sus avisos (pánico y saltos de alarma de esa propiedad) salen
  por delante en la Central con la marca «Contrato»; y las órdenes de trabajo de esa propiedad llevan descuento
  (10 %, 25 % o sin coste). El técnico cobra su parte del precio completo.
- **Impago:** si no se puede cobrar, el contrato queda suspendido (sin ventajas) y se reintenta cada hora; a los
  3 fallos se cancela. Los cancelados se borran a los 30 días.
- **G6 Operations → Contratos:** cartera de contratos con activos, suspendidos e ingresos por periodo.
- Planes, cuotas, periodo y descuentos en `config/gameplay.lua` (`Contracts`); textos en `config/brand.lua`.

## 0.18.2 — Textos nítidos en los minijuegos, un desmontaje a la vez y entrega aceptada en el cacheo

- **Arreglo:** los textos de los minijuegos (código de colores y bornes) se veían emborronados desde 0.17.0: el
  estilo de los iconos de la tablet se aplicaba a todos los dibujos. Ahora solo afecta a los iconos.
- Un desmontaje a la vez: mientras alguien desmonta un arco (o un dispositivo instalado), nadie más puede empezar a
  desmontarlo ni recogerlo. El arco se libera al terminar, al cancelar el minijuego, al desconectarse o a los 150 s.
- Retener en el cacheo pide permiso: al terminar, el cacheado ve la lista de lo que se le quiere retener y elige
  **Entregar** o **Negarme**. Si se niega o no responde a tiempo, no se retiene nada y se avisa al vigilante.

## 0.18.1 — Cacheo: objeto real y retención que sí quita del inventario

- **Arreglo:** retener en un cacheo no quitaba el objeto del inventario a partir de la segunda custodia. Los números
  `cu_…` (y los del arco, `md_…`) se reutilizan al retirarse, y el identificador de la operación de inventario se
  repetía: el inventario la daba por hecha y no quitaba nada. Ahora cada custodia y cada arco tienen un identificador
  propio (número + momento de creación). Lo mismo afectaba a volver a colocar un arco (no se gastaba).
- El cacheo muestra el nombre real del objeto (el del inventario; si no lo da, el del catálogo de OS Security).
  Necesita os_inventory con el nombre visible en `GetInventory`.
- Si el inventario no deja retener algo, el vigilante recibe «No se pudo retener: …» y no se apunta en custodia.

## 0.18.0 — Instalación con cámara cercana, polvo, chispas y más sonidos

- Durante el minijuego de montaje o desmontaje (cámaras, alarmas y arco detector) la cámara del juego se acerca de
  lado al personaje y al punto de trabajo, y vuelve al terminar.
- Taladro: polvo en la broca mientras perfora; chispas cuando la broca se calienta y al resbalar, con el golpe seco
  de la broca. Destornillador eléctrico: zumbido mientras se gira un tornillo.
- Paso final: al terminar bien, el personaje sostiene el equipo (la cámara o el teclado del kit) mientras lo coloca
  o lo retira, con su sonido; en el arco no hay objeto en la mano.
- El desmontaje devuelve la posición del equipo para encuadrar la cámara. Si un modelo, animación, partícula o sonido
  no existe en el juego, esa parte se omite sin error.

## 0.17.0 — Tablets con sistema propio: inicio, buscador, mapa y avisos

- Las tablets G6 Client y G6 Operations pasan a ser un **sistema de tablet**: marco con barra de estado (hora del
  juego, cobertura, batería, avisos y Cerrar), **pantalla de inicio** con saludo, widgets e iconos de apps, **dock**
  (Buscar, Mapa, Avisos y la primera app) y barra inferior para volver al inicio. Cada sección se abre como una app a
  pantalla completa con botón «Inicio».
- **Resumen** en el inicio (nueva acción `home`): dispositivos (operativos / con incidencias), alarmas armadas y
  sonando, solicitudes u órdenes, emergencias o avisos de la central, cámaras con señal y vehículos con alarma.
  Lista «Requiere atención» (alarmas sonando, averías, salud baja, avisos activos); tocar una fila abre lo que toca.
- **Buscador** (acción `search`, 2–40 caracteres): dispositivos por identificador, tipo, modelo o dirección; órdenes y
  avisos por número, lugar, nombre o nota; matrículas propias. Solo busca en lo que el perfil ya puede ver.
- **Mapa** (app Mapa) **dentro de la tablet**: imagen del mapa de GTA V con los dispositivos instalados, órdenes,
  avisos y vehículos propios como puntos (los que necesitan atención en rojo y parpadeando) y tu posición en vivo.
  Rueda o botones para acercar, arrastrar para mover; tocar un punto permite marcarlo en el GPS o abrirlo.
  La imagen **no se distribuye** (es material del juego): cada servidor la copia en `web/map/gtav.jpg|png|webp`
  (ver `web/map/LEEME.md`, ignorada por git). Calibración de fábrica para mapas cuadrados de la isla y calibración en
  el juego por un administrador con dos puntos (se guarda en `data/map.json`). Sin imagen se muestra la lista de puntos.
- **Configuración** (estilo iOS, en las dos tablets y en el dock): tema automático/claro/oscuro, seis fondos de
  pantalla, tamaño del texto, mostrar avisos en pantalla y sonido de avisos, restablecer ajustes e información de la
  tablet (modelo, versión, perfil, acreditación, sesión). Se guarda por jugador en su equipo (KVP del recurso).
- **Avisos en vivo**: con la tablet abierta, los avisos del servidor (alarmas, emergencias, órdenes asignadas…)
  aparecen como notificación dentro de la tablet, con contador en la campana y centro de avisos (con GPS si el aviso
  tiene posición). Escape cierra primero el buscador o el centro de avisos.
- Las tarjetas muestran el tipo de dispositivo traducido.

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
