param([ValidateSet('debug','release')][string]$Configuration='release')
$ErrorActionPreference='Stop'
Push-Location $PSScriptRoot
try {
    $arguments = @('build','--locked','--target','x86_64-pc-windows-gnu')
    $versionLine = Select-String -LiteralPath (Join-Path $PSScriptRoot 'Cargo.toml') -Pattern '^version = "([^"]+)"' | Select-Object -First 1
    $versionTag = $versionLine.Matches[0].Groups[1].Value.Replace('.','_')
    if ($Configuration -eq 'release') { $arguments += '--release' }
    & cargo @arguments
    if ($LASTEXITCODE -ne 0) { throw 'Native compilation failed; extension was not activated.' }
    $buildRoot = if ($env:CARGO_TARGET_DIR) { $env:CARGO_TARGET_DIR } else { Join-Path $PSScriptRoot 'target' }
    $artifact = Join-Path $buildRoot "x86_64-pc-windows-gnu/$Configuration/spatial_ml.dll"
    if (-not (Test-Path -LiteralPath $artifact)) { throw 'Expected DLL missing; extension was not activated.' }
    $destination = Join-Path $PSScriptRoot "bin/windows/$Configuration"
    New-Item -ItemType Directory -Force -Path $destination | Out-Null
    Copy-Item -LiteralPath $artifact -Destination (Join-Path $destination "spatial_ml_$versionTag.dll")
    $descriptor = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'spatial_ml.gdextension.in') -Raw
    $descriptor = $descriptor.Replace('{NATIVE_VERSION_TAG}',$versionTag)
    if ($Configuration -eq 'debug') { $descriptor = $descriptor.Replace(("windows.debug.x86_64 = `"res://rust/spatial_ml/bin/windows/release/spatial_ml_$versionTag.dll`""), ("windows.debug.x86_64 = `"res://rust/spatial_ml/bin/windows/debug/spatial_ml_$versionTag.dll`"")) }
    Set-Content -LiteralPath (Join-Path $PSScriptRoot 'spatial_ml.gdextension') -Value $descriptor
    Write-Output 'Native extension installed. NativeMLBridge.load_default_segmenter() loads the verified packaged artifacts.'
} finally { Pop-Location }
