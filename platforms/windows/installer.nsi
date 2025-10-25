; 泡泡单词 Windows 安装程序脚本
; 使用 NSIS (Nullsoft Scriptable Install System) 创建

!define APP_NAME "泡泡单词"
!define APP_VERSION "25.10.13"
!define APP_PUBLISHER "泡泡单词团队"
!define APP_URL "http://www.nnbdc.com"
!define APP_EXECUTABLE "nnbdc.exe"
!define APP_ICON "installer_temp\logo.png"

; 安装程序基本设置
Name "${APP_NAME}"
OutFile "nnbdc-setup.exe"
InstallDir "$PROGRAMFILES64\${APP_NAME}"
InstallDirRegKey HKLM "Software\${APP_NAME}" "Install_Dir"
RequestExecutionLevel admin

; 界面设置
!include "MUI2.nsh"

; 检查图标文件是否存在，如果不存在则使用默认图标
!ifdef APP_ICON
    !if /FileExists "${APP_ICON}"
        !define MUI_ICON "${APP_ICON}"
        !define MUI_UNICON "${APP_ICON}"
    !else
        !warning "图标文件不存在: ${APP_ICON}"
    !endif
!endif

!define MUI_HEADERIMAGE

; 检查头部图像是否存在
!if /FileExists "installer_temp\logo.png"
    !define MUI_HEADERIMAGE_BITMAP "installer_temp\logo.png"
    !define MUI_WELCOMEFINISHPAGE_BITMAP "installer_temp\logo.png"
!else
    !warning "头部图像文件不存在: installer_temp\logo.png"
!endif

; 安装程序页面
!insertmacro MUI_PAGE_WELCOME
; 检查许可协议文件是否存在
!if /FileExists "installer_temp\privacy.html"
    !insertmacro MUI_PAGE_LICENSE "installer_temp\privacy.html"
!else
    !warning "许可协议文件不存在，跳过许可协议页面"
!endif
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

; 卸载程序页面
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

; 语言设置
!insertmacro MUI_LANGUAGE "SimpChinese"

; 安装程序信息
VIProductVersion "${APP_VERSION}.0"
VIAddVersionKey "ProductName" "${APP_NAME}"
VIAddVersionKey "ProductVersion" "${APP_VERSION}"
VIAddVersionKey "CompanyName" "${APP_PUBLISHER}"
VIAddVersionKey "FileDescription" "${APP_NAME} 安装程序"
VIAddVersionKey "FileVersion" "${APP_VERSION}"

; 检查必要文件是否存在
Function .onInit
    ; 检查 logo.png 是否存在
    IfFileExists "installer_temp\logo.png" +3
        MessageBox MB_ICONINFORMATION "信息: 未找到 logo.png 文件，将使用默认图标"
    ; 检查 privacy.html 是否存在
    IfFileExists "installer_temp\privacy.html" +3
        MessageBox MB_ICONINFORMATION "信息: 未找到 privacy.html 文件，将跳过许可协议页面"
FunctionEnd

; 安装程序段
Section "主程序" SecMain
    ; 检查是否已安装旧版本
    ReadRegStr $0 HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_NAME}" "DisplayVersion"
    StrCmp $0 "" 0 +3
        ; 新安装
        SetOutPath "$INSTDIR"
        Goto install_files
        ; 升级安装
        SetOutPath "$INSTDIR"
        
    install_files:
    ; 复制应用程序文件
    File /r "installer_temp\*"
    
    ; 创建开始菜单快捷方式
    CreateDirectory "$SMPROGRAMS\${APP_NAME}"
    CreateShortCut "$SMPROGRAMS\${APP_NAME}\${APP_NAME}.lnk" "$INSTDIR\${APP_EXECUTABLE}" "" "$INSTDIR\${APP_EXECUTABLE}" 0
    CreateShortCut "$SMPROGRAMS\${APP_NAME}\卸载.lnk" "$INSTDIR\uninstall.exe"
    
    ; 创建桌面快捷方式
    CreateShortCut "$DESKTOP\${APP_NAME}.lnk" "$INSTDIR\${APP_EXECUTABLE}" "" "$INSTDIR\${APP_EXECUTABLE}" 0
    
    ; 写入注册表信息
    WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_NAME}" "DisplayName" "${APP_NAME}"
    WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_NAME}" "UninstallString" "$INSTDIR\uninstall.exe"
    WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_NAME}" "InstallLocation" "$INSTDIR"
    WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_NAME}" "DisplayVersion" "${APP_VERSION}"
    WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_NAME}" "Publisher" "${APP_PUBLISHER}"
    WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_NAME}" "URLInfoAbout" "${APP_URL}"
    WriteRegDWORD HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_NAME}" "NoModify" 1
    WriteRegDWORD HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_NAME}" "NoRepair" 1
    
    ; 创建卸载程序
    WriteUninstaller "$INSTDIR\uninstall.exe"
SectionEnd

; Visual C++ Redistributable 安装段
Section "Visual C++ Redistributable" SecVCRedist
    ; 检查是否已安装 Visual C++ Redistributable
    ReadRegStr $0 HKLM "SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64" "Version"
    StrCmp $0 "" 0 +3
        ; 如果未安装，则下载并安装
        inetc::get "https://aka.ms/vs/17/release/vc_redist.x64.exe" "$TEMP\vc_redist.x64.exe"
        ExecWait "$TEMP\vc_redist.x64.exe /quiet /norestart"
        Delete "$TEMP\vc_redist.x64.exe"
SectionEnd

; 安装程序描述
!insertmacro MUI_FUNCTION_DESCRIPTION_BEGIN
    !insertmacro MUI_DESCRIPTION_TEXT ${SecMain} "安装 ${APP_NAME} 主程序文件"
    !insertmacro MUI_DESCRIPTION_TEXT ${SecVCRedist} "安装 Visual C++ Redistributable（如果系统未安装）"
!insertmacro MUI_FUNCTION_DESCRIPTION_END

; 卸载程序段
Section "Uninstall"
    ; 删除文件
    RMDir /r "$INSTDIR"
    
    ; 删除开始菜单快捷方式
    Delete "$SMPROGRAMS\${APP_NAME}\${APP_NAME}.lnk"
    Delete "$SMPROGRAMS\${APP_NAME}\卸载.lnk"
    RMDir "$SMPROGRAMS\${APP_NAME}"
    
    ; 删除桌面快捷方式
    Delete "$DESKTOP\${APP_NAME}.lnk"
    
    ; 删除注册表项
    DeleteRegKey HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_NAME}"
    DeleteRegKey HKLM "Software\${APP_NAME}"
SectionEnd
