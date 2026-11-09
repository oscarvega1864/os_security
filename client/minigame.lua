-- Minijuego de instalacion (taladrar, atornillar y conectar cables) en la NUI del recurso.
-- Es solo de interfaz: decide si el cliente envia la confirmacion o la cancelacion de la colocacion.
-- El servidor sigue validando todo y no cobra materiales si se cancela o se falla.
OSSecurity.ClientMinigame = {}

function OSSecurity.ClientMinigame.new(options)
    local minigame, pending, generation = {}, nil, 0
    function minigame.active() return pending ~= nil end
    function minigame.finish(result)
        local callback = pending
        if not callback then return end
        pending, generation = nil, generation + 1
        options.focus(false); options.animate(false)
        options.send({ type = 'minigameClose' })
        local ok = type(result) == 'table' and result.ok == true
        callback(ok, not ok and type(result) == 'table' and result.reason == 'cancelled' and 'cancelled' or nil)
    end
    function minigame.run(callback, mode)
        if pending then minigame.finish({ ok = false, reason = 'cancelled' }) end
        generation = generation + 1
        local current = generation
        pending = callback
        options.animate(true); options.focus(true)
        options.send({ type = 'minigame', text = OSSecurity.Brand.Text.minigame, mode = mode == 'remove' and 'remove' or 'install' })
        options.timeout(function()
            if current == generation and pending then minigame.finish({ ok = false, reason = 'timeout' }) end
        end)
    end
    function minigame.cancel() minigame.finish({ ok = false, reason = 'cancelled' }) end
    return minigame
end
