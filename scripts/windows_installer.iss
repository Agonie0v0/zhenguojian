#ifndef AppVersion
  #define AppVersion "0.7.21"
#endif
#ifndef AppBuild
  #define AppBuild "81"
#endif
#define AppName "真果鉴"
#define BundleDir SourcePath + "..\build\windows\x64\runner\Release"
#if !FileExists(BundleDir + "\duanju_core.dll") || !FileExists(BundleDir + "\flutter_windows.dll") || !FileExists(BundleDir + "\libffmpegkit.dll") || !FileExists(BundleDir + "\libmpv-2.dll") || !FileExists(BundleDir + "\data\app.so")
  #error "Build and package the complete Windows release bundle first."
#endif

[Setup]
AppId={{51FC34E7-8A5C-45E0-9A38-C511B3F9B1D6}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher=真果鉴开源项目
AppPublisherURL=https://github.com/Agonie0v0/zhenguojian
AppSupportURL=https://github.com/Agonie0v0/zhenguojian/issues
VersionInfoVersion={#AppVersion}.{#AppBuild}
DefaultDirName={localappdata}\Programs\Zhenguojian
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.22000
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\zhenguojian.exe
OutputDir=..\dist\windows
OutputBaseFilename=zhenguojian-{#AppVersion}-windows-x64-setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Shortcuts:"; Flags: unchecked

[Files]
Source: "{#BundleDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\LICENSE"; DestDir: "{app}"; DestName: "LICENSE.txt"; Flags: ignoreversion

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\zhenguojian.exe"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\zhenguojian.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\zhenguojian.exe"; Description: "Launch {#AppName}"; Flags: nowait postinstall skipifsilent
