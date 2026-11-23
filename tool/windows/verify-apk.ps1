param([string]$OutputName = 'PiliPlus-offline-folders-2.2.1-dev.apk')
$ErrorActionPreference = 'Stop'
$jdk = Get-ChildItem "$PSScriptRoot/jdk17" -Directory | Where-Object { Test-Path "$($_.FullName)/bin/jlink.exe" } | Select-Object -First 1
if (-not $jdk) { throw 'Full Java 17 JDK with jlink is required' }
$env:JAVA_HOME = $jdk.FullName
$apk = [IO.Path]::GetFullPath("$PSScriptRoot/../PiliPlus-main/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk")
if (-not (Test-Path $apk)) { throw 'APK has not been produced' }
$certs = & "$PSScriptRoot/android-sdk/build-tools/37.0.0/apksigner.bat" verify --verbose --print-certs $apk
if ($LASTEXITCODE -ne 0) { throw 'APK signature verification failed' }
$certs
if (-not ($certs -match 'certificate SHA-256 digest: 135c908f219cc7e03b7e2fb9e5175ad43b5b7422013c510ed1e5c7a759940a7c$')) {
    throw 'APK signing certificate does not match the previous development build.'
}
$badging = & "$PSScriptRoot/android-sdk/build-tools/37.0.0/aapt.exe" dump badging $apk
if ($LASTEXITCODE -ne 0) { throw 'APK manifest inspection failed' }
if ((($badging -match '^native-code:') -join '').Trim() -cne "native-code: 'arm64-v8a'") {
    throw 'Expected exactly one APK ABI: arm64-v8a'
}
if ($OutputName -match '\+(\d+)-dev-arm64-v8a\.apk$') {
    $expectedCode = $Matches[1]
    if (-not ($badging -match "^package: name='com\.example\.piliplus\.dev' versionCode='$expectedCode'")) {
        throw "APK package identity or version code does not match the requested build ($expectedCode)."
    }
}
$badging | Select-String '^package:|^sdkVersion:|^targetSdkVersion:|^application-label:|^native-code:'
$output = [IO.Path]::GetFullPath("$PSScriptRoot/../$OutputName")
Copy-Item -LiteralPath $apk -Destination $output -Force
$hash = Get-FileHash -LiteralPath $output -Algorithm SHA256
[pscustomobject]@{APK=$output;Bytes=(Get-Item $output).Length;SHA256=$hash.Hash} | Format-List
