# Mapa de la tablet

La app **Mapa** de las tablets G6 muestra una imagen del mapa de GTA V con los dispositivos, órdenes, avisos y
vehículos encima. **La imagen no se incluye con os_security** (es material del juego): la pone cada servidor.

1. Copia la imagen en esta carpeta con uno de estos nombres: `gtav.webp`, `gtav.jpg` o `gtav.png`.
   Sirve cualquier mapa **cuadrado** de la isla completa (estilo atlas, satélite o carreteras). Recomendado: entre
   2048 y 4096 px de lado (más grande pesa más al descargar el recurso).
2. Reinicia el recurso (`refresh` y `restart os_security`, o reinicio completo).
3. Abre G6 Operations con un perfil de administrador → Mapa. Si los puntos no caen en su sitio, pulsa **Calibrar**:
   - Punto 1: haz clic en el mapa justo donde estás.
   - Aléjate más de 800 m en horizontal y en vertical (por ejemplo, de Los Santos a Sandy Shores).
   - Vuelve al mapa, pulsa **Calibrar: punto 2** y haz clic donde estás.

   La calibración se guarda en `data/map.json` y vale para todos los jugadores. **Calibración de fábrica** la deshace.

Los archivos de esta carpeta (salvo este LEEME) están en `.gitignore`: no se suben al repositorio ni a las releases.
