$ErrorActionPreference = "Stop"

$infraPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\infra"))
$supabaseCommand = Get-Command "supabase.exe" -ErrorAction SilentlyContinue
$supabaseCliPath = if ($supabaseCommand) { $supabaseCommand.Source } else { $env:SUPABASE_CLI_PATH }
if (-not $supabaseCliPath -and (Test-Path "D:\Tools\supabase-cli\bin\supabase.exe")) {
  $supabaseCliPath = "D:\Tools\supabase-cli\bin\supabase.exe"
}
if (-not $supabaseCliPath -and (Test-Path "D:\Tools\Supabase\supabase.exe")) {
  $supabaseCliPath = "D:\Tools\Supabase\supabase.exe"
}

if (-not $supabaseCliPath -or -not (Test-Path $supabaseCliPath)) {
  throw "Supabase CLI no está disponible. Instálala desde el release oficial y vuelve a abrir PowerShell."
}

function Protect-SupabaseOutput([object[]]$Lines) {
  $Lines | ForEach-Object {
    [string]$_ -replace '(?i)(ANON_KEY|SERVICE_ROLE_KEY|SECRET_KEY|JWT_SECRET|PUBLISHABLE_KEY|S3_PROTOCOL_ACCESS_KEY_ID|S3_PROTOCOL_ACCESS_KEY_SECRET)(["=: ]+)[^, "}]+', '$1$2[redacted]'
  }
}

$startOutput = @(& $supabaseCliPath start --exclude vector --workdir $infraPath 2>&1)
$startExitCode = $LASTEXITCODE
if ($startExitCode -ne 0) {
  Protect-SupabaseOutput $startOutput | Write-Error
  exit $startExitCode
}

$statusOutput = @(& $supabaseCliPath status -o json --workdir $infraPath 2>&1)
$statusExitCode = $LASTEXITCODE
if ($statusExitCode -ne 0) {
  Protect-SupabaseOutput $statusOutput | Write-Error
  exit $statusExitCode
}

$statusText = (@($statusOutput | ForEach-Object { [string]$_ }) -join [Environment]::NewLine)
$jsonStart = $statusText.IndexOf("{")
if ($jsonStart -lt 0) {
  throw "Supabase inició, pero el CLI no devolvió su estado estructurado."
}
$status = $statusText.Substring($jsonStart) | ConvertFrom-Json
[pscustomobject]@{
  API       = $status.API_URL
  REST      = $status.REST_URL
  Database  = "127.0.0.1:54322"
  Functions = $status.FUNCTIONS_URL
  Studio    = $status.STUDIO_URL
  Mailpit   = $status.MAILPIT_URL
}
