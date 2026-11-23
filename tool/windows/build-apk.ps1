param([string]$BuildNumber = '5658')
$ErrorActionPreference = 'Stop'
$repoDir = [IO.Path]::GetFullPath("$PSScriptRoot/../PiliPlus-main")
$wrapper = "$repoDir/android/gradle/wrapper/gradle-wrapper.properties"
$original = [IO.File]::ReadAllText($wrapper)
$sha = (Get-Content "$PSScriptRoot/gradle.sha256" -Raw).Trim()
$archive = [Uri]::new([IO.Path]::GetFullPath("$PSScriptRoot/distributions/gradle-9.5.0-all.zip")).AbsoluteUri
$env:ANDROID_USER_HOME = Join-Path $PSScriptRoot 'android-user'
$null = New-Item -Path $env:ANDROID_USER_HOME -ItemType Directory -Force
$backupKey = Join-Path $PSScriptRoot 'signing-backup/debug.keystore'
$buildKey = Join-Path $env:ANDROID_USER_HOME 'debug.keystore'
if (-not (Test-Path -LiteralPath $buildKey)) {
    Copy-Item -LiteralPath $backupKey -Destination $buildKey
}
if ((Get-FileHash -LiteralPath $backupKey).Hash -ne (Get-FileHash -LiteralPath $buildKey).Hash) {
    throw 'The build keystore does not match the signing backup.'
}
try {
    $local = $original -replace '(?m)^distributionUrl=.*$', "distributionUrl=$archive"
    [IO.File]::WriteAllText($wrapper, "$local`ndistributionSha256Sum=$sha`n")
    Push-Location $repoDir
    try {
        & "$PSScriptRoot/run-flutter.ps1" build apk --release --target-platform android-arm64 --split-per-abi --build-number $BuildNumber --android-project-arg dev=1 --no-pub
        if ($LASTEXITCODE -ne 0) { throw "APK build failed: $LASTEXITCODE" }
    } finally { Pop-Location }
} finally {
    [IO.File]::WriteAllText($wrapper, $original)
}
