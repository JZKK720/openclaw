[CmdletBinding()]
param(
  [string]$ImageTag,
  [switch]$SkipPull,
  [switch]$SkipRestart,
  [switch]$NoHealthCheck
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
$envPath = Join-Path $repoRoot ".env"

function Get-DotEnvMap {
  param([string]$Path)

  $result = @{}
  if (-not (Test-Path -LiteralPath $Path)) {
    return $result
  }

  foreach ($line in [System.IO.File]::ReadAllLines($Path)) {
    if ([string]::IsNullOrWhiteSpace($line) -or $line.TrimStart().StartsWith("#")) {
      continue
    }

    $parts = $line.Split("=", 2)
    if ($parts.Count -eq 2) {
      $result[$parts[0]] = $parts[1]
    }
  }

  return $result
}

function Set-DotEnvValue {
  param(
    [string]$Path,
    [string]$Key,
    [string]$Value
  )

  $lines = if (Test-Path -LiteralPath $Path) {
    [System.IO.File]::ReadAllLines($Path)
  } else {
    @()
  }

  $prefix = "$Key="
  $updated = $false
  for ($index = 0; $index -lt $lines.Length; $index++) {
    if ($lines[$index].StartsWith($prefix)) {
      $lines[$index] = "$prefix$Value"
      $updated = $true
      break
    }
  }

  if (-not $updated) {
    $lines += "$prefix$Value"
  }

  [System.IO.File]::WriteAllLines($Path, $lines)
}

function Invoke-Compose {
  param([string[]]$ComposeArgs)

  & docker compose @ComposeArgs
  if ($LASTEXITCODE -ne 0) {
    throw "docker compose $($ComposeArgs -join ' ') failed with exit code $LASTEXITCODE"
  }
}

$envValues = Get-DotEnvMap -Path $envPath
$currentImage = $envValues["OPENCLAW_IMAGE"]
if ([string]::IsNullOrWhiteSpace($currentImage)) {
  $currentImage = "ghcr.io/openclaw/openclaw:2026.5.4"
  Set-DotEnvValue -Path $envPath -Key "OPENCLAW_IMAGE" -Value $currentImage
}

$desiredImage = if ([string]::IsNullOrWhiteSpace($ImageTag)) {
  $currentImage
} else {
  "ghcr.io/openclaw/openclaw:$ImageTag"
}

if ($desiredImage -ne $currentImage) {
  Set-DotEnvValue -Path $envPath -Key "OPENCLAW_IMAGE" -Value $desiredImage
  $currentImage = $desiredImage
  Write-Host "Pinned OPENCLAW_IMAGE to $currentImage"
}

$gatewayPort = 18789
if ($envValues.ContainsKey("OPENCLAW_GATEWAY_PORT")) {
  $gatewayPort = [int]$envValues["OPENCLAW_GATEWAY_PORT"]
}

Push-Location $repoRoot
try {
  if (-not $SkipPull) {
    Invoke-Compose -ComposeArgs @("pull", "openclaw-gateway", "openclaw-cli")
  }

  if (-not $SkipRestart) {
    Invoke-Compose -ComposeArgs @("up", "-d", "--no-build", "openclaw-gateway")
  }

  if (-not $NoHealthCheck) {
    $healthUrl = "http://127.0.0.1:$gatewayPort/healthz"
    $deadline = (Get-Date).AddMinutes(2)
    $healthy = $false

    do {
      try {
        $response = Invoke-WebRequest -UseBasicParsing $healthUrl
        if ($response.StatusCode -eq 200) {
          $healthy = $true
          break
        }
      } catch {
      }

      Start-Sleep -Seconds 2
    } while ((Get-Date) -lt $deadline)

    if (-not $healthy) {
      throw "Gateway did not become healthy at $healthUrl"
    }

    Write-Host "Gateway healthy at $healthUrl"
  }

  Write-Host "OPENCLAW_IMAGE=$currentImage"
} finally {
  Pop-Location
}