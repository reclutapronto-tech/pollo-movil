# Respaldo y recuperación del Hito 0

## Respaldo comprobado

Directorio local: `D:\Projects\pollo-movil-backups\hito0-20261023`

- `pollo-movil-all-refs.bundle`: bundle con 13 refs locales/remotas y commit actual `9151800`. `git bundle verify` confirmó historial completo. SHA-256: `F7B3363830BF8874DB00992F2A44A63A2C50C5ED108BC657E964D63F682FCF74`.
- `flutter-working-tree-overlay.zip`: copia de los 14 archivos Flutter rastreados modificados; ZIP probado y con 14 archivos más entradas de directorio. SHA-256: `E1081956682DCE00034D52CB8AA24DDBF9448D3719A9A967D4B09F0CF9715FE8`.

## Contenido excluido y preservado

No se archivaron `.env.local`, tokens, claves, el keystore Android, caches `.dart-pub-cache`/`.gradle-home`/`.android-user-home` ni la memoria local `.swarm`; todos permanecieron en el checkout sin cambios. Las carpetas de caché son regenerables; `.swarm` y los datos de Android permanecen en su ruta original. El bundle guarda historia Git, incluida la historia upstream, pero no se publicó.

## Restaurar sin sobrescribir el checkout actual

1. Verificar el bundle antes de restaurar:

   ```powershell
   git bundle verify D:\Projects\pollo-movil-backups\hito0-20261023\pollo-movil-all-refs.bundle
   ```

2. Clonar el bundle a un directorio nuevo vacío, no encima del proyecto actual:

   ```powershell
   git clone D:\Projects\pollo-movil-backups\hito0-20261023\pollo-movil-all-refs.bundle D:\Projects\pollo-movil-recovered
   ```

3. Para recuperar cambios Flutter, extraer `flutter-working-tree-overlay.zip` a una carpeta temporal y revisar la lista/hash antes de copiar los archivos necesarios. Nunca copiar `*.env`, keystores o archivos locales sensibles desde otro respaldo.

El backup no altera ni sustituye los datos activos, servicios Docker o archivos locales del proyecto.
