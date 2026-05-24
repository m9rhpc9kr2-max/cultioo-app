[Setup]
AppName=Cultioo
AppVersion={#AppVersion}
AppPublisher=Cultioo
AppPublisherURL=https://cultioo.com
AppSupportURL=https://cultioo.com
AppUpdatesURL=https://cultioo.com
DefaultDirName={autopf}\Cultioo
DefaultGroupName=Cultioo
AllowNoIcons=yes
OutputDir=installer_output
OutputBaseFilename=cultioo_setup
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
Compression=lzma
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "german"; MessagesFile: "compiler:Languages\German.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "release_build\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Cultioo"; Filename: "{app}\cultioo.exe"
Name: "{group}\{cm:UninstallProgram,Cultioo}"; Filename: "{uninstallexe}"
Name: "{commondesktop}\Cultioo"; Filename: "{app}\cultioo.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\cultioo.exe"; Description: "{cm:LaunchProgram,Cultioo}"; Flags: nowait postinstall skipifsilent
