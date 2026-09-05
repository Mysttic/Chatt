; Instalator Windows dla Chatta (Inno Setup 6).
;
; Wersja przenośna (zip) zostaje obok, nie każdy chce cokolwiek instalować.
; Instalator dokłada to, czego zip nie daje: skrót w menu Start, odinstalowanie
; z ustawień systemu i jedno miejsce, w które trafia aktualizacja.
;
; Numer wersji wchodzi z zewnątrz, żeby nie było go w dwóch miejscach:
;   ISCC.exe /DWersja=0.3.0 windows\installer\chatt.iss
;
; Katalog z buildem można nadpisać (domyślnie ten z `flutter build windows`):
;   /DZrodlo=..\..\build\windows\x64\runner\Release

#ifndef Wersja
  #define Wersja "0.0.0"
#endif
#ifndef Zrodlo
  #define Zrodlo "..\..\build\windows\x64\runner\Release"
#endif

[Setup]
AppId={{7C2F1B54-9E0B-4E52-9C6E-3B4D2A8F1E77}
AppName=Chatt
AppVersion={#Wersja}
AppPublisher=Mysttic
AppSupportURL=https://github.com/Mysttic/Chatt
DefaultDirName={autopf}\Chatt
DefaultGroupName=Chatt
; Bez pytania o katalog menu Start: aplikacja ma jeden skrót i nic więcej.
DisableProgramGroupPage=yes
; Instalacja dla użytkownika, nie dla całego komputera, dzięki temu nie ma
; okna UAC, a autostart (wpis w HKCU) i tak dotyczy tylko tego konta.
PrivilegesRequired=lowest
OutputDir=..\..\..\dist
OutputBaseFilename=chatt-{#Wersja}-instalator
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\chatt.exe
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
; Bez ArchitecturesAllowed: nazwy identyfikatorów zmieniały się między
; wersjami Inno Setup, a instalacja per-użytkownik i tak ląduje
; w {localappdata}\Programs, gdzie tryb 64-bitowy niczego nie zmienia.
; Windows 11 nie ma wydania 32-bitowego, więc nie ma czego odsiewać.

[Languages]
Name: "polski"; MessagesFile: "compiler:Languages\Polish.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; Cały katalog Release: sam .exe nie wystarczy, obok muszą leżeć biblioteki
; Fluttera, wtyczek i katalog `data` z zasobami.
Source: "{#Zrodlo}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Chatt"; Filename: "{app}\chatt.exe"
Name: "{autodesktop}\Chatt"; Filename: "{app}\chatt.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\chatt.exe"; Description: "{cm:LaunchProgram,Chatt}"; Flags: nowait postinstall skipifsilent

[Code]
// Wpis autostartu zakłada sama aplikacja (HKCU\...\Run), więc przy
// odinstalowaniu trzeba go sprzątnąć: inaczej Windows przy każdym starcie
// próbowałby uruchomić coś, czego już nie ma. Robimy to dopiero przy
// odinstalowaniu: instalacja nie ma prawa wyłączyć komuś autostartu.
//
// Baza i klucz zostają: to dane użytkownika, leżą w Dokumentach i po
// ponownej instalacji historia ma być na miejscu.
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usPostUninstall then
    RegDeleteValue(HKEY_CURRENT_USER,
      'Software\Microsoft\Windows\CurrentVersion\Run', 'Chatt');
end;
