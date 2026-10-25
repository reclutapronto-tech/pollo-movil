# Hito 0 — Consolidación de Pollo Móvil

Actualizado el **23 de octubre de 2026** tras estabilizar localmente las pruebas E2E de autenticación. No se publicó ni sincronizó código. El commit de código candidato de esta corrección es `7196eba121f8daf98a805a38612326c679e83d6e`; el commit documental separado registra los resultados. Distinguir la evidencia local de servicios remotos y de una sesión autenticada real.

## Decisión de fuente de verdad

- Principal aprobado: [`reclutapronto-tech/pollo-movil`](https://github.com/reclutapronto-tech/pollo-movil).
- Espejo: [`serviciosdigitalesmx/pollo-movil`](https://github.com/serviciosdigitalesmx/pollo-movil), sin desarrollo independiente.
- La comparación de ramas, commits recuperados y estrategia de paridad está en [repository-differences.md](repository-differences.md) y [git-consolidation-and-mirror.md](git-consolidation-and-mirror.md).

## Estado en una frase

El checkout `pollo-movil` conserva la consolidación del Hito 0 y añade un ajuste local de Playwright: usa el build de producción en un puerto dedicado para evitar que una instancia fría de Next dev o un servicio ajeno como Grafana afecten las pruebas. TypeScript, build Next y 7 de 9 E2E pasaron; dos E2E que requieren credenciales autorizadas se omitieron. ESLint sigue bloqueado por una dependencia ausente del `node_modules` local. El HEAD remoto Recluta (`21894cde`) fue consultado y es ancestro del candidato; el historial local sigue siendo fast-forward. No hubo push, despliegue ni cambios de Supabase remoto. El estado completo y los límites están en [validation-security.md](validation-security.md).

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
