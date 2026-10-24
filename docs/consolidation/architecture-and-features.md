# Arquitectura e inventario funcional

## Mapa de componentes

```text
Flutter (`apps/fieldops_mobile`)
   ├─ Auth y sesión; UI móvil operativa
   ├─ repositorio `restaurant_ops` y SQLite/Drift local
   └─ cola/sincronización offline → Supabase Edge Functions

Next.js (`apps/fieldops_web`)
   ├─ panel operativo heredado de FieldOps
   ├─ rutas de restaurante / calendario / inspecciones
   └─ `/platform` para administración SaaS, detrás de Auth/rol

Next.js (`apps/fieldops_admin`, app separada y heredada)
   └─ `/companies`, `/admins`, `/claim`; reutiliza `platform_admin`

Supabase (`infra/supabase`)
   ├─ PostgreSQL, 76 migraciones locales y políticas RLS
   ├─ `restaurant_ops`, `platform_admin`, `invites` y funciones compartidas
   └─ Auth, Storage y Realtime

Asignación: `restaurant_ops` → cliente Timefold Java/Quarkus opcional
            → valida resultado → fallback TypeScript explícito si no disponible
```

El cliente Edge Function sigue siendo autoritativo para validar/persistir asignaciones; el sidecar no debe escribir directamente en Supabase. El fallback local existe en código y debe quedar identificable en logs. El contenedor Docker local `pollo-movil-timefold` aparece encendido, pero en este snapshot no se verificó una asignación real ni salud HTTP desde el host.

## Código presente (no equivale a aceptación de producción)

- **Operación restaurante:** sucursales, áreas/puestos, personal/roles, tareas, asignación/rotación, programación/calendario, turnos y coberturas, ausencias, inspecciones y botes, incidencias, relevos, evidencia, notificaciones y recuperación de sincronización.
- **Asistencia:** configuración por sucursal. GPS y checador opcionales/desactivados por defecto; el código y las reglas del producto prohíben seguimiento continuo.
- **Administración SaaS:** `/platform`, invitaciones corporativas, licencias por sucursal, historial/auditoría y modelo de roles de plataforma/corporativo/gerente. La Fase 1 está en `9151800` local, no en los heads remotos consultados; su migración aún no está en Staging.
- **Duplicación que requiere decisión antes de refactorizar:** `apps/fieldops_admin` es una app Next.js independiente con administración de empresas, admins e invitaciones/claim, y también invoca la Edge Function `platform_admin`. `/platform` en `apps/fieldops_web` cubre clientes e invitaciones y añade sucursales/licencias/auditoría. Existe solapamiento de dominio y endpoints, pero no se verificó paridad funcional suficiente para eliminar una app. No se retiró ninguna. Las workflows web consultadas construyen `apps/fieldops_web`; no se confirmó despliegue activo de `fieldops_admin`.
- `apps/pollo_movil_admin` solo tiene `node_modules` ignorado y directorios `src` sin contenido de producto visible; no hay `package.json` ni archivos versionados. Se conservó intacto y no se considera una app ejecutable.
- **Autenticación:** guard de rutas, restablecimiento de contraseña, invitaciones y callback Supabase para code/fragments. Las pruebas actuales verifican enlaces caducados/invalidos; no una recuperación completa con correo real.
- **Timefold:** servicio Java basado en Community Edition, reglas de elegibilidad/capacidad, balanceo y rotación; el planificador TypeScript permanece como fallback.

## Decisiones de alcance vigentes

- Producto llamado Pollo Móvil, independiente del PMS/CMS de hotel.
- Datos, empleados, turnos y actividades oficiales deben venir del cliente; no crear datos comerciales de Madero hasta recibirlos y autorizar el alta.
- No incluye POS, caja, propinas ni radar de mesas.
- Las reglas comerciales están en `platform_license_terms`; Staging tiene términos configurados, pero no compañías ni licencias activas.
- Los documentos PRD/arquitectura heredados describen FieldOps AI y contienen requisitos de otro producto (por ejemplo, rastreo/mapa continuo). No deben imponerse sobre las reglas específicas de Pollo Móvil.

## Componentes aún no verificados end-to-end

Acceso real del propietario a `/platform`; recuperación válida desde email; sincronización de una tarea entre web y teléfono; despliegue/llamada autenticada de Timefold desde Edge Function; observabilidad del fallback en Staging; autenticación/redirect URLs cloud; Android/iOS en el estado actual `9151800`; aislamiento contra datos de una organización real. El diseño y las pruebas locales no sustituyen esas verificaciones.
