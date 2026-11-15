param([string]$BundleRoot=(Join-Path $PSScriptRoot '../resources/cortex'))
$ErrorActionPreference='Stop'
$bundle=(Resolve-Path -LiteralPath $BundleRoot).Path
$catalog=Get-Content -Raw -LiteralPath (Join-Path $bundle 'catalog.json') | ConvertFrom-Json
$artifacts=@($catalog.mobile_sam.encoder,$catalog.mobile_sam.decoder,$catalog.mobile_sam.windows_runtime,$catalog.qwen.model)+@($catalog.qwen.runtime_files)
$artifacts += @($catalog.mobile_sam.windows_runtime.dependencies)
$sam=Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot '../modules/spatial_intelligence/models/sam3-pack-manifest.json') | ConvertFrom-Json
foreach($member in $sam.members) {
    $artifacts += [pscustomobject]@{path=($catalog.sam3.directory+'/'+$member.path);bytes=$member.bytes;sha256=$member.sha256}
}
if($catalog.qwen.runtime_files.Count -eq 0) { throw 'The pinned Qwen CPU runtime is missing from the catalog.' }
$total=[long]0
function Get-CortexHash([string]$Path) {
    $stream=[IO.File]::OpenRead($Path)
    $hash=[Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($hash.ComputeHash($stream))).Replace('-','').ToLowerInvariant() }
    finally { $hash.Dispose(); $stream.Dispose() }
}
foreach($artifact in $artifacts) {
    $path=[IO.Path]::GetFullPath((Join-Path $bundle $artifact.path))
    if(-not $path.StartsWith($bundle+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw 'An artifact path escapes the bundle.' }
    if(-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw ('Missing Cortex resource: '+$artifact.path) }
    $file=Get-Item -LiteralPath $path
    if($file.Length -ne $artifact.bytes -or (Get-CortexHash $path) -ne $artifact.sha256) { throw ('Cortex integrity failure: '+$artifact.path) }
    $total += $file.Length
}
foreach($license in @('models/segmentation/mobilesam/vit_t/LICENSE-MobileSAM.txt','models/segmentation/sam3/vit_h_20260220/LICENSE.txt','models/language/qwen3/1.7b-q8_0/LICENSE.txt','runtimes/llama.cpp/b12387/windows-x86_64/LICENSE-llama.cpp.txt')) {
    if(-not (Test-Path -LiteralPath (Join-Path $bundle $license) -PathType Leaf)) { throw ('Missing license: '+$license) }
}
Write-Output ('Verified {0} pinned model/runtime files; {1:N2} GiB. No inference started.' -f $artifacts.Count,($total/1GB))
