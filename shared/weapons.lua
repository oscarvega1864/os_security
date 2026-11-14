-- Armas que el arco detector y el cacheo tienen en cuenta: nombre en espanol, si llevan metal (pitan) y
-- zona del cuerpo donde se encuentran al cachear. Las lleva el ped de GTA (no hay inventario de armas aun):
-- el cliente informa de las que tiene; el servidor solo acepta nombres de esta lista.
-- Zonas: waist (cintura), back (espalda), chest (pecho), leftArm/rightArm, leftLeg/rightLeg, ankles (tobillos).
OSSecurity.Weapons = {}
local list = {
    -- Cuerpo a cuerpo
    { 'weapon_dagger', 'Daga de caballeria antigua', true, 'ankles' }, { 'weapon_bat', 'Bate de beisbol', false, 'back' },
    { 'weapon_bottle', 'Botella rota', false, 'rightArm' }, { 'weapon_crowbar', 'Palanca', true, 'back' },
    { 'weapon_flashlight', 'Linterna', true, 'waist' }, { 'weapon_golfclub', 'Palo de golf', true, 'back' },
    { 'weapon_hammer', 'Martillo', true, 'waist' }, { 'weapon_hatchet', 'Hacha', true, 'back' },
    { 'weapon_knuckle', 'Puno americano', true, 'rightArm' }, { 'weapon_knife', 'Cuchillo', true, 'ankles' },
    { 'weapon_machete', 'Machete', true, 'back' }, { 'weapon_switchblade', 'Navaja automatica', true, 'rightLeg' },
    { 'weapon_nightstick', 'Porra', false, 'waist' }, { 'weapon_wrench', 'Llave inglesa', true, 'waist' },
    { 'weapon_battleaxe', 'Hacha de guerra', true, 'back' }, { 'weapon_poolcue', 'Taco de billar', false, 'back' },
    { 'weapon_stone_hatchet', 'Hacha de piedra', false, 'back' },
    -- Pistolas
    { 'weapon_pistol', 'Pistola', true, 'waist' }, { 'weapon_pistol_mk2', 'Pistola Mk II', true, 'waist' },
    { 'weapon_combatpistol', 'Pistola de combate', true, 'waist' }, { 'weapon_appistol', 'Pistola AP', true, 'waist' },
    { 'weapon_stungun', 'Taser', true, 'waist' }, { 'weapon_pistol50', 'Pistola .50', true, 'waist' },
    { 'weapon_snspistol', 'Pistola SNS', true, 'ankles' }, { 'weapon_snspistol_mk2', 'Pistola SNS Mk II', true, 'ankles' },
    { 'weapon_heavypistol', 'Pistola pesada', true, 'waist' }, { 'weapon_vintagepistol', 'Pistola vintage', true, 'chest' },
    { 'weapon_flaregun', 'Pistola de bengalas', true, 'waist' }, { 'weapon_marksmanpistol', 'Pistola de tirador', true, 'waist' },
    { 'weapon_revolver', 'Revolver pesado', true, 'waist' }, { 'weapon_revolver_mk2', 'Revolver pesado Mk II', true, 'waist' },
    { 'weapon_doubleaction', 'Revolver de doble accion', true, 'waist' }, { 'weapon_ceramicpistol', 'Pistola de ceramica', false, 'ankles' },
    { 'weapon_navyrevolver', 'Revolver naval', true, 'waist' }, { 'weapon_gadgetpistol', 'Pistola de Perico', true, 'waist' },
    { 'weapon_pistolxm3', 'Pistola WM 29', true, 'waist' },
    -- Subfusiles, escopetas, fusiles y pesadas
    { 'weapon_microsmg', 'Microsubfusil', true, 'chest' }, { 'weapon_smg', 'Subfusil', true, 'back' },
    { 'weapon_smg_mk2', 'Subfusil Mk II', true, 'back' }, { 'weapon_assaultsmg', 'Subfusil de asalto', true, 'back' },
    { 'weapon_combatpdw', 'ADP de combate', true, 'back' }, { 'weapon_machinepistol', 'Pistola ametralladora', true, 'chest' },
    { 'weapon_minismg', 'Minisubfusil', true, 'chest' }, { 'weapon_tecpistol', 'Subfusil tactico', true, 'chest' },
    { 'weapon_pumpshotgun', 'Escopeta de corredera', true, 'back' }, { 'weapon_pumpshotgun_mk2', 'Escopeta de corredera Mk II', true, 'back' },
    { 'weapon_sawnoffshotgun', 'Escopeta recortada', true, 'back' }, { 'weapon_assaultshotgun', 'Escopeta de asalto', true, 'back' },
    { 'weapon_bullpupshotgun', 'Escopeta bullpup', true, 'back' }, { 'weapon_heavyshotgun', 'Escopeta pesada', true, 'back' },
    { 'weapon_dbshotgun', 'Escopeta de doble canon', true, 'back' }, { 'weapon_autoshotgun', 'Escopeta Sweeper', true, 'back' },
    { 'weapon_combatshotgun', 'Escopeta de combate', true, 'back' }, { 'weapon_musket', 'Mosquete', true, 'back' },
    { 'weapon_assaultrifle', 'Fusil de asalto', true, 'back' }, { 'weapon_assaultrifle_mk2', 'Fusil de asalto Mk II', true, 'back' },
    { 'weapon_carbinerifle', 'Carabina', true, 'back' }, { 'weapon_carbinerifle_mk2', 'Carabina Mk II', true, 'back' },
    { 'weapon_advancedrifle', 'Fusil avanzado', true, 'back' }, { 'weapon_specialcarbine', 'Carabina especial', true, 'back' },
    { 'weapon_specialcarbine_mk2', 'Carabina especial Mk II', true, 'back' }, { 'weapon_bullpuprifle', 'Fusil bullpup', true, 'back' },
    { 'weapon_bullpuprifle_mk2', 'Fusil bullpup Mk II', true, 'back' }, { 'weapon_compactrifle', 'Fusil compacto', true, 'back' },
    { 'weapon_militaryrifle', 'Fusil militar', true, 'back' }, { 'weapon_heavyrifle', 'Fusil pesado', true, 'back' },
    { 'weapon_mg', 'Ametralladora', true, 'back' }, { 'weapon_combatmg', 'Ametralladora de combate', true, 'back' },
    { 'weapon_combatmg_mk2', 'Ametralladora de combate Mk II', true, 'back' }, { 'weapon_gusenberg', 'Gusenberg', true, 'back' },
    { 'weapon_sniperrifle', 'Fusil de francotirador', true, 'back' }, { 'weapon_heavysniper', 'Francotirador pesado', true, 'back' },
    { 'weapon_heavysniper_mk2', 'Francotirador pesado Mk II', true, 'back' }, { 'weapon_marksmanrifle', 'Fusil de tirador', true, 'back' },
    { 'weapon_marksmanrifle_mk2', 'Fusil de tirador Mk II', true, 'back' }, { 'weapon_precisionrifle', 'Fusil de precision', true, 'back' },
    { 'weapon_rpg', 'Lanzacohetes', true, 'back' }, { 'weapon_grenadelauncher', 'Lanzagranadas', true, 'back' },
    { 'weapon_minigun', 'Minigun', true, 'back' }, { 'weapon_compactlauncher', 'Lanzagranadas compacto', true, 'back' },
    { 'weapon_hominglauncher', 'Lanzamisiles guiado', true, 'back' }, { 'weapon_firework', 'Lanzafuegos artificiales', true, 'back' },
    -- Arrojadizas
    { 'weapon_grenade', 'Granada', true, 'chest' }, { 'weapon_stickybomb', 'Bomba lapa', true, 'chest' },
    { 'weapon_pipebomb', 'Bomba casera', true, 'chest' }, { 'weapon_proxmine', 'Mina de proximidad', true, 'chest' },
    { 'weapon_bzgas', 'Gas BZ', true, 'chest' }, { 'weapon_smokegrenade', 'Gas lacrimogeno', true, 'chest' },
    { 'weapon_molotov', 'Coctel molotov', false, 'chest' }, { 'weapon_flare', 'Bengala', false, 'chest' },
    { 'weapon_petrolcan', 'Bidon de gasolina', true, 'rightArm' }
}
OSSecurity.Weapons.Zones = { 'chest', 'back', 'waist', 'leftArm', 'rightArm', 'leftLeg', 'rightLeg', 'ankles' }
OSSecurity.Weapons.List = {}
for _, entry in ipairs(list) do
    OSSecurity.Weapons.List[entry[1]] = { label = entry[2], metal = entry[3], zone = entry[4] }
end
