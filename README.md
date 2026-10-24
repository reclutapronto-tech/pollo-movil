# Pollo Móvil

Pollo Móvil es un producto independiente para coordinar la operación diaria de restaurantes. Este repositorio no pertenece al CMS del hotel ni comparte su aplicación.

## Plataformas

- **Android y iPhone:** una aplicación Flutter compartida.
- **Web:** panel operativo Next.js para administrar sucursales y consultar la operación desde un navegador de computadora.
- **Escritorio nativo:** no hay un instalador de escritorio separado; en computadora se usa el panel web.

## Operación incluida

- Sucursales, zonas, puestos, empleados y permisos por rol.
- Actividades configurables, programación, asignación y rotación equilibrada.
- Turnos, solicitudes de cobertura y ausencias.
- Incidencias, inspecciones, entrega y recepción de turno.
- Notificaciones, sincronización móvil sin conexión y actualizaciones en tiempo real.
- Checador y GPS opcionales por sucursal; ambos están apagados por defecto. Si una sucursal habilita GPS, se consulta únicamente al registrar entrada o salida; no hay rastreo continuo.

No incluye punto de venta, caja, propinas ni radar de mesas. Las actividades, horarios y empleados deben configurarse con información real del restaurante.

## Componentes

```text
apps/fieldops_mobile/   Aplicación Flutter Android/iOS
apps/fieldops_web/      Panel Next.js
infra/supabase/         Configuración local, migraciones y Edge Functions
infra/timefold/         Servicio opcional de optimización de asignaciones
scripts/                Inicio y configuración del entorno local
```

El asignador local sigue funcionando sin el servicio opcional de Timefold. Ninguna credencial privada debe guardarse en archivos versionados ni exponerse en aplicaciones cliente.

## Desarrollo local en Windows

Requisitos: Docker Desktop, Supabase CLI, Node.js y Flutter para ejecutar la app móvil. La configuración local existente está en `infra/supabase`.

Desde `D:\Projects\pollo-movil`:

```powershell
.\scripts\start-pollo-movil-local.ps1
.\scripts\run-pollo-movil-local.ps1 -App web
```

Para Android, conecta un dispositivo o inicia un emulador y ejecuta:

```powershell
.\scripts\run-pollo-movil-local.ps1 -App android
```

El panel web se sirve localmente en `http://localhost:3000`. Las URLs y claves publicables locales las obtiene el script desde Supabase CLI; no las copies al código fuente.

## iPhone

La compilación y ejecución nativa de iOS requieren macOS y Xcode. Configura un archivo local ignorado por Git con la URL de Supabase accesible desde el simulador o dispositivo y ejecuta Flutter desde `apps/fieldops_mobile`.

Consulta [la guía de la aplicación móvil](apps/fieldops_mobile/README.md) para detalles de configuración por dispositivo. No se hacen push ni despliegues desde este flujo local.
