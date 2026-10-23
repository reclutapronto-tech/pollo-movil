# Hito 0 — Consolidación de Pollo Móvil

Snapshot de solo lectura realizado el **23 de octubre de 2026**. No se publicó ni sincronizó código. Los documentos describen evidencia del checkout local, CLI/API disponibles y proyecto Supabase identificado; distinguen código presente de comportamiento operativo comprobado.

## Decisión de fuente de verdad

- Principal aprobado: [`reclutapronto-tech/pollo-movil`](https://github.com/reclutapronto-tech/pollo-movil).
- Espejo: [`serviciosdigitalesmx/pollo-movil`](https://github.com/serviciosdigitalesmx/pollo-movil), sin desarrollo independiente.
- La comparación de ramas, commits recuperados y estrategia de paridad está en [repository-differences.md](repository-differences.md) y [git-consolidation-and-mirror.md](git-consolidation-and-mirror.md).

## Estado en una frase

El checkout local `pollo-movil` en `9151800` contiene los cuatro commits que estaban únicamente en Servicios Digitales MX, dos commits locales posteriores y el código de Fase 1; los remotos todavía no los contienen. Hay una copia verificable de refs y cambios Flutter. Staging Supabase está activo, pero la migración de consola Fase 1 sigue pendiente allí; no se verificó sesión real del propietario ni despliegue Vercel Staging.

## Índice

- [Arquitectura e inventario funcional](architecture-and-features.md)
- [Repositorios, servicios y accesos](environments-and-access.md)
- [Pruebas y seguridad](validation-security.md)
- [Consolidación Git y política de espejo](git-consolidation-and-mirror.md)
- [Respaldo y recuperación](backup-recovery.md)
- [Memoria operativa compacta](operational-memory.md)

La auditoría encontró una app histórica independiente `apps/fieldops_admin` que se solapa parcialmente con `/platform` y usa la misma Edge Function `platform_admin`. Se documenta como decisión pendiente, no se borró ni consolidó en este Hito.

## Evidencia y límites

- El backup está en `D:\Projects\pollo-movil-backups\hito0-20261023`; el bundle pasó `git bundle verify` y el ZIP del overlay tiene SHA-256 registrado en [backup-recovery.md](backup-recovery.md).
- Se conservaron en su ubicación original los cambios no rastreados y cachés; no se copiaron secretos, `.env.local` ni el keystore Android al backup.
- No se cambiaron remotos, permisos, credenciales, roles, datos, migraciones, despliegues ni configuración de servicios.
- No se encontró una exportación de conversación en los lugares de exportación revisados; las decisiones de este snapshot se contrastaron con los documentos del repo y el estado de código. Los documentos heredados del PRD de FieldOps AI no se trataron como requisitos actuales de Pollo Móvil.
