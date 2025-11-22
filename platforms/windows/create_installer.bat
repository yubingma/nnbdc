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
    REM 验证文件是否成功复制
    if not exist "%TEMP_DIR%\privacy.html" (
        echo [ERROR] privacy.html 复制失败！
        goto cleanup
    )
    
    REM 从 HTML 提取纯文本内容，创建 .txt 文件供 NSIS 使用
    echo [INFO] 正在从 HTML 提取纯文本内容...
    powershell -Command "$html = Get-Content '%TEMP_DIR%\privacy.html' -Raw -Encoding UTF8; $html = $html -replace '<[^>]+>', ''; $html = $html -replace '&nbsp;', ' '; $html = $html -replace '&lt;', '<'; $html = $html -replace '&gt;', '>'; $html = $html -replace '&amp;', '&'; $html = $html.Trim(); [System.IO.File]::WriteAllText('%TEMP_DIR%\privacy.txt', $html, [System.Text.Encoding]::UTF8)"
    if errorlevel 1 (
        echo [WARN] 无法使用 PowerShell 提取文本，将创建简单的文本版本
        REM 如果 PowerShell 失败，创建一个简单的文本版本
        echo 泡泡单词用户隐私政策 > "%TEMP_DIR%\privacy.txt"
        echo. >> "%TEMP_DIR%\privacy.txt"
        echo 请访问应用程序内的隐私政策页面查看完整内容。 >> "%TEMP_DIR%\privacy.txt"
    ) else (
        echo [INFO] 已创建纯文本版本: privacy.txt
    )
) else (
    echo [WARN] privacy.html 文件不存在，将创建默认许可协议
    echo 泡泡单词用户隐私政策 > "%TEMP_DIR%\privacy.txt"
    echo. >> "%TEMP_DIR%\privacy.txt"
    echo 请访问官方网站获取最新隐私政策。 >> "%TEMP_DIR%\privacy.txt"
)

REM 最终验证 privacy.txt 是否存在（NSIS 需要 .txt 文件）
if not exist "%TEMP_DIR%\privacy.txt" (
    echo [ERROR] privacy.txt 文件不存在于临时目录中！
    echo [ERROR] 无法继续编译安装程序
    goto cleanup
)

echo [INFO] 编译 NSIS 安装脚本...
echo [INFO] 当前目录: %CD%
echo [INFO] 临时目录内容:
dir "%TEMP_DIR%" /B

REM 再次确认关键文件存在（NSIS 需要 .txt 文件）
if not exist "%TEMP_DIR%\privacy.txt" (
    echo [ERROR] 错误: privacy.txt 文件不存在于 installer_temp 目录中！
    echo [ERROR] 无法继续编译安装程序
    goto cleanup
)

makensis installer.nsi
if errorlevel 1 (
    echo [ERROR] NSIS 编译失败
    echo [INFO] 请检查以下文件是否存在:
    echo   - installer_temp\logo.png
    echo   - installer_temp\privacy.txt
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
