#pragma charset "utf-8"
; Compile with: ISCC.exe /DAppVersion=1.2.3 installer\HonsenWMS.iss
#ifndef AppVersion
  #error AppVersion must be supplied by the build script.
#endif

#define AppName "Honsen WMS"
#define AppId "honsen.wms"
#define AppExeName "Honsen海外仓库管理同步版.exe"
#define RunnerExeName "HonsenUpdateRunner.exe"
#define UpdateUrl "https://api.github.com/repos/etianwang/Honsen-WMS/releases/latest"

[Setup]
AppId={{D042C6D9-3395-4C57-9CA6-3DC0B152C911}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher=Honsen
DefaultDirName={code:DefaultInstallDir}
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
Source: "..\dist\{#RunnerExeName}"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\dist\honsen.app.json"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#RunnerExeName}"; Parameters: "launch --app-id {#AppId} --source shell"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#RunnerExeName}"; Parameters: "launch --app-id {#AppId} --source shell"; IconFilename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"

[Run]
Filename: "{app}\{#RunnerExeName}"; Parameters: "launch --app-id {#AppId} --source installer"; Description: "Launch {#AppName}"; Flags: nowait postinstall skipifsilent

[Code]
const
  HonsenKey = 'Software\Honsen Program\Apps\{#AppId}';
  UpdateUrl = '{#UpdateUrl}';

var
  RegisteredRoot: Integer;
  ExistingLocation: String;

function SamePath(const Left, Right: String): Boolean;
begin
  Result := CompareText(RemoveBackslashUnlessRoot(ExpandFileName(Left)), RemoveBackslashUnlessRoot(ExpandFileName(Right))) = 0;
end;

function ReadRegisteredLocation(Root: Integer; var Location: String): Boolean;
var
  RegisteredId: String;
begin
  Result := RegQueryStringValue(Root, HonsenKey, 'AppId', RegisteredId) and
            (RegisteredId = '{#AppId}') and
            RegQueryStringValue(Root, HonsenKey, 'InstallLocation', Location);
end;

function FindExistingRegistration(): Boolean;
begin
  Result := ReadRegisteredLocation(HKLM, ExistingLocation);
  if Result then begin
    RegisteredRoot := HKLM;
    exit;
  end;
  Result := ReadRegisteredLocation(HKCU, ExistingLocation);
  if Result then
    RegisteredRoot := HKCU;
end;

function InitializeSetup(): Boolean;
var
  RequestedDirectory: String;
begin
  Result := True;
  if FindExistingRegistration() then begin
    RequestedDirectory := ExpandConstant('{param:DIR}');
    if (RequestedDirectory <> '') and not SamePath(RequestedDirectory, ExistingLocation) then begin
      SuppressibleMsgBox('{#AppName} is already installed at ' + ExistingLocation + '. Update or repair must use that directory.', mbError, MB_OK, IDOK);
      Result := False;
    end;
  end else if IsAdminInstallMode then
    RegisteredRoot := HKLM
  else
    RegisteredRoot := HKCU;
end;

function DefaultInstallDir(Param: String): String;
begin
  if ExistingLocation <> '' then
    Result := ExistingLocation
  else
    Result := ExpandConstant('{autopf}\Honsen Program\Honsen WMS');
end;

procedure InitializeWizard();
begin
  if ExistingLocation <> '' then
    WizardDirValue := ExistingLocation;
end;

function NextButtonClick(CurPageID: Integer): Boolean;
begin
  Result := True;
  if (CurPageID = wpSelectDir) and (ExistingLocation <> '') and not SamePath(WizardDirValue, ExistingLocation) then begin
    MsgBox('Existing Honsen WMS installations can only be updated or repaired in their original directory.', mbError, MB_OK);
    Result := False;
  end;
end;

function HonsenRoot(): Integer;
begin
  Result := RegisteredRoot;
end;

procedure WriteHonsenValue(const Name, Value: String);
begin
  RegWriteStringValue(HonsenRoot(), HonsenKey, Name, Value);
end;

procedure RegisterHonsenApp();
var
  Scope: String;
begin
  if HonsenRoot() = HKLM then
    Scope := 'machine'
  else
    Scope := 'user';

  WriteHonsenValue('AppId', '{#AppId}');
  WriteHonsenValue('DisplayName', '{#AppName}');
  WriteHonsenValue('Version', '{#AppVersion}');
  WriteHonsenValue('InstallLocation', ExpandConstant('{app}'));
  WriteHonsenValue('ExecutablePath', ExpandConstant('{app}\{#AppExeName}'));
  WriteHonsenValue('LauncherPath', ExpandConstant('{app}\{#RunnerExeName}'));
  WriteHonsenValue('UpdateRunnerPath', ExpandConstant('{app}\{#RunnerExeName}'));
  WriteHonsenValue('InstallScope', Scope);
  WriteHonsenValue('Publisher', 'Honsen');
  WriteHonsenValue('UpdateManifestUrl', UpdateUrl);
  WriteHonsenValue('UpdateUrl', UpdateUrl);
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
