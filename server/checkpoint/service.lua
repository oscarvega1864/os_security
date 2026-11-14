-- Control de acceso: arcos detectores de metales y cacheo (os_security 0.16.0).
-- Arco: cualquier empleado de servicio de una empresa (os_devtools) coloca el objeto os_metal_detector; el arco
-- es de su empresa y la misma empresa lo recoge. Al cruzarlo, pita si se lleva metal (objetos de Metal o armas
-- con metal) y avisa a los empleados de esa empresa que esten cerca. No dice que se lleva: para eso, cacheo.
-- Cacheo: un empleado de servicio (de cualquier empresa) lo pide a quien tiene delante; el cacheado acepta o
-- rechaza. Con permiso, el vigilante palpa por zonas y puede retener armas y objetos peligrosos (Retainable):
-- quedan en custodia de su empresa y el dueno los recoge en el mismo sitio con /custodia.
-- Las armas las lleva el ped de GTA: las informa el cliente del propio jugador y solo se aceptan las de
-- shared/weapons.lua. Un cliente modificado podria ocultarlas; el inventario si lo lee el servidor.
local util = OSSecurity.Util
OSSecurity.CheckpointService = {}

local function flat(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) end
local function distance(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + ((a.z or 0) - (b.z or 0)) ^ 2) end
local POCKETS = { 'leftLeg', 'rightLeg', 'chest', 'waist' }
local ITEM_ZONES = { telefono = 'rightLeg', bank_card = 'leftLeg', tarjeta_acceso = 'leftLeg', herramienta = 'waist', os_lockpick = 'leftArm',
    os_screwdriver = 'waist', os_drill = 'back' }

function OSSecurity.CheckpointService.new(options)
    local config = OSSecurity.GameplayConfig.Checkpoint
    local T = OSSecurity.Brand.Text.checkpoint
    local service = {}
    local passes = {}   -- source..':'..detector -> instante
    local pending = {}  -- cacheado -> { guard, expires }
    local frisks = {}   -- vigilante -> { target, holder, findings, expires, company }

    local function detectors() return options.inventory.detectors() or {} end
    local function custody() return options.inventory.custody() or {} end
    local function name(source) local value = options.playerName and options.playerName(source); return type(value) == 'string' and value:sub(1, 64) or ('Jugador ' .. tostring(source)) end
    local function notify(source, text, kind, position) if source and options.notify then options.notify(source, text, kind or 'info', position) end end
    local function nextId(list, prefix)
        local highest = 0
        for id in pairs(list) do highest = math.max(highest, tonumber(id:sub(4)) or 0) end
        return ('%s_%06d'):format(prefix, highest + 1)
    end
    local function where(source)
        local point, bucket = options.world(source)
        return point, bucket or 0
    end
    -- Empresa de servicio del jugador (cualquier empleo de os_devtools); nil sin empleo o fuera de servicio.
    local function company(source)
        local value = options.company and options.company(source)
        return OSSecurity.InventoryState.company(value) and value or nil
    end
    local function canFrisk(source) return company(source) ~= nil or (options.isStaff and options.isStaff(source)) end
    local function holderOf(source) return options.items and options.items.holder(source) or nil end
    local function weaponsOf(list)
        local result, seen = {}, {}
        if type(list) ~= 'table' then return result end
        for index, entry in ipairs(list) do
            if index > config.MaxWeapons then break end
            local weaponName = type(entry) == 'table' and entry.name or entry
            local ammo = type(entry) == 'table' and math.tointeger(tonumber(entry.ammo)) or 0
            if type(weaponName) == 'string' and OSSecurity.Weapons.List[weaponName] and not seen[weaponName] then
                seen[weaponName] = true
                result[#result + 1] = { name = weaponName, ammo = math.max(0, math.min(9999, ammo or 0)) }
            end
        end
        return result
    end
    local function broadcast(position, bucket, radius, event, payload)
        for _, player in ipairs(options.players and options.players() or {}) do
            local point, playerBucket = where(player)
            if point and playerBucket == bucket and distance(point, position) <= radius then options.send(player, event, payload) end
        end
    end

    -- Arcos -------------------------------------------------------------------------------------------
    function service.list()
        local result = {}
        for _, detector in pairs(detectors()) do
            result[#result + 1] = { id = detector.id, x = detector.position.x, y = detector.position.y, z = detector.position.z,
                h = detector.heading, bucket = detector.bucket, company = detector.company }
        end
        table.sort(result, function(a, b) return a.id < b.id end)
        return result
    end
    local function changed() if options.changed then options.changed(service.list()) end end
    -- Herramientas de montaje (taladro y destornillador, como alarmas y camaras): se comprueban, no se gastan.
    local function hasTools(holder)
        for _, tool in ipairs(config.Tools) do if options.items.count(holder, tool) < 1 then return false end end
        return true
    end
    -- Antes de abrir el minijuego de montaje: empresa, objeto y herramientas.
    function service.mountCheck(source)
        local job = company(source)
        if not job then return nil, T.needJob end
        if not options.items or not options.items.available() then return nil, T.needInventory end
        local holder = holderOf(source)
        if not holder or options.items.count(holder, 'os_metal_detector') < 1 then return nil, T.needItem end
        if not hasTools(holder) then return nil, T.needTools end
        return { job = job, holder = holder }
    end
    function service.place(source, args)
        local ready, why = service.mountCheck(source)
        if not ready then return nil, why end
        local job, holder = ready.job, ready.holder
        if not util.object(args, { x = true, y = true, z = true, h = true }) then return nil, T.badPlace end
        local x, y, z, h = tonumber(args.x), tonumber(args.y), tonumber(args.z), tonumber(args.h)
        local here, bucket = where(source)
        if not x or not y or not z or not h or x ~= x or y ~= y or z ~= z or h ~= h or not here then return nil, T.badPlace end
        if distance(here, { x = x, y = y, z = z }) > config.PlaceDistance + 1.5 then return nil, T.tooFar end
        for _, other in pairs(detectors()) do
            if other.bucket == bucket and flat(other.position, { x = x, y = y }) < 1.5 then return nil, T.tooClose end
        end
        local list = detectors()
        local detector = { id = nextId(list, 'md'), company = job, placedBy = options.identity.resolve(source),
            position = { x = util.round(x, 2), y = util.round(y, 2), z = util.round(z, 2) }, heading = util.round(h % 360, 1) % 360,
            bucket = bucket, createdAt = options.now() }
        if not detector.placedBy then return nil, T.badPlace end
        local taken, takeError = options.items.takeAny(holder, 'os_metal_detector', 1, 'detector:' .. detector.id .. ':place')
        if not taken then return nil, takeError end
        local saved, err = options.inventory.apply({ kind = 'detector', detectorId = detector.id, detector = detector })
        if not saved then
            options.items.giveAny(holder, 'os_metal_detector', 1, 'detector:' .. detector.id .. ':refund')
            return nil, err
        end
        changed()
        options.audit('detector_placed', source, detector.id)
        return { message = T.placed:format(job), id = detector.id }
    end
    local function nearest(source, radius, accept)
        local here, bucket = where(source)
        if not here then return nil end
        local best, bestDistance
        for _, detector in pairs(detectors()) do
            local d = distance(here, detector.position)
            if detector.bucket == bucket and d <= radius and (not accept or accept(detector)) and (not bestDistance or d < bestDistance) then best, bestDistance = detector, d end
        end
        return best
    end
    -- Antes de abrir el minijuego de desmontaje: empresa, arco suyo al lado y herramientas.
    function service.unmountCheck(source)
        local job = company(source)
        if not job then return nil, T.needJob end
        local detector = nearest(source, config.PickupDistance, function(item) return item.company == job end)
        if not detector then return nil, T.noOwnNear end
        local holder = holderOf(source)
        if not holder then return nil, T.needInventory end
        if not hasTools(holder) then return nil, T.needTools end
        return { detector = detector, holder = holder }
    end
    function service.pickup(source)
        local ready, why = service.unmountCheck(source)
        if not ready then return nil, why end
        local detector, holder = ready.detector, ready.holder
        local saved, err = options.inventory.apply({ kind = 'detector', detectorId = detector.id })
        if not saved then return nil, err end
        options.items.giveAny(holder, 'os_metal_detector', 1, 'detector:' .. detector.id .. ':pickup')
        changed()
        options.audit('detector_removed', source, detector.id)
        return { message = T.pickedUp }
    end
    -- Paso por el arco: el cliente avisa al cruzarlo; el servidor comprueba sitio, bucket y repeticion.
    function service.pass(source, detectorId, weapons)
        if not OSSecurity.InventoryState.detectorId(detectorId) then return nil end
        local detector = detectors()[detectorId]
        local here, bucket = where(source)
        if not detector or not here or bucket ~= detector.bucket then return nil end
        if flat(here, detector.position) > config.PassRadius or math.abs(here.z - detector.position.z) > 2.5 then return nil end
        local key = source .. ':' .. detectorId
        local now = options.now()
        if passes[key] and now - passes[key] < config.PassCooldown then return nil end
        passes[key] = now
        local metal = false
        for _, weapon in ipairs(weaponsOf(weapons)) do if OSSecurity.Weapons.List[weapon.name].metal then metal = true end end
        if not metal then
            local holder = holderOf(source)
            for item in pairs(holder and options.items.contents(holder) or {}) do if config.Metal[item] then metal = true end end
        end
        broadcast(detector.position, detector.bucket, 30.0, 'detector', { id = detector.id, alarm = metal })
        if metal then
            for _, player in ipairs(options.players and options.players() or {}) do
                local point, playerBucket = where(player)
                if player ~= source and company(player) == detector.company and point and playerBucket == detector.bucket
                    and distance(point, detector.position) <= config.AlertRadius then
                    notify(player, T.alarm:format(name(source)), 'warning', detector.position)
                end
            end
        end
        return { alarm = metal }
    end

    -- Cacheo ------------------------------------------------------------------------------------------
    function service.request(guard, target)
        if not canFrisk(guard) then return nil, T.needJob end
        if not util.integer(target, 1, 2147483647) or target == guard then return nil, T.noTarget end
        local a, bucketA = where(guard); local b, bucketB = where(target)
        if not a or not b or bucketA ~= bucketB or distance(a, b) > config.FriskDistance then return nil, T.noTarget end
        if frisks[guard] then return nil, T.busy end
        local current = pending[target]
        if current and current.expires > options.now() then return nil, T.targetBusy end
        pending[target] = { guard = guard, expires = options.now() + config.RequestSeconds }
        options.send(target, 'friskAsk', { from = name(guard), company = company(guard) or OSSecurity.Brand.Name, seconds = config.RequestSeconds })
        return { message = T.asked:format(name(target)) }
    end
    local function findingsOf(holder, weapons)
        local zones = {}
        for _, zone in ipairs(OSSecurity.Weapons.Zones) do zones[zone] = {} end
        for index, weapon in ipairs(weapons) do
            local info = OSSecurity.Weapons.List[weapon.name]
            table.insert(zones[info.zone], { kind = 'weapon', name = weapon.name, label = info.label, count = 1, retainable = true, metal = info.metal })
        end
        local items = holder and options.items.contents(holder) or {}
        local names = {}
        for item in pairs(items) do names[#names + 1] = item end
        table.sort(names)
        for index, item in ipairs(names) do
            if index > config.MaxItems then break end
            local zone = ITEM_ZONES[item] or POCKETS[(index - 1) % #POCKETS + 1]
            table.insert(zones[zone], { kind = 'item', name = item, label = items[item].label, count = items[item].count,
                retainable = config.Retainable[item] == true, metal = config.Metal[item] == true })
        end
        return zones
    end
    function service.answer(target, accept, weapons)
        local request = pending[target]
        pending[target] = nil
        if not request or request.expires < options.now() then return nil, T.expired end
        local guard = request.guard
        if accept ~= true then
            notify(guard, T.refused:format(name(target)), 'warning')
            return { message = T.youRefused }
        end
        local a, bucketA = where(guard); local b, bucketB = where(target)
        if not a or not b or bucketA ~= bucketB or distance(a, b) > config.FriskDistance + 1.0 or not canFrisk(guard) then
            return nil, T.noTarget
        end
        local holder = holderOf(target)
        local list = weaponsOf(weapons)
        frisks[guard] = { target = target, holder = holder, weapons = list, findings = findingsOf(holder, list),
            company = company(guard) or 'gruppe6', expires = options.now() + config.FriskSeconds }
        options.send(guard, 'friskOpen', { target = name(target), zones = util.copy(frisks[guard].findings), order = OSSecurity.Weapons.Zones })
        options.send(target, 'friskBegin', { guard = guard })
        return { message = T.accepted }
    end
    local function endFrisk(guard)
        local frisk = frisks[guard]
        frisks[guard] = nil
        if frisk then options.send(frisk.target, 'friskEnd', {}) end
        return frisk
    end
    -- Fin del cacheo: lo marcado para retener pasa a custodia de la empresa del vigilante.
    function service.finish(guard, retain)
        local frisk = frisks[guard]
        if not frisk then return nil, T.noFrisk end
        if frisk.expires < options.now() then endFrisk(guard); return nil, T.expired end
        local wantItems, wantWeapons = {}, {}
        if type(retain) == 'table' then
            if type(retain.items) == 'table' then for item, amount in pairs(retain.items) do wantItems[item] = amount end end
            if type(retain.weapons) == 'table' then for _, weaponName in ipairs(retain.weapons) do wantWeapons[weaponName] = true end end
        end
        local found = {}
        for _, entries in pairs(frisk.findings) do for _, entry in ipairs(entries) do found[entry.kind .. ':' .. entry.name] = entry end end
        local record = { items = {}, weapons = {} }
        local list = custody()
        local id = nextId(list, 'cu')
        local point, bucket = where(frisk.target)
        if not point then endFrisk(guard); return nil, T.noTarget end
        for item, amount in pairs(wantItems) do
            local entry = found['item:' .. tostring(item)]
            amount = math.tointeger(tonumber(amount))
            if entry and entry.retainable and amount and amount >= 1 and amount <= entry.count and frisk.holder then
                if options.items.takeAny(frisk.holder, item, amount, ('custody:%s:%s:take'):format(id, item)) then record.items[item] = amount end
            end
        end
        local removed = {}
        for _, weapon in ipairs(frisk.weapons) do
            if wantWeapons[weapon.name] and found['weapon:' .. weapon.name] then record.weapons[#record.weapons + 1] = util.copy(weapon); removed[#removed + 1] = weapon.name end
        end
        endFrisk(guard)
        if next(record.items) == nil and #record.weapons == 0 then
            notify(frisk.target, T.clean, 'success')
            return { message = T.nothingRetained }
        end
        local entry = { id = id, owner = options.identity.resolve(frisk.target), holder = next(record.items) and frisk.holder or nil,
            ownerName = name(frisk.target), company = frisk.company, guardName = name(guard), items = record.items, weapons = record.weapons,
            position = { x = util.round(point.x, 2), y = util.round(point.y, 2), z = util.round(point.z, 2) }, bucket = bucket, createdAt = options.now() }
        local saved, err = entry.owner and options.inventory.apply({ kind = 'custody', custodyId = id, custody = entry })
        if not saved then
            for item, amount in pairs(record.items) do options.items.giveAny(frisk.holder, item, amount, ('custody:%s:%s:undo'):format(id, item)) end
            return nil, err or T.noTarget
        end
        if #removed > 0 then options.send(frisk.target, 'removeWeapons', removed) end
        notify(frisk.target, T.retainedOwner:format(entry.company), 'warning')
        options.audit('custody_created', guard, id)
        return { message = T.retained:format(id) }
    end
    function service.cancel(guard) if endFrisk(guard) then return { message = T.cancelled } end; return nil, T.noFrisk end
    -- Recoger lo retenido: el dueno, en el mismo sitio donde se lo retuvieron.
    function service.reclaim(source)
        local principal = options.identity.resolve(source)
        local here, bucket = where(source)
        if not principal or not here then return nil, T.noCustody end
        local found, far
        for _, record in pairs(custody()) do
            if record.owner == principal then
                if record.bucket == bucket and distance(here, record.position) <= config.PickupDistance + 2.0 then found = record; break end
                far = record
            end
        end
        if not found then return nil, far and T.goBack:format(far.company) or T.noCustody end
        local holder = holderOf(source)
        if next(found.items) and holder ~= found.holder then return nil, T.otherCharacter end
        local saved, err = options.inventory.apply({ kind = 'custody', custodyId = found.id })
        if not saved then return nil, err end
        for item, amount in pairs(found.items) do options.items.giveAny(holder, item, amount, ('custody:%s:%s:return'):format(found.id, item)) end
        if #found.weapons > 0 then options.send(source, 'giveWeapons', found.weapons) end
        options.audit('custody_returned', source, found.id)
        return { message = T.returned }
    end
    function service.tick()
        local now = options.now()
        for target, request in pairs(pending) do
            if request.expires < now then pending[target] = nil; notify(request.guard, T.noAnswer, 'info') end
        end
        for guard, frisk in pairs(frisks) do if frisk.expires < now then endFrisk(guard) end end
    end
    function service.forget(source)
        pending[source] = nil
        for target, request in pairs(pending) do if request.guard == source then pending[target] = nil end end
        endFrisk(source)
        for guard, frisk in pairs(frisks) do if frisk.target == source then endFrisk(guard); notify(guard, T.cancelled, 'info') end end
        for key in pairs(passes) do if key:match('^' .. source .. ':') then passes[key] = nil end end
    end
    return service
end
