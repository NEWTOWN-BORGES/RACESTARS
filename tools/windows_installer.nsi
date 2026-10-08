Unicode true
!include "MUI2.nsh"

!ifndef APP_VERSION
  !define APP_VERSION "0.7"
!endif
!ifndef PAYLOAD_DIR
  !error "Use tools/package_windows.sh to provide the exported Windows files."
!endif
!ifndef PAYLOAD_UNINSTALL
  !error "The generated uninstall file list is required."
!endif
!ifndef OUTPUT_FILE
  !error "OUTPUT_FILE is required."
!endif

Name "RACESTARS ${APP_VERSION}"
OutFile "${OUTPUT_FILE}"
InstallDir "$LOCALAPPDATA\RACESTARS"
InstallDirRegKey HKCU "Software\RACESTARS" "InstallDir"
RequestExecutionLevel user
SetCompressor /SOLID lzma
ShowInstDetails show
ShowUninstDetails show

!define MUI_ABORTWARNING
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_UNPAGE_FINISH
!insertmacro MUI_LANGUAGE "PortugueseBR"

Section "RACESTARS" Main
  SetShellVarContext current
  SetOutPath "$INSTDIR"
  File /r "${PAYLOAD_DIR}/*"
  WriteUninstaller "$INSTDIR\Uninstall.exe"

  CreateDirectory "$SMPROGRAMS\RACESTARS"
  CreateShortcut "$SMPROGRAMS\RACESTARS\RACESTARS.lnk" "$INSTDIR\RACESTARS.exe"
  CreateShortcut "$SMPROGRAMS\RACESTARS\Desinstalar RACESTARS.lnk" "$INSTDIR\Uninstall.exe"
  CreateShortcut "$DESKTOP\RACESTARS.lnk" "$INSTDIR\RACESTARS.exe"

  WriteRegStr HKCU "Software\RACESTARS" "InstallDir" "$INSTDIR"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\RACESTARS" "DisplayName" "RACESTARS"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\RACESTARS" "DisplayVersion" "${APP_VERSION}"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\RACESTARS" "DisplayIcon" "$INSTDIR\RACESTARS.exe"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\RACESTARS" "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\RACESTARS" "UninstallString" '$\"$INSTDIR\Uninstall.exe$\"'
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\RACESTARS" "QuietUninstallString" '$\"$INSTDIR\Uninstall.exe$\" /S'
  WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\RACESTARS" "NoModify" 1
  WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\RACESTARS" "NoRepair" 1
  WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\RACESTARS" "EstimatedSize" ${PAYLOAD_KIB}
SectionEnd

Section "Uninstall"
  SetShellVarContext current
  ; Delete only files shipped in this build; leave any user-created files alone.
  !include "${PAYLOAD_UNINSTALL}"
  Delete "$INSTDIR\Uninstall.exe"
  RMDir "$INSTDIR"
  Delete "$DESKTOP\RACESTARS.lnk"
  Delete "$SMPROGRAMS\RACESTARS\RACESTARS.lnk"
  Delete "$SMPROGRAMS\RACESTARS\Desinstalar RACESTARS.lnk"
  RMDir "$SMPROGRAMS\RACESTARS"
  DeleteRegKey HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\RACESTARS"
  DeleteRegKey HKCU "Software\RACESTARS"
SectionEnd
