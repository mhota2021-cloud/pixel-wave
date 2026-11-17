# Pixel Wave（Rust版）のリリースビルドとインストーラー作成（Output\PixelWaveSetup.exe）
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path

Push-Location $root
try {
    cargo build --release
    if ($LASTEXITCODE -ne 0) { throw "cargo build --release が失敗しました（終了コード $LASTEXITCODE）" }

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

    ISCC.exe (Join-Path $root 'installer.iss')
    if ($LASTEXITCODE -ne 0) { throw "ISCC.exe が失敗しました（終了コード $LASTEXITCODE）" }
} finally {
    Pop-Location
}
Write-Host 'built: win\Output\PixelWaveSetup.exe'
