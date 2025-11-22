; 泡泡单词 Windows 安装程序脚本
; 使用 NSIS (Nullsoft Scriptable Install System) 创建
; 注意：此文件必须使用 UTF-8 with BOM 编码以确保中文正确显示

; Unicode 模式（NSIS 3.x 默认启用，但明确指定以确保兼容性）
Unicode True

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
; 检查许可协议文件是否存在（NSIS 需要纯文本文件，不是 HTML）
!if /FileExists "installer_temp\privacy.txt"
    !insertmacro MUI_PAGE_LICENSE "installer_temp\privacy.txt"
!else
    !error "错误: 未找到 privacy.txt 文件！$\n$\n请确保已运行 create_installer.bat 脚本准备安装文件，$\n脚本会自动从 app\assets\privacy.html 提取纯文本内容。"
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

; 初始化函数（如果需要，可以在这里添加其他初始化逻辑）
Function .onInit
    ; 文件检查已在编译时完成，运行时无需再次检查
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
    
    ; 注意：vc_redist.x64.exe 也会被复制到安装目录，用于后续安装
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
; 默认选中且必需（如果系统未安装）
Section "Visual C++ Redistributable" SecVCRedist
    SectionIn RO  ; 只读，用户无法取消选择
    ; 检查是否已安装 Visual C++ Redistributable
    ReadRegStr $0 HKLM "SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64" "Version"
    StrCmp $0 "" install_vcredist skip_vcredist
    
    install_vcredist:
        ; 如果未安装，则从本地文件安装（已在构建时下载并复制到安装目录）
        IfFileExists "$INSTDIR\vc_redist.x64.exe" 0 vcredist_not_found
            ExecWait '"$INSTDIR\vc_redist.x64.exe" /quiet /norestart'
            Delete "$INSTDIR\vc_redist.x64.exe"
            Goto skip_vcredist
        
        vcredist_not_found:
            MessageBox MB_OK|MB_ICONEXCLAMATION "警告: 未找到 Visual C++ Redistributable 安装程序。$\n$\n程序可能无法正常运行。$\n$\n请访问以下链接手动下载并安装：$\nhttps://aka.ms/vs/17/release/vc_redist.x64.exe"
    
    skip_vcredist:
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
