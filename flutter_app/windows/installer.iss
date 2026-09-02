; Network Console 2.0 (Flutter) - Inno Setup script.
; Yonetici hakki gerekmez (kullanici profiline kurulur), eski 1.5.x
; kurulumuyla ayni sekilde. Payload klasoru CI tarafindan
; build\windows\x64\runner\Release + NetworkConsole-Agent.exe + ikon
; ile PAYLOAD_DIR degiskeninde saglanir; yerel test icin varsayilan yol
; asagida.
#ifndef MyAppVersion
  #define MyAppVersion "2.0.1"
#endif
#ifndef PayloadDir
  #define PayloadDir "..\build\windows\x64\runner\Release"
#endif

[Setup]
AppId={{B7B6C6C0-6E1E-4C0D-9C4B-0A6F5A8F0E20}
AppName=Network Console
AppVersion={#MyAppVersion}
AppPublisher=Network Console
DefaultDirName={localappdata}\Programs\NetworkConsole2
DefaultGroupName=Network Console
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputBaseFilename=Network_Console_{#MyAppVersion}_windows_Setup
OutputDir=..\..\dist2
Compression=lzma2
SolidCompression=yes
SetupIconFile=..\..\network-console-icon.ico
UninstallDisplayIcon={app}\network_console_app.exe
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Files]
Source: "{#PayloadDir}\*"; DestDir: "{app}"; Flags: recursesubdirs ignoreversion

[Icons]
Name: "{group}\Network Console"; Filename: "{app}\network_console_app.exe"
Name: "{userdesktop}\Network Console"; Filename: "{app}\network_console_app.exe"

[Run]
Filename: "{app}\network_console_app.exe"; Description: "Launch Network Console"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
Type: filesandordirs; Name: "{app}"
