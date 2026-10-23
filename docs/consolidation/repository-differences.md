# Diferencias entre repositorios

## Refs comprobadas

| Ubicación | `main` | `pollo-movil` | Observación |
|---|---|---|---|
| ReclutaPronto (`pollo-destination`) | `6c790dc` | `21894cd` | Repo principal aprobado; ambas refs remotas se consultaron directamente. |
| Servicios Digitales MX (`pollo-github`) | `6c790dc` | `69c4240` | Espejo actual; conserva avances que faltaban en el remoto de ReclutaPronto. |
| Checkout local | `main`=`02f8669` | `pollo-movil`=`9151800` | Rama de trabajo sigue a `pollo-destination/pollo-movil`, +6 commits; `main` local pertenece a la historia upstream de FieldOps AI, no usarla para publicar Pollo Móvil. |
| Upstream FieldOps AI (`origin`) | `02f8669` | No usar como destino | Solo upstream de referencia. No publicar ahí. |

Los identificadores completos y conteos Git fueron obtenidos localmente el 2026-10-23. Los remotos pueden avanzar después del snapshot; volver a consultar heads antes de preparar una integración.

## Avances exclusivos detectados

Servicios Digitales MX tenía cuatro commits que no estaban en el branch remoto de ReclutaPronto, y los cuatro ya son ancestros de `HEAD` local:

- `e83b438` — licencias de sucursales y rol de plataforma.
- `3da1a9e` — añadió una ruta keep-alive de Render; el commit posterior `2c31b25` eliminó la ruta Vercel/cron. El árbol actual no contiene `src/app/api/cron/keep-alive/route.ts` y `vercel.json` no declara cron.
- `2c31b25` — reversión del cron de Vercel.
- `69c4240` — fixture CI de licencia para la prueba de operaciones.

El checkout local añade, después de `69c4240`:

- `59f0bcc` — flujo de recuperación de contraseña e invitaciones; todavía requiere validación con enlace vigente y sesión real.
- `9151800` — consola SaaS Fase 1, migración y pruebas; local-only en este snapshot.

Por tanto, ReclutaPronto remoto está 6 commits detrás del checkout local y Servicios Digitales MX está 2 commits detrás. No se detectaron commits exclusivos de los remotos objetivo que falten en el checkout local. Esto no es autorización para publicar.

## Árbol de trabajo

Hay **14 archivos Flutter rastreados modificados** (Gradle, localización y registrantes generados) y estos directorios/archivos no rastreados, que se dejaron intactos: `.android-user-home/`, `.dart-pub-cache/`, `.gradle-home/`, `.swarm/memory.db*`. `.env.local` existe, está ignorado por Git y no se incluyó en el backup. No se deben agrupar automáticamente las modificaciones Flutter con cambios web/SQL de Fase 1.

## Base de producto

Ambos remotos objetivo comparten `main` en `6c790dc`. El checkout local tiene también una rama `main` en la historia del upstream FieldOps AI (`02f8669`); esa rama no es base autorizada para la rama Pollo Móvil. La rama local `pollo-movil` sí se deriva de la base compartida `6c790dc`.
