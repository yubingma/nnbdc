#!/bin/bash

# iOS App 构建和上传到 App Store Connect 脚本
# 用途：自动化构建 iOS App 并上传到 App Store Connect

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 打印函数
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# 配置（需要根据实际情况修改）
APPLE_ID="${APPLE_ID:-your-apple-id@example.com}"
TEAM_ID="${TEAM_ID:-YOUR_TEAM_ID}"
APP_PASSWORD="${APP_PASSWORD:-}"  # App 专用密码（可通过环境变量传入）
BUNDLE_ID="com.nn.nnbdc.nnbdc"
SCHEME="Runner"
WORKSPACE="app/ios/Runner.xcworkspace"
CONFIGURATION="Release"
EXPORT_METHOD="app-store"  # app-store, ad-hoc, enterprise, development

# 目录配置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_DIR="$PROJECT_ROOT/app"
IOS_DIR="$APP_DIR/ios"
BUILD_DIR="$IOS_DIR/build"
ARCHIVE_DIR="$BUILD_DIR/archive"
EXPORT_DIR="$BUILD_DIR/export"
IPA_DIR="$BUILD_DIR/ipa"

# 标志
SKIP_BUILD=false
SKIP_UPLOAD=false
BUILD_ONLY=false
UPLOAD_ONLY=false
CLEAN_BUILD=true
CONFIG_BACKUP_FILE=""  # 配置文件备份路径

# 显示使用说明
show_usage() {
    cat << EOF
用法: $0 [选项]

选项:
  --apple-id ID          Apple ID（也可以通过 APPLE_ID 环境变量设置）
  --team-id ID           Team ID（也可以通过 TEAM_ID 环境变量设置）
  --app-password PASS    App 专用密码（也可以通过 APP_PASSWORD 环境变量设置）
  --skip-clean          跳过清理步骤
  --skip-build          跳过构建步骤（仅上传）
  --skip-upload         跳过上传步骤（仅构建）
  --build-only          仅构建，不上传
  --upload-only         仅上传已有构建，不重新构建
  --help                显示此帮助信息

环境变量:
  APPLE_ID               Apple ID
  TEAM_ID                Team ID
  APP_PASSWORD           App 专用密码（推荐使用环境变量，更安全）

示例:
  # 构建并上传（需要先设置环境变量）
  export APPLE_ID="your-id@example.com"
  export TEAM_ID="YOUR_TEAM_ID"
  export APP_PASSWORD="your-app-specific-password"
  $0

  # 使用命令行参数
  $0 --apple-id "your-id@example.com" --team-id "YOUR_TEAM_ID" --app-password "your-password"

  # 仅构建
  $0 --build-only

  # 仅上传已有构建
  $0 --upload-only

配置说明:
  1. 需要 Apple Developer 账号 (https://developer.apple.com)
  2. 需要创建 App 专用密码 (https://appleid.apple.com → 安全性 → App 专用密码)
  3. 需要有效的 Distribution 证书和 Provisioning Profile
  4. 确保 Xcode 中已配置正确的签名设置

EOF
}

# 解析命令行参数
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --apple-id)
                APPLE_ID="$2"
                shift 2
                ;;
            --team-id)
                TEAM_ID="$2"
                shift 2
                ;;
            --app-password)
                APP_PASSWORD="$2"
                shift 2
                ;;
            --skip-clean)
                CLEAN_BUILD=false
                shift
                ;;
            --skip-build)
                SKIP_BUILD=true
                shift
                ;;
            --skip-upload)
                SKIP_UPLOAD=true
                shift
                ;;
            --build-only)
                BUILD_ONLY=true
                SKIP_UPLOAD=true
                shift
                ;;
            --upload-only)
                UPLOAD_ONLY=true
                SKIP_BUILD=true
                shift
                ;;
            --help|-h)
                show_usage
                exit 0
                ;;
            *)
                print_error "未知选项: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

# 检查必要的工具
check_tools() {
    print_step "检查必要的工具..."
    
    local missing_tools=()
    
    if ! command -v flutter &> /dev/null; then
        missing_tools+=("flutter")
    fi
    
    if ! command -v pod &> /dev/null; then
        missing_tools+=("cocoapods")
    fi
    
    if ! command -v xcodebuild &> /dev/null; then
        missing_tools+=("xcodebuild")
    fi
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        print_error "缺少必要的工具: ${missing_tools[*]}"
        print_info "请安装缺少的工具后再试"
        exit 1
    fi
    
    print_info "Flutter 版本: $(flutter --version | head -n 1)"
    print_info "CocoaPods 版本: $(pod --version)"
    print_info "Xcode 版本: $(xcodebuild -version | head -n 1)"
}

# 检查配置
check_config() {
    if [ "$SKIP_UPLOAD" = false ] && [ "$BUILD_ONLY" = false ]; then
        print_step "检查上传配置..."
        
        if [ -z "$APPLE_ID" ] || [ "$APPLE_ID" = "your-apple-id@example.com" ]; then
            print_error "未设置 Apple ID"
            print_info "请使用 --apple-id 参数或设置 APPLE_ID 环境变量"
            exit 1
        fi
        
        if [ -z "$TEAM_ID" ] || [ "$TEAM_ID" = "YOUR_TEAM_ID" ]; then
            print_error "未设置 Team ID"
            print_info "请使用 --team-id 参数或设置 TEAM_ID 环境变量"
            exit 1
        fi
        
        if [ -z "$APP_PASSWORD" ]; then
            print_error "未设置 App 专用密码"
            print_info "请使用 --app-password 参数或设置 APP_PASSWORD 环境变量"
            print_info "获取 App 专用密码: https://appleid.apple.com → 安全性 → App 专用密码"
            exit 1
        fi
    fi
}

# 清理构建
clean_build() {
    if [ "$CLEAN_BUILD" = true ]; then
        print_step "清理构建..."
        cd "$APP_DIR"
        flutter clean
        print_info "清理完成"
    else
        print_info "跳过清理步骤"
    fi
}

# 获取 Flutter 依赖
get_flutter_dependencies() {
    print_step "获取 Flutter 依赖..."
    cd "$APP_DIR"
    flutter pub get
    print_info "依赖获取完成"
}

# 安装 CocoaPods 依赖
install_pods() {
    print_step "安装 CocoaPods 依赖..."
    cd "$IOS_DIR"
    
    # 设置 UTF-8 编码（避免 CocoaPods 编码错误）
    export LANG=en_US.UTF-8
    
    pod install
    print_info "CocoaPods 依赖安装完成"
}

# 确保配置文件使用 prod 环境
ensure_prod_config() {
    print_step "检查配置文件环境..."
    local config_file="$APP_DIR/lib/config.dart"
    
    if [ ! -f "$config_file" ]; then
        print_error "配置文件不存在: $config_file"
        exit 1
    fi
    
    # 检查当前配置（使用 awk 提取）
    local current_profile=$(awk -F'"' '/profileName =/ {print $2; exit}' "$config_file" 2>/dev/null || echo "")
    
    if [ -z "$current_profile" ]; then
        print_warn "无法解析当前 profile，尝试设置为 prod"
        current_profile="unknown"
    fi
    
    if [ "$current_profile" != "prod" ]; then
        print_warn "当前 profile 为 '$current_profile'，将切换为 'prod'"
        
        # 备份原文件到相同目录
        local backup_file="${config_file}.bak"
        cp "$config_file" "$backup_file"
        print_info "已备份配置文件: $backup_file"
        
        # 使用 sed 替换 profileName
        if [[ "$OSTYPE" == "darwin"* ]]; then
            # macOS 使用 BSD sed
            sed -i '' 's/profileName = "[^"]*"/profileName = "prod"/' "$config_file" || {
                print_error "配置文件修改失败"
                # 恢复备份
                if [ -f "$backup_file" ]; then
                    mv "$backup_file" "$config_file"
                fi
                exit 1
            }
        else
            # Linux 使用 GNU sed
            sed -i 's/profileName = "[^"]*"/profileName = "prod"/' "$config_file" || {
                print_error "配置文件修改失败"
                # 恢复备份
                if [ -f "$backup_file" ]; then
                    mv "$backup_file" "$config_file"
                fi
                exit 1
            }
        fi
        
        # 验证修改是否成功（使用 awk 提取）
        local new_profile=$(awk -F'"' '/profileName =/ {print $2; exit}' "$config_file" 2>/dev/null || echo "")
        if [ "$new_profile" = "prod" ]; then
            print_info "配置文件已成功设置为 prod 环境"
            CONFIG_BACKUP_FILE="$backup_file"  # 保存备份文件名，用于后续恢复
        else
            print_error "配置文件修改失败"
            # 恢复备份
            if [ -f "$backup_file" ]; then
                mv "$backup_file" "$config_file"
            fi
            exit 1
        fi
    else
        print_info "配置文件已经是 prod 环境，无需修改"
    fi
}

# 恢复配置文件
restore_config() {
    if [ -n "$CONFIG_BACKUP_FILE" ] && [ -f "$CONFIG_BACKUP_FILE" ]; then
        print_step "恢复配置文件到原始状态..."
        local config_file="$APP_DIR/lib/config.dart"
        
        # 恢复备份文件
        if mv "$CONFIG_BACKUP_FILE" "$config_file" 2>/dev/null; then
            print_info "配置文件已恢复"
            CONFIG_BACKUP_FILE=""  # 清空备份文件路径
        else
            print_warn "配置文件恢复失败，请手动检查: $config_file"
        fi
    fi
}

# 构建 iOS App（使用 flutter build ipa）
build_ipa() {
    print_step "构建 iOS App (IPA)..."
    cd "$APP_DIR"
    
    # 确保使用 prod 配置
    ensure_prod_config
    
    # 构建 IPA
    if flutter build ipa --release; then
        # 检查 IPA 文件是否存在
        local ipa_file="$APP_DIR/build/ios/ipa/*.ipa"
        if ls $ipa_file 1> /dev/null 2>&1; then
            IPA_FILE=$(ls -t $ipa_file | head -n 1)
            print_info "IPA 构建成功: $IPA_FILE"
            print_info "IPA 文件大小: $(du -h "$IPA_FILE" | cut -f1)"
        else
            print_error "IPA 文件未找到"
            restore_config  # 构建失败时恢复配置
            exit 1
        fi
    else
        print_error "构建失败"
        restore_config  # 构建失败时恢复配置
        exit 1
    fi
    
    # 构建成功后恢复配置
    restore_config
}

# 上传到 App Store Connect
upload_to_app_store() {
    print_step "上传到 App Store Connect..."
    
    if [ -z "$IPA_FILE" ]; then
        # 尝试找到最新的 IPA 文件
        if [ -d "$APP_DIR/build/ios/ipa" ]; then
            IPA_FILE=$(ls -t "$APP_DIR/build/ios/ipa"/*.ipa 2>/dev/null | head -n 1)
        fi
        
        if [ -z "$IPA_FILE" ] || [ ! -f "$IPA_FILE" ]; then
            print_error "未找到 IPA 文件"
            print_info "请先运行构建步骤或指定 IPA 文件路径"
            exit 1
        fi
    fi
    
    print_info "使用 IPA 文件: $IPA_FILE"
    
    # 检查 macOS 版本，选择合适的上传工具
    local macos_version=$(sw_vers -productVersion | cut -d. -f1,2)
    local macos_major=$(echo $macos_version | cut -d. -f1)
    
    if [ "$macos_major" -ge 13 ]; then
        # macOS 13+ 使用 notarytool（推荐）
        print_info "使用 notarytool 上传（macOS 13+）..."
        
        # 注意：notarytool 主要用于公证，上传应该使用 altool 或 Transporter
        # 这里我们使用 altool（即使在新版本 macOS 上也仍可用）
        upload_with_altool
    else
        # macOS 12 及以下使用 altool
        upload_with_altool
    fi
}

# 使用 altool 上传
upload_with_altool() {
    print_info "使用 altool 上传..."
    
    # 检查 xcrun altool 是否可用
    if ! command -v xcrun &> /dev/null; then
        print_error "xcrun 不可用"
        exit 1
    fi
    
    # 验证凭证
    print_info "验证 Apple ID 凭证..."
    xcrun altool --validate-app \
        --file "$IPA_FILE" \
        --type ios \
        --username "$APPLE_ID" \
        --password "$APP_PASSWORD" \
        --team-id "$TEAM_ID" || {
        print_error "IPA 验证失败"
        exit 1
    }
    
    # 上传
    print_info "上传 IPA 到 App Store Connect..."
    xcrun altool --upload-app \
        --file "$IPA_FILE" \
        --type ios \
        --username "$APPLE_ID" \
        --password "$APP_PASSWORD" \
        --team-id "$TEAM_ID" || {
        print_error "上传失败"
        exit 1
    }
    
    print_info "上传成功！"
    print_info "请前往 App Store Connect 查看构建状态："
    print_info "https://appstoreconnect.apple.com"
}

# 主函数
main() {
    # 设置退出时恢复配置的 trap（确保即使脚本被中断也能恢复）
    trap 'restore_config' EXIT INT TERM
    
    print_info "========================================="
    print_info "iOS App 构建和上传脚本"
    print_info "========================================="
    echo ""
    
    # 解析参数
    parse_args "$@"
    
    # 切换到项目根目录
    cd "$PROJECT_ROOT"
    
    # 检查工具
    check_tools
    
    # 检查配置
    check_config
    
    # 构建流程
    if [ "$SKIP_BUILD" = false ] && [ "$UPLOAD_ONLY" = false ]; then
        clean_build
        get_flutter_dependencies
        install_pods
        build_ipa
    else
        print_info "跳过构建步骤"
    fi
    
    # 上传流程
    if [ "$SKIP_UPLOAD" = false ] && [ "$BUILD_ONLY" = false ]; then
        upload_to_app_store
    else
        print_info "跳过上传步骤"
        if [ "$BUILD_ONLY" = true ]; then
            print_info "IPA 文件位置: $IPA_FILE"
            print_info "可以使用以下命令手动上传："
            echo ""
            echo "  xcrun altool --upload-app \\"
            echo "    --file \"$IPA_FILE\" \\"
            echo "    --type ios \\"
            echo "    --username \"\$APPLE_ID\" \\"
            echo "    --password \"\$APP_PASSWORD\" \\"
            echo "    --team-id \"\$TEAM_ID\""
            echo ""
        fi
    fi
    
    # 确保配置文件已恢复
    restore_config
    
    # 移除 trap（配置已恢复，脚本正常结束）
    trap - EXIT INT TERM
    
    print_info "========================================="
    print_info "完成！"
    print_info "========================================="
}

# 运行主函数
main "$@"
