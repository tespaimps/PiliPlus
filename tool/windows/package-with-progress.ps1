param([ValidateRange(1, 2100000000)][int]$BuildNumber = 5658)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$logDir = Join-Path $PSScriptRoot 'build-logs'
$null = New-Item -ItemType Directory -Path $logDir -Force
$log = Join-Path $logDir ("android-" + (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + ".log")
$timer = [Diagnostics.Stopwatch]::StartNew()
$versionLine = Select-String -LiteralPath (Join-Path $root 'PiliPlus-main/pubspec.yaml') -Pattern '^version:\s*([^+\s]+)' | Select-Object -First 1
if (-not $versionLine) { throw 'Version missing in pubspec.yaml' }
$version = $versionLine.Matches[0].Groups[1].Value
$output = "PiliPlus-local-$version+$BuildNumber-dev-arm64-v8a.apk"

function Show-Stage([int]$step, [string]$label) {
    "[ $step/3 ] $label  ($($timer.Elapsed.ToString('hh\:mm\:ss')))" |
        Tee-Object -FilePath $log -Append | Out-Host
}

try {
    Show-Stage 1 'Checking local build environment'
    if (-not (Test-Path -LiteralPath (Join-Path $root 'PiliPlus-main/.dart_tool/package_config.json'))) {
        throw 'Flutter dependencies are missing. Prepare this workspace before building.'
    }
    Show-Stage 2 'Building ARM64 release APK'
    & "$PSScriptRoot/build-apk.ps1" -BuildNumber $BuildNumber 2>&1 |
        Tee-Object -FilePath $log -Append | Out-Host
    Show-Stage 3 'Verifying signature and ABI, then copying the APK'
    & "$PSScriptRoot/verify-apk.ps1" -OutputName $output 2>&1 |
        Tee-Object -FilePath $log -Append | Out-Host
    Write-Host ("Completed in " + $timer.Elapsed.ToString('hh\:mm\:ss')) -ForegroundColor Green
} catch {
    "Build failed: $($_.Exception.Message)" |
        Tee-Object -FilePath $log -Append | Out-Host
    exit 1
} finally {
    Write-Host "Log: $log"
}
