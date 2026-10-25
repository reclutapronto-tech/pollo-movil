# Plan de consolidación Git y paridad unidireccional

## Fuente de verdad

`reclutapronto-tech/pollo-movil` es el principal. `serviciosdigitalesmx/pollo-movil` es un espejo de releases aprobados, no un segundo espacio de desarrollo. No se activó sincronización automática.

## Secuencia segura propuesta (todavía no ejecutada)

1. Actualizar solo refs con `git fetch` explícito de `pollo-destination` y `pollo-github`; revisar HEADs, ancestry y árbol sucio. Nunca usar `origin` como destino: localmente apunta a `seancheick/FieldOpsAi`.
2. Mantener Flutter WIP separado. Revisar los 14 archivos modificados y las carpetas locales; no staged/commit automático.
3. Hacer revisión final de licencias, dependencias, workflows y secretos de los commits de código. No incluir `.env.local`, tokens, `debug.keystore`, caches ni base `.swarm`.
4. Con autorización de publicación, actualizar la rama `pollo-movil` del principal con fast-forward ordinario desde `9151800` solo si el remoto sigue siendo ancestro. Si existe divergencia, parar y preparar integración/PR; nunca force push.
5. Mantener `main` sin cambios hasta revisión y merge separado autorizado. Crear/verificar los checks para el SHA exacto publicado; los checks de `69c4240` no validan `9151800`.
6. Solo tras SHA aprobado en principal, sincronizar el espejo en una operación unidireccional y fast-forward-only. Antes, exigir que el head del espejo sea ancestro del SHA principal; si tiene commits únicos, no moverlo: recuperar esos commits mediante integración revisada en el principal.

## Paridad del snapshot

Los dos `main` remotos comparten `6c790dc`; las ramas difieren en cuatro commits de Servicios Digitales MX, ya integrados en el checkout local. El local añade después `59f0bcc` y `9151800`. El branch principal remoto Recluta está en `21894cd`; el espejo está en `69c4240`. Esta diferencia es reparable con fast-forward desde la rama local actual si no hay cambios remotos nuevos, pero no se ejecutó ningún push.

## Destinos/remotos locales comprobados

- `origin` → upstream FieldOps AI; solo lectura/referencia.
- `pollo-destination` → principal ReclutaPronto.
- `pollo-github` → espejo Servicios Digitales MX.

No se renombraron ni alteraron remotos. Antes de publicar debe usarse destino explícito y revisar el resultado de `git remote -v` en esa sesión.
