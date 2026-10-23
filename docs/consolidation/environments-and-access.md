# Repositorios, entornos y acceso

## GitHub

- **Principal:** `reclutapronto-tech/pollo-movil` (público, default `main`). Con `gh auth switch` temporal, `gh api user` confirmó `reclutapronto-tech`; permisos efectivos: admin/push. Se restauró la cuenta activa de CLI a `serviciosdigitalesmx` al terminar.
- **Espejo:** `serviciosdigitalesmx/pollo-movil` (público, default `main`). La cuenta Servicios Digitales MX es admin/push; la cuenta ReclutaPronto solo tiene lectura. Sincronización no activada.
- `main` de ambos = `6c790dc`; rama de Recluta = `21894cd`, rama de Servicios = `69c4240`, checkout local `pollo-movil` = `9151800`.
- Últimos seis workflows consultados en GitHub fueron exitosos en `69c4240`, no en `9151800` (ver [validación](validation-security.md)).

## Vercel

- El proyecto de Staging esperado es `pollo-movil-staging`, team `sdmx2`, dominio `https://pollo-movil-staging.vercel.app`. La API devuelve **403**: falta autorización del scope `sdmx2`; la lista de equipos de esta conexión solo devuelve Servicios Digitales MX. No hay Vercel CLI instalable/en PATH en esta sesión y no se obtuvo acceso a sus variables/Git settings.
- Proyecto distinto visible en la cuenta de Servicios Digitales MX: `pollo-movil`, proyecto `prj_DrNx3NuFIY3dHwje6bgdQ3RImjGm`, dominio `https://pollo-movil.vercel.app`. Su despliegue más reciente consultado está `READY`, target `production`, desde `serviciosdigitalesmx/pollo-movil`, branch `pollo-movil`, SHA `69c4240`. No fue creado ni modificado en este Hito. Tratarlo como producción y no tocarlo sin autorización específica.
- No hay evidencia actual de que `sdmx2` o el proyecto Staging estén bajo ReclutaPronto, aunque ese es el entorno esperado.

## Supabase

- MCP enumera solo `serviciosdigitalesmx's Org` (`fgutlqdzqiftwhxhzbhm`). `pollo-movil-staging` (`pfhmzoknxprxyftpwlel`) está allí, `ACTIVE_HEALTHY`, us-east-1, PostgreSQL 17.11. No se encontró un proyecto Pollo Móvil bajo una cuenta/org ReclutaPronto con las herramientas disponibles.
- Supabase CLI 2.121.0 está presente, pero `supabase projects list` devuelve `projects: []`; no da acceso CLI verificable a ese proyecto. El Staging fue leído por el conector de Servicios Digitales MX, no por el CLI de Recluta.
- Las Edge Functions `restaurant_ops`, `platform_admin` e `invites` aparecen activas en el proyecto Staging; `restaurant_ops` tiene `verify_jwt=true`. La presencia/estado no prueba una solicitud autenticada de extremo a extremo.
- Staging tiene 75 migraciones aplicadas hasta `corporate_admin_branch_scope`; la migración de consola `20261023031508_platform_console_phase1` (presente local) está pendiente. No se aplicó.
- Usuario existente: registro `platform_superadmin` activo enlazado al ID de Auth correcto; no se probó una sesión real. Conteos Staging: 0 compañías, 0 sucursales, 0 membresías, 0 tareas, 0 turnos y 0 licencias por compañía; hay 1 fila de términos comerciales configurables.
- Configuración Auth Site URL/Redirect URLs no fue accesible por API/CLI en este Hito. La web local apunta a `http://127.0.0.1:54321`; no imprimir valores de claves ni tokens locales.

## Render y entorno local

- Render CLI no está disponible en PATH y no hay conector Render habilitado aquí; el workspace `Recluta's workspace` y el servicio remoto Timefold no pudieron verificarse.
- Docker local ejecuta Supabase y otros contenedores del PMS del hotel. No se apagó ni reinició ningún contenedor. Supabase Auth respondió HTTP 200; el contenedor `supabase_vector_pollo-movil` aparece `Restarting`. El contenedor Timefold aparece `Up`, pero el endpoint HTTP local probado no respondió.
- La documentación de Timefold indica host port `8088`, pero `infra/timefold/compose.yaml` publica `18088`; el contenedor tiene ese mapping, aunque `http://127.0.0.1:18088/q/health/ready` no respondió. No se cambió la configuración.
- En `.env.local` solo se inspeccionaron nombres de variables y se confirmó endpoint local; el archivo está ignorado. Nunca copiar su token OIDC ni claves al repo, informe o backup.
