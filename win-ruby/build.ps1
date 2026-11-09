#PixelWave.exeを作る（ocranでRuby本体と素材を1つのexeにまとめる）
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$stage = Join-Path $root 'build-stage'

Remove-Item -Recurse -Force $stage -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $stage | Out-Null
Copy-Item (Join-Path $root 'main.rb') $stage
Copy-Item -Recurse (Join-Path $root 'lib') $stage
Copy-Item -Recurse (Join-Path (Split-Path $root) 'assets') $stage

Push-Location $stage
try {
    ocran --output (Join-Path $root 'PixelWave.exe') --add-all-core --windows main.rb lib assets
} finally {
    Pop-Location
}
Remove-Item -Recurse -Force $stage
Write-Host 'built: PixelWave.exe'
