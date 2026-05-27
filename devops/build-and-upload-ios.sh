#!/bin/bash

# iOS App 构建和上传到 App Store Connect 脚本
# 用途：自动化构建 iOS App 并上传到 App Store Connect

set -e

# 确保使用 bash 执行（脚本内部使用了 bash 语法，如 [[ ]]、数组等）
if [ -z "${BASH_VERSION:-}" ]; then
    echo "[ERROR] 请使用 bash 执行此脚本，例如: bash $0"
    exit 1
fi

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
API_KEY="${API_KEY:-}"            # App Store Connect API Key ID
API_ISSUER="${API_ISSUER:-}"      # App Store Connect API Issuer ID
BUNDLE_ID="com.nn.nnbdc.nnbdc"
SCHEME="Runner"
WORKSPACE="app/ios/Runner.xcworkspace"
CONFIGURATION="Release"
EXPORT_METHOD="app-store"  # app-store, ad-hoc, enterprise, development

# 目录配置
#
# 说明：为了支持“在任意目录下执行”，不能直接用 dirname "${BASH_SOURCE[0]}"
# 因为当脚本通过 PATH 以“文件名”形式执行时，BASH_SOURCE[0] 可能不含路径，dirname 会变成 "."
# 这里通过 command -v 定位脚本真实路径，并解析 symlink，得到稳定的 SCRIPT_DIR。
SCRIPT_PATH="${BASH_SOURCE[0]:-$0}"
if [[ "$SCRIPT_PATH" != */* ]]; then
    SCRIPT_PATH="$(command -v -- "$SCRIPT_PATH" 2>/dev/null || true)"
fi
if [ -z "$SCRIPT_PATH" ]; then
    echo -e "${RED}[ERROR]${NC} 无法定位脚本路径，请使用带路径的方式执行（例如: ./devops/build-and-upload-ios.sh）"
    exit 1
fi
while [ -L "$SCRIPT_PATH" ]; do
    SCRIPT_LINK_DIR="$(cd -P "$(dirname "$SCRIPT_PATH")" && pwd)"
    SCRIPT_PATH="$(readlink "$SCRIPT_PATH")"
    [[ "$SCRIPT_PATH" != /* ]] && SCRIPT_PATH="$SCRIPT_LINK_DIR/$SCRIPT_PATH"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SCRIPT_PATH")" && pwd)"
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
TAG_REPO=true           # 默认打 tag，--no-tag 关闭
CONFIG_BACKUP_FILE=""   # 配置文件备份路径
INFOPLIST_BACKUP_FILE="" # Info.plist 备份路径

# 显示使用说明
show_usage() {
    cat << EOF
用法: $0 [选项]

选项:
  --apple-id ID          Apple ID（也可以通过 APPLE_ID 环境变量设置）
  --team-id ID           Team ID（也可以通过 TEAM_ID 环境变量设置）
  --app-password PASS    App 专用密码（也可以通过 APP_PASSWORD 环境变量设置）
  --api-key KEY          App Store Connect API Key ID (用于替代 Apple ID 登录)
  --api-issuer ISSUER    App Store Connect API Issuer ID
  --skip-clean          跳过清理步骤
  --skip-build          跳过构建步骤（仅上传）
  --skip-upload         跳过上传步骤（仅构建）
  --build-only          仅构建，不上传
  --upload-only         仅上传已有构建，不重新构建
  --no-tag              跳过 Git 打标签
  --tag-name NAME       自定义 Git 标签名（默认: ios/v{VERSION}）
  --help                显示此帮助信息

环境变量:
  APPLE_ID               Apple ID
  TEAM_ID                Team ID
  APP_PASSWORD           App 专用密码
  API_KEY                API Key ID (如 XXXXXXXXXX)
  API_ISSUER             API Issuer ID

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
            --api-key)
                API_KEY="$2"
                shift 2
                ;;
            --api-issuer)
                API_ISSUER="$2"
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
            --no-tag)
                TAG_REPO=false
                shift
                ;;
            --tag-name)
                TAG_NAME="$2"
                shift 2
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
    # 校验版本号格式
    print_step "校验版本号格式..."
    local pubspec_path="$APP_DIR/pubspec.yaml"
    if [ ! -f "$pubspec_path" ]; then
        print_error "找不到 pubspec.yaml: $pubspec_path"
        exit 1
    fi
    
    local version=$(grep "^version:" "$pubspec_path" | awk '{print $2}')
    if [[ ! $version =~ ^[0-9]{2}\.[0-9]{2}\.[0-9]{2}\+[0-9]{6}[0-9]{2}$ ]]; then
        print_error "版本号格式必须为 YY.MM.DD+YYMMDDXX (例如: 26.05.23+26052301)"
        print_info "当前版本号: $version"
        exit 1
    fi
    
    local date_dots=$(echo $version | cut -d'+' -f1)
    local date_num=$(echo $version | cut -d'+' -f2 | cut -c1-6)
    if [ "${date_dots//./}" != "$date_num" ]; then
        print_error "版本名称中的日期 ($date_dots) 与构建号中的日期 ($date_num) 不一致"
        exit 1
    fi
    
    local mm=$(echo $date_dots | cut -d'.' -f2)
    local dd=$(echo $date_dots | cut -d'.' -f3)
    if [ $((10#$mm)) -lt 1 ] || [ $((10#$mm)) -gt 12 ]; then
        print_error "月份 ($mm) 无效"
        exit 1
    fi
    if [ $((10#$dd)) -lt 1 ] || [ $((10#$dd)) -gt 31 ]; then
        print_error "日期 ($dd) 无效"
        exit 1
    fi

    # 验证日期不晚于明天
    local tomorrow=$(python3 -c "from datetime import datetime, timedelta; print((datetime.now() + timedelta(days=1)).strftime('%y%m%d'))" 2>/dev/null || \
                     python -c "from datetime import datetime, timedelta; print((datetime.now() + timedelta(days=1)).strftime('%y%m%d'))" 2>/dev/null)
    if [ -n "$tomorrow" ]; then
        if [ "$date_num" -gt "$tomorrow" ]; then
            print_error "版本日期 ($date_num) 不能超过明天 ($tomorrow)"
            exit 1
        fi
    fi

    print_info "版本号校验通过: $version"

    # 校验 min_ver_code 格式
    local min_ver_code=$(grep "^min_ver_code:" "$pubspec_path" | awk '{print $2}')
    if [ -n "$min_ver_code" ]; then
        if [[ ! $min_ver_code =~ ^[0-9]{8}$ ]]; then
            print_error "min_ver_code 格式必须为 YYMMDDXX (例如: 26051101)"
            print_info "当前 min_ver_code: $min_ver_code"
            exit 1
        fi

        local build_number=$(echo $version | cut -d'+' -f2)
        if [ "$min_ver_code" -gt "$build_number" ]; then
            print_error "min_ver_code ($min_ver_code) 不能大于当前构建号 ($build_number)"
            exit 1
        fi

        local min_mm=$(echo $min_ver_code | cut -c3-4)
        local min_dd=$(echo $min_ver_code | cut -c5-6)
        if [ $((10#$min_mm)) -lt 1 ] || [ $((10#$min_mm)) -gt 12 ]; then
            print_error "min_ver_code 中的月份 ($min_mm) 无效"
            exit 1
        fi
        if [ $((10#$min_dd)) -lt 1 ] || [ $((10#$min_dd)) -gt 31 ]; then
            print_error "min_ver_code 中的日期 ($min_dd) 无效"
            exit 1
        fi
        print_info "min_ver_code 校验通过: $min_ver_code"
    fi

    if [ "$SKIP_UPLOAD" = false ] && [ "$BUILD_ONLY" = false ]; then
        print_step "检查上传配置..."
        
        if [ -n "$API_KEY" ] && [ -n "$API_ISSUER" ]; then
            print_info "已配置 App Store Connect API Key，将使用 API Key 进行上传验证"
        else
            if [ -z "$APPLE_ID" ] || [ "$APPLE_ID" = "your-apple-id@example.com" ]; then
                print_error "未设置 Apple ID 且缺乏 API Key"
                print_info "请使用 --apple-id 参数、设置 APPLE_ID 环境变量，或同时配置 --api-key 和 --api-issuer"
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

# 移除 Info.plist 中的调试专用权限（本地网络权限）
clean_debug_permissions() {
    print_step "检查并移除 Info.plist 中的调试权限..."
    local plist_file="$IOS_DIR/Runner/Info.plist"
    
    if [ ! -f "$plist_file" ]; then
        print_error "Info.plist 不存在: $plist_file"
        exit 1
    fi

    # 备份 Info.plist
    local backup_file="${plist_file}.bak"
    cp "$plist_file" "$backup_file"
    INFOPLIST_BACKUP_FILE="$backup_file"
    print_info "已备份 Info.plist: $backup_file"

    # 使用 python3 脚本精确处理 Plist (比 sed 更可靠)
    # 移除 NSLocalNetworkUsageDescription 和 NSBonjourServices
    python3 - <<EOF
import sys
import plistlib

plist_path = "$plist_file"
try:
    with open(plist_path, 'rb') as f:
        pl = plistlib.load(f)
    
    modified = False
    if 'NSLocalNetworkUsageDescription' in pl:
        del pl['NSLocalNetworkUsageDescription']
        modified = True
    if 'NSBonjourServices' in pl:
        del pl['NSBonjourServices']
        modified = True
        
    if modified:
        with open(plist_path, 'wb') as f:
            plistlib.dump(pl, f)
        print("已成功移除调试专用权限 (NSLocalNetworkUsageDescription, NSBonjourServices)")
    else:
        print("未发现调试专用权限，无需修改")
except Exception as e:
    print(f"处理 Info.plist 失败: {e}")
    sys.exit(1)
EOF
    if [ $? -ne 0 ]; then
        print_error "处理 Info.plist 失败"
        restore_debug_permissions
        exit 1
    fi
}

# 恢复 Info.plist
restore_debug_permissions() {
    if [ -n "$INFOPLIST_BACKUP_FILE" ] && [ -f "$INFOPLIST_BACKUP_FILE" ]; then
        print_step "恢复 Info.plist 到原始状态..."
        local plist_file="$IOS_DIR/Runner/Info.plist"
        if mv "$INFOPLIST_BACKUP_FILE" "$plist_file" 2>/dev/null; then
            print_info "Info.plist 已恢复"
            INFOPLIST_BACKUP_FILE=""
        else
            print_warn "Info.plist 恢复失败，请手动检查"
        fi
    fi
}

# 恢复所有备份（配置和权限）
restore_all_backups() {
    restore_config
    restore_debug_permissions
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

# Git 打标签
tag_repo() {
    if [ "$TAG_REPO" = false ]; then
        print_info "跳过 Git 打标签"
        return
    fi

    local version=$(grep "^version:" "$APP_DIR/pubspec.yaml" | awk '{print $2}')
    local tag_name="${TAG_NAME:-ios/v${version}}"

    # 检查是否有未提交的变更
    if ! git diff-index --quiet HEAD -- 2>/dev/null; then
        print_warn "工作区有未提交的变更，标签将指向当前 HEAD（可能不包含这些变更）"
    fi

    # 检查标签是否已存在
    if git rev-parse "$tag_name" >/dev/null 2>&1; then
        print_warn "标签 $tag_name 已存在，跳过"
        return
    fi

    print_step "创建 Git 标签: $tag_name"
    git tag -a "$tag_name" -m "iOS build $version"
    print_info "标签 $tag_name 已创建（本地）"
    print_info "推送到远程: git push origin $tag_name"
}

# 构建 iOS App（使用 flutter build ipa）
build_ipa() {
    print_step "构建 iOS App (IPA)..."
    cd "$APP_DIR"
    
    # 确保使用 prod 配置
    ensure_prod_config
    
    # 移除调试权限
    clean_debug_permissions
    
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
    restore_all_backups
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
    print_info "验证 App 凭证..."
    
    if [ -n "$API_KEY" ] && [ -n "$API_ISSUER" ]; then
        print_info "验证方式: App Store Connect API Key"
        xcrun altool --validate-app \
            --file "$IPA_FILE" \
            --type ios \
            --apiKey "$API_KEY" \
            --apiIssuer "$API_ISSUER" || {
            print_error "IPA 验证失败"
            exit 1
        }
        
        print_info "上传 IPA 到 App Store Connect..."
        xcrun altool --upload-app \
            --file "$IPA_FILE" \
            --type ios \
            --apiKey "$API_KEY" \
            --apiIssuer "$API_ISSUER" || {
            print_error "上传失败"
            exit 1
        }
    else
        print_info "验证方式: Apple ID"
        xcrun altool --validate-app \
            --file "$IPA_FILE" \
            --type ios \
            --username "$APPLE_ID" \
            --password "$APP_PASSWORD" \
            --team-id "$TEAM_ID" || {
            print_error "IPA 验证失败"
            exit 1
        }
        
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
    fi
    
    print_info "上传成功！"
    print_info "请前往 App Store Connect 查看构建状态："
    print_info "https://appstoreconnect.apple.com"
}

# 主函数
main() {
    # 记录开始时间
    local start_time=$(date +%s)
    
    # 设置退出时恢复配置的 trap（确保即使脚本被中断也能恢复）
    trap 'restore_all_backups' EXIT INT TERM
    
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
            if [ -n "$API_KEY" ] && [ -n "$API_ISSUER" ]; then
                echo "  xcrun altool --upload-app \\"
                echo "    --file \"$IPA_FILE\" \\"
                echo "    --type ios \\"
                echo "    --apiKey \"\$API_KEY\" \\"
                echo "    --apiIssuer \"\$API_ISSUER\""
            else
                echo "  xcrun altool --upload-app \\"
                echo "    --file \"$IPA_FILE\" \\"
                echo "    --type ios \\"
                echo "    --username \"\$APPLE_ID\" \\"
                echo "    --password \"\$APP_PASSWORD\" \\"
                echo "    --team-id \"\$TEAM_ID\""
            fi
            echo ""
        fi
    fi
    
    tag_repo
    
    # 确保配置文件已恢复
    restore_all_backups
    
    # 移除 trap（配置已恢复，脚本正常结束）
    trap - EXIT INT TERM
    
    # 计算并打印总耗时
    local end_time=$(date +%s)
    local total_seconds=$((end_time - start_time))
    local hours=$((total_seconds / 3600))
    local minutes=$(((total_seconds % 3600) / 60))
    local seconds=$((total_seconds % 60))
    
    print_info "========================================="
    print_info "完成！"
    if [ $hours -gt 0 ]; then
        print_info "总耗时: ${hours}小时 ${minutes}分钟 ${seconds}秒"
    elif [ $minutes -gt 0 ]; then
        print_info "总耗时: ${minutes}分钟 ${seconds}秒"
    else
        print_info "总耗时: ${seconds}秒"
    fi
    print_info "========================================="
}

# 运行主函数
main "$@"
