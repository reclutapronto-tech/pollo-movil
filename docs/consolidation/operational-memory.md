# Memoria operativa compacta

Actualizado: 2026-10-23; checkout `D:\Projects\pollo-movil`, branch `pollo-movil`. Corrección E2E de código: `7196eba121f8daf98a805a38612326c679e83d6e`; el commit documental separado se crea después de este resumen.

- Fuente de verdad elegida: `reclutapronto-tech/pollo-movil`; espejo `serviciosdigitalesmx/pollo-movil`. No sincronizar automáticamente hasta autorización posterior.
- Recluta `pollo-movil` se reconsultó el 2026-10-23: remoto `21894cde97661f703cccd35dff708e9517271458`; es ancestro del candidato local. Había ocho commits locales antes del commit documental de estabilización (nueve después), por lo que la historia es fast-forward. El mirror no se modificó. `origin` local apunta a upstream `seancheick/FieldOpsAi`: jamás push allí.
- 14 cambios Flutter rastreados conservados; además hay cachés, keystore local y `.swarm` no rastreados. No limpiar ni agrupar sin autorización.
- Vercel: CLI ausente; API ve equipo Servicios y devuelve 403 para Staging `sdmx2`. El proyecto Vercel accesible `pollo-movil` tiene despliegue Production en SHA `69c4240`; no confundir con Staging.
- Supabase: único Staging visible está bajo Servicios Digitales MX; proyecto healthy, 75 migraciones, Phase 1 local pendiente, Auth role `platform_superadmin` activo. No sesión real; sin compañía/sucursal/licencia.
- Render no verificado (CLI ausente). Docker local contiene Supabase y Timefold; Vector reinicia; el health HTTP de Timefold no respondió.
- Estabilización Hito 1: TypeScript y Next build pasan; Playwright 7 pasan, 2 se omiten y 0 fallan usando `next start` en puerto dedicado, sin reusar Grafana/otro proceso. Causa de los cuatro Loading fue compilación fría de Next dev en paralelo, no un error confirmado de Supabase Auth. ESLint bloqueado porque el paquete fijado en el lockfile falta localmente y npm no está disponible. pgTAP 49 PASS son resultado anterior, no repetido en esta corrección. Flutter local no disponible. CI verde solo para `69c4240`.
- No listo para Madero: faltan env/deploy Staging funcional, login real, migración de consola aplicada con aprobación y datos/horarios/licencia piloto autorizados.
- Próximo hito: revisar permisos/propiedad Recluta de Supabase, Vercel y Render; actualizar el mirror solo después de versionar/aprobar en el principal. No push, despliegue, migración ni alta Madero hasta autorización.
