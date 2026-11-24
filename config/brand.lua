-- Identidad comercial. Los nombres tecnicos del recurso y sus datos no cambian.
OSSecurity = OSSecurity or {}
OSSecurity.Brand = {
    Name = 'Gruppe Sechs', Monogram = 'G6', EmployeePrefix = 'G6-E', DevicePrefix = 'G6-D',
    Tagline = 'Protección que permanece.',
    Profiles = { client = 'Cliente', technician = 'Técnico', supervisor = 'Supervisor', admin = 'Administrador', inventory = 'Equipo personal' },
    Themes = {
        client = { background = '#edf0e9', surface = '#ffffff', ink = '#17281f', accent = '#536e38', muted = '#667165' },
        operations = { background = '#101a17', surface = '#192820', ink = '#edf3e8', accent = '#a9c66f', muted = '#a2b1a6' }
    },
    Tablets = {
        client = { name = 'G6 Client', item = 'g6_client_tablet', subtitle = 'Su seguridad, en un mismo lugar.' },
        operations = { name = 'G6 Operations', item = 'g6_operations_tablet', subtitle = 'Herramientas para quienes protegen.' }
    },
    Text = {
        inventory = 'Equipo personal', close = 'Cerrar', refresh = 'Actualizar', previous = 'Anterior', next = 'Siguiente',
        -- Sistema de la tablet: inicio, widgets, buscador, mapa y avisos.
        home = {
            title = 'Inicio', back = 'Inicio', search = 'Buscar', map = 'Mapa', notices = 'Avisos',
            greeting = { morning = 'Buenos días', afternoon = 'Buenas tardes', night = 'Buenas noches' },
            searchPlaceholder = 'Dispositivos, direcciones, órdenes, avisos, matrículas...',
            searchHint = 'Escribe al menos 2 caracteres.', noResults = 'Sin resultados.',
            mapHelp = 'Toca un punto para ver que es y marcarlo en el GPS.', you = 'Estás aquí', open = 'Abrir',
            gps = 'Marcar en el GPS', gpsMarked = 'Marcado en el GPS.', noPoints = 'Nada que mostrar en el mapa todavía.',
            noNotices = 'Sin avisos nuevos.', clear = 'Borrar', attention = 'Requiere atención', allGood = 'Todo en orden.',
            apps = 'Aplicaciones', session = 'Sesión hasta',
            widgets = { devices = 'Dispositivos', ok = 'operativos', attention = 'con incidencias', alarms = 'Alarmas', armed = 'armadas',
                triggered = 'sonando', orders = 'Órdenes', ordersOpen = 'sin asignar', ordersMine = 'mias', requests = 'Solicitudes',
                active = 'en curso', calls = 'Central', callsActive = 'avisos activos', callsMine = 'mios', emergencies = 'Emergencias',
                cameras = 'Cámaras', live = 'con señal', cars = 'Vehículos', carsAlarm = 'con alarma sonando' },
            reasons = { triggered = 'Alarma sonando', fault = 'Avería', maintenance = 'En mantenimiento', worn = 'Salud baja',
                sounding = 'Alarma del vehículo sonando', panic = 'Botón de pánico', alarm = 'Salto de alarma', tamper = 'Manipulación de teclado' },
            kinds = { device = 'Dispositivo', order = 'Orden', call = 'Aviso', car = 'Vehículo' },
            orderStatus = { open = 'Sin asignar', accepted = 'Aceptada', billed = 'Facturada', paid = 'Pagada', cancelled = 'Cancelada' },
            carState = { sounding = 'Alarma sonando', parked = 'Localizado' },
            legend = { device = 'Dispositivos', order = 'Órdenes', call = 'Avisos', car = 'Vehículos' },
            mapMissing = 'El mapa no esta disponible en este servidor. Debajo tienes la lista de puntos con su GPS.',
            mapMissingAdmin = 'Falta la imagen del mapa: copia un mapa de GTA V en os_security/web/map/gtav.jpg (o .png / .webp) y reinicia el recurso. Instrucciones en web/map/LEEME.md.',
            calibration = { start = 'Calibrar', second = 'Calibrar: punto 2', reset = 'Calibración de fábrica',
                step1 = 'Punto 1: haz clic en el mapa justo donde estás ahora.',
                waiting = 'Punto 1 guardado. Aléjate más de 800 m en las dos direcciones (por ejemplo a Sandy Shores), vuelve al mapa y pulsa Calibrar: punto 2.',
                step2 = 'Punto 2: haz clic en el mapa justo donde estás ahora.', noPosition = 'Aún no se conoce tu posición; espera un segundo.' },
            settings = {
                title = 'Configuración', general = 'General', display = 'Pantalla y brillo', wallpaper = 'Fondo de pantalla',
                notifications = 'Notificaciones', about = 'Información',
                generalGroup = 'Tablet', startScreen = 'Pantalla al abrir', searchScope = 'El buscador incluye',
                searchScopeValue = 'Dispositivos, órdenes, avisos y vehículos', reset = 'Restablecer ajustes', resetButton = 'Restablecer',
                resetHelp = 'Vuelve al tema, fondo, texto y avisos de fábrica. Tus datos no se tocan.',
                appearance = 'Aspecto', theme = 'Tema', themeAuto = 'Automático', themeLight = 'Claro', themeDark = 'Oscuro',
                themeHelp = 'Automático usa el tema de cada tablet: claro en G6 Client y oscuro en G6 Operations.',
                text = 'Texto', textSize = 'Tamaño del texto', textNormal = 'Normal', textLarge = 'Grande',
                chooseWallpaper = 'Elige un fondo', wallpapers = { 'Gruppe Sechs', 'Noche', 'Atardecer', 'Grafito', 'Bosque', 'Océano' },
                notificationsGroup = 'Avisos', banners = 'Mostrar avisos en pantalla', sounds = 'Sonido de avisos',
                notificationsHelp = 'Los avisos se guardan siempre en el centro de avisos (campana), aunque no se muestren.',
                name = 'Nombre', model = 'Modelo', modelValue = 'G6 Tab 11', version = 'Versión del sistema', profile = 'Perfil',
                employee = 'Acreditación', sessionUntil = 'Sesión válida hasta', operator = 'Operador'
            }
        },
        deviceTypes = { cctv_camera = 'Cámara CCTV', alarm_panel = 'Alarma', alarm_sensor = 'Sensor de alarma', smart_lock = 'Cerradura',
            vehicle_tracker = 'Localizador', bodycam = 'Bodycam', security_monitor = 'Monitor de seguridad' },
        loading = 'Consultando el servidor...', unavailable = 'No disponible en esta fase', empty = 'No hay dispositivos accesibles en esta página.',
        noSignal = 'Sin señal de vídeo.', session = 'Sesión autorizada',
        noInventory = 'No dispone de equipo.', use = 'Utilizar', items = 'Artículos', condition = 'Condición',
        details = 'Consultar', maintenance = 'Mantenimiento', inspect = 'Inspeccionar', repair = 'Reparar', replace = 'Sustituir',
        provision = 'Equipar registro antiguo', beginMaintenance = 'Pasar a mantenimiento', endMaintenance = 'Volver a servicio',
        replaceAll = 'Sustituir todo el equipo', swap = 'Hacer el cambio', swapCancelled = 'Cambio cancelado.', swapPending = 'Visita %s pendiente: ve al equipo y haz el cambio.',
        slotLabels = { power = 'la alimentación', optics = 'la óptica', controller = 'la placa', sensor = 'el sensor', actuator = 'el actuador',
            radio = 'la radio', storage = 'el almacenamiento', display = 'la pantalla' },
        notInMaintenance = 'El dispositivo no está en mantenimiento.', failedParts = 'Hay piezas averiadas: sustitúyelas antes de volver a servicio.',
        installed = 'Instalación vinculada',
        logical = 'Registro lógico', back = 'Volver', health = 'Salud', hours = 'Horas', history = 'Última intervención',
        noHistory = 'Sin intervenciones', employee = 'Acreditación', client = 'Titular autorizado',
        clientHero = 'La tranquilidad empieza por saber.', operationsHero = 'Cada dispositivo. Una responsabilidad.',
        inventoryHero = 'Preparado para el servicio.', assigned = 'Dispositivos accesibles', page = 'Página',
        installationAction = 'Preparar instalación CCTV', inspectionNote = 'La salud refleja la última evaluación confirmada.',
        type = 'Tipo', model = 'Modelo', state = 'Estado', installationDate = 'Instalación',
        states = { registered = 'Registrado', installing = 'Instalando', installed = 'Instalado', active = 'Activo',
            maintenance = 'Mantenimiento', fault = 'Avería administrativa', retired = 'Retirado',
            healthy = 'En buen estado', worn = 'Desgastado', degraded = 'Degradado', critical = 'Crítico', failed = 'Fallido' },
        pending = 'Pendiente de implementación', failed = 'No se pudo completar la solicitud.',
        placementHelp = 'Flechas: mover  Mayus+flechas: girar  Q/Z: separar/acercar  R: invertir',
        placementHelp2 = '~n~Ctrl: fino  Tab: montaje  E: colocar  Retroceso: salir',
        anchorAimHelp = 'Apunta a pared o techo  + / -: tamaño  E: fijar superficie  Retroceso o Esc: salir',
        anchorHelp = 'Flechas: mover  + / -: tamaño  Ctrl: fino  E: registrar  Retroceso: volver a apuntar',
        anchorZone = 'Zona',
        installFailed = 'Instalación fallida: no se ha consumido material.',
        minigame = {
            title = 'Instalación CCTV', cancel = 'Cancelar (Esc)',
            drillTitle = 'Taladrar los anclajes', drillHelp = 'Manten pulsado el ratón sobre cada marca hasta perforarla. Suelta para enfriar la broca; no te salgas de la marca.',
            heat = 'Temperatura de la broca', slips = 'Resbalones', slip = 'La broca ha resbalado', tooHot = 'Demasiado caliente: suelta para enfriar',
            drilling = 'Perforando...', holeDone = 'Agujero hecho',
            screwTitle = 'Atornillar el soporte', screwHelp = 'Pulsa sobre un tornillo y gira el ratón a su alrededor en sentido horario. Sin prisas: con demasiada fuerza se pasa la rosca.',
            torque = 'Fuerza', strips = 'Roscas pasadas', turnHint = 'Gira en sentido horario', tooStrong = 'Demasiada fuerza: más despacio',
            stripped = 'Rosca pasada: vuelve a empezar ese tornillo', hit = 'Tornillo apretado',
            cablesTitle = 'Conectar el cableado', cablesHelp = 'Arrastra cada cable hasta el borne de su señal según el código de colores (los bornes solo llevan la etiqueta).',
            wireCode = 'Rojo +12V · Negro GND · Verde A+ · Blanco B- · Amarillo TAMP',
            colors = { 'Rojo', 'Azul', 'Amarillo', 'Verde' }, shorts = 'Cortocircuitos', connected = 'Conectado', wrongWire = 'Borne incorrecto',
            removeTitle = 'Desmontaje', unplugTitle = 'Desconectar el cableado',
            unplugHelp = 'Arrastra cada cable fuera de su borne hasta la bandeja de la izquierda.', unplugged = 'Desconectado',
            unscrewTitle = 'Desatornillar el soporte', unscrewHelp = 'Pulsa sobre un tornillo y gira el ratón en sentido ANTIHORARIO hasta sacarlo. Sin forzar.',
            unscrewed = 'Tornillo fuera',
            -- Sustitucion en el sitio (variante 'swap'): diagnostico, extraer, encajar y autotest.
            swap = {
                title = 'Sustitución G6', mistakes = 'Errores',
                diagnoseTitle = 'Diagnosticar el equipo',
                diagnoseHelp = 'Mantén pulsado el polímetro sobre la toma (círculo) de cada módulo para medirlo. Después pulsa sobre los que estén fuera de rango para marcarlos como averiados.',
                measuring = 'Midiendo...', progress = 'Medición', inRange = 'En rango', outOfRange = 'Fuera de rango',
                marked = 'Marcado como averiado', wrongMark = 'Ese módulo está bien: no lo marques', measureFirst = 'Mídelo antes de marcarlo',
                extractTitle = 'Extraer el módulo',
                extractHelp = 'Desliza el pestillo amarillo hacia la derecha y tira del módulo hacia abajo poco a poco: si tiras rápido se doblan los pines.',
                tension = 'Tensión del conector', latchOpen = 'Pestillo abierto', bent = 'Pines doblados: vuelve a tirar más despacio',
                extracted = 'Módulo fuera', whole = 'Equipo completo', latchFirst = 'Abre antes el pestillo',
                insertTitle = 'Encajar el módulo nuevo',
                insertHelp = 'Gira el módulo con la rueda del ratón (o el botón ⟳) hasta que su muesca quede arriba, como la de la ranura, y arrástralo dentro.',
                rotate = '⟳', notch = 'La muesca no coincide: así no entra', inserted = 'Módulo encajado',
                testTitle = 'Autotest de arranque',
                testHelp = 'Pulsa el piloto que esté encendido. Se van encendiendo de uno en uno y esperan a que lo pulses: sin prisa.',
                pressLit = 'Pulsa el piloto encendido:', wrongLed = 'Ese no. Pulsa el piloto encendido:', progressTest = 'Autotest',
                colorNames = { 'Rojo', 'Verde', 'Azul', 'Amarillo' },
                passed = 'Autotest superado'
            }
        },
        placementMount = 'Montaje',
        miniInstallAction = 'Instalar cámara mini (interior)', domeInstallAction = 'Instalar cámara domo 360',
        alarmInstallAction = 'Instalar alarma (teclado)', alarmPanelInstallAction = 'Instalar alarma (panel lector)',
        remove = 'Desmontar', removed = 'Dispositivo %s desmontado: el kit vuelve a tu inventario.', removeCancelled = 'Desmontaje cancelado.',
        removeHelp = 'Debes estar junto al dispositivo con taladro y destornillador.',
        alarm = {
            title = 'Alarma', triggered = 'SALTO DE ALARMA', arm = 'Armar total', partial = 'Armar parcial', disarm = 'Desarmar',
            modes = { disarmed = 'Desarmada', armed = 'Armada (total)', partial = 'Armada (parcial)' },
            createPin = 'Crear código (4-6 cifras)', newPin = 'Nuevo código', savePin = 'Guardar código', pinFormat = 'El código debe tener entre 4 y 6 cifras.',
            tags = 'Chapas', programTag = 'Programar chapa', revokeTags = 'Revocar chapas',
            events = { armed = 'Armada', partial = 'Armada parcial', disarmed = 'Desarmada', triggered = 'Salto de alarma', wrong_pin = 'Código o chapa incorrectos',
                lockout = 'Teclado bloqueado', pin_set = 'Código cambiado', tag_added = 'Chapa programada', tags_revoked = 'Chapas revocadas', entry = 'Entrada detectada' },
            keypadHint = '~INPUT_CONTEXT~ teclado de alarma   ~INPUT_DETONATE~ acercar chapa',
            pad = { armed = 'ARMADA', partial = 'PARCIAL', disarmed = 'DESARMADA', locked = 'BLOQUEADO', entry = 'INTRODUZCA CÓDIGO', triggered = 'ALARMA',
                arm = 'Total', partial = 'Parcial', disarm = 'Desarmar', tag = 'Acercar chapa', clear = 'Borrar', close = 'Salir (Esc)' },
            entryWarning = 'Alarma armada: introduce el código en %d s o saltará.'
        },
        locks = {
            lockHint = '~INPUT_CONTEXT~ cerrar con llave', unlockHint = '~INPUT_CONTEXT~ abrir con llave',
            minigame = {
                title = 'Cambio de bombín', cancel = 'Cancelar (Esc)',
                unscrewTitle = 'Quitar el tornillo de fijación', unscrewHelp = 'Pulsa sobre el tornillo del canto de la puerta y gira el ratón en sentido ANTIHORARIO hasta sacarlo. Sin forzar.',
                outTitle = 'Sacar el bombín viejo', outHelp = 'Gira la llave arrastrando a su alrededor hasta que la leva quede arriba (verde). Después arrastra el bombín hacia fuera, a la izquierda.',
                inTitle = 'Meter el bombín nuevo', inHelp = 'Alinea arriba la leva del bombín nuevo (verde) y empújalo hacia dentro de la cerradura.',
                screwTitle = 'Apretar el tornillo de fijación', screwHelp = 'Pulsa sobre el tornillo y gira en sentido horario hasta apretarlo. Con demasiada fuerza se pasa la rosca.',
                torque = 'Fuerza', strips = 'Roscas pasadas', jams = 'Atascos', turnHint = 'Sigue girando',
                jammed = 'La leva tropieza: alinéala arriba antes de mover el bombín', aligned = 'Leva alineada: ya puedes moverlo',
                tooStrong = 'Demasiada fuerza: más despacio', stripped = 'Rosca pasada: vuelve a empezar', screwOut = 'Tornillo fuera',
                cylinderOut = 'Bombín viejo fuera', cylinderIn = 'Bombín nuevo dentro', done = 'Bombín cambiado'
            }
        },
        cars = {
            minigame = {
                title = 'Instalación en vehículo', cancel = 'Cancelar (Esc)', kinds = { lock = 'Cierre centralizado', alarm = 'Alarma', tracker = 'Localizador', hotwire = 'Puente' },
                hotwireTitle = 'Vehículo sin llave', coverTitle = 'Quitar la tapa de la columna', coverHelp = 'Manten pulsado sobre cada grapa y suelta cuando la tensión este en la franja verde. Si te pasas, la grapa se rompe.',
                starterTitle = 'Dar al motor de arranque', starterHelp = 'Manten pulsado ARRANCAR y suelta cuando la carga este en la franja verde. Antes no arranca; si te pasas, se quema el fusible.',
                start = 'ARRANCAR', charge = 'Arranque', fuses = 'Fusibles', cranking = 'Girando el motor...', started = 'Arranca',
                noStart = 'No arranca: vuelve a intentarlo', fuse = 'Fusible quemado',
                trimTitle = 'Quitar el embellecedor bajo el volante', trimHelp = 'Manten pulsado sobre cada grapa y suelta cuando la tensión este en la franja verde. Si te pasas, la grapa se rompe.',
                tension = 'Tensión', broken = 'Grapas rotas', pulling = 'Tirando...', clipOut = 'Grapa fuera', notEnough = 'Poca fuerza: vuelve a tirar',
                clipBroken = 'Grapa rota',
                wireTitle = 'Medir y empalmar', wireHelp = '1) Pulsa cada cable: el multímetro dice que es y su nombre queda escrito debajo. 2) Arrastra cada hilo del módulo hasta el cable con su mismo nombre.',
                probe = 'Lectura', spliced = 'Empalmado', wrongWire = 'Cable equivocado: el módulo no responde', shorts = 'Fallos',
                testTitle = 'Probar el mando', testHelp = 'Pulsa el botón del mando: el LED del módulo debe responder.', works = 'Funciona'
            }
        },
        lockpick = {
            title = 'Ganzúa', heading = 'Forzar la cerradura', cancel = 'Dejarlo (Esc)', misses = 'Fallos',
            help = 'Haz clic o pulsa Espacio cuando el pin que se mueve pase por su zona verde. Uno tras otro; con tres fallos lo dejas.',
            set = 'Pin fijado', miss = 'Se escapa el pin',
            kinds = { door = 'Puerta', vehicle = 'Vehículo' }, tiers = { 'Seguridad básica', 'Seguridad media', 'Alta seguridad' }
        },
        hello = 'Gruppe Sechs: servicio de seguridad disponible.',
        orders = {
            kinds = { cctv = 'Instalar cámaras', alarm = 'Instalar alarma', repair = 'Reparar un dispositivo', lock = 'Cambiar bombín',
                car = 'Seguridad del vehículo', other = 'Otro trabajo', replace = 'Sustitución en el sitio' },
            status = { open = 'Pendiente', accepted = 'En camino', billed = 'Por pagar', paid = 'Pagada', cancelled = 'Cancelada' },
            here = 'Donde estoy ahora', clientPlace = 'Ubicación del cliente',
            clientTitle = 'Pide a Gruppe Sechs lo que necesites.', clientHelp = 'Un técnico de servicio acepta tu solicitud, viene al sitio y, al terminar, te pasa la factura para pagar desde aquí.',
            newRequest = 'Nueva solicitud', kind = 'Trabajo', place = 'Lugar', note = 'Que necesitas (max. %d caracteres)', send = 'Enviar solicitud',
            empty = 'No tienes solicitudes.', cancel = 'Cancelar', pay = 'Pagar $%s', tech = 'Técnico', price = 'Importe',
            staffTitle = 'Trabajo pendiente en la calle.', staffHelp = 'Acepta una orden, ve al punto marcado, haz el trabajo y factúralo. Cobras el %s% del importe al pagar el cliente.',
            staffEmpty = 'No hay órdenes de trabajo abiertas.', accept = 'Aceptar', release = 'Soltar', gps = 'GPS', bill = 'Facturar', amount = 'Importe ($)',
            yourShare = 'Tu parte: $%s', payoutPending = 'Cobro pendiente', payoutDone = 'Cobrado', distance = 'a %s m', mine = 'Tuya',
            newOrder = 'G6 · Nueva orden de trabajo: %s en %s.', created = 'Solicitud %s enviada a Gruppe Sechs.', cancelled = 'Solicitud cancelada.',
            cancelledTech = 'El cliente ha cancelado la orden %s.', accepted = 'Orden %s aceptada: marcada en tu GPS.', released = 'Orden devuelta a la lista.',
            acceptedClient = 'G6 · Tu solicitud %s la atiende %s.', billed = 'Orden %s facturada. Tu parte: $%d al pagar el cliente.',
            billedClient = 'G6 · Trabajo %s terminado: paga $%d desde tu tablet G6 Client.',
            visitClient = 'G6 · %s va a ir a %s: %s. Recibe al técnico en el lugar.', visitCreated = 'Visita %s enviada al cliente. Ve al equipo y pulsa «Hacer el cambio».',
            visitPending = 'Ya tienes la visita %s para este equipo: ve al sitio y pulsa «Hacer el cambio».',
            swapPart = 'Sustituir %s de %s', swapAll = 'Sustituir el equipo completo %s', swapDoneClient = 'G6 · Equipo de %s sustituido. El técnico te enviará la factura.',
            swapDone = 'Cambio hecho. Factura la orden %s desde Órdenes de trabajo.', paid = 'Pagado: $%d. Gracias por confiar en Gruppe Sechs.',
            paidTech = 'G6 · Has cobrado $%d por la orden %s.'
        },
        live = {
            watch = 'Ver en directo', rec = 'REC', cam = 'CÁMARA', noise = 'Señal degradada', noVideo = 'NO VIDEO',
            logo = true, -- logo de la plantilla arriba a la izquierda (web/live/logo.png); false = plantilla sin logo
            help = 'Ratón o flechas: mover · Rueda o + / -: zoom · Q / E: cámara anterior / siguiente · Retroceso: salir',
            lost = 'Se ha perdido la señal de la cámara.', interrupted = 'Vista interrumpida: te están atacando.'
        },
        shop = {
            prompt = '~INPUT_CONTEXT~ Tienda Gruppe Sechs', title = 'Equipos de seguridad', close = 'Cerrar (Esc)',
            categories = { tablet = 'Tablets', kit = 'Kits e instalaciones', tool = 'Herramientas', material = 'Consumibles', access = 'Accesos', other = 'Otros' },
            staffItem = 'Personal G6', staffOnly = 'Solo personal G6 de servicio', cart = 'Tu pedido', empty = 'Elige productos con + y -.',
            total = 'Total', pay = 'Pagar con', accounts = { bank = 'Banco', cash = 'Efectivo' }, buy = 'Pagar', paying = 'Pagando...',
            insufficient = 'No tienes saldo suficiente en esa cuenta.', failed = 'No se pudo completar la compra.',
            staffHint = 'Los kits de cámaras y alarmas y el taladro son para técnicos G6 de servicio.'
        },
        -- Seccion Instalaciones (G6 Operations): zonas de montaje marcadas con el visor e instalacion.
        zones = {
            title = 'Zonas de montaje', hero = 'Marca la zona. Instala sin volver a la oficina.',
            heroHelp = 'Elige el cliente, marca la zona con el visor y desde su ficha instala la cámara o la alarma estando a menos de %d m.',
            newZone = 'Nueva zona', client = 'Cliente', self = 'Yo mismo', mark = 'Marcar zona con el visor',
            markHelp = 'La tablet se cierra: apunta, E fija la superficie, flechas mueven, + y - cambian el tamaño y E hace la foto.',
            noClients = 'No hay clientes cerca.', empty = 'Todavía no hay zonas. Marca la primera con el visor.',
            surfaces = { wall = 'Pared', ceiling = 'Techo', floor = 'Suelo' },
            states = { free = 'Libre', pending = 'Pendiente', installed = 'Instalada' },
            install = 'Instalar', kit = 'Kit', noKits = 'Sin kits en el inventario', delete = 'Borrar zona',
            distance = 'a %s m', unknownPlace = 'Lugar sin nombre', here = 'Aquí', goCloser = 'Acércate (%s m)', size = '%s x %s m', notMine = 'Zona de otro técnico',
            device = 'Dispositivo', viewDevice = 'Ver dispositivo', site = 'Sitio', materials = 'Material disponible'
        },
        viewfinder = {
            rec = 'REC', aim = 'Apunta a la pared, techo o suelo y pulsa E', adjust = 'Flechas: mover · + / -: tamaño · Ctrl: fino · E: foto · Retroceso: volver',
            noSurface = 'Sin superficie', shot = 'Zona capturada', client = 'Cliente', zone = 'Zona'
        },
        doors = { title = 'Cerraduras de tus propiedades', help = 'Puertas con bombín G6 en tus propiedades y negocios. La llave la lleva tu personaje.',
            empty = 'No hay puertas con cerradura en tus propiedades.', locked = 'Cerrada con llave', open = 'Abierta', level = 'Nivel %d' },
        trackers = { title = 'Tus vehículos protegidos', help = 'Vehículos con cierre centralizado, alarma o localizador G6. Si están en la calle, puedes marcarlos en el GPS (también con /localizar).',
            empty = 'No tienes vehículos con equipo G6.', lock = 'Cierre centralizado', alarm = 'Alarma', tracker = 'Localizador', stolen = 'ROBADO · SIGUE EL PUNTO ROJO', locked = 'Cerrado', open = 'Abierto',
            sounding = 'ALARMA SONANDO', gps = 'Marcar en el GPS', away = 'Guardado o fuera de alcance',
            lastSignal = 'Sin señal · última hace %s min', lastSignalNow = 'Sin señal · última hace un momento' },
        incidents = { title = 'Historial de incidencias', help = 'Últimos sucesos de todas tus alarmas, del más reciente al más antiguo.',
            empty = 'Sin incidencias registradas.' },
        checkpoint = {
            needJob = 'Tienes que estar de servicio en una empresa.', needInventory = 'Requiere el inventario de personajes.',
            needItem = 'Necesitas un arco detector de metales.', badPlace = 'Posición no válida.', tooFar = 'Demasiado lejos para colocarlo.',
            tooClose = 'Ya hay un arco ahí mismo.', placed = 'Arco detector colocado para %s.', noOwnNear = 'No hay un arco de tu empresa a tu lado.',
            pickedUp = 'Arco recogido: vuelve a tu inventario.', alarm = 'Arco detector: metal detectado en %s.',
            noTarget = 'No hay nadie delante para cachear.', busy = 'Ya estás cacheando a alguien.', targetBusy = 'Esa persona ya tiene una petición de cacheo.',
            asked = 'Pides permiso a %s para cachearle...', refused = '%s no acepta el cacheo.', youRefused = 'Has rechazado el cacheo.',
            accepted = 'Has aceptado el cacheo: no te muevas.', expired = 'La petición de cacheo ha caducado.', noAnswer = 'No ha respondido al cacheo.',
            noFrisk = 'No estás cacheando a nadie.', cancelled = 'Cacheo cancelado.', clean = 'Cacheo terminado: puedes continuar.',
            nothingRetained = 'Cacheo terminado sin retener nada.', retained = 'Objetos en custodia (%s).', notRetained = 'No se pudo retener: %s.',
            retainedOwner = 'Te han retenido objetos (custodia de %s). Recógelos aquí mismo con /custodia.',
            noCustody = 'No tienes objetos en custodia.', goBack = 'Tus objetos están en custodia de %s: vuelve al sitio donde te los retuvieron.',
            otherCharacter = 'Esos objetos son de otro personaje.', returned = 'Te devuelven tus objetos.',
            -- Cliente
            placeHelp = 'Rueda: girar · E: colocar · Retroceso: cancelar', askTitle = 'Petición de cacheo', ask = '%s (%s) quiere cachearte.',
            accept = 'Aceptar', refuse = 'Rechazar', friskTitle = 'Cacheo de %s', friskHelp = 'Pasa las manos por cada zona (mantén el ratón encima) para palpar.',
            zones = { chest = 'Pecho', back = 'Espalda', waist = 'Cintura', leftArm = 'Brazo izq.', rightArm = 'Brazo der.', leftLeg = 'Pierna izq.', rightLeg = 'Pierna der.', ankles = 'Tobillos' },
            found = 'Encontrado', nothing = 'Nada', retain = 'Retener', finish = 'Terminar cacheo', cancel = 'Cancelar', pending = 'Faltan zonas por palpar (%d).',
            metal = 'metal', weapon = 'arma', item = 'objeto',
            needTools = 'Necesitas taladro y destornillador.', mountCancelled = 'Montaje cancelado: el arco sigue en tu inventario.',
            unmountCancelled = 'Desmontaje cancelado: el arco sigue en su sitio.',
            unmountBusy = 'Otra persona ya está desmontando este arco.', notStarted = 'Empieza el desmontaje con /arco recoger.',
            turnedOn = 'Arco detector encendido: ya detecta metal.', turnedOff = 'Arco detector apagado: no detecta ni avisa.',
            alreadyOn = 'Este arco ya está encendido.', alreadyOff = 'Este arco ya está apagado.', offLabel = 'ARCO APAGADO',
            promptOn = 'Encender el arco', promptOff = 'Apagar el arco', promptUnmount = 'Desmontar el arco',
            -- Retener en el cacheo: el cacheado acepta o se niega a entregar lo que se le quiere retener.
            retainAsked = 'Pides a %s que entregue lo que quieres retener...', waitingAnswer = 'Esperando a que acepte o rechace la retención.',
            retainRefused = '%s se niega a entregar los objetos: no se retiene nada.', youRefusedRetain = 'Te has negado a entregar los objetos.',
            retainTitle = 'Retención de objetos', retainAsk = '%s (%s) quiere retener:', retainAccept = 'Entregar', retainRefuse = 'Negarme',
            -- Minijuego de montaje y desmontaje (sustituye a los textos comunes del minijuego de instalacion).
            minigame = {
                title = 'Montaje del arco detector', removeTitle = 'Desmontaje del arco detector',
                drillTitle = 'Anclar las bases al suelo', drillHelp = 'Manten pulsado sobre cada marca de las placas de anclaje hasta perforar el suelo. Suelta para enfriar la broca; no te salgas de la marca.',
                screwTitle = 'Atornillar los postes a las bases', screwHelp = 'Pulsa sobre cada perno y gira el ratón en sentido horario hasta apretarlo. Con demasiada fuerza se pasa la rosca.',
                cablesTitle = 'Conectar la unidad de control', cablesHelp = 'Arrastra cada cable del arco hasta su borne en la unidad de control según el código de colores.',
                wireCode = 'Rojo +12V · Negro GND · Verde SENSOR IZQ · Blanco SENSOR DER · Amarillo ZUMBADOR',
                terminals = { red = '+12V', black = 'GND', green = 'SEN I', white = 'SEN D', yellow = 'ZUMB' },
                unplugTitle = 'Desconectar la unidad de control', unplugHelp = 'Arrastra cada cable fuera de su borne hasta la bandeja de la izquierda.',
                unscrewTitle = 'Soltar los pernos de las bases', unscrewHelp = 'Pulsa sobre cada perno y gira el ratón en sentido ANTIHORARIO hasta sacarlo. Sin forzar.'
            }
        },
        patrols = {
            title = 'Rondas de vigilancia', help = 'Recorre una ruta fichando en cada punto de control. Los supervisores crean las rutas marcando los puntos donde están.',
            empty = 'No hay rutas de rondas.', newRoute = 'Nueva ruta', name = 'Nombre de la ruta', forSite = 'Propiedad con contrato', noSite = 'Sin propiedad',
            create = 'Crear', addPoint = 'Añadir punto aquí', delete = 'Borrar ruta', start = 'Empezar ronda', cancel = 'Abandonar ronda',
            points = '%d puntos', rounds = '%d rondas', last = 'Última: %s por %s (%d min)', never = 'Sin rondas todavía', running = 'En curso: punto %d de %d',
            noAccess = 'Solo supervisores y administradores gestionan rutas.', invalid = 'Petición no válida.', needName = 'Pon un nombre a la ruta.',
            noContract = 'Ese contrato no existe o esta de baja.', created = 'Ruta %s creada: añade puntos donde estes.', notFound = 'Ruta no encontrada.',
            full = 'Una ruta tiene como mucho %d puntos.', noPosition = 'Posición no disponible.', tooClose = 'Demasiado cerca de otro punto (mínimo %d m).',
            pointAdded = 'Punto %d añadido a %s.', deleted = 'Ruta %s borrada.', needPoints = 'La ruta necesita al menos 2 puntos.',
            started = 'Ronda %s: %d puntos. Ve al primero y pulsa E.', noRun = 'No estás haciendo ninguna ronda.', abandoned = 'Ronda abandonada.',
            expired = 'Ronda caducada: has tardado demasiado.', tooFar = 'Tienes que estar junto al punto de control.',
            checked = 'Punto %d de %d fichado.', finished = 'Ronda %s completada.', help3D = 'E: fichar punto de control', blip = 'Punto de control',
            clientRounds = 'Rondas hechas: %d · última %s'
        },
        transport = {
            title = 'Transporte de fondos', help = 'Pide una misión para tu equipo, sigue cada parada y únete a las de tus compañeros.',
            unavailable = 'Transporte de fondos no disponible en este servidor.', invalid = 'Petición no válida.',
            failed = 'No se pudo completar.', done = 'Hecho.', current = 'Tu misión', none = 'No tienes una misión en curso.',
            request = 'Pedir misión', random = 'Al azar', kind = 'Tipo', start = 'Pedir', cancel = 'Cancelar misión', leave = 'Salir del equipo',
            gps = 'Marcar en el GPS', step = 'Parada %d de %d', crew = 'Equipo', pay = 'Pago', vehicle = 'Vehículo', lobby = 'Esperando equipo',
            offer = 'Oferta de %s: %s (cobrarías %d $).', accept = 'Unirme', decline = 'Rechazar', running = 'Misiones en curso',
            noRunning = 'No hay misiones en curso.', notEmployed = 'No puedes pedir misiones: %s',
            roles = { driver = 'Conductor', porter = 'Operario', solo = 'Solo' }
        },
        bodycams = {
            title = 'Bodycams', help = 'Cámaras de pecho del personal de servicio. Pulsa Ver en directo para mirar lo que ve el vigilante.',
            empty = 'Nadie lleva la bodycam encendida ahora mismo.', watch = 'Ver en directo', since = 'Encendida desde',
            distance = '%d m', noAccess = 'Solo supervisores y administradores ven las bodycams.',
            needDuty = 'Tienes que estar de servicio en Gruppe Sechs.', needItem = 'Necesitas una bodycam.',
            on = 'Bodycam encendida: la Central puede ver lo que ves.', off = 'Bodycam apagada.',
            autoOff = 'Bodycam apagada (fuera de servicio o sin el equipo).', notFound = 'Esa bodycam ya no esta encendida.',
            noSignal = 'Sin señal de la bodycam.', lost = 'Se ha perdido la señal de la bodycam.', waiting = 'Conectando con la bodycam...',
            label = 'BODYCAM', help2 = 'Q / E: otra bodycam   Retroceso: salir', recording = 'Grabando', you = 'tu'
        },
        contracts = {
            plans = {
                basic = { name = 'Básico', description = 'Seguimiento de tus equipos G6 y 10 % de descuento en reparaciones.' },
                alarm = { name = 'Alarma conectada', description = 'Tus avisos salen primero en la central y 25 % de descuento en reparaciones.' },
                premium = { name = 'Vigilancia total', description = 'Prioridad en la central y reparaciones sin coste.' }
            },
            title = 'Contratos de seguridad', help = 'Contrata un plan para cada propiedad o negocio. Se paga al contratar y después cada %s desde tu banco.',
            staffHelp = 'Cartera de contratos de los clientes. Los avisos de clientes con prioridad salen primero en la central.',
            newTitle = 'Nuevo contrato', place = 'Propiedad', plan = 'Plan', hire = 'Contratar', cancel = 'Dar de baja', fee = 'Cuota',
            priority = 'Prioridad en la central', discount = 'Descuento en reparaciones', free = 'Reparaciones sin coste',
            noPlaces = 'No tienes propiedades o negocios sin contrato.', empty = 'Aun no tienes contratos.', staffEmpty = 'No hay contratos.',
            nextCharge = 'Próximo cobro', paidTotal = 'Pagado en total', client = 'Cliente', active = 'Activos', suspendedCount = 'Suspendidos',
            income = 'Ingresos por periodo', confirmCancel = 'Pulsa otra vez para confirmar la baja.',
            status = { active = 'Activo', suspended = 'Suspendido (impago)', cancelled = 'Dado de baja' },
            period = { day = 'dia', hours = '%d h' },
            choosePlan = 'Elige una propiedad y un plan.', notYours = 'Esa propiedad no es tuya.', already = 'Esa propiedad ya tiene contrato.',
            noPayments = 'Pagos no disponibles en este servidor.', noFunds = 'Saldo insuficiente en el banco.', payRejected = 'Pago rechazado.',
            created = 'Contrato %s para %s: pagados %d $.', notFound = 'Contrato no encontrado.', alreadyCancelled = 'Ese contrato ya esta dado de baja.',
            cancelled = 'Contrato de %s dado de baja.', charged = 'Cuota de seguridad cobrada: %d $ (%s).',
            suspended = 'No se pudo cobrar el contrato de %s (%d $): queda suspendido hasta que se pague.',
            cancelledUnpaid = 'Contrato de %s cancelado por impago.', contractBadge = 'Contrato', discountApplied = 'Con descuento de contrato'
        },
        dispatch = {
            kinds = { panic = 'Botón de pánico', alarm = 'Salto de alarma', tamper = 'Manipulación de teclado' },
            status = { open = 'Sin asignar', assigned = 'En camino', resolved = 'Resuelto', cancelled = 'Cancelado' },
            here = 'Donde estoy ahora', clientPlace = 'Ubicación del cliente',
            -- Avisos (servidor)
            newCall = 'Central G6: %s en %s.', newPanic = 'Central G6: BOTÓN DE PÁNICO de %s en %s.',
            repeated = 'Central G6: %s otra vez en %s (x%d).', assignedYou = 'Central G6: te asignan %s en %s (%s).',
            onTheWay = 'Gruppe Sechs: %s va de camino.', resolvedClient = 'Gruppe Sechs ha cerrado tu aviso (%s): %s',
            cancelledTech = 'El cliente ha cancelado el aviso %s.', falseAlarm = 'Cancelado por el cliente (falsa alarma).',
            panicSent = 'Aviso enviado: %d agentes de Gruppe Sechs de servicio lo han recibido.',
            panicNobody = 'Aviso registrado. Ahora mismo no hay agentes de servicio; lo verán al entrar.',
            cancelled = 'Aviso cancelado.', taken = 'Aviso %s asignado a ti. Marcado en el GPS.',
            assigned = 'Aviso %s asignado a %s.', released = 'Aviso devuelto a la central.', resolved = 'Aviso %s cerrado.',
            -- Tablet Client > Emergencias
            clientTitle = 'Emergencias', clientHelp = 'Si estas en peligro pulsa el botón: el aviso llega al momento a todo el personal de Gruppe Sechs de servicio.',
            panic = 'BOTÓN DE PÁNICO', place = 'Donde', note = 'Que pasa (opcional, %d caracteres)', wait = 'Podrás enviar otro aviso en %d s.',
            activeNote = 'Tienes un aviso en curso: Gruppe Sechs ya esta avisado.', cancel = 'Cancelar (falsa alarma)',
            history = 'Tus avisos', empty = 'No has enviado avisos.',
            -- Tablet Operations > Central de operaciones
            staffTitle = 'Central de operaciones', staffHelp = 'Avisos en curso por prioridad: pánico, saltos de alarma y manipulaciones. Asígnate uno, ve con el GPS y ciérralo con lo que ha pasado.',
            staffEmpty = 'Sin avisos. Todo en calma.', take = 'Me lo asigno', gps = 'GPS', release = 'Devolver', resolve = 'Cerrar aviso',
            resolveNote = 'Que ha pasado (obligatorio)', assignTo = 'Asignar a', assign = 'Asignar', tech = 'Agente', client = 'Cliente',
            times = 'x%d', distance = 'a %s m', mine = 'Tuyo', nobody = 'Nadie de servicio', resolution = 'Resolución'
        },
        profileAbilities = 'Funciones de su perfil',
        abilities = { view = 'Consultar', inspect = 'Inspeccionar', repair = 'Reparar', replace = 'Sustituir piezas',
            provision = 'Equipar registros', beginMaintenance = 'Abrir mantenimiento', endMaintenance = 'Cerrar mantenimiento', install = 'Instalar CCTV' },
        serviceNames = { cctv = 'Registro CCTV', maintenance = 'Servicio técnico', installation = 'Instalaciones', inventory = 'Inventario técnico' }
    },
    Modules = {
        client = {
            { id = 'overview', name = 'Mis dispositivos', implemented = true },
            { id = 'cctv', name = 'CCTV autorizado', implemented = true },
            { id = 'alarms', name = 'Alarmas residenciales y comerciales', implemented = true },
            { id = 'locks', name = 'Cerraduras', implemented = true },
            { id = 'trackers', name = 'Localizadores de vehículos', implemented = true },
            { id = 'emergencies', name = 'Emergencias', implemented = true },
            { id = 'contracts', name = 'Contratos', implemented = true },
            { id = 'requests', name = 'Solicitudes de mantenimiento', implemented = true },
            { id = 'incidents', name = 'Historial de incidencias', implemented = true }
        },
        operations = {
            { id = 'overview', name = 'Dispositivos asignados', implemented = true },
            { id = 'installations', name = 'Instalaciones', implemented = true, requires = 'install' },
            { id = 'maintenance', name = 'Mantenimiento', implemented = true },
            { id = 'inventory', name = 'Inventario técnico', implemented = true },
            { id = 'cctv', name = 'Registro CCTV', implemented = true },
            { id = 'work_orders', name = 'Órdenes de trabajo', implemented = true, requires = 'install' },
            { id = 'bodycams', name = 'Bodycams', implemented = true },
            { id = 'alarms', name = 'Alarmas', implemented = true },
            { id = 'access', name = 'Control de accesos', implemented = false },
            { id = 'trackers', name = 'Localizadores', implemented = false },
            { id = 'patrols', name = 'Rondas', implemented = true },
            { id = 'dispatch', name = 'Central de operaciones', implemented = true },
            { id = 'contracts', name = 'Contratos', implemented = true },
            { id = 'cash_transport', name = 'Transporte de fondos', implemented = true }
        }
    }
}

-- Identificadores que ve el jugador: solo el numero entero ('osd_0000000012' -> 12). El dato guardado no cambia.
function OSSecurity.Brand.number(id)
    local digits = type(id) == 'string' and id:match('(%d+)$')
    return digits and tonumber(digits) or id
end
function OSSecurity.Brand.deviceLabel(id) return OSSecurity.Brand.DevicePrefix .. ' · ' .. tostring(OSSecurity.Brand.number(id)) end
