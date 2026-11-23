$env:FLUTTER_ROOT = "$PSScriptRoot/flutter"
$env:FLUTTER_SUPPRESS_ANALYTICS = 'true'
$env:DART_SUPPRESS_ANALYTICS = 'true'
$env:FLUTTER_STORAGE_BASE_URL = 'https://storage.flutter-io.cn'
$env:PUB_CACHE = "$PSScriptRoot/pub-cache"
$env:ANDROID_HOME = "$PSScriptRoot/android-sdk"
$env:ANDROID_SDK_ROOT = $env:ANDROID_HOME
$jdk = Get-ChildItem "$PSScriptRoot/jdk17" -Directory | Where-Object { Test-Path "$($_.FullName)/bin/jlink.exe" } | Select-Object -First 1
if (-not $jdk) { throw 'Full Java 17 JDK with jlink is required' }
$env:JAVA_HOME = $jdk.FullName
$env:GRADLE_USER_HOME = "$PSScriptRoot/gradle-cache"
$env:FLUTTER_WINDOWS = 'false'
$env:FLUTTER_LINUX = 'false'
$env:FLUTTER_MACOS = 'false'
$env:Path = "$env:FLUTTER_ROOT/bin;$env:JAVA_HOME/bin;$env:Path"
& "$env:FLUTTER_ROOT/bin/flutter.bat" @args
exit $LASTEXITCODE
