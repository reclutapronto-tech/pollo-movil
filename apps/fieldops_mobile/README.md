# Pollo Móvil

Aplicación móvil Flutter para Android y iPhone. En computadora, el panel operativo se usa desde la web de Next.js en `apps/fieldops_web`; no es una aplicación de escritorio separada.

## Desarrollo local en Windows

Desde la raíz `D:\Projects\pollo-movil`, inicia los servicios locales:

```powershell
.\scripts\start-pollo-movil-local.ps1
```

Después, para Android Emulator:

```powershell
Set-Location D:\Projects\pollo-movil\apps\fieldops_mobile
flutter run --dart-define-from-file=env/local.json
```

El archivo local usa la dirección del host accesible desde Android Emulator. Para un teléfono físico, configura un archivo local ignorado por Git con una URL de Supabase alcanzable desde ese dispositivo.

## iPhone

La compilación y ejecución nativa de iOS requieren macOS y Xcode. En un simulador iOS:

```bash
cd apps/fieldops_mobile
flutter run --dart-define-from-file=env/local-ios.json
```

Para un iPhone físico, configura una URL de Supabase accesible desde la red del teléfono.

## Panel web en computadora

```powershell
Set-Location D:\Projects\pollo-movil\apps\fieldops_web
npm run dev
```

Las configuraciones `env/local*.json` son locales y no deben incluirse en commits. No agregues claves de producción al código ni a archivos versionados. El GPS y el checador son opcionales por sucursal; cuando GPS está activado, se consulta solo al marcar entrada o salida.
