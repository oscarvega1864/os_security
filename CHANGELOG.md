# Changelog

## 0.2.0 — Device Core

- Registro exclusivamente en servidor con IDs persistentes y consultas paginadas.
- Catálogo central de siete tipos y validación extensible de metadatos.
- Máquina de estados con historial, retirada irreversible y límites explícitos.
- JSON con snapshots alternos, validación de carga, comprobación de escritura
  y bloqueo ante corrupción, errores de IO o cambios externos.
- Interfaz de almacenamiento preparada para un adaptador futuro, sin MySQL.
- Permiso ACE `ossecurity.admin`, autorización por operación y límites por jugador.
- Comando `osdev` con `list`, `create`, `info`, `state` y `remove`.
- Contratos separados para instalación, componentes, salud y mantenimiento;
  sin simulación, reparaciones ni sustituciones funcionales.
- Pruebas automatizadas en Lua 5.4 y documentación de validación real pendiente.
- Conservados `/oshello`, `osstatus` y los registros `[OS SECURITY]`.

## 0.1.0 — Recurso base

- Manifiesto `cerulean`/`gta5`, configuración y separación cliente/servidor.
- Comandos de diagnóstico y registros de inicio y detención.
