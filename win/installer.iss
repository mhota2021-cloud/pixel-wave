; Pixel Wave（Rust版）のインストーラー
; 旧Ruby版の上から上書きインストールでき、設定（%APPDATA%\PixelWave）は引き継ぐ

[Setup]
AppId=PixelWave
AppName=Pixel Wave
AppVersion=1.1.0
AppPublisher=xp_Beaker
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
Compression=lzma2
SolidCompression=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "japanese"; MessagesFile: "compiler:Languages\Japanese.isl"

[InstallDelete]
; 旧Ruby版から上書きするときに不要なランタイムを残さない
Type: filesandordirs; Name: "{app}\bin"
Type: filesandordirs; Name: "{app}\gems"
Type: filesandordirs; Name: "{app}\lib"
Type: filesandordirs; Name: "{app}\msys64"
Type: filesandordirs; Name: "{app}\src"
Type: files; Name: "{app}\launcher.bat"
Type: files; Name: "{app}\no_bundler_setup.rb"

[Files]
Source: "target\release\PixelWave.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "target\release\PixelWave.exe"; DestDir: "{app}"; DestName: "PixelWave.scr"; Flags: ignoreversion
Source: "..\assets\icon.ico"; DestDir: "{app}\assets"; Flags: ignoreversion
Source: "..\assets\paintings\*"; DestDir: "{app}\assets\paintings"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Pixel Wave"; Filename: "{app}\PixelWave.exe"
Name: "{autodesktop}\Pixel Wave"; Filename: "{app}\PixelWave.exe"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; Flags: unchecked

[Run]
Filename: "{app}\PixelWave.exe"; Description: "{cm:LaunchProgram,Pixel Wave}"; Flags: nowait postinstall skipifsilent
