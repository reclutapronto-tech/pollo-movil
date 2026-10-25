param(
  [ValidateSet('web', 'android')]
  [string]$App = 'web',
  [string]$MobileSupabaseUrl,
  [string]$AndroidDeviceId
)

$ErrorActionPreference = 'Stop'

$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$infraPath = Join-Path $projectRoot 'infra'
$cliCommand = Get-Command 'supabase.exe' -ErrorAction SilentlyContinue
$cliPath = if ($cliCommand) { $cliCommand.Source } else { $env:SUPABASE_CLI_PATH }
if (-not $cliPath -and (Test-Path -LiteralPath 'D:\Tools\supabase-cli\bin\supabase.exe')) {
  $cliPath = 'D:\Tools\supabase-cli\bin\supabase.exe'
}
if (-not $cliPath -and (Test-Path -LiteralPath 'D:\Tools\Supabase\supabase.exe')) {
  $cliPath = 'D:\Tools\Supabase\supabase.exe'
}

if (-not (Test-Path -LiteralPath $cliPath)) {
  throw 'No se encontró Supabase CLI. Ejecuta primero scripts/start-pollo-movil-local.ps1.'
}

$statusLines = @(& $cliPath status -o json --workdir $infraPath 2>$null)
if ($LASTEXITCODE -ne 0) {
  throw 'Supabase local no está iniciado. Ejecuta scripts/start-pollo-movil-local.ps1.'
}

$statusText = (@($statusLines | ForEach-Object { [string]$_ }) -join [Environment]::NewLine)
$jsonStart = $statusText.IndexOf('{')
if ($jsonStart -lt 0) {
  throw 'Supabase CLI no devolvió su configuración local.'
}

$status = $statusText.Substring($jsonStart) | ConvertFrom-Json
$apiUrl = [string]$status.API_URL
$publishableKey = [string]$status.ANON_KEY
if (-not $publishableKey) { $publishableKey = [string]$status.PUBLISHABLE_KEY }
if (-not $apiUrl -or -not $publishableKey) {
  throw 'Supabase local no proporcionó URL y clave publicable.'
}

$apiUri = [Uri]$apiUrl
if ($apiUri.Scheme -ne 'http' -or $apiUri.Host -notin @('127.0.0.1', 'localhost', '::1')) {
  throw 'La URL devuelta por Supabase no es una dirección local; se canceló el arranque.'
}

if ($App -eq 'web') {
  $oldUrl = $env:NEXT_PUBLIC_SUPABASE_URL
  $oldKey = $env:NEXT_PUBLIC_SUPABASE_ANON_KEY
  try {
    $env:NEXT_PUBLIC_SUPABASE_URL = $apiUrl
    $env:NEXT_PUBLIC_SUPABASE_ANON_KEY = $publishableKey
    Push-Location (Join-Path $projectRoot 'apps\fieldops_web')
    try {
      $pnpmCommand = Get-Command 'pnpm.cmd' -ErrorAction SilentlyContinue
      $npmCommand = Get-Command 'npm.cmd' -ErrorAction SilentlyContinue
      $bundledPnpm = if ($env:USERPROFILE) {
        Join-Path $env:USERPROFILE '.cache\codex-runtimes\codex-primary-runtime\dependencies\bin\fallback\pnpm.cmd'
      }

      if ($pnpmCommand) {
        & $pnpmCommand.Source run dev
      } elseif ($npmCommand) {
        & $npmCommand.Source run dev
      } elseif ($bundledPnpm -and (Test-Path -LiteralPath $bundledPnpm)) {
        & $bundledPnpm run dev
      } else {
        throw 'No se encontró pnpm ni npm. Instala las dependencias de apps/fieldops_web antes de iniciar el panel.'
      }
      if ($LASTEXITCODE -ne 0) { throw "El panel Next.js terminó con código $LASTEXITCODE." }
    } finally {
      Pop-Location
    }
  } finally {
    if ($null -eq $oldUrl) { Remove-Item Env:NEXT_PUBLIC_SUPABASE_URL -ErrorAction SilentlyContinue }
    else { $env:NEXT_PUBLIC_SUPABASE_URL = $oldUrl }
    if ($null -eq $oldKey) { Remove-Item Env:NEXT_PUBLIC_SUPABASE_ANON_KEY -ErrorAction SilentlyContinue }
    else { $env:NEXT_PUBLIC_SUPABASE_ANON_KEY = $oldKey }
  }
  return
}

$mobileUrl = if ($MobileSupabaseUrl) { $MobileSupabaseUrl.TrimEnd('/') } else { 'http://10.0.2.2:54321' }
$mobileUri = [Uri]$mobileUrl
if ($mobileUri.Scheme -ne 'http' -or $mobileUri.Host -notin @('10.0.2.2', 'localhost')) {
  throw 'En desarrollo Android, la URL local debe usar 10.0.2.2 (emulador) o localhost (dispositivo con ADB reverse).'
}
if ($mobileUri.Host -eq 'localhost') {
  $adbCommand = Get-Command 'adb.exe' -ErrorAction SilentlyContinue
  if (-not $adbCommand) {
    throw 'Para un teléfono por USB se necesita Android Platform Tools (adb) para enlazar localhost con Supabase.'
  }
  $adbArguments = @()
  if ($AndroidDeviceId) { $adbArguments += @('-s', $AndroidDeviceId) }
  $adbArguments += @('reverse', 'tcp:54321', 'tcp:54321')
  & $adbCommand.Source @adbArguments
  if ($LASTEXITCODE -ne 0) {
    throw 'No se pudo crear ADB reverse. Confirma que el teléfono esté conectado y autorizado.'
  }
}

$oldPubCache = $env:PUB_CACHE
$pubCachePath = 'D:\Tools\PubCache'
$flutterCommand = Get-Command 'flutter' -ErrorAction SilentlyContinue
$flutterPath = if ($flutterCommand) { $flutterCommand.Source } else { 'D:\Tools\Flutter\flutter\bin\flutter.bat' }
if (-not (Test-Path -LiteralPath $flutterPath)) {
  throw 'No se encontró Flutter. Instálalo en D:\Tools\Flutter o agrega flutter a PATH.'
}
Push-Location (Join-Path $projectRoot 'apps\fieldops_mobile')
try {
  New-Item -ItemType Directory -Path $pubCachePath -Force | Out-Null
  $env:PUB_CACHE = $pubCachePath
  & $flutterPath pub get
  $pubGetExitCode = $LASTEXITCODE
  if ($pubGetExitCode -ne 0) {
    throw "Flutter no pudo preparar las dependencias (código $pubGetExitCode). En Windows, si el mensaje menciona enlaces simbólicos, habilita Modo desarrollador con 'start ms-settings:developers' y vuelve a ejecutar."
  }

  $dartDefines = @(
    "--dart-define=SUPABASE_URL=$mobileUrl",
    "--dart-define=SUPABASE_ANON_KEY=$publishableKey"
  )
  $firebaseConfig = @{}
  $firebaseConfigPath = Join-Path $projectRoot 'apps\fieldops_mobile\.env.firebase'
  if (Test-Path -LiteralPath $firebaseConfigPath) {
    foreach ($line in Get-Content -LiteralPath $firebaseConfigPath) {
      if ($line -match '^\s*([A-Z0-9_]+)\s*=\s*(.*?)\s*$' -and $Matches[1] -like 'FIREBASE_*') {
        $firebaseConfig[$Matches[1]] = $Matches[2].Trim('"').Trim("'")
      }
    }
  }
  foreach ($name in @(
    'FIREBASE_API_KEY',
    'FIREBASE_PROJECT_ID',
    'FIREBASE_MESSAGING_SENDER_ID',
    'FIREBASE_ANDROID_APP_ID',
    'FIREBASE_IOS_APP_ID',
    'FIREBASE_IOS_BUNDLE_ID'
  )) {
    $value = [Environment]::GetEnvironmentVariable($name)
    if (-not $value -and $firebaseConfig.ContainsKey($name)) {
      $value = $firebaseConfig[$name]
    }
    if ($value) { $dartDefines += "--dart-define=$name=$value" }
  }
  & $flutterPath run @dartDefines
  if ($LASTEXITCODE -ne 0) { throw "Flutter terminó con código $LASTEXITCODE." }
} finally {
  Pop-Location
  if ($null -eq $oldPubCache) { Remove-Item Env:PUB_CACHE -ErrorAction SilentlyContinue }
  else { $env:PUB_CACHE = $oldPubCache }
}
