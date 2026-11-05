param([int]$BuildNumber = 0)
$ErrorActionPreference = 'Stop'
$projectDirectory = Split-Path -Parent $PSScriptRoot
Push-Location -LiteralPath $projectDirectory
try {
    & python (Join-Path $PSScriptRoot 'package_customization.py')
    if ($LASTEXITCODE -ne 0) { throw 'Customization backend packaging failed.' }
    $buildArguments = @('build', 'apk', '--release', '--target-platform', 'android-arm64', '-t', 'lib/main.dart')
    if ($BuildNumber -gt 0) { $buildArguments += @('--build-number', "$BuildNumber") }
    & flutter @buildArguments
    if ($LASTEXITCODE -ne 0) { throw 'APK build failed.' }
    $outputDirectory = Join-Path $projectDirectory 'build\app\outputs\flutter-apk'
    $releaseApk = Join-Path $outputDirectory 'app-release.apk'
    & python (Join-Path $PSScriptRoot 'verify_customization_apk.py') $releaseApk
    if ($LASTEXITCODE -ne 0) { throw 'Xposed release entry verification failed.' }
    $updateApk = Join-Path $outputDirectory 'node-cockpit-update.apk'
    Copy-Item -LiteralPath $releaseApk -Destination $updateApk -Force
    # Build 2 phones still point at this path. The APK is a release build even
    # under the legacy filename; Android checks its contents, not its name.
    Copy-Item -LiteralPath $releaseApk -Destination (Join-Path $outputDirectory 'app-debug.apk') -Force
    $versionLine = Select-String -LiteralPath (Join-Path $projectDirectory 'pubspec.yaml') -Pattern '^version:\s*(\S+)'
    $versionParts = $versionLine.Matches[0].Groups[1].Value.Split('+')
    $publishedBuild = if ($BuildNumber -gt 0) { $BuildNumber } else { [int]$versionParts[1] }
    $manifest = @{ version = $versionParts[0]; build = $publishedBuild } | ConvertTo-Json -Compress
    foreach ($apkPath in @($updateApk, (Join-Path $outputDirectory 'app-debug.apk'))) {
        [System.IO.File]::WriteAllText("$apkPath.json", $manifest, [System.Text.UTF8Encoding]::new($false))
    }
    Write-Output "Update ready: $updateApk"
    Write-Output ('Size: {0:N1} MB' -f ((Get-Item -LiteralPath $updateApk).Length / 1MB))
} finally { Pop-Location }
