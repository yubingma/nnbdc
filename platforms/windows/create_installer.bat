@echo off
REM 本地创建 Windows 安装包脚本
REM 需要先安装 NSIS: https://nsis.sourceforge.io/Download

setlocal enabledelayedexpansion

echo [INFO] ======== 创建 Windows 安装包 ========
echo.

REM 检查 NSIS 是否安装
where makensis >nul 2>&1
if errorlevel 1 (
    echo [ERROR] NSIS 未安装或不在 PATH 中
    echo 请从 https://nsis.sourceforge.io/Download 下载并安装 NSIS
    pause
    exit /b 1
)

REM 检查 Flutter 构建文件是否存在
if not exist "..\..\app\build\windows\x64\runner\Release\nnbdc.exe" (
    echo [ERROR] Flutter Windows 构建文件不存在
    echo 请先运行: cd ../../app && flutter build windows --release
    pause
    exit /b 1
)

REM 创建临时目录
set "TEMP_DIR=%~dp0installer_temp"
if exist "%TEMP_DIR%" rd /s /q "%TEMP_DIR%"
mkdir "%TEMP_DIR%"

echo [INFO] 复制构建文件...
xcopy "..\..\app\build\windows\x64\runner\Release\*" "%TEMP_DIR%\" /E /I /Y

REM 复制资源文件（如果存在）
if exist "..\..\app\assets\images\logo.png" (
    copy "..\..\app\assets\images\logo.png" "%TEMP_DIR%\logo.png"
    echo [INFO] 复制了 logo.png
) else (
    echo [WARN] logo.png 文件不存在，将创建占位符
    echo [INFO] 请确保 logo.png 文件存在于 app\assets\images\ 目录中
)

if exist "..\..\app\assets\privacy.html" (
    copy "..\..\app\assets\privacy.html" "%TEMP_DIR%\privacy.html"
    echo [INFO] 复制了 privacy.html
) else (
    echo [WARN] privacy.html 文件不存在，将创建默认许可协议
    echo ^<!DOCTYPE html^> > "%TEMP_DIR%\privacy.html"
    echo ^<html^>^<head^>^<title^>隐私政策^</title^>^</head^> >> "%TEMP_DIR%\privacy.html"
    echo ^<body^>^<h1^>隐私政策^</h1^>^<p^>请访问官方网站获取最新隐私政策。^</p^>^</body^>^</html^> >> "%TEMP_DIR%\privacy.html"
)

echo [INFO] 编译 NSIS 安装脚本...
echo [INFO] 当前目录: %CD%
echo [INFO] 临时目录内容:
dir "%TEMP_DIR%" /B

makensis installer.nsi
if errorlevel 1 (
    echo [ERROR] NSIS 编译失败
    echo [INFO] 请检查以下文件是否存在:
    echo   - installer_temp\logo.png
    echo   - installer_temp\privacy.html
    echo   - 所有应用程序文件
    goto cleanup
)

if exist "nnbdc-setup.exe" (
    echo [INFO] 安装包创建成功: nnbdc-setup.exe
    echo [INFO] 文件大小: 
    dir nnbdc-setup.exe | find "nnbdc-setup.exe"
) else (
    echo [ERROR] 安装包文件未生成
)

:cleanup
REM 清理临时文件
if exist "%TEMP_DIR%" rd /s /q "%TEMP_DIR%"

echo.
echo [INFO] 安装包创建完成
pause
exit /b 0
