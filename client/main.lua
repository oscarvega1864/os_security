local constants = OSSecurity.Constants

-- Usa el evento del chat estandar de FiveM, sin librerias adicionales.
RegisterCommand('oshello', function()
    TriggerEvent('chat:addMessage', {
        args = { constants.CHAT_TITLE, OSSecurity.Brand.Text.hello }
    })
end, false)
