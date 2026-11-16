-- Ajustes de juego que tambien necesita el cliente. El resto de config/gameplay.lua solo se carga en el servidor;
-- config/gameplay.lua toma estos mismos valores de aqui (no se repiten). No introducir secretos en este archivo.
OSSecurity = OSSecurity or {}
OSSecurity.SharedGameplay = {
    -- Lector de tarjetas de os_inventory: pasar la tarjeta (arrastrarla al lector) antes de abrir/cerrar/arrancar con la
    -- llave-tarjeta, usar la chapa de alarma o pagar con tarjeta en la tienda G6. Sin os_inventory no se pide.
    CardSwipe = { Cars = true, AlarmTag = true, Shop = true },
    -- Camarita sujeta al pecho mientras la bodycam esta encendida (objeto del juego, hueso SKEL_Spine3).
    -- Para ajustar la posicion en el juego: /bodycamajuste x y z rx ry rz (solo en tu pantalla) y copiar aqui.
    BodycamWear = { Model = 'prop_npc_phone_02', Bone = 24818, Offset = { 0.16, 0.12, 0.13 }, Rotation = { 0.0, 90.0, 180.0 } },
}
