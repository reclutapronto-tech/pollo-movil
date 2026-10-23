# Estado de pruebas y seguridad — 2026-10-23

## Pruebas ejecutadas en este snapshot

| Validación | Resultado real | Alcance |
|---|---|---|
| TypeScript (`tsc --noEmit --incremental false`) | **PASS** | Web local `apps/fieldops_web`. |
| Next.js production build | **PASS** | Next 15.5.28; compiló, verificó tipos y generó 36 páginas. Next informó “Skipping linting”, por eso no cuenta como lint. |
| Playwright auth + consola | **7 PASS, 2 SKIP** | Recuperación con link caducado, code inválido, sesión expirada, ruta sin sesión e invitación inválida. Se omitieron los dos escenarios que requieren credenciales E2E autorizadas. No valida acceso con sesión real ni recovery exitoso. |
| ESLint | **BLOCKED** | El árbol local no resuelve `eslint-plugin-react-hooks`, requerido por `eslint-config-next`. No se instaló ni se cambió lockfile. |
| pgTAP Supabase local | **49 PASS** | 22 consola, 19 licencias/RLS y 8 operaciones. El comando `supabase test db --local` falló antes de ejecutar tests porque el runner no resolvió hostname Docker `db`; las mismas tres pruebas, cada una con `BEGIN`/`ROLLBACK`, se ejecutaron por `psql` dentro del contenedor local existente y pasaron. No se hizo reset ni se persistieron fixtures. |
| `flutter test`, Android/iOS local | **NOT RUN** | Flutter y Dart no están disponibles en PATH ni se encontró SDK en las rutas verificadas. |
| CI GitHub | **PASS en commit antiguo** | Android, iOS, Web, Supabase, Timefold e Integración/seguridad pasan en `69c4240`; no cubren `59f0bcc` ni `9151800`. Links en esta tabla: [Android](https://github.com/serviciosdigitalesmx/pollo-movil/actions/runs/39617867451), [iOS](https://github.com/serviciosdigitalesmx/pollo-movil/actions/runs/39617867466), [Web](https://github.com/serviciosdigitalesmx/pollo-movil/actions/runs/39617867464), [Supabase](https://github.com/serviciosdigitalesmx/pollo-movil/actions/runs/39617867624), [Timefold](https://github.com/serviciosdigitalesmx/pollo-movil/actions/runs/39617867460), [Integración/seguridad](https://github.com/serviciosdigitalesmx/pollo-movil/actions/runs/39617867494). |

La comprobación HTTP de Auth local devolvió 200. Esto es salud de servicio, no verificación de login. Docker mostró Postgres/Auth/Realtime/Storage locales en ejecución; Vector está reiniciando. No se comprobó una asignación real Timefold en Staging.

El workflow Web revisado construye con `NEXT_PUBLIC_SUPABASE_URL=http://127.0.0.1:54321` y una clave publicable de placeholder. Ese workflow verifica compilación/UI, no una autenticación real contra Supabase; la integración backend corre en un workflow independiente. Por ello, su estado verde en `69c4240` no contradice el bundle Vercel previamente reportado sin variables.

## Seguridad observada

- El proyecto Supabase Staging informó a los advisors: 102 observaciones INFO `RLS Enabled No Policy` (particiones/relaciones con RLS sin política, por defecto denegadas para esos roles); 1 WARN de `search_path` mutable; 8 funciones SECURITY DEFINER ejecutables por `anon`; 10 ejecutables por `authenticated`; 1 WARN de protección de contraseñas filtradas deshabilitada. No se verificó que esos avisos sean explotables ni se corrigieron en este Hito; los permisos exactos y el uso de cada función requieren revisión antes de producción.
- Las pruebas pgTAP locales ejercitan superadmin sin membresía, separación corporativa, aislamiento entre empresas, manager por sucursal y bloqueo de capacidad excedida.
- `.env.local` está ignorado y no rastreado; contiene configuración local y material sensible (no se muestran valores). `.env.example` y ejemplos versionados son plantillas. Gitleaks no está instalado, por lo que no se afirma que se haya completado un scan de secretos en todo el historial.
- `LICENSE` y `THIRD_PARTY_NOTICES.md` conservan la atribución MIT de FieldOps AI y declaran Timefold Community bajo Apache 2.0. No se generó un SBOM ni se completó la licencia paquete por paquete; hacerlo es requisito antes de una nueva redistribución.
- Auth del usuario propietario está verificado en la fila de rol de Staging, pero no su sesión ni acceso desde Vercel. El error anterior de recovery tiene dos capas documentadas: link `otp_expired` y bundle web reportado sin una o ambas variables públicas Supabase; el acceso Vercel impidió verificar el entorno actual.
- No se verificó la configuración Supabase Auth `Site URL`/redirects ni las variables de Vercel; no publicar hasta confirmar ambos.
