; Builds Zip-Receipt-Setup.exe (Inno Setup). Installs for the current user only, so no admin rights are needed.
[Setup]
AppId={{8C1F3B7E-6A0D-4E2B-9B7C-2F5A1D9E4C31}
AppName=ZIPPY
AppVersion=2.2
AppPublisher=Hands of Hope (HOH)
DefaultDirName={localappdata}\Programs\Zip Receipt
DisableProgramGroupPage=yes
DisableDirPage=yes
PrivilegesRequired=lowest
OutputDir=Output
OutputBaseFilename=Zip-Receipt-Setup
SetupIconFile=AppIcon.ico
UninstallDisplayIcon={app}\ZipReceipt.exe
UninstallDisplayName=ZIPPY
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
CloseApplications=yes

[Tasks]
Name: "desktopicon"; Description: "Put a ZIPPY shortcut on the desktop"; GroupDescription: "Shortcuts:"

[InstallDelete]
; shortcuts from before the rename
Type: files; Name: "{autoprograms}\Zip Receipt.lnk"
Type: files; Name: "{autodesktop}\Zip Receipt.lnk"

[Files]
Source: "publish\ZipReceipt.exe"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\ZIPPY"; Filename: "{app}\ZipReceipt.exe"
Name: "{autodesktop}\ZIPPY"; Filename: "{app}\ZipReceipt.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\ZipReceipt.exe"; Description: "Open ZIPPY"; Flags: nowait postinstall skipifsilent
; after an automatic update (silent install), reopen ZIPPY
Filename: "{app}\ZipReceipt.exe"; Flags: nowait; Check: WizardSilent
