#Pixel Waveのインストーラー（Output\PixelWaveSetup.exe）を作る
#ocranの--innosetupでRuby本体と素材をまとめ、Inno Setupでインストーラーにする
#1つのexeに詰める形は、起動のたびに%TEMP%へ展開して実行するため、Defenderに消された（2026-11-10）
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$stage = Join-Path $root 'build-stage'

#ocranはPATHからISCC.exeを呼ぶので、見つからなければInno Setupの既定の場所を足す
if (-not (Get-Command ISCC.exe -ErrorAction SilentlyContinue)) {
    $candidates = @(
        "$env:LOCALAPPDATA\Programs\Inno Setup 6",
        "${env:ProgramFiles(x86)}\Inno Setup 6",
        "$env:ProgramFiles\Inno Setup 6"
    )
    $inno = $candidates | Where-Object { Test-Path (Join-Path $_ 'ISCC.exe') } | Select-Object -First 1
    if (-not $inno) { throw 'Inno Setup 6が見つかりません（winget install JRSoftware.InnoSetup）' }
    $env:PATH = "$inno;$env:PATH"
}

Remove-Item -Recurse -Force $stage -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $stage | Out-Null
Copy-Item (Join-Path $root 'main.rb') $stage
Copy-Item -Recurse (Join-Path $root 'lib') $stage
Copy-Item -Recurse (Join-Path (Split-Path $root) 'assets') $stage

Push-Location $stage
try {
    $env:BUNDLE_GEMFILE = Join-Path $root 'Gemfile'
    bundle exec ocran --output PixelWave.exe --add-all-core --windows --no-lzma --chdir-first `
        --icon assets\icon.ico `
        --innosetup (Join-Path $root 'installer.iss') main.rb lib assets
    if ($LASTEXITCODE -ne 0) { throw "ocranが失敗しました（終了コード$LASTEXITCODE）" }
    $setup = Get-ChildItem -Recurse -Filter 'PixelWaveSetup.exe' | Select-Object -First 1
    if (-not $setup) { throw 'PixelWaveSetup.exeができていません' }
    New-Item -ItemType Directory -Force (Join-Path $root 'Output') | Out-Null
    Copy-Item $setup.FullName (Join-Path $root 'Output\PixelWaveSetup.exe') -Force
} finally {
    Pop-Location
}
Remove-Item -Recurse -Force $stage
Write-Host 'built: Output\PixelWaveSetup.exe'
