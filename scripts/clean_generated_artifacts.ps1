param(
    [int]$AcceptedBuild = 254,
    [int]$RollbackBuild = 252,
    [switch]$Execute
)
$ErrorActionPreference = 'Stop'
$workspace = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
$prefix = $workspace + '\'
if ((Get-Item -LiteralPath $workspace -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Workspace must not be a reparse point.' }
function Assert-Child([string]$Path) {
    $absolute = [IO.Path]::GetFullPath($Path)
    if (-not $absolute.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw "Outside workspace: $absolute" }
    $cursor = $absolute
    while ($cursor -and $cursor -ne $workspace) {
        if (Test-Path -LiteralPath $cursor) {
            if ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Reparse point rejected: $cursor" }
        }
        $cursor = [IO.Path]::GetDirectoryName($cursor)
    }
    return $absolute
}
function Local([string]$Relative) { return Assert-Child (Join-Path $workspace $Relative) }
$versionText = Get-Content -LiteralPath (Local 'pubspec.yaml') -Raw
if ($versionText -notmatch '(?m)^version:\s*[^+\r\n]+\+(\d+)') { throw 'Cannot read current source build.' }
if ([int]$Matches[1] -ne $AcceptedBuild) { throw 'Only clean at an accepted source milestone; specify its build explicitly.' }
if ($RollbackBuild -ge $AcceptedBuild) { throw 'Rollback build must be older than accepted build.' }
$artifactRoot = Local 'build/artifacts'
$accepted = @(Get-ChildItem -LiteralPath $artifactRoot -File -Filter "Node-Cockpit-*-build$AcceptedBuild.apk")
$rollback = @(Get-ChildItem -LiteralPath $artifactRoot -File -Filter "Node-Cockpit-*-build$RollbackBuild.apk")
if ($accepted.Count -ne 1 -or $rollback.Count -ne 1) { throw 'Need exactly one accepted and one rollback artifact.' }
$engine = @(Get-ChildItem -LiteralPath $artifactRoot -File -Filter 'Glass-Engine-Lab-*-build*.apk' | Sort-Object { if ($_.Name -match '-build(\d+)\.apk$') { [int]$Matches[1] } else { -1 } } -Descending | Select-Object -First 1)
if ($engine.Count -ne 1) { throw 'Latest engine lab APK missing.' }
$keepers = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$critical = [Collections.Generic.List[string]]::new()
foreach ($item in @($accepted[0], $rollback[0], $engine[0])) {
    $path = Assert-Child $item.FullName
    $null = $keepers.Add($path)
    $critical.Add($path)
    $checksumPath = $path + '.sha256'
    if (-not (Test-Path -LiteralPath $checksumPath)) { throw "Missing archive checksum: $path" }
    $expected = ((Get-Content -LiteralPath $checksumPath -Raw).Trim() -split '\s+')[0]
    if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ine $expected) { throw "Archive checksum mismatch: $path" }
}
$currentPaths = @(
    'build/app/outputs/apk/release/app-release.apk',
    'build/app/outputs/flutter-apk/app-debug.apk',
    'build/app/outputs/flutter-apk/app-release.apk',
    'build/app/outputs/flutter-apk/node-cockpit-update.apk',
    ('build/app/outputs/flutter-apk/' + $accepted[0].Name)
)
$acceptedHash = (Get-FileHash -LiteralPath $accepted[0].FullName -Algorithm SHA256).Hash
foreach ($relative in $currentPaths) {
    $path = Local $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Current updater APK missing: $path" }
    if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $acceptedHash) { throw "Updater APK differs from accepted archive: $path" }
    $null = $keepers.Add($path)
    $critical.Add($path)
}
$required = @(
    '.dart_tool/package_config.json',
    '.dart_tool/flutter_build/dart_plugin_registrant.dart',
    '.dart_tool/flutter_build/fcb34e5a82cfb429eb2d277eb1931ace/native_assets.json',
    ('build/camera-notification-ring/node' + $AcceptedBuild + '.so'),
    ('build/camera-notification-ring/node' + $AcceptedBuild + '.dill'),
    'build/app/intermediates/flutter/release/arm64-v8a/app.so',
    'android/app/libs/tsnet.aar',
    'build/SystemUIGoogle-inspect.apk',
    'build/framework-res-pill-inspect.apk',
    'build/qs-native-inspect.apk',
    'build/native-sf-bridge/framework.jar'
)
foreach ($relative in $required) {
    $path = Local $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required retained input missing: $path" }
    $null = $keepers.Add($path)
    $critical.Add($path)
}
$criticalHashes = @{}
foreach ($path in $critical) { $criticalHashes[$path] = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash }
$candidates = [Collections.Generic.List[object]]::new()
$seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
function Add-Candidate([string]$Path, [string]$Category) {
    $absolute = Assert-Child $Path
    if (-not (Test-Path -LiteralPath $absolute) -or $keepers.Contains($absolute) -or -not $seen.Add($absolute)) { return }
    $item = Get-Item -LiteralPath $absolute -Force
    foreach ($kept in $keepers) {
        if ($kept.StartsWith($absolute + '\', [StringComparison]::OrdinalIgnoreCase)) { throw "Cleanup would contain retained input: $kept" }
    }
    [long]$bytes = 0
    if ($item.PSIsContainer) {
        $links = @(Get-ChildItem -LiteralPath $absolute -Recurse -Force -Attributes ReparsePoint -ErrorAction Stop)
        if ($links.Count -gt 0) { throw "Nested reparse points rejected: $absolute" }
        $measure = Get-ChildItem -LiteralPath $absolute -Recurse -Force -File | Measure-Object -Property Length -Sum
        $bytes = [long]$measure.Sum
    } else { $bytes = $item.Length }
    $candidates.Add([pscustomobject]@{ path = $absolute; category = $Category; directory = [bool]$item.PSIsContainer; bytes = $bytes })
}
$apkFiles = @((Get-ChildItem -LiteralPath $workspace -File -Filter '*.apk'), (Get-ChildItem -LiteralPath (Local 'build') -File -Recurse -Filter '*.apk')) | ForEach-Object { $_ }
foreach ($apk in $apkFiles) {
    if ($keepers.Contains($apk.FullName)) { continue }
    Add-Candidate $apk.FullName 'Obsolete APK archives'
    foreach ($suffix in @('.json', '.sha1', '.sha256', '.idsig')) { Add-Candidate ($apk.FullName + $suffix) 'Obsolete APK sidecars' }
}
$flutterCache = Local '.dart_tool/flutter_build'
foreach ($folder in Get-ChildItem -LiteralPath $flutterCache -Directory -Force) {
    if ($folder.Name -eq 'fcb34e5a82cfb429eb2d277eb1931ace') { continue }
    Add-Candidate $folder.FullName 'Obsolete Flutter build caches'
}
Add-Candidate (Local 'build/test_cache') 'Generated Flutter test cache'
Add-Candidate (Local '.tools/gocache') 'Generated Go build cache'
Add-Candidate (Local 'build/app/intermediates/merged_native_libs') 'Regenerable merged native libraries'
foreach ($file in Get-ChildItem -LiteralPath (Local 'build/camera-notification-ring') -File) {
    if ($file.Name -match '^node(\d+)\.(so|dill|d)$' -and [int]$Matches[1] -ne $AcceptedBuild) { Add-Candidate $file.FullName 'Obsolete ring frontend intermediates' }
}
# Resolve every target again before any recursive deletion. All operations stay in PowerShell.
foreach ($candidate in $candidates) { $null = Assert-Child $candidate.path }
$maintenance = Local 'build/maintenance'
$null = New-Item -ItemType Directory -Path $maintenance -Force
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$planPath = Join-Path $maintenance "cleanup-$stamp-plan.json"
$summary = @($candidates | Group-Object category | ForEach-Object { [pscustomobject]@{ category = $_.Name; entries = $_.Count; GiB = [math]::Round(($_.Group | Measure-Object bytes -Sum).Sum / 1GB, 3) } })
$plan = [ordered]@{ workspace = $workspace; acceptedBuild = $AcceptedBuild; rollbackBuild = $RollbackBuild; engine = $engine[0].Name; execute = [bool]$Execute; candidates = @($candidates); retainedHashes = $criticalHashes; summary = $summary }
$plan | ConvertTo-Json -Depth 7 | Set-Content -LiteralPath $planPath -Encoding utf8
$summary | Format-Table -AutoSize
Write-Output "Plan: $planPath"
if (-not $Execute) { Write-Output 'Dry run only. Use -Execute after reviewing the plan.'; return }
$deleted = [Collections.Generic.List[string]]::new()
$failures = [Collections.Generic.List[object]]::new()
foreach ($candidate in $candidates) {
    $absolute = Assert-Child $candidate.path
    if (-not (Test-Path -LiteralPath $absolute)) { continue }
    try {
        if ($candidate.directory) { Remove-Item -LiteralPath $absolute -Recurse -Force -ErrorAction Stop }
        else { Remove-Item -LiteralPath $absolute -Force -ErrorAction Stop }
        $deleted.Add($absolute)
    } catch { $failures.Add([pscustomobject]@{ path = $absolute; error = $_.Exception.Message }) }
}
$verified = 0
foreach ($path in $criticalHashes.Keys) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $criticalHashes[$path]) { throw "Retained input changed: $path" }
    $verified++
}
$result = [ordered]@{ plan = $planPath; deletedEntries = $deleted.Count; failures = @($failures); verifiedRetainedFiles = $verified; deleted = @($deleted) }
$resultPath = Join-Path $maintenance "cleanup-$stamp-result.json"
$result | ConvertTo-Json -Depth 7 | Set-Content -LiteralPath $resultPath -Encoding utf8
Write-Output "Deleted entries: $($deleted.Count); failures: $($failures.Count); retained hashes verified: $verified"
Write-Output "Result: $resultPath"
if ($failures.Count -gt 0) { throw 'Some cleanup targets could not be removed; inspect the result log.' }
