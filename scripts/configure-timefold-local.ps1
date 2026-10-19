$ErrorActionPreference = 'Stop'

$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$timefoldEnv = Join-Path $projectRoot 'infra\timefold\.env'
$functionsEnv = Join-Path $projectRoot 'infra\supabase\functions\.env'
$expectedUrl = 'http://timefold:8080/api/assignments/solve'

if (-not (Test-Path -LiteralPath $functionsEnv -PathType Leaf)) {
  throw 'No se encontró infra/supabase/functions/.env. Inicia y configura Supabase local antes de vincular Timefold.'
}

function Read-LocalEnvValue([string]$Path, [string]$Name) {
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return '' }
  $pattern = '^\s*' + [regex]::Escape($Name) + '\s*=(.*)$'
  $matches = @([regex]::Matches([System.IO.File]::ReadAllText($Path), $pattern, [System.Text.RegularExpressions.RegexOptions]::Multiline))
  if ($matches.Count -gt 1) { throw "La variable $Name está duplicada en un archivo local; no se modificó ningún archivo." }
  if ($matches.Count -eq 0) { return '' }
  return $matches[0].Groups[1].Value.Trim()
}

function Set-LocalEnvValue([string]$Path, [string]$Name, [string]$Value) {
  $lines = [System.Collections.Generic.List[string]]::new()
  if (Test-Path -LiteralPath $Path -PathType Leaf) {
    foreach ($line in [System.IO.File]::ReadAllLines($Path)) { $lines.Add($line) }
  }
  $pattern = '^\s*' + [regex]::Escape($Name) + '\s*='
  $indices = @()
  for ($index = 0; $index -lt $lines.Count; $index++) {
    if ([regex]::IsMatch($lines[$index], $pattern)) { $indices += $index }
  }
  if ($indices.Count -gt 1) { throw "La variable $Name está duplicada; no se modificó ningún archivo." }
  if ($indices.Count -eq 1) {
    $lines[$indices[0]] = "$Name=$Value"
  } else {
    $lines.Add("$Name=$Value")
  }
  [System.IO.File]::WriteAllLines($Path, $lines.ToArray(), [System.Text.UTF8Encoding]::new($false))
}

$configuredUrl = Read-LocalEnvValue $functionsEnv 'TIMEFOLD_SERVICE_URL'
if ($configuredUrl -and $configuredUrl -ne $expectedUrl) {
  throw 'TIMEFOLD_SERVICE_URL ya apunta a otra dirección. No se modificó ningún archivo.'
}

$sidecarToken = Read-LocalEnvValue $timefoldEnv 'TIMEFOLD_API_TOKEN'
$functionToken = Read-LocalEnvValue $functionsEnv 'TIMEFOLD_SERVICE_TOKEN'
if ($sidecarToken -and $functionToken -and $sidecarToken -cne $functionToken) {
  throw 'Los tokens locales de Timefold y restaurant_ops no coinciden. No se modificó ningún archivo.'
}

$token = if ($sidecarToken) { $sidecarToken } elseif ($functionToken) { $functionToken } else { '' }
if (-not $token) {
  $randomBytes = New-Object byte[] 32
  $generator = [System.Security.Cryptography.RandomNumberGenerator]::Create()
  try {
    $generator.GetBytes($randomBytes)
    $token = [Convert]::ToBase64String($randomBytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
  } finally {
    $generator.Dispose()
    [Array]::Clear($randomBytes, 0, $randomBytes.Length)
  }
}

$timefoldOriginal = if (Test-Path -LiteralPath $timefoldEnv -PathType Leaf) { [System.IO.File]::ReadAllText($timefoldEnv) } else { $null }
$functionsOriginal = [System.IO.File]::ReadAllText($functionsEnv)
try {
  Set-LocalEnvValue $timefoldEnv 'TIMEFOLD_API_TOKEN' $token
  Set-LocalEnvValue $functionsEnv 'TIMEFOLD_SERVICE_TOKEN' $token
  Set-LocalEnvValue $functionsEnv 'TIMEFOLD_SERVICE_URL' $expectedUrl
} catch {
  if ($null -eq $timefoldOriginal) {
    if (Test-Path -LiteralPath $timefoldEnv -PathType Leaf) { Remove-Item -LiteralPath $timefoldEnv -Force }
  } else {
    [System.IO.File]::WriteAllText($timefoldEnv, $timefoldOriginal)
  }
  [System.IO.File]::WriteAllText($functionsEnv, $functionsOriginal)
  throw
}

Write-Output 'Timefold quedó configurado localmente. El token se guardó en archivos ignorados y no se mostró.'
Write-Output 'Reinicia Supabase local y levanta infra/timefold/compose.yaml para aplicar los cambios.'
