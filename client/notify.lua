-- Mensajes al jugador: notificacion compacta si os_notify (opcional) esta iniciado; si no, chat estandar.
-- OS Security no depende de os_notify: es portable y funciona igual sin el.
local KINDS = { info = true, success = true, warning = true, error = true }

function OSSecurity.Notify(message, kind)
    message = message or OSSecurity.Brand.Text.failed
    kind = KINDS[kind] and kind or 'info'
    if GetResourceState('os_notify') == 'started' then
        local ok = pcall(function() exports.os_notify:Notify(message, kind) end)
        if ok then return 'os_notify' end
    end
    TriggerEvent('chat:addMessage', { args = { OSSecurity.Brand.Name, message } })
    return 'chat'
end
