param([ValidateSet('debug','release')][string]$Configuration='release')
$ErrorActionPreference='Stop'
Push-Location $PSScriptRoot
try {
    $arguments = @('build','--locked')
    if ($Configuration -eq 'release') { $arguments += '--release' }
    & cargo @arguments
    if ($LASTEXITCODE -ne 0) { throw 'Native compilation failed; extension was not activated.' }
    $artifact = Join-Path $PSScriptRoot "target/x86_64-pc-windows-gnu/$Configuration/spatial_ml.dll"
    if (-not (Test-Path -LiteralPath $artifact)) { throw 'Expected DLL missing; extension was not activated.' }
    $destination = Join-Path $PSScriptRoot "bin/windows/$Configuration"
    New-Item -ItemType Directory -Force -Path $destination | Out-Null
    Copy-Item -LiteralPath $artifact -Destination (Join-Path $destination 'spatial_ml.dll')
    $descriptor = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'spatial_ml.gdextension.in') -Raw
    if ($Configuration -eq 'debug') { $descriptor = $descriptor.Replace('windows.debug.x86_64 = "res://rust/spatial_ml/bin/windows/release/spatial_ml.dll"', 'windows.debug.x86_64 = "res://rust/spatial_ml/bin/windows/debug/spatial_ml.dll"') }
    Set-Content -LiteralPath (Join-Path $PSScriptRoot 'spatial_ml.gdextension') -Value $descriptor
    Write-Output 'Native extension installed. Set ORT_DYLIB_PATH to a compatible ONNX Runtime DLL before launching Godot.'
} finally { Pop-Location }
