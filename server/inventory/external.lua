-- Proveedor externo de objetos por personaje (por ejemplo os_inventory + os_devtools).
-- Solo gestiona cantidades de objetos del catalogo de OS Security. Montajes, instalaciones y
-- concesiones siguen en el registro local. Toda escritura usa identificadores de operacion
-- deterministas: repetir tras un corte no cobra ni devuelve dos veces.
OSSecurity.ExternalItems = {}

local function sorted(map)
    local keys = {}
    for key in pairs(map) do keys[#keys + 1] = key end
    table.sort(keys)
    return keys
end

-- api: available() -> bool; holder(source) -> id|nil; count(holder, item) -> integer|nil
--      add(holder, item, amount, operationId) -> bool, err; remove(holder, item, amount, operationId) -> bool, err
function OSSecurity.ExternalItems.new(api)
    local util = OSSecurity.Util
    local items = { external = true }

    local function operation(installationId, kind, item) return ('%s:%s:%s'):format(installationId, kind, item) end
    local function safe(fn, ...)
        local ok, first, second = pcall(fn, ...)
        if not ok then return nil, 'Proveedor de objetos no disponible.' end
        return first, second
    end

    function items.available() return safe(api.available) == true end
    function items.holder(source)
        if not items.available() then return nil, 'Inventario de personajes no disponible.' end
        local holder = safe(api.holder, source)
        if not OSSecurity.InventoryState.holder(holder) then return nil, 'Personaje activo no disponible.' end
        return holder
    end
    function items.count(holder, item)
        if not OSSecurity.InventoryState.holder(holder) or not OSSecurity.ItemCatalog[item] then return 0 end
        local amount = safe(api.count, holder, item)
        return util.integer(amount, 0, 2147483647) and amount or 0
    end
    function items.has(holder, item, amount) return items.count(holder, item) >= (amount or 1) end
    function items.list(holder)
        local result = {}
        for _, item in ipairs(sorted(OSSecurity.ItemCatalog)) do
            local amount = items.count(holder, item)
            if amount > 0 then result[item] = amount end
        end
        return result
    end
    function items.grant(holder, item, amount, operationId)
        if not OSSecurity.InventoryState.holder(holder) or not OSSecurity.ItemCatalog[item] then return nil, 'Destino u objeto no valido.' end
        local ok, err = safe(api.add, holder, item, amount, operationId)
        if ok ~= true then return nil, err or 'Entrega rechazada por el inventario.' end
        return true
    end
    -- Cobra los materiales de una instalacion. Se detiene en el primer fallo; el llamante
    -- debe usar refund, que liquida lo cobrado sin depender de saber hasta donde llego.
    function items.take(installationId, holder, materials)
        for _, item in ipairs(sorted(materials)) do
            local ok, err = safe(api.remove, holder, item, materials[item], operation(installationId, 'take', item))
            if ok ~= true then return nil, err or 'Faltan materiales.' end
        end
        return true
    end
    -- Devuelve los materiales cobrados. Repite cada cobro con su mismo identificador: si ya se
    -- hizo no repite el efecto; si nunca se hizo se aplica ahora y se devuelve, saldo cero.
    -- Un cobro imposible (sin materiales) no genera devolucion.
    function items.refund(installationId, holder, materials)
        if not items.available() then return nil, 'Inventario de personajes no disponible; devolucion pendiente.' end
        for _, item in ipairs(sorted(materials)) do
            local amount = materials[item]
            if safe(api.remove, holder, item, amount, operation(installationId, 'take', item)) == true then
                local ok, err = safe(api.add, holder, item, amount, operation(installationId, 'refund', item))
                if ok ~= true then return nil, err or 'Devolucion pendiente.' end
            end
        end
        return true
    end
    -- Chapas de alarma: objeto g6_alarm_tag con metadatos { reference = dispositivo, serial }.
    function items.tagSerials(holder, deviceId)
        local list = {}
        if not OSSecurity.InventoryState.holder(holder) or not api.inventory then return list end
        local inventory = safe(api.inventory, holder)
        if type(inventory) ~= 'table' or type(inventory.slots) ~= 'table' then return list end
        for _, entry in pairs(inventory.slots) do
            local meta = type(entry) == 'table' and entry.metadata
            if entry.name == 'g6_alarm_tag' and type(meta) == 'table' and meta.reference == deviceId and type(meta.serial) == 'string' then
                list[#list + 1] = meta.serial
            end
        end
        return list
    end
    -- Gasta una chapa en blanco y entrega la programada; si la entrega falla, devuelve la de blanco.
    function items.makeTag(holder, deviceId, serial)
        if not OSSecurity.InventoryState.holder(holder) or not api.addMeta or not api.removeMeta then return nil, 'Proveedor sin soporte de metadatos.' end
        local base = 'g6tag:' .. serial
        if safe(api.removeMeta, holder, 'g6_alarm_tag', 1, {}, base .. ':blank') ~= true then
            return nil, 'Necesitas una chapa en blanco (' .. OSSecurity.ItemCatalog.g6_alarm_tag.name .. ').'
        end
        local ok, err = safe(api.addMeta, holder, 'g6_alarm_tag', 1, { label = 'Chapa ' .. deviceId, reference = deviceId, serial = serial }, base .. ':programmed')
        if ok ~= true then
            safe(api.addMeta, holder, 'g6_alarm_tag', 1, {}, base .. ':refund')
            return nil, err or 'No se pudo programar la chapa.'
        end
        return true
    end
    return items
end
