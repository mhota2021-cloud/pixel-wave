; Pixel Waveのインストーラー（build.ps1がocranの--innosetupで使う。[Files]はocranが足す）
; 管理者権限を使わず、ユーザーごとに %LOCALAPPDATA%\Programs\PixelWave へ入れる

[Setup]
AppId=PixelWave
AppName=Pixel Wave
AppVersion=0.1.0
AppPublisher=Hotaka Mori
DefaultDirName={localappdata}\Programs\PixelWave
DefaultGroupName=Pixel Wave
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=Output
OutputBaseFilename=PixelWaveSetup
UninstallDisplayIcon={app}\PixelWave.exe
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
WizardStyle=modern

[Languages]
Name: "japanese"; MessagesFile: "compiler:Languages\Japanese.isl"

[Icons]
Name: "{autoprograms}\Pixel Wave"; Filename: "{app}\PixelWave.exe"
Name: "{autodesktop}\Pixel Wave"; Filename: "{app}\PixelWave.exe"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "デスクトップにアイコンを作る"; Flags: unchecked

[Run]
Filename: "{app}\PixelWave.exe"; Description: "Pixel Waveを起動する"; Flags: nowait postinstall skipifsilent
