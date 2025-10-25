@echo off
REM 部署修复脚本 - 解决 CI/CD 环境中的文件复制问题
REM 特别针对 ver.json 文件复制错误

setlocal enabledelayedexpansion

echo [INFO] ======== 部署修复脚本 ========
echo.

REM 检查 PowerShell 是否可用
where powershell >nul 2>&1
if errorlevel 1 (
    echo [ERROR] PowerShell 未找到
    exit /b 1
)

REM 使用 PowerShell 脚本修复文件复制问题
echo [INFO] 使用 PowerShell 修复文件复制问题...
powershell -ExecutionPolicy Bypass -File "fix-deploy-script.ps1"

if errorlevel 1 (
    echo [ERROR] PowerShell 脚本执行失败
    exit /b 1
)

echo [INFO] 部署修复完成
exit /b 0
