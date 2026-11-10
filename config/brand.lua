-- Identidad comercial. Los nombres tecnicos del recurso y sus datos no cambian.
OSSecurity = OSSecurity or {}
OSSecurity.Brand = {
    Name = 'Gruppe Sechs', Monogram = 'G6', EmployeePrefix = 'G6-E', DevicePrefix = 'G6-D',
    Tagline = 'Proteccion que permanece.',
    Profiles = { client = 'Cliente', technician = 'Tecnico', supervisor = 'Supervisor', admin = 'Administrador', inventory = 'Equipo personal' },
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
        loading = 'Consultando el servidor...', unavailable = 'No disponible en esta fase', empty = 'No hay dispositivos accesibles en esta pagina.',
        noSignal = 'Solo registro. Transmision de imagen no implementada.', session = 'Sesion autorizada',
        noInventory = 'No dispone de equipo.', use = 'Utilizar', items = 'Articulos', condition = 'Condicion',
        details = 'Consultar', maintenance = 'Mantenimiento', inspect = 'Inspeccionar', repair = 'Reparar', replace = 'Sustituir',
        provision = 'Equipar registro antiguo', beginMaintenance = 'Pasar a mantenimiento', installed = 'Instalacion vinculada',
        logical = 'Registro logico', back = 'Volver', health = 'Salud', hours = 'Horas', history = 'Ultima intervencion',
        noHistory = 'Sin intervenciones', employee = 'Acreditacion', client = 'Titular autorizado',
        clientHero = 'La tranquilidad empieza por saber.', operationsHero = 'Cada dispositivo. Una responsabilidad.',
        inventoryHero = 'Preparado para el servicio.', assigned = 'Dispositivos accesibles', page = 'Pagina',
        installationAction = 'Preparar instalacion CCTV', inspectionNote = 'La salud refleja la ultima evaluacion confirmada.',
        type = 'Tipo', model = 'Modelo', state = 'Estado', installationDate = 'Instalacion',
        states = { registered = 'Registrado', installing = 'Instalando', installed = 'Instalado', active = 'Activo',
            maintenance = 'Mantenimiento', fault = 'Averia administrativa', retired = 'Retirado',
            healthy = 'En buen estado', worn = 'Desgastado', degraded = 'Degradado', critical = 'Critico', failed = 'Fallido' },
        pending = 'Pendiente de implementacion', failed = 'No se pudo completar la solicitud.',
        placementHelp = 'Flechas: mover  Mayus+flechas: girar  Q/Z: separar/acercar  R: invertir',
        placementHelp2 = '~n~Ctrl: fino  Tab: montaje  E: colocar  Retroceso: salir',
        anchorAimHelp = 'Apunta a pared o techo  + / -: tamano  E: fijar superficie  Retroceso o Esc: salir',
        anchorHelp = 'Flechas: mover  + / -: tamano  Ctrl: fino  E: registrar  Retroceso: volver a apuntar',
        anchorZone = 'Zona',
        installFailed = 'Instalacion fallida: no se ha consumido material.',
        minigame = {
            title = 'Instalacion CCTV', cancel = 'Cancelar (Esc)',
            drillTitle = 'Taladrar los anclajes', drillHelp = 'Manten pulsado el raton sobre cada marca hasta perforarla. Suelta para enfriar la broca; no te salgas de la marca.',
            heat = 'Temperatura de la broca', slips = 'Resbalones', slip = 'La broca ha resbalado', tooHot = 'Demasiado caliente: suelta para enfriar',
            drilling = 'Perforando...', holeDone = 'Agujero hecho',
            screwTitle = 'Atornillar el soporte', screwHelp = 'Pulsa sobre un tornillo y gira el raton a su alrededor en sentido horario. Sin prisas: con demasiada fuerza se pasa la rosca.',
            torque = 'Fuerza', strips = 'Roscas pasadas', turnHint = 'Gira en sentido horario', tooStrong = 'Demasiada fuerza: mas despacio',
            stripped = 'Rosca pasada: vuelve a empezar ese tornillo', hit = 'Tornillo apretado',
            cablesTitle = 'Conectar el cableado', cablesHelp = 'Arrastra cada cable hasta el borne de su senal segun el codigo de colores (los bornes solo llevan la etiqueta).',
            wireCode = 'Rojo +12V · Negro GND · Verde A+ · Blanco B- · Amarillo TAMP',
            colors = { 'Rojo', 'Azul', 'Amarillo', 'Verde' }, shorts = 'Cortocircuitos', connected = 'Conectado', wrongWire = 'Borne incorrecto',
            removeTitle = 'Desmontaje', unplugTitle = 'Desconectar el cableado',
            unplugHelp = 'Arrastra cada cable fuera de su borne hasta la bandeja de la izquierda.', unplugged = 'Desconectado',
            unscrewTitle = 'Desatornillar el soporte', unscrewHelp = 'Pulsa sobre un tornillo y gira el raton en sentido ANTIHORARIO hasta sacarlo. Sin forzar.',
            unscrewed = 'Tornillo fuera'
        },
        placementMount = 'Montaje',
        miniInstallAction = 'Instalar camara mini (interior)', domeInstallAction = 'Instalar camara domo 360',
        alarmInstallAction = 'Instalar alarma (teclado)', alarmPanelInstallAction = 'Instalar alarma (panel lector)',
        remove = 'Desmontar', removed = 'Dispositivo %s desmontado: el kit vuelve a tu inventario.', removeCancelled = 'Desmontaje cancelado.',
        removeHelp = 'Debes estar junto al dispositivo con taladro y destornillador.',
        alarm = {
            title = 'Alarma', triggered = 'SALTO DE ALARMA', arm = 'Armar total', partial = 'Armar parcial', disarm = 'Desarmar',
            modes = { disarmed = 'Desarmada', armed = 'Armada (total)', partial = 'Armada (parcial)' },
            createPin = 'Crear codigo (4-6 cifras)', newPin = 'Nuevo codigo', savePin = 'Guardar codigo', pinFormat = 'El codigo debe tener entre 4 y 6 cifras.',
            tags = 'Chapas', programTag = 'Programar chapa', revokeTags = 'Revocar chapas',
            events = { armed = 'Armada', partial = 'Armada parcial', disarmed = 'Desarmada', triggered = 'Salto de alarma', wrong_pin = 'Codigo o chapa incorrectos',
                lockout = 'Teclado bloqueado', pin_set = 'Codigo cambiado', tag_added = 'Chapa programada', tags_revoked = 'Chapas revocadas', entry = 'Entrada detectada' },
            keypadHint = '~INPUT_CONTEXT~ teclado de alarma   ~INPUT_DETONATE~ acercar chapa',
            pad = { armed = 'ARMADA', partial = 'PARCIAL', disarmed = 'DESARMADA', locked = 'BLOQUEADO', entry = 'INTRODUZCA CODIGO', triggered = 'ALARMA',
                arm = 'Total', partial = 'Parcial', disarm = 'Desarmar', tag = 'Acercar chapa', clear = 'Borrar', close = 'Salir (Esc)' },
            entryWarning = 'Alarma armada: introduce el codigo en %d s o saltara.'
        },
        locks = {
            lockHint = '~INPUT_CONTEXT~ cerrar con llave', unlockHint = '~INPUT_CONTEXT~ abrir con llave',
            minigame = {
                title = 'Cambio de bombin', cancel = 'Cancelar (Esc)',
                unscrewTitle = 'Quitar el tornillo de fijacion', unscrewHelp = 'Pulsa sobre el tornillo del canto de la puerta y gira el raton en sentido ANTIHORARIO hasta sacarlo. Sin forzar.',
                outTitle = 'Sacar el bombin viejo', outHelp = 'Gira la llave arrastrando a su alrededor hasta que la leva quede arriba (verde). Despues arrastra el bombin hacia fuera, a la izquierda.',
                inTitle = 'Meter el bombin nuevo', inHelp = 'Alinea arriba la leva del bombin nuevo (verde) y empujalo hacia dentro de la cerradura.',
                screwTitle = 'Apretar el tornillo de fijacion', screwHelp = 'Pulsa sobre el tornillo y gira en sentido horario hasta apretarlo. Con demasiada fuerza se pasa la rosca.',
                torque = 'Fuerza', strips = 'Roscas pasadas', jams = 'Atascos', turnHint = 'Sigue girando',
                jammed = 'La leva tropieza: alineala arriba antes de mover el bombin', aligned = 'Leva alineada: ya puedes moverlo',
                tooStrong = 'Demasiada fuerza: mas despacio', stripped = 'Rosca pasada: vuelve a empezar', screwOut = 'Tornillo fuera',
                cylinderOut = 'Bombin viejo fuera', cylinderIn = 'Bombin nuevo dentro', done = 'Bombin cambiado'
            }
        },
        cars = {
            minigame = {
                title = 'Instalacion en vehiculo', cancel = 'Cancelar (Esc)', kinds = { lock = 'Cierre centralizado', alarm = 'Alarma', hotwire = 'Puente' },
                hotwireTitle = 'Vehiculo sin llave', coverTitle = 'Quitar la tapa de la columna', coverHelp = 'Manten pulsado sobre cada grapa y suelta cuando la tension este en la franja verde. Si te pasas, la grapa se rompe.',
                starterTitle = 'Dar al motor de arranque', starterHelp = 'Manten pulsado ARRANCAR y suelta cuando la carga este en la franja verde. Antes no arranca; si te pasas, se quema el fusible.',
                start = 'ARRANCAR', charge = 'Arranque', fuses = 'Fusibles', cranking = 'Girando el motor...', started = 'Arranca',
                noStart = 'No arranca: vuelve a intentarlo', fuse = 'Fusible quemado',
                trimTitle = 'Quitar el embellecedor bajo el volante', trimHelp = 'Manten pulsado sobre cada grapa y suelta cuando la tension este en la franja verde. Si te pasas, la grapa se rompe.',
                tension = 'Tension', broken = 'Grapas rotas', pulling = 'Tirando...', clipOut = 'Grapa fuera', notEnough = 'Poca fuerza: vuelve a tirar',
                clipBroken = 'Grapa rota',
                wireTitle = 'Medir y empalmar', wireHelp = '1) Pulsa cada cable: el multimetro dice que es y su nombre queda escrito debajo. 2) Arrastra cada hilo del modulo hasta el cable con su mismo nombre.',
                probe = 'Lectura', spliced = 'Empalmado', wrongWire = 'Cable equivocado: el modulo no responde', shorts = 'Fallos',
                testTitle = 'Probar el mando', testHelp = 'Pulsa el boton del mando: el LED del modulo debe responder.', works = 'Funciona'
            }
        },
        lockpick = {
            title = 'Ganzua', heading = 'Forzar la cerradura', cancel = 'Dejarlo (Esc)', misses = 'Fallos',
            help = 'Haz clic o pulsa Espacio cuando el pin que se mueve pase por su zona verde. Uno tras otro; con tres fallos lo dejas.',
            set = 'Pin fijado', miss = 'Se escapa el pin',
            kinds = { door = 'Puerta', vehicle = 'Vehiculo' }, tiers = { 'Seguridad basica', 'Seguridad media', 'Alta seguridad' }
        },
        hello = 'Gruppe Sechs: servicio de seguridad disponible.',
        shop = {
            prompt = '~INPUT_CONTEXT~ Tienda Gruppe Sechs', title = 'Equipos de seguridad', close = 'Cerrar (Esc)',
            categories = { tablet = 'Tablets', kit = 'Kits e instalaciones', tool = 'Herramientas', material = 'Consumibles', access = 'Accesos', other = 'Otros' },
            staffItem = 'Personal G6', staffOnly = 'Solo personal G6 de servicio', cart = 'Tu pedido', empty = 'Elige productos con + y -.',
            total = 'Total', pay = 'Pagar con', accounts = { bank = 'Banco', cash = 'Efectivo' }, buy = 'Pagar', paying = 'Pagando...',
            insufficient = 'No tienes saldo suficiente en esa cuenta.', failed = 'No se pudo completar la compra.',
            staffHint = 'Los kits de camaras y alarmas y el taladro son para tecnicos G6 de servicio.'
        },
        -- Seccion Instalaciones (G6 Operations): zonas de montaje marcadas con el visor e instalacion.
        zones = {
            title = 'Zonas de montaje', hero = 'Marca la zona. Instala sin volver a la oficina.',
            heroHelp = 'Elige el cliente, marca la zona con el visor y desde su ficha instala la camara o la alarma estando a menos de %d m.',
            newZone = 'Nueva zona', client = 'Cliente', self = 'Yo mismo', mark = 'Marcar zona con el visor',
            markHelp = 'La tablet se cierra: apunta, E fija la superficie, flechas mueven, + y - cambian el tamano y E hace la foto.',
            noClients = 'No hay clientes cerca.', empty = 'Todavia no hay zonas. Marca la primera con el visor.',
            surfaces = { wall = 'Pared', ceiling = 'Techo', floor = 'Suelo' },
            states = { free = 'Libre', pending = 'Pendiente', installed = 'Instalada' },
            install = 'Instalar', kit = 'Kit', noKits = 'Sin kits en el inventario', delete = 'Borrar zona',
            distance = 'a %s m', unknownPlace = 'Lugar sin nombre', here = 'Aqui', goCloser = 'Acercate (%s m)', size = '%s x %s m', notMine = 'Zona de otro tecnico',
            device = 'Dispositivo', viewDevice = 'Ver dispositivo', site = 'Sitio', materials = 'Material disponible'
        },
        viewfinder = {
            rec = 'REC', aim = 'Apunta a la pared, techo o suelo y pulsa E', adjust = 'Flechas: mover · + / -: tamano · Ctrl: fino · E: foto · Retroceso: volver',
            noSurface = 'Sin superficie', shot = 'Zona capturada', client = 'Cliente', zone = 'Zona'
        },
        doors = { title = 'Cerraduras de tus propiedades', help = 'Puertas con bombin G6 en tus propiedades y negocios. La llave la lleva tu personaje.',
            empty = 'No hay puertas con cerradura en tus propiedades.', locked = 'Cerrada con llave', open = 'Abierta', level = 'Nivel %d' },
        trackers = { title = 'Tus vehiculos protegidos', help = 'Vehiculos con cierre centralizado o alarma G6. Si estan en la calle, puedes marcarlos en el GPS.',
            empty = 'No tienes vehiculos con equipo G6.', lock = 'Cierre centralizado', alarm = 'Alarma', locked = 'Cerrado', open = 'Abierto',
            sounding = 'ALARMA SONANDO', gps = 'Marcar en el GPS', away = 'Guardado o fuera de alcance' },
        incidents = { title = 'Historial de incidencias', help = 'Ultimos sucesos de todas tus alarmas, del mas reciente al mas antiguo.',
            empty = 'Sin incidencias registradas.' },
        profileAbilities = 'Funciones de su perfil',
        abilities = { view = 'Consultar', inspect = 'Inspeccionar', repair = 'Reparar', replace = 'Sustituir piezas',
            provision = 'Equipar registros', beginMaintenance = 'Abrir mantenimiento', install = 'Instalar CCTV' },
        serviceNames = { cctv = 'Registro CCTV', maintenance = 'Servicio tecnico', installation = 'Instalaciones', inventory = 'Inventario tecnico' }
    },
    Modules = {
        client = {
            { id = 'overview', name = 'Mis dispositivos', implemented = true },
            { id = 'cctv', name = 'CCTV autorizado', implemented = true },
            { id = 'alarms', name = 'Alarmas residenciales y comerciales', implemented = true },
            { id = 'locks', name = 'Cerraduras', implemented = true },
            { id = 'trackers', name = 'Localizadores de vehiculos', implemented = true },
            { id = 'emergencies', name = 'Emergencias', implemented = false },
            { id = 'contracts', name = 'Contratos', implemented = false },
            { id = 'requests', name = 'Solicitudes de mantenimiento', implemented = false },
            { id = 'incidents', name = 'Historial de incidencias', implemented = true }
        },
        operations = {
            { id = 'overview', name = 'Dispositivos asignados', implemented = true },
            { id = 'installations', name = 'Instalaciones', implemented = true, requires = 'install' },
            { id = 'maintenance', name = 'Mantenimiento', implemented = true },
            { id = 'inventory', name = 'Inventario tecnico', implemented = true },
            { id = 'cctv', name = 'Registro CCTV', implemented = true },
            { id = 'work_orders', name = 'Ordenes de trabajo', implemented = false },
            { id = 'bodycams', name = 'Bodycams', implemented = false },
            { id = 'alarms', name = 'Alarmas', implemented = true },
            { id = 'access', name = 'Control de accesos', implemented = false },
            { id = 'trackers', name = 'Localizadores', implemented = false },
            { id = 'patrols', name = 'Rondas', implemented = false },
            { id = 'dispatch', name = 'Central de operaciones', implemented = false },
            { id = 'cash_transport', name = 'Transporte de fondos', implemented = false }
        }
    }
}
