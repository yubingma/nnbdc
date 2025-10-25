# PowerShell 脚本：修复部署过程中的文件复制问题
# 用于解决 ver.json 文件复制错误

param(
    [string]$SourceFile = "ver.json",
    [string]$TargetDir = "deploy",
    [string]$TargetFile = "ver.json"
)

Write-Host "[INFO] 修复部署脚本 - 处理文件复制问题" -ForegroundColor Green

# 检查源文件是否存在
if (-not (Test-Path $SourceFile)) {
    Write-Host "[ERROR] 源文件不存在: $SourceFile" -ForegroundColor Red
    exit 1
}

# 确保目标目录存在
if (-not (Test-Path $TargetDir)) {
    New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null
    Write-Host "[INFO] 创建目标目录: $TargetDir" -ForegroundColor Yellow
}

$targetPath = Join-Path $TargetDir $TargetFile

# 检查是否是同一个文件
if ((Resolve-Path $SourceFile).Path -eq (Resolve-Path $targetPath -ErrorAction SilentlyContinue).Path) {
    Write-Host "[WARN] 源文件和目标文件是同一个文件，跳过复制" -ForegroundColor Yellow
    Write-Host "[INFO] 源文件: $((Resolve-Path $SourceFile).Path)" -ForegroundColor Cyan
    Write-Host "[INFO] 目标文件: $targetPath" -ForegroundColor Cyan
} else {
    # 执行文件复制
    try {
        Copy-Item $SourceFile $targetPath -Force
        Write-Host "[INFO] 文件复制成功: $SourceFile -> $targetPath" -ForegroundColor Green
    } catch {
        Write-Host "[ERROR] 文件复制失败: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

Write-Host "[INFO] 部署脚本修复完成" -ForegroundColor Green
