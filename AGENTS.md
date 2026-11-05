# OS Security — Reglas de desarrollo

## Desarrollo

- Trabajar exclusivamente dentro del repositorio `os_security`.
- Mantener una arquitectura modular y código profesional.
- Respetar las funcionalidades existentes.
- No modificar archivos externos al repositorio.
- No incorporar dependencias innecesarias.
- Evitar código duplicado y soluciones provisionales sin documentar.

## Control de versiones automático

Al finalizar cada tarea de desarrollo:

1. Revisar `git status` y `git diff`.
2. Comprobar que los cambios pertenecen únicamente a la tarea actual.
3. Ejecutar las pruebas disponibles.
4. Si las pruebas pasan, crear automáticamente un commit.
5. Utilizar Conventional Commits.
6. No realizar commits si se detectan errores graves o pruebas fallidas.
7. No incluir claves, credenciales ni archivos sensibles.
8. No incluir modificaciones ajenas a la tarea.
9. No ejecutar `git push` automáticamente.
10. No realizar `git reset --hard`, `git clean -fd` ni otras operaciones destructivas.

## Formato de commits

- `feat(core): descripción`
- `feat(cctv): descripción`
- `feat(alarms): descripción`
- `feat(locks): descripción`
- `feat(bodycam): descripción`
- `feat(tracking): descripción`
- `fix(module): descripción`
- `refactor(module): descripción`
- `docs: descripción`
- `test(module): descripción`

Los mensajes deben describir cambios reales, no utilizar textos genéricos.

## Finalización

Después de cada commit, informar de:

- Archivos modificados.
- Funcionalidades implementadas.
- Pruebas ejecutadas y resultados.
- Hash del commit.
- Limitaciones o pruebas pendientes dentro de FiveM.

Las pruebas estáticas no equivalen a una validación real dentro de FiveM.

## Seguridad

Nunca incluir `server.cfg`, licencias de Cfx.re, tokens o contraseñas en los commits.

No modificar automáticamente el servidor de producción ni otros repositorios.
