#Requires -Version 7.0
<#
.SYNOPSIS
Preview or apply the reviewed build retention policy. Unknown directories stay put.
.EXAMPLE
pwsh -NoProfile -File tools/clean_build.ps1
.EXAMPLE
pwsh -NoProfile -File tools/clean_build.ps1 -Apply
#>
[CmdletBinding()]
param([switch]$Apply)

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$buildRoot = Join-Path $repoRoot 'build'
$policy = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'build-retention.json') -Raw | ConvertFrom-Json
if ($policy.schema_version -ne 1) { throw 'Unsupported build retention policy.' }
$retained = @($policy.retained.PSObject.Properties.Name)
$retired = @($policy.retired)
foreach ($name in @($retained) + @($retired)) {
    if ($name -notmatch '^[A-Za-z0-9][A-Za-z0-9_-]*$') { throw "Invalid directory name: $name" }
}
if (@($retired | Select-Object -Unique).Count -ne $retired.Count) { throw 'Duplicate retired directory.' }
if (@($retired | Where-Object { $retained -contains $_ }).Count) { throw 'Retained and retired directories overlap.' }
if (-not (Test-Path -LiteralPath $buildRoot)) { Write-Output 'No build directory.'; return }

function Assert-BuildPath([string]$Path) {
    $absolute = [IO.Path]::GetFullPath($Path)
    if (-not $absolute.StartsWith($buildRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Path escapes build directory: $absolute"
    }
    return $absolute
}

function Assert-NoLinks([string]$Path) {
    $item = Get-Item -LiteralPath $Path -Force
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Linked path is protected: $Path" }
    if ($item.PSIsContainer) {
        foreach ($entry in Get-ChildItem -LiteralPath $Path -Recurse -Force) {
            if ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Linked path is protected: $($entry.FullName)" }
        }
    }
}

Assert-NoLinks $buildRoot
$targets = @(foreach ($name in $retired) {
    $candidate = Assert-BuildPath (Join-Path $buildRoot $name)
    if (Test-Path -LiteralPath $candidate -PathType Container) { Get-Item -LiteralPath $candidate }
})
$looseFiles = @(Get-ChildItem -LiteralPath $buildRoot -File -Force | Where-Object {
    $_.Extension -in @('.log', '.json', '.py', '.txt', '.png', '.import', '.c')
})
$plannedBytes = [long]0
foreach ($target in $targets) {
    $bytes = [long](Get-ChildItem -LiteralPath $target.FullName -File -Recurse -Force | Measure-Object Length -Sum).Sum
    $plannedBytes += $bytes
    Write-Output ('Retire {0,-38} {1,8:N2} GiB' -f $target.Name, ($bytes / 1GB))
}
foreach ($entry in Get-ChildItem -LiteralPath $buildRoot -Directory -Force) {
    if ($retired -notcontains $entry.Name) { Write-Output "Keep   $($entry.Name)" }
}
Write-Output ("Archive {0} loose diagnostics/helpers; {1} retired directories, {2:N2} GiB before evidence preservation." -f $looseFiles.Count, $targets.Count, ($plannedBytes / 1GB))
if (-not $Apply) { Write-Output 'Preview only. Use -Apply to archive evidence and remove the reviewed outputs.'; return }
if (-not $targets.Count -and -not $looseFiles.Count) { Write-Output 'Nothing to clean.'; return }

# Do not retire a running export or a workspace used by an active command.
if ($env:OS -eq 'Windows_NT') {
    foreach ($process in Get-CimInstance Win32_Process) {
        if ($process.ProcessId -eq $PID) { continue }
        foreach ($target in $targets) {
            if (($process.ExecutablePath -and $process.ExecutablePath.StartsWith($target.FullName + '\', [StringComparison]::OrdinalIgnoreCase)) -or
                ($process.CommandLine -and ($process.CommandLine.IndexOf($target.FullName, [StringComparison]::OrdinalIgnoreCase) -ge 0 -or
                 $process.CommandLine.IndexOf('build/' + $target.Name, [StringComparison]::OrdinalIgnoreCase) -ge 0 -or
                 $process.CommandLine.IndexOf('build\' + $target.Name, [StringComparison]::OrdinalIgnoreCase) -ge 0))) {
                throw "Retired directory is in use by process $($process.ProcessId): $($target.Name)"
            }
        }
    }
}

$archiveRoot = Assert-BuildPath (Join-Path $buildRoot ('_archive\' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8)))
New-Item -ItemType Directory -Path $archiveRoot -Force | Out-Null
$evidence = [Collections.Generic.List[object]]::new()
$omitted = [Collections.Generic.List[object]]::new()
$snapshots = [Collections.Generic.List[object]]::new()

function Save-Evidence([IO.FileInfo]$File, [string]$Relative) {
    $destination = Assert-BuildPath (Join-Path $archiveRoot $Relative)
    New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
    $before = (Get-FileHash -LiteralPath $File.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    Copy-Item -LiteralPath $File.FullName -Destination $destination
    $after = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($before -ne $after) { throw "Archive verification failed: $Relative" }
    $evidence.Add([ordered]@{ path = $Relative.Replace('\', '/'); bytes = $File.Length; sha256 = $after })
}

foreach ($target in $targets) {
    $receiptPath = Join-Path $target.FullName 'package-receipt.json'
    $payloads = @{}
    if (Test-Path -LiteralPath $receiptPath) {
        $receipt = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json
        foreach ($property in $receipt.files.PSObject.Properties) { $payloads[$property.Name.Replace('\', '/')] = $property.Value }
    }
    foreach ($file in Get-ChildItem -LiteralPath $target.FullName -File -Recurse -Force) {
        $relative = $file.FullName.Substring($target.FullName.Length + 1).Replace('\', '/')
        $snapshots.Add([ordered]@{ path = $file.FullName; bytes = $file.Length; modified_ticks = $file.LastWriteTimeUtc.Ticks })
        if ($relative -match '(^|/)\.godot/') { continue }
        # Only receipted package binaries/models are discarded. Unreceipted files,
        # source snapshots, screenshots, scripts, notices and diagnostics survive.
        if ($payloads.ContainsKey($relative) -and
            ($file.Extension -in @('.exe', '.dll', '.pck', '.onnx', '.gguf', '.lib') -or
             $relative -match '^resources/cortex/(models|runtimes)/')) {
            $omitted.Add([ordered]@{ path = ($target.Name + '/' + $relative); bytes = $file.Length; receipt_sha256 = $payloads[$relative] })
            continue
        }
        Save-Evidence $file ('directories\' + $target.Name + '\' + $relative.Replace('/', '\'))
    }
}
foreach ($file in $looseFiles) {
    $snapshots.Add([ordered]@{ path = $file.FullName; bytes = $file.Length; modified_ticks = $file.LastWriteTimeUtc.Ticks })
    Save-Evidence $file ('root\' + $file.Name)
}

# Check for changed or newly added files after archiving and before any deletion.
foreach ($snapshot in $snapshots) {
    $file = Get-Item -LiteralPath $snapshot.path -Force
    if ($file.Length -ne $snapshot.bytes -or $file.LastWriteTimeUtc.Ticks -ne $snapshot.modified_ticks) {
        throw "Build changed during archiving; nothing removed: $($snapshot.path)"
    }
}
$directoryFileCount = 0
foreach ($target in $targets) { $directoryFileCount += @(Get-ChildItem -LiteralPath $target.FullName -File -Recurse -Force).Count }
if ($directoryFileCount + $looseFiles.Count -ne $snapshots.Count) { throw 'Build changed during archiving; nothing removed.' }

$manifest = [ordered]@{
    schema_version = 1
    classification = 'Repository maintenance; no runtime or application version change.'
    created_at_utc = [DateTime]::UtcNow.ToString('o')
    repository = $repoRoot
    state = 'evidence_verified'
    retained = $policy.retained
    retired = @($targets.Name)
    retired_directory_bytes = $plannedBytes
    evidence = $evidence.ToArray()
    discarded_receipted_payloads = $omitted.ToArray()
    note = 'Historical package receipts are evidence, not a complete binary backup. Godot caches are disposable. Existing docs/audit remains authoritative for qualification.'
}
$manifestPath = Join-Path $archiveRoot 'manifest.json'
$manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'build-retention.json') -Destination (Join-Path $archiveRoot 'retention-policy.json')
foreach ($target in $targets) {
    $checked = Assert-BuildPath $target.FullName
    Assert-NoLinks $checked
    Remove-Item -LiteralPath $checked -Recurse -Force
}
foreach ($file in $looseFiles) { Remove-Item -LiteralPath (Assert-BuildPath $file.FullName) -Force }
$manifest.state = 'complete'
$manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
Set-Content -LiteralPath (Join-Path $buildRoot '.gdignore') -Value '' -Encoding ASCII
Write-Output "Cleanup complete. Verified evidence: $archiveRoot"
