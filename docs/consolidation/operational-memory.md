# Memoria operativa compacta

Snapshot: 2026-10-23; checkout `D:\Projects\pollo-movil`, branch `pollo-movil`, HEAD `9151800`.

- Fuente de verdad elegida: `reclutapronto-tech/pollo-movil`; espejo `serviciosdigitalesmx/pollo-movil`. No sincronizar automáticamente hasta autorización posterior.
- Local tiene seis commits sobre el branch Recluta remoto y dos sobre el mirror; recupera los cuatro commits que solo tenía el mirror. `origin` local apunta a upstream `seancheick/FieldOpsAi`: jamás push allí.
- 14 cambios Flutter rastreados conservados; además hay cachés, keystore local y `.swarm` no rastreados. No limpiar ni agrupar sin autorización.
- Vercel: CLI ausente; API ve equipo Servicios y devuelve 403 para Staging `sdmx2`. El proyecto Vercel accesible `pollo-movil` tiene despliegue Production en SHA `69c4240`; no confundir con Staging.
- Supabase: único Staging visible está bajo Servicios Digitales MX; proyecto healthy, 75 migraciones, Phase 1 local pendiente, Auth role `platform_superadmin` activo. No sesión real; sin compañía/sucursal/licencia.
- Render no verificado (CLI ausente). Docker local contiene Supabase y Timefold; Vector reinicia; el health HTTP de Timefold no respondió.
- Tests actuales: Next build y TypeScript pasan; Playwright 7 pasan/2 omitidas; lint bloqueado por paquete local ausente; pgTAP 49 pasan vía `docker exec` con rollback; Flutter local no disponible. Seis CI verdes solo para `69c4240`.
- No listo para Madero: faltan env/deploy Staging funcional, login real, migración de consola aplicada con aprobación y datos/horarios/licencia piloto autorizados.
- Próximo hito: revisar permisos/propiedad Recluta de Supabase, Vercel y Render; actualizar el mirror solo después de versionar/aprobar en el principal. No push, despliegue, migración ni alta Madero hasta autorización.
