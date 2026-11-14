-- Minijuego de instalacion (taladrar, atornillar y conectar cables) en la NUI del recurso.
-- Es solo de interfaz: decide si el cliente envia la confirmacion o la cancelacion de la colocacion.
-- El servidor sigue validando todo y no cobra materiales si se cancela o se falla.
OSSecurity.ClientMinigame = {}

function OSSecurity.ClientMinigame.new(options)
    local minigame, pending, generation, pending_mode = {}, nil, 0, nil
    function minigame.active() return pending ~= nil end
    function minigame.finish(result)
        local callback = pending
        if not callback then return end
        pending, generation = nil, generation + 1
        local ok = type(result) == 'table' and result.ok == true
        options.focus(false)
        -- Exito: paso final con el equipo en la mano (si hay efectos); si no, se retiran los efectos ya.
        if ok and options.finale then options.finale(pending_mode) else options.animate(false) end
        options.send({ type = 'minigameClose' })
        callback(ok, not ok and type(result) == 'table' and result.reason == 'cancelled' and 'cancelled' or nil)
    end
    -- variant: nil (CCTV y alarmas) o 'detector' (arco detector: sus textos sustituyen a los comunes).
    -- extra (opcional): { focus = posicion del montaje (camara cercana), prop = modelo del paso final o false }.
    function minigame.run(callback, mode, variant, extra)
        if pending then minigame.finish({ ok = false, reason = 'cancelled' }) end
        generation = generation + 1
        local current = generation
        pending, pending_mode = callback, mode == 'remove' and 'remove' or 'install'
        options.animate(true, extra); options.focus(true)
        local text = OSSecurity.Brand.Text.minigame
        if variant == 'detector' and OSSecurity.Brand.Text.checkpoint and OSSecurity.Brand.Text.checkpoint.minigame then
            text = {}
            for key, value in pairs(OSSecurity.Brand.Text.minigame) do text[key] = value end
            for key, value in pairs(OSSecurity.Brand.Text.checkpoint.minigame) do text[key] = value end
        end
        options.send({ type = 'minigame', text = text, mode = mode == 'remove' and 'remove' or 'install', variant = variant == 'detector' and 'detector' or nil })
        options.timeout(function()
            if current == generation and pending then minigame.finish({ ok = false, reason = 'timeout' }) end
        end)
    end
    function minigame.cancel() minigame.finish({ ok = false, reason = 'cancelled' }) end
    return minigame
end
