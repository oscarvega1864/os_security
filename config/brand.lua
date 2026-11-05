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
        placementHelp = 'Apunte al montaje autorizado. Rueda: orientar. E: confirmar. Retroceso: cancelar.',
        hello = 'Gruppe Sechs: servicio de seguridad disponible.',
        serviceNames = { cctv = 'Registro CCTV', maintenance = 'Servicio tecnico', installation = 'Instalaciones', inventory = 'Inventario tecnico' }
    },
    Modules = {
        client = {
            { id = 'overview', name = 'Mis dispositivos', implemented = true },
            { id = 'cctv', name = 'CCTV autorizado', implemented = true },
            { id = 'alarms', name = 'Alarmas residenciales y comerciales', implemented = false },
            { id = 'locks', name = 'Cerraduras electronicas', implemented = false },
            { id = 'trackers', name = 'Localizadores de vehiculos', implemented = false },
            { id = 'emergencies', name = 'Emergencias', implemented = false },
            { id = 'contracts', name = 'Contratos', implemented = false },
            { id = 'requests', name = 'Solicitudes de mantenimiento', implemented = false },
            { id = 'incidents', name = 'Historial de incidencias', implemented = false }
        },
        operations = {
            { id = 'overview', name = 'Dispositivos asignados', implemented = true },
            { id = 'installations', name = 'Instalaciones', implemented = true },
            { id = 'maintenance', name = 'Mantenimiento', implemented = true },
            { id = 'inventory', name = 'Inventario tecnico', implemented = true },
            { id = 'cctv', name = 'Registro CCTV', implemented = true },
            { id = 'work_orders', name = 'Ordenes de trabajo', implemented = false },
            { id = 'bodycams', name = 'Bodycams', implemented = false },
            { id = 'alarms', name = 'Alarmas', implemented = false },
            { id = 'access', name = 'Control de accesos', implemented = false },
            { id = 'trackers', name = 'Localizadores', implemented = false },
            { id = 'patrols', name = 'Rondas', implemented = false },
            { id = 'dispatch', name = 'Central de operaciones', implemented = false },
            { id = 'cash_transport', name = 'Transporte de fondos', implemented = false }
        }
    }
}
