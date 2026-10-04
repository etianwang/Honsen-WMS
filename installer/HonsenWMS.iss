#pragma charset "utf-8"
; Compile with: ISCC.exe /DAppVersion=1.2.1 installer\HonsenWMS.iss
#ifndef AppVersion
  #error AppVersion must be supplied by the build script.
#endif

#define AppName "Honsen WMS"
#define AppId "honsen.wms"
#define AppExeName "Honsen海外仓库管理同步版.exe"

[Setup]
AppId={{D042C6D9-3395-4C57-9CA6-3DC0B152C911}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher=Honsen
DefaultDirName={autopf}\Honsen WMS
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
OutputDir=..\dist
OutputBaseFilename=HonsenWMS-{#AppVersion}-Setup
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64compatible
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
UninstallDisplayName={#AppName}

[Files]
Source: "..\dist\{#AppExeName}"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\dist\honsen.app.json"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExeName}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"

[Run]
Filename: "{app}\{#AppExeName}"; Description: "Launch {#AppName}"; Flags: nowait postinstall skipifsilent

[Code]
const
  HonsenKey = 'Software\Honsen Program\Apps\{#AppId}';

function HonsenRoot(): Integer;
begin
  if IsAdminInstallMode then
    Result := HKLM
  else
    Result := HKCU;
end;

procedure WriteHonsenValue(const Name, Value: String);
begin
  RegWriteStringValue(HonsenRoot(), HonsenKey, Name, Value);
end;

procedure RegisterHonsenApp();
var
  Scope: String;
begin
  if IsAdminInstallMode then
    Scope := 'machine'
  else
    Scope := 'user';

  WriteHonsenValue('AppId', '{#AppId}');
  WriteHonsenValue('DisplayName', '{#AppName}');
  WriteHonsenValue('Version', '{#AppVersion}');
  WriteHonsenValue('InstallLocation', ExpandConstant('{app}'));
  WriteHonsenValue('ExecutablePath', ExpandConstant('{app}\{#AppExeName}'));
  WriteHonsenValue('InstallScope', Scope);
  WriteHonsenValue('Publisher', 'Honsen');
  WriteHonsenValue('UpdateManifestUrl', '');
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
    RegisterHonsenApp();
end;

procedure RemoveHonsenRegistration(Root: Integer);
var
  InstallLocation: String;
begin
  if RegQueryStringValue(Root, HonsenKey, 'InstallLocation', InstallLocation) and
     (CompareText(InstallLocation, ExpandConstant('{app}')) = 0) then
    RegDeleteKeyIncludingSubkeys(Root, HonsenKey);
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usUninstall then begin
    RemoveHonsenRegistration(HKCU);
    RemoveHonsenRegistration(HKLM);
  end;
end;
