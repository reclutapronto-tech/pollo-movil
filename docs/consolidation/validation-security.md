# Estabilización Hito 1 — pruebas y seguridad — 2026-10-23

## Resultado de la estabilización local

| Validación | Resultado real | Alcance |
|---|---|---|
| TypeScript (`tsc --noEmit --incremental false`) | **PASS** | Repetido tras ajustar la configuración E2E en `apps/fieldops_web`. |
| Next.js production build | **PASS** | Next 15.5.28; compiló, verificó tipos y generó 36 páginas. Next informa “Skipping linting”, por eso no cuenta como lint. |
| Playwright auth + consola | **7 PASS, 2 SKIP, 0 FAIL** | Nueve escenarios; se corrieron otra vez contra el build recién generado. Cuatro escenarios de login/recuperación que antes quedaban en `Loading…` pasan. Los dos skips requieren credenciales E2E autorizadas. No valida un login real ni una recuperación exitosa por correo. |
| ESLint | **BLOCKED (entorno local)** | El lockfile fija `eslint-plugin-react-hooks@5.2.0`, requerido por `eslint-config-next`, pero el paquete no está en el `node_modules` local. `npm` no está disponible en PATH; no se cambió el lockfile ni se instaló con otro gestor que pudiera reinterpretarlo. |
| pgTAP Supabase local | **49 PASS en verificación anterior; no repetido en esta corrección** | 22 consola, 19 licencias/RLS y 8 operaciones. El ajuste solo afecta el servidor Playwright; no modifica esquema, políticas ni lógica de backend. El resultado previo se obtuvo con pruebas transaccionales `BEGIN`/`ROLLBACK`; no se hizo reset ni se persistieron fixtures en esta tarea. |
| `flutter test`, Android/iOS local | **NOT RUN** | Flutter y Dart no están disponibles en PATH ni se encontró SDK en las rutas verificadas. Los 14 cambios Flutter preexistentes no se incluyeron en la corrección. |
| CI GitHub | **PASS en commit antiguo; no ejecutado para este candidato** | Android, iOS, Web, Supabase, Timefold e Integración/seguridad pasan en `69c4240`; no cubren esta configuración E2E ni los commits posteriores. |

## Causa raíz y corrección

Las cuatro pruebas E2E fallidas no demostraban un fallo de Supabase Auth. Los registros locales mostraron que `next dev` estaba compilando las rutas de login y recuperación bajo demanda (aprox. 14–20 s en frío) mientras Playwright ejecutaba cuatro workers en paralelo y sus aserciones esperaban la interfaz. El navegador terminaba mostrando los formularios al calentarse la ruta; no se observó un error de consola persistente ni un fallo de red de Auth que explicara el estado inicial. Auth local respondió HTTP 200 en sus endpoints de salud/configuración. No se emplearon credenciales reales.

También existía riesgo de que Playwright reutilizara cualquier proceso que respondiera en `127.0.0.1:3000` (incluido Grafana). En el commit de código `7196eba121f8daf98a805a38612326c679e83d6e`, `playwright.config.ts` pasó a arrancar `next start` sobre el build ya generado, por defecto en `127.0.0.1:4318` (configurable con `PLAYWRIGHT_PORT` o `PLAYWRIGHT_BASE_URL`), y a no reutilizar un servidor existente. El workflow Web ya ejecuta `npm run build` antes de Playwright, así que el cambio mantiene ese orden y evita aumentar timeouts o falsear resultados.

Playwright conserva `trace: on-first-retry`; como la repetición final tuvo cero fallos y los reintentos locales están en cero, no se generó una traza de fallo nueva. El diagnóstico previo se basó en los logs de compilación/servidor, respuestas HTTP, eventos de consola/red y la comparación del comportamiento frío y del build de producción. Los warnings de color/Sentry observados no bloquearon las pruebas.

## Alcance no verificado

Los casos de link caducado, código PKCE inválido y sesión implícita expirada prueban rechazos seguros; no se completó una recuperación real con un enlace vigente ni se confirmó sesión de propietario. Los dos escenarios autenticados permanecen omitidos por falta de credenciales E2E de prueba autorizadas. La prueba no cambió cuentas, contraseñas, usuarios ni datos reales.

La comprobación HTTP de Auth local devolvió 200. Esto es salud de servicio, no verificación de login. Docker mostró Postgres/Auth/Realtime/Storage locales en ejecución; Vector está reiniciando. No se comprobó una asignación real Timefold en Staging.

El workflow Web revisado construye con `NEXT_PUBLIC_SUPABASE_URL=http://127.0.0.1:54321` y una clave publicable de placeholder. Ese workflow verifica compilación/UI, no una autenticación real contra Supabase; la integración backend corre en un workflow independiente. Por ello, su estado verde en `69c4240` no contradice el bundle Vercel previamente reportado sin variables.

## Seguridad observada

- El proyecto Supabase Staging informó a los advisors: 102 observaciones INFO `RLS Enabled No Policy` (particiones/relaciones con RLS sin política, por defecto denegadas para esos roles); 1 WARN de `search_path` mutable; 8 funciones SECURITY DEFINER ejecutables por `anon`; 10 ejecutables por `authenticated`; 1 WARN de protección de contraseñas filtradas deshabilitada. No se verificó que esos avisos sean explotables ni se corrigieron en este Hito; los permisos exactos y el uso de cada función requieren revisión antes de producción.
- Las pruebas pgTAP locales ejercitan superadmin sin membresía, separación corporativa, aislamiento entre empresas, manager por sucursal y bloqueo de capacidad excedida.
- `.env.local` está ignorado y no rastreado; contiene configuración local y material sensible (no se muestran valores). `.env.example` y ejemplos versionados son plantillas. Gitleaks no está instalado, por lo que no se afirma que se haya completado un scan de secretos en todo el historial.
- `LICENSE` y `THIRD_PARTY_NOTICES.md` conservan la atribución MIT de FieldOps AI y declaran Timefold Community bajo Apache 2.0. No se generó un SBOM ni se completó la licencia paquete por paquete; hacerlo es requisito antes de una nueva redistribución.
- Auth del usuario propietario está verificado en la fila de rol de Staging, pero no su sesión ni acceso desde Vercel. El error anterior de recovery tiene dos capas documentadas: link `otp_expired` y bundle web reportado sin una o ambas variables públicas Supabase; el acceso Vercel impidió verificar el entorno actual.
- No se verificó la configuración Supabase Auth `Site URL`/redirects ni las variables de Vercel; no publicar hasta confirmar ambos.
