-- Catalogo de piezas logicas. No son modelos GTA ni objetos fisicos.
OSSecurity.ComponentConfig = {
    IntervalSeconds = 60,
    MaxElapsedHours = 72,
    MaxSimulationHours = 24,
    RepairGain = 25,
    RepairCeiling = 90,
    AllowFailedRepair = false,
    InstallationQuality = 75,
    UsageIntensity = 1,
    EnvironmentFactor = 1,
    Definitions = {
        power_supply = { defaultModel = 'power_standard', models = { power_standard = { lifeHours = 5000, quality = 80 } } },
        optical_module = { defaultModel = 'optics_standard', models = { optics_standard = { lifeHours = 4000, quality = 80 } } },
        control_board = { defaultModel = 'board_standard', models = { board_standard = { lifeHours = 6000, quality = 85 } } },
        signal_sensor = { defaultModel = 'sensor_standard', models = { sensor_standard = { lifeHours = 3500, quality = 80 } } },
        lock_actuator = { defaultModel = 'actuator_standard', models = { actuator_standard = { lifeHours = 3000, quality = 80 } } },
        radio_module = { defaultModel = 'radio_standard', models = { radio_standard = { lifeHours = 4500, quality = 80 } } },
        storage_module = { defaultModel = 'storage_standard', models = { storage_standard = { lifeHours = 3500, quality = 80 } } },
        display_panel = { defaultModel = 'display_standard', models = { display_standard = { lifeHours = 5000, quality = 80 } } }
    },
    Compatibility = {
        cctv_camera = { power = 'power_supply', optics = 'optical_module' },
        alarm_panel = { power = 'power_supply', controller = 'control_board' },
        alarm_sensor = { power = 'power_supply', sensor = 'signal_sensor' },
        smart_lock = { power = 'power_supply', actuator = 'lock_actuator' },
        vehicle_tracker = { power = 'power_supply', radio = 'radio_module' },
        bodycam = { power = 'power_supply', optics = 'optical_module', storage = 'storage_module' },
        security_monitor = { power = 'power_supply', display = 'display_panel' }
    }
}
