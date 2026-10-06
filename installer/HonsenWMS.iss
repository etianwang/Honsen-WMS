; Compile with: ISCC.exe /DAppVersion=1.2.4 installer\HonsenWMS.iss
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
  RegisteredView: Integer;
  ExistingLocation: String;
  ExistingVersion: String;
  ExistingDamaged: Boolean;

function SamePath(const Left, Right: String): Boolean;
begin
  Result := CompareText(RemoveBackslashUnlessRoot(ExpandFileName(Left)), RemoveBackslashUnlessRoot(ExpandFileName(Right))) = 0;
end;

function ReadRegisteredLocation(Root, View: Integer; var Location: String): Boolean;
var
  RegisteredId, ExecutablePath: String;
begin
  SetRegView(View);
  Result := RegQueryStringValue(Root, HonsenKey, 'AppId', RegisteredId) and
            (RegisteredId = '{#AppId}') and
            RegQueryStringValue(Root, HonsenKey, 'InstallLocation', Location);
  if Result then begin
    RegQueryStringValue(Root, HonsenKey, 'Version', ExistingVersion);
    ExistingDamaged := not RegQueryStringValue(Root, HonsenKey, 'ExecutablePath', ExecutablePath) or not FileExists(ExecutablePath);
  end;
end;

function FindExistingInRoot(Root: Integer): Boolean;
begin
  Result := False;
  if IsWin64 then
    Result := ReadRegisteredLocation(Root, 64, ExistingLocation);
  if Result then begin
    RegisteredRoot := Root;
    RegisteredView := 64;
    exit;
  end;
  Result := ReadRegisteredLocation(Root, 32, ExistingLocation);
  if Result then begin
    RegisteredRoot := Root;
    RegisteredView := 32;
  end;
end;

function FindExistingRegistration(): Boolean;
begin
  Result := FindExistingInRoot(HKLM);
  if not Result then
    Result := FindExistingInRoot(HKCU);
end;

function InitializeSetup(): Boolean;
var
  RequestedDirectory: String;
begin
  Result := True;
  if FindExistingRegistration() then begin
    RequestedDirectory := ExpandConstant('{param:DIR}');
    if (RequestedDirectory <> '') and not SamePath(RequestedDirectory, ExistingLocation) then begin
      SuppressibleMsgBox('{#AppName} ' + ExistingVersion + ' is already installed at ' + ExistingLocation + '. Update or repair must use that directory.', mbError, MB_OK, IDOK);
      Result := False;
    end;
    if ExistingDamaged then
      SuppressibleMsgBox('{#AppName} has a damaged installation at ' + ExistingLocation + '. Only repair in that directory is allowed.', mbInformation, MB_OK, IDOK);
  end else if IsAdminInstallMode then
    RegisteredRoot := HKLM
  else
    RegisteredRoot := HKCU;
  if ExistingLocation = '' then begin
    if IsWin64 then
      RegisteredView := 64
    else
      RegisteredView := 32;
  end;
  SetRegView(RegisteredView);
end;

function DefaultInstallDir(Param: String): String;
begin
  if ExistingLocation <> '' then
    Result := ExistingLocation
  else
    Result := ExpandConstant('{autopf}\Honsen Program\Honsen WMS');
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
  SetRegView(RegisteredView);
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

procedure RemoveHonsenRegistration(Root, View: Integer);
var
  InstallLocation: String;
begin
  SetRegView(View);
  if RegQueryStringValue(Root, HonsenKey, 'InstallLocation', InstallLocation) and
     SamePath(InstallLocation, ExpandConstant('{app}')) then
    RegDeleteKeyIncludingSubkeys(Root, HonsenKey);
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usUninstall then begin
    RemoveHonsenRegistration(HKCU, 32);
    RemoveHonsenRegistration(HKLM, 32);
    if IsWin64 then begin
      RemoveHonsenRegistration(HKCU, 64);
      RemoveHonsenRegistration(HKLM, 64);
    end;
  end;
end;
