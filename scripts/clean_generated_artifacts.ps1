param([switch]$Execute)

$ErrorActionPreference = 'Stop'
$workspace = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')

function WorkspaceItem([string]$RelativePath) {
    $path = [IO.Path]::GetFullPath((Join-Path $workspace $RelativePath))
    if (-not $path.StartsWith($workspace + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw "Outside workspace: $path"
    }
    $item = Get-Item -LiteralPath $path -Force
    for ($parent = $item.FullName; $parent; $parent = [IO.Path]::GetDirectoryName($parent)) {
        if ((Get-Item -LiteralPath $parent -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw "Reparse point rejected: $parent"
        }
        if ($parent -eq $workspace) { break }
    }
    return $item
}

function MatchingHash([string]$Name) {
    $archivePath = "build/artifacts/$Name"
    if (-not (Test-Path -LiteralPath (Join-Path $workspace "$archivePath.sha256") -PathType Leaf)) {
        return
    }
    if (-not (Test-Path -LiteralPath (Join-Path $workspace $archivePath) -PathType Leaf)) {
        return
    }
    $archive = WorkspaceItem $archivePath
    $checksum = WorkspaceItem "$archivePath.sha256"
    $copy = WorkspaceItem "build/app/outputs/flutter-apk/$Name"
    $expected = ((Get-Content -LiteralPath $checksum.FullName -Raw).Trim() -split '\s+')[0]
    if ($expected -match '^[a-fA-F0-9]{64}$' -and
        (Get-FileHash -LiteralPath $archive.FullName).Hash -eq $expected -and
        (Get-FileHash -LiteralPath $copy.FullName).Hash -eq $expected) {
        return $expected
    }
}

$output = WorkspaceItem 'build/app/outputs/flutter-apk'
$copies = @(foreach ($file in Get-ChildItem -LiteralPath $output.FullName -File -Filter '*.apk') {
    if ($file.Name -notmatch '^(Wirehelm|Node-Cockpit)-[0-9.]+-build[0-9]+\.apk$') { continue }
    $hash = MatchingHash $file.Name
    if ($hash) { [pscustomobject]@{ Name = $file.Name; Bytes = $file.Length; Hash = $hash } }
})

$copies | Format-Table Name, Bytes
$bytes = ($copies | Measure-Object -Property Bytes -Sum).Sum
if (-not $Execute) {
    Write-Output "Preview: $($copies.Count) verified duplicate APKs, $([long]$bytes) bytes."
    return
}

foreach ($copy in $copies) {
    if ((MatchingHash $copy.Name) -ne $copy.Hash) { throw "APK changed during cleanup: $($copy.Name)" }
    $file = WorkspaceItem "build/app/outputs/flutter-apk/$($copy.Name)"
    Remove-Item -LiteralPath $file.FullName
}
Write-Output "Removed $($copies.Count) verified duplicate APKs, $([long]$bytes) bytes."
