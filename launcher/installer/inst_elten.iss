#ifndef SourceDir
#define SourceDir "..\..\dist\windows\Elten"
#endif

#ifndef OutputDir
#define OutputDir "..\..\dist\windows"
#endif

#ifndef OutputBaseFilename
#define OutputBaseFilename "EltenSetup"
#endif

[Setup]
AppId={{9FE2B24B-49F4-4D0B-A36B-31F267F9B114}
AppName=ELTEN
AppVersion=ELTEN 3.0 BETA 15
AppVerName=ELTEN 3.0 BETA 15
AppPublisher=Dawid Pieper
AppPublisherURL=https://elten.link
AppSupportURL=https://elten.link/
AppUpdatesURL=https://elten.link
AppCopyright=Copyright (C) 2014-2021 Dawid Pieper
DefaultDirName={autopf}\ELTEN
DefaultGroupName=ELTEN
AllowNoIcons=yes
OutputDir={#OutputDir}
OutputBaseFilename={#OutputBaseFilename}
Compression=Lzma2/ultra
SolidCompression=yes
RestartIfNeededByRun=no
PrivilegesRequiredOverridesAllowed=commandline dialog
LicenseFile=gpl-3.0.txt
WizardStyle=modern

#define Use_UninsHs_Default_CustomMessages

[InstallDelete]
Type: filesandordirs; Name: "{app}\*"

[Languages]
Name: "en"; MessagesFile: "compiler:Default.isl"
Name: "pl"; MessagesFile: "compiler:Languages\Polish.isl"
Name: "de"; MessagesFile: "compiler:Languages\German.isl"
Name: "fr"; MessagesFile: "compiler:Languages\French.isl"
Name: "ru"; MessagesFile: "compiler:Languages\Russian.isl"
Name: "es"; MessagesFile: "compiler:Languages\Spanish.isl"
Name: "tr"; MessagesFile: "compiler:Languages\Turkish.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}";

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: "ignoreversion createallsubdirs recursesubdirs"

[Icons]
Name: "{group}\ELTEN"; Filename: "{app}\elten.exe"
Name: "{group}\{cm:ProgramOnTheWeb,ELTEN}"; Filename: "https://elten-net.eu"
Name: "{group}\{cm:UninstallProgram,ELTEN}"; Filename: "{uninstallexe}"
Name: "{commondesktop}\ELTEN"; Filename: "{app}\elten.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\elten.exe"; Description: "{cm:LaunchProgram,{#StringChange("ELTEN", '&', '&&')}}"; Flags: nowait postinstall

[INI]
Filename: "{userappdata}\elten\elten.ini"; Section: "Interface"; Key: "Language"; String: "de-DE"; Languages: de
Filename: "{userappdata}\elten\elten.ini"; Section: "Interface"; Key: "Language"; String: "pl-PL"; Languages: pl
Filename: "{userappdata}\elten\elten.ini"; Section: "Interface"; Key: "Language"; String: "fr-FR"; Languages: fr
Filename: "{userappdata}\elten\elten.ini"; Section: "Interface"; Key: "Language"; String: "ru-RU"; Languages: ru
Filename: "{userappdata}\elten\elten.ini"; Section: "Interface"; Key: "Language"; String: "es-PA"; Languages: es
Filename: "{userappdata}\elten\elten.ini"; Section: "Interface"; Key: "Language"; String: "tr-TR"; Languages: tr

