-- Seccion "Gruppe Sechs" para el panel y la consola de os_admin (opcional, sin dependencia).
-- Cada accion ejecuta los comandos administrativos existentes (osdev, osmaint, osg6) con sus
-- mismas validaciones, ACE ossecurity.admin y auditoria; sus respuestas vuelven al panel.
OSSecurity.AdminPanel = {}

local FAILURE = { '^uso', 'denegado', 'no se pudo', 'invalid', 'rechaz', 'se requiere', 'no disponible', 'requiere',
    'inexistente', 'no encontrado', 'faltan', 'fuera de', 'desconocid', 'no admite', 'no mejoraria', 'debe ', 'no existe' }

-- Ejecuta un comando registrado recogiendo sus respuestas. 'capture' es la tabla compartida con reply.
function OSSecurity.AdminPanel.runner(handlers, capture)
    return function(source, command, args)
        local handler = handlers[command]
        if not handler then return { ok = false, message = 'Comando no disponible: ' .. command } end
        local previous = capture.current
        capture.current = { source = source, lines = {} }
        local ok, err = pcall(handler, source, args)
        local lines = capture.current.lines
        capture.current = previous
        if not ok then
            print(('%s [ERROR] Fallo en %s desde el panel: %s'):format(OSSecurity.Constants.LOG_PREFIX, command, tostring(err)))
            return { ok = false, message = 'El comando fallo; revisar la consola.' }
        end
        if #lines == 0 then return { ok = true, message = 'Hecho.' } end
        local failed = false
        for _, line in ipairs(lines) do
            local lower = line:lower()
            for _, pattern in ipairs(FAILURE) do if lower:find(pattern) then failed = true end end
        end
        if #lines == 1 then return { ok = not failed, message = lines[1] } end
        local rows = {}
        for index = 2, #lines do rows[#rows + 1] = { lines[index] } end
        return { ok = not failed, message = lines[1], columns = { 'Detalle' }, rows = rows }
    end
end

function OSSecurity.AdminPanel.build(run)
    local ace = OSSecurity.ServerConfig.AdminAce
    local device = { id = 'dispositivo', label = 'Dispositivo (osd_...)', type = 'text', max = 20 }
    local slot = { id = 'pieza', label = 'Pieza (power, optics...)', type = 'text', max = 40 }
    local function options(list) local result = {}; for _, item in ipairs(list) do result[#result + 1] = { value = item[1], label = item[2] } end; return result end
    local types = options({ { 'cctv_camera', 'Camara CCTV' }, { 'alarm_panel', 'Central de alarma' }, { 'alarm_sensor', 'Sensor de alarma' },
        { 'smart_lock', 'Cerradura inteligente' }, { 'vehicle_tracker', 'Localizador de vehiculo' }, { 'bodycam', 'Bodycam' }, { 'security_monitor', 'Monitor' } })
    local states = options({ { 'registered', 'Registrado' }, { 'installing', 'Instalando' }, { 'installed', 'Instalado' }, { 'active', 'Activo' },
        { 'maintenance', 'Mantenimiento' }, { 'fault', 'Averia administrativa' } })
    local items = {}
    for id, definition in pairs(OSSecurity.ItemCatalog) do items[#items + 1] = { value = id, label = definition.name } end
    table.sort(items, function(a, b) return a.label < b.label end)
    local function cmd(command, build)
        return function(source, values) return run(source, command, build(values)) end
    end
    return {
        id = 'gruppe6', label = 'Gruppe Sechs', order = 60,
        actions = {
            { id = 'dispositivos', label = 'Listar dispositivos', ace = ace, handler = cmd('osdev', function() return { 'list', '0', '100' } end) },
            { id = 'detalle', label = 'Detalle y diagnostico', ace = ace, fields = { device }, description = 'Estado, salud y piezas.',
              handler = function(source, values)
                  local info = run(source, 'osdev', { 'info', values.dispositivo })
                  if not info.ok then return info end
                  local diagnosis = run(source, 'osmaint', { 'diagnose', values.dispositivo })
                  local rows = {}
                  for _, row in ipairs(info.rows or {}) do rows[#rows + 1] = row end
                  rows[#rows + 1] = { diagnosis.message }
                  for _, row in ipairs(diagnosis.rows or {}) do rows[#rows + 1] = row end
                  return { ok = true, message = info.message, columns = { 'Detalle' }, rows = rows }
              end },
            { id = 'estado', label = 'Cambiar estado', ace = ace, fields = { device, { id = 'estado', label = 'Nuevo estado', type = 'select', options = states } },
              handler = cmd('osdev', function(v) return { 'state', v.dispositivo, v.estado } end) },
            { id = 'crear', label = 'Registrar dispositivo logico', ace = ace, fields = { { id = 'tipo', label = 'Tipo', type = 'select', options = types } },
              handler = cmd('osdev', function(v) return { 'create', v.tipo } end) },
            { id = 'retirar', label = 'Retirar dispositivo', ace = ace, confirm = true, fields = { device }, description = 'Pasa a retirado; conserva datos e historial.',
              handler = cmd('osdev', function(v) return { 'remove', v.dispositivo } end) },
            { id = 'averia', label = 'Provocar averia', ace = ace, description = 'Baja la salud de una pieza (pruebas y demostraciones).',
              fields = { device, slot, { id = 'salud', label = 'Salud final (0-100)', type = 'number', min = 0, max = 100 } },
              handler = cmd('osmaint', function(v) return { 'fault', v.dispositivo, v.pieza, tostring(v.salud) } end) },
            { id = 'reparar', label = 'Reparar pieza', ace = ace, fields = { device, slot }, description = 'Requiere estado Mantenimiento.',
              handler = cmd('osmaint', function(v) return { 'repair', v.dispositivo, v.pieza } end) },
            { id = 'sustituir', label = 'Sustituir pieza', ace = ace, fields = { device, slot }, description = 'Requiere estado Mantenimiento.',
              handler = cmd('osmaint', function(v) return { 'replace', v.dispositivo, v.pieza } end) },
            { id = 'historial', label = 'Historial de mantenimiento', ace = ace, fields = { device },
              handler = cmd('osmaint', function(v) return { 'history', v.dispositivo, '0', '50' } end) },
            { id = 'montaje', label = 'Crear zona de montaje (camara o alarma)', ace = ace, self = true,
              description = 'Al aceptar se abre el editor: apunta a la pared o techo, E fija, flechas/rueda ajustan y E registra.',
              fields = { { id = 'cliente', label = 'Cliente (dueno del dispositivo)', type = 'player' },
                  { id = 'instalador', label = 'Tecnico instalador (vacio: tu)', type = 'player', required = false },
                  { id = 'vinculo', label = 'Para', type = 'select', options = options({ { 'none', 'Sin propiedad' }, { 'propiedad', 'Propiedad' }, { 'negocio', 'Negocio' } }) },
                  { id = 'id', label = 'ID de la propiedad o negocio', type = 'number', integer = true, min = 1, max = 2147483646, required = false },
                  { id = 'nombre', label = 'Nombre de la zona (vacio: automatico)', type = 'text', max = 40, required = false } },
              handler = function(source, values)
                  local hook = OSSecurity.AdminPanel.hooks.anchorEditor
                  if not hook then return { ok = false, message = 'No disponible.' } end
                  local site
                  if values.vinculo ~= 'none' then
                      if not values.id then return { ok = false, message = 'Indica el ID de la propiedad o negocio.' } end
                      site = { kind = values.vinculo == 'negocio' and 'business' or 'property', id = values.id }
                  end
                  local name = values.nombre or OSSecurity.AdminPanel.anchorName(source, site)
                  if not name:match('^[%w_%-]+$') then return { ok = false, message = 'El nombre solo admite letras, numeros, _ y -.' } end
                  hook(source, { id = name, client = values.cliente, installer = values.instalador, site = site })
                  return { ok = true, close = true, message = ('Zona %s: apunta a la pared o al techo y pulsa E.'):format(name) }
              end },
            { id = 'dar', label = 'Dar tablet, kit o herramienta', ace = ace,
              fields = { { id = 'jugador', label = 'Jugador', type = 'player' }, { id = 'objeto', label = 'Objeto', type = 'select', options = items },
                  { id = 'cantidad', label = 'Cantidad', type = 'number', integer = true, min = 1, max = OSSecurity.GameplayConfig.MaxItemQuantity, default = 1 } },
              handler = cmd('osg6', function(v) return { 'give', tostring(v.jugador), v.objeto, tostring(v.cantidad) } end) },
            { id = 'equipo', label = 'Ver equipo G6 de un jugador', ace = ace, fields = { { id = 'jugador', label = 'Jugador', type = 'player' } },
              handler = cmd('osg6', function(v) return { 'inventory', tostring(v.jugador) } end) },
            { id = 'acceso', label = 'Dar o quitar acceso a un dispositivo', ace = ace,
              fields = { { id = 'jugador', label = 'Jugador', type = 'player' }, device,
                  { id = 'rol', label = 'Acceso', type = 'select', options = options({ { 'client', 'Cliente (consulta)' }, { 'technician', 'Tecnico' }, { 'supervisor', 'Supervisor' }, { 'none', 'Quitar acceso' } }) } },
              handler = cmd('osg6', function(v) return { 'access', tostring(v.jugador), v.dispositivo, v.rol } end) },
            { id = 'vincular', label = 'Vincular a propiedad o negocio', ace = ace,
              fields = { device, { id = 'tipo', label = 'Vinculo', type = 'select', options = options({ { 'propiedad', 'Propiedad' }, { 'negocio', 'Negocio' }, { 'none', 'Quitar vinculo' } }) },
                  { id = 'id', label = 'ID de la propiedad o negocio', type = 'number', integer = true, min = 1, max = 2147483646, required = false } },
              handler = function(source, values)
                  if values.tipo == 'none' then return run(source, 'osg6', { 'site', values.dispositivo, 'none' }) end
                  if not values.id then return { ok = false, message = 'Indica el ID de la propiedad o negocio.' } end
                  return run(source, 'osg6', { 'site', values.dispositivo, values.tipo, tostring(values.id) })
              end },
            { id = 'instalaciones', label = 'Instalaciones registradas', ace = ace, handler = cmd('osg6', function() return { 'installations' } end) },
            { id = 'puertaapuntada', label = 'Anadir la puerta que apunto', ace = ace, self = true,
              description = 'Para una puerta que no se detecta sola. Al aceptar, apunta a la puerta y pulsa E.',
              fields = { { id = 'tipo', label = 'De', type = 'select', options = options({ { 'propiedad', 'Propiedad' }, { 'negocio', 'Negocio' } }) },
                  { id = 'id', label = 'ID de la propiedad o negocio', type = 'number', integer = true, min = 1, max = 2147483646 } },
              handler = function(source, values)
                  local hook = OSSecurity.AdminPanel.hooks.aimDoor
                  if not hook then return { ok = false, message = 'No disponible.' } end
                  hook(source, { kind = values.tipo, id = values.id })
                  return { ok = true, close = true, message = 'Apunta a la puerta y pulsa E (Retroceso: salir).' }
              end },
            { id = 'puertacercana', label = 'Dar de baja la puerta mas cercana', ace = ace, self = true, confirm = true,
              description = 'La puerta con cerradura a menos de 3 m de ti queda libre y no se vuelve a detectar.',
              handler = function(source)
                  local hook = OSSecurity.AdminPanel.hooks.removeNearDoor
                  if not hook then return { ok = false, message = 'No disponible.' } end
                  local message, err = hook(source)
                  return { ok = message ~= nil, message = message or err }
              end },
            { id = 'puertas', label = 'Puertas con cerradura', ace = ace, description = 'Puertas detectadas en propiedades y negocios, bombin y estado.',
              handler = cmd('osg6', function() return { 'doors' } end) },
            { id = 'borrarpuerta', label = 'Dar de baja una puerta', ace = ace, confirm = true,
              fields = { { id = 'puerta', label = 'Puerta (p12_1...)', type = 'text', max = 24 } },
              description = 'Para puertas detectadas por error: queda libre y no se vuelve a detectar (/g6puerta la recupera).',
              handler = cmd('osg6', function(v) return { 'door', 'remove', v.puerta } end) },
            { id = 'diagnostico', label = 'Estado del sistema G6', ace = ace, handler = cmd('osg6', function() return { 'diagnose' } end) }
        }
    }
end

-- Acciones que continuan en el juego (editores de apuntar); las asigna server/main.lua.
OSSecurity.AdminPanel.hooks = OSSecurity.AdminPanel.hooks or {}
-- Nombre automatico de zona: propiedad/negocio y una marca de tiempo corta, unico por administrador.
function OSSecurity.AdminPanel.anchorName(source, site)
    local base = site and ((site.kind == 'business' and 'negocio' or 'prop') .. site.id) or 'zona'
    return ('%s_%s%d'):format(base, ('%x'):format(os.time() % 0x1000000), source % 100)
end

function OSSecurity.AdminPanel.publish(run)
    local state = GetResourceState('os_admin')
    if state ~= 'started' and state ~= 'starting' then return end
    local ok, err = pcall(function() return exports.os_admin:RegisterSection(OSSecurity.AdminPanel.build(run)) end)
    if not ok then print(('%s [ERROR] No se pudo registrar la seccion de administracion: %s'):format(OSSecurity.Constants.LOG_PREFIX, tostring(err))) end
end
