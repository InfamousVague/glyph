; Ghost Messaging for Windows: the installer (Matt, 2026-11-14: "Add a mac and windows build to ghost-sms.com").
; Built by .github/workflows/messaging-windows.yml after `flutter build windows`, with the version passed in:
;   iscc /DAppVersion=0.7.21 /DSource=build\windows\x64\runner\Release windows\installer.iss
; It installs for the person alone (no administrator), into their own Programs folder, with a Start menu entry and
; an uninstaller; running a newer one over it updates it in place, which the app does itself (silently, then
; reopened) when the person chooses Restart to update. The AppId stays the same for every version.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef Source
  #define Source "build\windows\x64\runner\Release"
#endif

[Setup]
AppId={{B97205D6-26C4-4B1D-B648-5E26BB43325D}
AppName=Ghost Messaging
AppVersion={#AppVersion}
AppVerName=Ghost Messaging {#AppVersion}
AppPublisher=MattsSoftware
AppPublisherURL=https://ghost-sms.com
AppSupportURL=https://ghost-sms.com
DefaultDirName={localappdata}\Programs\Ghost Messaging
DefaultGroupName=Ghost Messaging
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=..\build\windows-installer
OutputBaseFilename=ghost-messaging-setup
SetupIconFile=runner\resources\app_icon.ico
UninstallDisplayIcon={app}\ghost_messaging.exe
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
CloseApplications=yes

[Tasks]
Name: "desktopicon"; Description: "Put Ghost Messaging on the desktop"; GroupDescription: "Shortcuts:"; Flags: unchecked

[Files]
Source: "..\{#Source}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Ghost Messaging"; Filename: "{app}\ghost_messaging.exe"
Name: "{userdesktop}\Ghost Messaging"; Filename: "{app}\ghost_messaging.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\ghost_messaging.exe"; Description: "Open Ghost Messaging"; Flags: nowait postinstall skipifsilent
; The app's own update (lib/desktop/updates.dart, WindowsUpdateHost) runs this silently with /RELAUNCH and quits:
; open it again. Any other silent install (the build's own check) leaves it closed.
Filename: "{app}\ghost_messaging.exe"; Flags: nowait runasoriginaluser; Check: Relaunch

[Code]
function Relaunch: Boolean;
begin
  Result := WizardSilent and (Pos('/RELAUNCH', Uppercase(GetCmdTail)) > 0);
end;
