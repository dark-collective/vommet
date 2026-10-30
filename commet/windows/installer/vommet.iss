; Vommet: the Windows installer (Inno Setup 6). CI builds it from the
; `flutter build windows` output next to the portable zip:
;   iscc /DAppVersion=<label> /DSourceDir=<...\runner\Release> /O<out> vommet.iss
;
; A per-user install (no admin prompt) into %LOCALAPPDATA%\Programs\Vommet with
; a Start menu entry, a desktop shortcut and an entry in Windows' Apps list.
; Vommet's data lives in %APPDATA%\nether.im\Vommet, not here, so installing,
; updating or uninstalling never touches the account.
;
; Vommet updates itself by running this installer (ReleaseUpdate.runInstaller):
;   installed copy:  /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /RELAUNCH=1
;                    no windows; starts Vommet again when done.
;   portable zip:    /OLDDIR=<folder of the running vommet.exe>
;                    the normal wizard; afterwards it offers to remove that
;                    folder's Vommet files and desktop shortcuts to its exe.

#ifndef AppVersion
  #define AppVersion "dev"
#endif
#ifndef SourceDir
  #define SourceDir "..\..\build\windows\x64\runner\Release"
#endif

[Setup]
AppId={{B0765DB1-DF41-4427-9077-50793C3CA441}
AppName=Vommet
AppVersion={#AppVersion}
AppVerName=Vommet {#AppVersion}
AppPublisher=nether.im
AppPublisherURL=https://vommet.app
AppSupportURL=https://vommet.app
VersionInfoVersion=1.0.0.0
DefaultDirName={localappdata}\Programs\Vommet
DisableDirPage=auto
DisableProgramGroupPage=yes
DisableReadyPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputBaseFilename=vommet-windows-x64-setup
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\vommet.exe
UninstallDisplayName=Vommet
WizardStyle=modern
Compression=lzma2
SolidCompression=yes
; Vommet closes itself before an update; Restart Manager closes anything of it
; still running (another window, a crashed copy). Vommet is started again by
; [Run] below, not by Restart Manager.
CloseApplications=force
RestartApplications=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[CustomMessages]
english.RemoveOldFolder=Vommet is installed now. Remove the old copy in%n%n%1%n%nand its desktop shortcuts? Your account and settings stay.

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[InstallDelete]
; Flutter's assets folder: replace it whole so no file of an older release
; is left behind.
Type: filesandordirs; Name: "{app}\data"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Vommet"; Filename: "{app}\vommet.exe"
Name: "{autodesktop}\Vommet"; Filename: "{app}\vommet.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\vommet.exe"; Description: "{cm:LaunchProgram,Vommet}"; Flags: nowait postinstall skipifsilent
Filename: "{app}\vommet.exe"; Flags: nowait; Check: Relaunch

[Code]
function Relaunch: Boolean;
begin
  Result := WizardSilent and (ExpandConstant('{param:relaunch|0}') = '1');
end;

{ Desktop shortcuts that start the old portable vommet.exe. }
procedure RemoveOldShortcuts(const OldExe: String);
var
  FindRec: TFindRec;
  Shell, Link: Variant;
  Dir, Path: String;
begin
  Dir := ExpandConstant('{userdesktop}');
  try
    Shell := CreateOleObject('WScript.Shell');
  except
    Exit;
  end;
  if FindFirst(Dir + '\*.lnk', FindRec) then
  try
    repeat
      Path := Dir + '\' + FindRec.Name;
      try
        Link := Shell.CreateShortcut(Path);
        if CompareText(Link.TargetPath, OldExe) = 0 then
          DeleteFile(Path);
      except
      end;
    until not FindNext(FindRec);
  finally
    FindClose(FindRec);
  end;
end;

{ Only the files this installer puts in the install folder (by name) and Flutter's data
  folder: the old folder may hold other things of the user's, which stay. The
  folder itself goes only if that leaves it empty. }
procedure RemoveOldFolder(const Old: String);
var
  FindRec: TFindRec;
begin
  if FindFirst(ExpandConstant('{app}') + '\*', FindRec) then
  try
    repeat
      if (FindRec.Attributes and FILE_ATTRIBUTE_DIRECTORY) = 0 then
        DeleteFile(Old + '\' + FindRec.Name);
    until not FindNext(FindRec);
  finally
    FindClose(FindRec);
  end;
  if DirExists(Old + '\data\flutter_assets') then
    DelTree(Old + '\data', True, True, True);
  RemoveDir(Old);
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  Old: String;
begin
  if CurStep <> ssPostInstall then
    Exit;
  Old := RemoveBackslashUnlessRoot(ExpandConstant('{param:olddir|}'));
  if (Old = '') or (Length(Old) <= 3) then
    Exit;
  if not FileExists(Old + '\vommet.exe') then
    Exit;
  if FileExists(Old + '\unins000.exe') then
    Exit;
  if CompareText(Old, RemoveBackslashUnlessRoot(ExpandConstant('{app}'))) = 0 then
    Exit;
  if SuppressibleMsgBox(FmtMessage(CustomMessage('RemoveOldFolder'), [Old]),
      mbConfirmation, MB_YESNO, IDNO) = IDYES then
  begin
    RemoveOldShortcuts(Old + '\vommet.exe');
    RemoveOldFolder(Old);
  end;
end;
