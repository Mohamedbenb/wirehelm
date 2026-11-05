param(
    [string]$GoExecutable,
    [string]$AndroidSdk,
    [string]$JavaDirectory,
    [string]$Targets = 'android/arm64,android/amd64'
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not $GoExecutable) {
    $localGo = Join-Path $projectRoot '.tools/go/bin/go.exe'
    $GoExecutable = if (Test-Path $localGo) { $localGo } else { (Get-Command go -ErrorAction Stop).Source }
}
if (-not $AndroidSdk) {
    $sdkLine = Get-Content (Join-Path $projectRoot 'android/local.properties') | Where-Object { $_ -like 'sdk.dir=*' }
    $AndroidSdk = $sdkLine.Substring(8).Replace('\\', '\').Replace('\:', ':')
}
if (-not $JavaDirectory) {
    $JavaDirectory = if ($env:JAVA_HOME) { $env:JAVA_HOME } else { 'C:/Program Files/Android/Android Studio/jbr' }
}
$ndk = Get-ChildItem (Join-Path $AndroidSdk 'ndk') -Directory | Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1
if (-not $ndk) { throw 'Android NDK is required; install it in the Android SDK manager.' }
$env:ANDROID_HOME = $AndroidSdk
$env:ANDROID_NDK_HOME = $ndk.FullName
$env:JAVA_HOME = $JavaDirectory
$env:GOPATH = Join-Path $projectRoot '.tools/gopath'
$env:GOCACHE = Join-Path $projectRoot '.tools/gocache'
$env:PATH = (Split-Path $GoExecutable) + ';' + (Join-Path $env:GOPATH 'bin') + ';' + (Join-Path $JavaDirectory 'bin') + ';' + $env:PATH
Push-Location (Join-Path $projectRoot 'native/tsnet')
try {
    & $GoExecutable mod download
    if ($LASTEXITCODE -ne 0) { throw 'Go dependency download failed.' }
    & $GoExecutable install golang.org/x/mobile/cmd/gomobile
    if ($LASTEXITCODE -ne 0) { throw 'gomobile install failed.' }
    & $GoExecutable install golang.org/x/mobile/cmd/gobind
    if ($LASTEXITCODE -ne 0) { throw 'gobind install failed.' }
    & (Join-Path $env:GOPATH 'bin/gomobile.exe') init
    if ($LASTEXITCODE -ne 0) { throw 'gomobile init failed.' }
    $libraryDirectory = Join-Path $projectRoot 'android/app/libs'
    New-Item -ItemType Directory -Force $libraryDirectory | Out-Null
    & (Join-Path $env:GOPATH 'bin/gomobile.exe') bind -target $Targets -androidapi 24 -javapkg com.remotecontrol.tsnet -o (Join-Path $libraryDirectory 'tsnet.aar') ./bridge
    if ($LASTEXITCODE -ne 0) { throw 'tsnet Android binding failed.' }
} finally {
    Pop-Location
}
