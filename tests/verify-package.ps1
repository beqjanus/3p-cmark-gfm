param(
    [Parameter(Mandatory = $true)][string]$StageDir
)

$ErrorActionPreference = 'Stop'
$required = @(
    'include/cmark-gfm.h',
    'include/cmark-gfm-extension_api.h',
    'include/cmark-gfm_export.h',
    'include/cmark-gfm_version.h',
    'include/cmark-gfm-core-extensions.h',
    'lib/cmark-gfm_static.lib',
    'lib/cmark-gfm-extensions_static.lib',
    'LICENSES/cmark-gfm-COPYING.txt',
    'VERSION.txt'
)
foreach ($path in $required) {
    if (-not (Test-Path (Join-Path $StageDir $path) -PathType Leaf)) {
        throw "Missing required file: $path"
    }
}

$forbidden = Get-ChildItem -Path $StageDir -Recurse -File -Include *.dll,*.so,*.dylib,cmark-gfm.exe
if ($forbidden) {
    throw "Package contains forbidden shared library or executable: $($forbidden.FullName -join ', ')"
}

foreach ($library in @('cmark-gfm_static.lib', 'cmark-gfm-extensions_static.lib')) {
    $headers = & dumpbin /headers (Join-Path $StageDir "lib/$library") 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0 -or $headers -notmatch 'machine \(x64\)') {
        throw "Static archive is not an x64 MSVC archive: $library"
    }
}
