; 泡泡单词 Windows 安装程序脚本
; 使用 NSIS (Nullsoft Scriptable Install System) 创建

!define APP_NAME "泡泡单词"
!define APP_VERSION "25.10.13"
!define APP_PUBLISHER "泡泡单词团队"
!define APP_URL "http://www.nnbdc.com"
!define APP_EXECUTABLE "nnbdc.exe"

; 安装程序基本设置
Name "${APP_NAME}"
OutFile "nnbdc-setup.exe"
InstallDir "$PROGRAMFILES64\${APP_NAME}"
InstallDirRegKey HKLM "Software\${APP_NAME}" "Install_Dir"
RequestExecutionLevel admin

; 界面设置
!include "MUI2.nsh"

; 注意：NSIS 只支持 .ico 格式的图标，PNG 不能用作图标
; 如果需要自定义图标，请提供 .ico 文件并取消下面的注释
; !define MUI_ICON "installer_temp\icon.ico"
; !define MUI_UNICON "installer_temp\icon.ico"

; 注意：NSIS 的头部图像和欢迎页面图像只支持 BMP 格式，不支持 PNG
; 如果需要自定义图像，请将 logo.png 转换为 BMP 格式并取消下面的注释
; !define MUI_HEADERIMAGE
; !define MUI_HEADERIMAGE_BITMAP "installer_temp\logo.bmp"
; !define MUI_WELCOMEFINISHPAGE_BITMAP "installer_temp\logo.bmp"

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
    ; 检查 privacy.html 是否存在（logo.png 用于头部图像，不是必需的）
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
; 注意：由于 inetc 插件在 GitHub Actions 环境中不可用，此功能已禁用
; 如果用户系统缺少 Visual C++ Redistributable，程序运行时会提示安装
; Section "Visual C++ Redistributable" SecVCRedist
;     ; 检查是否已安装 Visual C++ Redistributable
;     ReadRegStr $0 HKLM "SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64" "Version"
;     StrCmp $0 "" 0 +3
;         ; 如果未安装，则提示用户手动下载安装
;         MessageBox MB_OK "系统未检测到 Visual C++ Redistributable。$\n$\n如果程序无法运行，请访问以下链接下载并安装：$\nhttps://aka.ms/vs/17/release/vc_redist.x64.exe"
; SectionEnd

; 安装程序描述
!insertmacro MUI_FUNCTION_DESCRIPTION_BEGIN
    !insertmacro MUI_DESCRIPTION_TEXT ${SecMain} "安装 ${APP_NAME} 主程序文件"
    ; !insertmacro MUI_DESCRIPTION_TEXT ${SecVCRedist} "安装 Visual C++ Redistributable（如果系统未安装）"
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
