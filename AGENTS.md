# Instrucciones para agentes — Pollo Móvil

- Este repositorio es el producto Pollo Móvil, independiente de `hotel-pms-mexico` y del CMS del hotel. No modificar el proyecto del hotel al trabajar aquí.
- Fuente de verdad aprobada por el propietario: `reclutapronto-tech/pollo-movil`. Espejo: `serviciosdigitalesmx/pollo-movil`. El upstream `seancheick/FieldOpsAi` es solo referencia; el remoto local `origin` apunta allí y nunca debe recibir un push.
- Antes de cualquier operación Git, verificar rama, HEAD, `git status` y remoto destino explícito. No hacer push, merge, despliegue, cambios de permisos, migraciones remotas ni cambios de datos persistentes sin autorización expresa para esa acción.
- Preservar los cambios Flutter preexistentes. No sobrescribir ni limpiar las modificaciones del árbol de trabajo, cachés locales, `.swarm` o `.android-user-home`. No versionar `.env.local`, tokens, llaves, keystores ni salidas de compilación.
- La configuración local de Supabase vive bajo `infra/supabase`; CLI desde el repo usa `--workdir infra`. No ejecutar `db reset` ni pruebas de integración con escrituras sobre bases existentes. Las pruebas pgTAP actuales usan transacciones y `ROLLBACK`.
- Políticas de producto: nombre exclusivo Pollo Móvil; GPS y checador por sucursal, opcionales y apagados por defecto; GPS solo al marcar entrada/salida, nunca rastreo continuo. No inventar empleados, actividades u horarios oficiales. No agregar POS, caja, propinas o radar de mesas.
- Mantener aislamiento multiempresa y RLS; el superadministrador de plataforma no es una membresía de cliente ni recibe acceso indiscriminado a datos de clientes. No exponer `service_role`, tokens de Timefold ni credenciales en clientes o logs.
- Las notas heredadas de FieldOps AI describen su producto upstream y no sustituyen las decisiones específicas de Pollo Móvil. Si existe conflicto, preservar la identidad y reglas de Pollo Móvil y documentar la discrepancia.
- Antes de publicar, verificar en la cuenta y servicio correctos; no asumir que una sesión MCP, CLI o Chrome comparte identidad/permisos con otra.

El snapshot comprobado y los bloqueos actuales están en [`docs/consolidation/README.md`](docs/consolidation/README.md).
