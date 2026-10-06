#!/bin/bash

# ==============================================================================
# 全平台 App 构建与上传总控流水线 (iOS App Store + 华为应用市场 + 小米应用商店)
#
# 特性：
# 1. 统一前置预检 (版本号、min_ver_code、工具链、全渠道凭证提前验证，避免中途报错)
# 2. 全局单元测试只跑 1 次，严禁多渠道重复测试浪费时间
# 3. 串行编译确保文件与配置安全，杜绝 config.dart 踩踏
# 4. 各渠道构建各自的 Android APK：华为渠道包的应用名是「泡泡单词英语版」（华为商店重名），
#    小米渠道包是「泡泡单词」（工信部备案名），因此两个渠道不能共用同一个包
# 5. 流水线并发上传：iOS 构建完成立刻在后台启动上传，同时前台构建 Android，
#    各市场构建完成后所有上传后台并发进行，彻底掩盖网络等待延迟
# 6. 全渠道完成后自动统一打 Git Tag (v{VERSION})
# ==============================================================================

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

print_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_step()  { echo -e "${BLUE}[STEP]${NC} ${BOLD}$1${NC}"; }
print_succ()  { echo -e "${CYAN}[DONE]${NC} $1"; }

# 脚本路径解析
SCRIPT_PATH="${BASH_SOURCE[0]:-$0}"
while [ -L "$SCRIPT_PATH" ]; do
    SCRIPT_LINK_DIR="$(cd -P "$(dirname "$SCRIPT_PATH")" && pwd)"
    SCRIPT_PATH="$(readlink "$SCRIPT_PATH")"
    [[ "$SCRIPT_PATH" != /* ]] && SCRIPT_PATH="$SCRIPT_LINK_DIR/$SCRIPT_PATH"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SCRIPT_PATH")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_DIR="$PROJECT_ROOT/app"
TMP_DIR="$PROJECT_ROOT/tmp"
mkdir -p "$TMP_DIR"

# 标志与参数
ENABLE_IOS=true
ENABLE_HUAWEI=true
ENABLE_XIAOMI=true
SKIP_TESTS=false
BUILD_ONLY=false
UPLOAD_ONLY=false
SKIP_CLEAN=false
TAG_REPO=true
CUSTOM_TAG_NAME=""

show_usage() {
    cat << EOF
用法: $0 [选项]

选项:
  --skip-tests          跳过全局单元测试步骤
  --skip-ios            跳过 iOS 平台的构建与上传
  --skip-huawei         跳过华为平台的构建与上传
  --skip-xiaomi         跳过小米平台的构建与上传
  --build-only          仅构建所有平台的安装包（不上传）
  --upload-only         仅上传已有构建产物（不重新构建与测试）
  --skip-clean          iOS 构建时跳过 flutter clean
  --no-tag              全部完成后跳过创建 Git Tag
  --tag-name NAME       自定义 Git 标签名（默认: v{VERSION}）
  --help, -h            显示此帮助信息

示例:
  # 默认完整流水线 (测试 -> 串行构建 -> 并发上传 -> 打Tag)
  $0

  # 仅构建全渠道安装包，不上传
  $0 --build-only

  # 仅并发上传已构建好的包
  $0 --upload-only

  # 只发国内安卓市场（跳过 iOS）
  $0 --skip-ios

  # 快速发版：跳过测试与 clean
  $0 --skip-tests --skip-clean

EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --skip-tests)
                SKIP_TESTS=true
                shift
                ;;
            --skip-ios)
                ENABLE_IOS=false
                shift
                ;;
            --skip-huawei)
                ENABLE_HUAWEI=false
                shift
                ;;
            --skip-xiaomi)
                ENABLE_XIAOMI=false
                shift
                ;;
            --build-only)
                BUILD_ONLY=true
                shift
                ;;
            --upload-only)
                UPLOAD_ONLY=true
                shift
                ;;
            --skip-clean)
                SKIP_CLEAN=true
                shift
                ;;
            --no-tag)
                TAG_REPO=false
                shift
                ;;
            --tag-name)
                CUSTOM_TAG_NAME="$2"
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

# 后台任务管理
BACKGROUND_PIDS=()
BACKGROUND_NAMES=()
BACKGROUND_LOGS=()

cleanup_background_tasks() {
    if [ ${#BACKGROUND_PIDS[@]} -gt 0 ]; then
        print_warn "检测到脚本退出/被中断，正在清理后台任务..."
        for pid in "${BACKGROUND_PIDS[@]}"; do
            if kill -0 "$pid" 2>/dev/null; then
                kill "$pid" 2>/dev/null || true
            fi
        done
    fi
}
trap cleanup_background_tasks EXIT INT TERM

# ==============================================================================
# 1. 严格前置预检 (版本号 + 工具 + 凭证)
# ==============================================================================
preflight_check() {
    print_step "1. 正在执行前置预检 (Fail-Fast)..."

    local pubspec_path="$APP_DIR/pubspec.yaml"
    if [ ! -f "$pubspec_path" ]; then
        print_error "找不到 pubspec.yaml: $pubspec_path"
        exit 1
    fi

    # 版本号格式校验
    VERSION=$(grep "^version:" "$pubspec_path" | awk '{print $2}')
    if [[ ! $VERSION =~ ^[0-9]{2}\.[0-9]{2}\.[0-9]{2}\+[0-9]{6}[0-9]{2}$ ]]; then
        print_error "版本号格式必须为 YY.MM.DD+YYMMDDXX (例如: 26.05.23+26052301)，当前: $VERSION"
        exit 1
    fi

    local date_dots=$(echo $VERSION | cut -d'+' -f1)
    local date_num=$(echo $VERSION | cut -d'+' -f2 | cut -c1-6)
    if [ "${date_dots//./}" != "$date_num" ]; then
        print_error "版本名称中的日期 ($date_dots) 与构建号中的日期 ($date_num) 不一致"
        exit 1
    fi

    local mm=$(echo $date_dots | cut -d'.' -f2)
    local dd=$(echo $date_dots | cut -d'.' -f3)
    if [ $((10#$mm)) -lt 1 ] || [ $((10#$mm)) -gt 12 ] || [ $((10#$dd)) -lt 1 ] || [ $((10#$dd)) -gt 31 ]; then
        print_error "版本号月份 ($mm) 或日期 ($dd) 无效"
        exit 1
    fi

    # 校验 min_ver_code
    local min_ver_code=$(grep "^min_ver_code:" "$pubspec_path" | awk '{print $2}')
    if [ -n "$min_ver_code" ]; then
        if [[ ! $min_ver_code =~ ^[0-9]{8}$ ]]; then
            print_error "min_ver_code 格式必须为 YYMMDDXX，当前: $min_ver_code"
            exit 1
        fi
        local build_number=$(echo $VERSION | cut -d'+' -f2)
        if [ "$min_ver_code" -gt "$build_number" ]; then
            print_error "min_ver_code ($min_ver_code) 不能大于当前构建号 ($build_number)"
            exit 1
        fi
    fi
    # 先落到变量再拼接：macOS 自带 bash 3.2 里 ${min_ver_code:-无} 紧邻 } 的多字节字符会丢首字节
    local min_ver_code_display="${min_ver_code:-无}"
    print_info "✅ 版本校验通过: $VERSION (min_ver_code: $min_ver_code_display)"

    # 基础工具
    if ! command -v flutter &> /dev/null; then
        print_error "缺少 flutter 命令行工具"
        exit 1
    fi

    # iOS 检查
    if [ "$ENABLE_IOS" = true ]; then
        if ! command -v xcodebuild &> /dev/null; then
            print_error "缺少 xcodebuild 工具"
            exit 1
        fi
        if ! command -v pod &> /dev/null; then
            print_error "缺少 pod 工具"
            exit 1
        fi
        if [ "$BUILD_ONLY" = false ]; then
            if [ -z "$API_KEY" ] || [ -z "$API_ISSUER" ]; then
                if [ -z "$APPLE_ID" ] || [ -z "$TEAM_ID" ] || [ -z "$APP_PASSWORD" ]; then
                    print_error "iOS 上传缺少凭证！请设置 API_KEY+API_ISSUER 或 APPLE_ID+TEAM_ID+APP_PASSWORD"
                    exit 1
                fi
            fi
        fi
        print_info "✅ iOS 工具与凭证检查通过"
    fi

    # Android 渠道共用的 Python 环境
    if [ "$ENABLE_HUAWEI" = true ] || [ "$ENABLE_XIAOMI" = true ]; then
        local python_exec="$PROJECT_ROOT/.venv/bin/python"
        if [ ! -f "$python_exec" ]; then
            print_error "找不到 Python 虚拟环境: $python_exec"
            exit 1
        fi
    fi

    # 华为检查
    if [ "$ENABLE_HUAWEI" = true ]; then
        if [ "$BUILD_ONLY" = false ]; then
            local hw_secret=${HUAWEI_API_CLIENT_SECRET:-$HUAWEI_CLIENT_SECRET}
            local hw_app_id=${HUAWEI_PPDC_APP_ID:-$HUAWEI_APP_ID}
            if [ -z "$hw_secret" ] || [ -z "$hw_app_id" ]; then
                print_error "华为上传缺少凭证！请设置 HUAWEI_API_CLIENT_SECRET 与 HUAWEI_PPDC_APP_ID"
                exit 1
            fi
        fi
        print_info "✅ 华为 Python 环境与凭证检查通过"
    fi

    # 小米检查
    if [ "$ENABLE_XIAOMI" = true ]; then
        if [ "$BUILD_ONLY" = false ]; then
            if [ -z "$XIAOMI_DEV_ACCOUNT" ] || [ -z "$XIAOMI_DEV_PRIVATE_KEY" ] || [ -z "$XIAOMI_DEV_PUBLIC_KEY" ]; then
                print_error "小米上传缺少凭证！请设置 XIAOMI_DEV_ACCOUNT (登录邮箱)、XIAOMI_DEV_PRIVATE_KEY (自动发布接口私钥)、XIAOMI_DEV_PUBLIC_KEY (公钥证书 .cer 路径)"
                exit 1
            fi
            if [ ! -f "$XIAOMI_DEV_PUBLIC_KEY" ]; then
                print_error "找不到小米公钥证书文件: $XIAOMI_DEV_PUBLIC_KEY"
                exit 1
            fi
        fi
        print_info "✅ 小米 Python 环境与凭证检查通过"
    fi

    # 检查是否至少启用了一个平台
    if [ "$ENABLE_IOS" = false ] && [ "$ENABLE_HUAWEI" = false ] && [ "$ENABLE_XIAOMI" = false ]; then
        print_error "未启用任何平台！请不要同时指定 --skip-ios 和 --skip-huawei 和 --skip-xiaomi。"
        exit 1
    fi
}

# ==============================================================================
# 2. 全局单元测试 (只跑 1 次)
# ==============================================================================
run_global_tests() {
    if [ "$SKIP_TESTS" = true ]; then
        print_info "⏭️  跳过全局单元测试 (--skip-tests)"
        return
    fi
    if [ "$UPLOAD_ONLY" = true ]; then
        print_info "⏭️  上传模式，无需执行测试"
        return
    fi

    print_step "2. 正在运行全局单元测试 (仅执行一次，全平台共享)..."
    cd "$APP_DIR"
    if flutter test -j 1; then
        print_succ "所有单元测试通过！"
    else
        print_error "❌ 单元测试失败！发布流程已终止。"
        exit 1
    fi
}

# ==============================================================================
# 3. 流水线构建与并发上传
# ==============================================================================
pipeline_build_and_upload() {
    local start_time=$(date +%s)
    local timestamp=$(date +%Y%m%d_%H%M%S)

    # -------------------------------------------------------------
    # 模式 A: 纯上传模式 (--upload-only)
    # -------------------------------------------------------------
    if [ "$UPLOAD_ONLY" = true ]; then
        print_step "3. 并发启动各平台上传任务..."

        if [ "$ENABLE_IOS" = true ]; then
            local ios_log="$TMP_DIR/upload_ios_${timestamp}.log"
            print_info "启动 iOS 上传任务 (日志: $ios_log)..."
            bash "$SCRIPT_DIR/build-and-upload-ios.sh" --upload-only --no-tag > "$ios_log" 2>&1 &
            BACKGROUND_PIDS+=($!)
            BACKGROUND_NAMES+=("iOS App Store")
            BACKGROUND_LOGS+=("$ios_log")
        fi

        if [ "$ENABLE_HUAWEI" = true ]; then
            local huawei_log="$TMP_DIR/upload_huawei_${timestamp}.log"
            print_info "启动华为上传任务 (日志: $huawei_log)..."
            bash "$SCRIPT_DIR/build-and-upload-huawei.sh" --upload-only > "$huawei_log" 2>&1 &
            BACKGROUND_PIDS+=($!)
            BACKGROUND_NAMES+=("华为应用市场")
            BACKGROUND_LOGS+=("$huawei_log")
        fi

        if [ "$ENABLE_XIAOMI" = true ]; then
            local xiaomi_log="$TMP_DIR/upload_xiaomi_${timestamp}.log"
            print_info "启动小米上传任务 (日志: $xiaomi_log)..."
            bash "$SCRIPT_DIR/build-and-upload-xiaomi.sh" --upload-only > "$xiaomi_log" 2>&1 &
            BACKGROUND_PIDS+=($!)
            BACKGROUND_NAMES+=("小米应用商店")
            BACKGROUND_LOGS+=("$xiaomi_log")
        fi

        wait_for_uploads
        return
    fi

    # -------------------------------------------------------------
    # 模式 B: 流水线构建 + 并发上传
    # -------------------------------------------------------------
    print_step "3. 进入串行构建与流水线并发上传流程..."

    # --- 阶段 1: iOS 构建 ---
    if [ "$ENABLE_IOS" = true ]; then
        print_step "3.1 开始构建 iOS IPA..."
        local ios_build_args=("--build-only" "--skip-tests" "--no-tag")
        if [ "$SKIP_CLEAN" = true ]; then
            ios_build_args+=("--skip-clean")
        fi

        bash "$SCRIPT_DIR/build-and-upload-ios.sh" "${ios_build_args[@]}"
        print_succ "iOS IPA 构建成功！"

        # 若需要上传，立刻放入后台并发上传
        if [ "$BUILD_ONLY" = false ]; then
            local ios_log="$TMP_DIR/upload_ios_${timestamp}.log"
            print_info "🚀 触发 iOS 后台并发上传 (日志: $ios_log)..."
            bash "$SCRIPT_DIR/build-and-upload-ios.sh" --upload-only --no-tag > "$ios_log" 2>&1 &
            BACKGROUND_PIDS+=($!)
            BACKGROUND_NAMES+=("iOS App Store")
            BACKGROUND_LOGS+=("$ios_log")
        fi
    fi

    # --- 阶段 2: Android APK 构建（两个渠道的应用名不同，各构建一份独立产物） ---
    if [ "$ENABLE_HUAWEI" = true ]; then
        print_step "3.2 开始构建华为渠道 APK（应用名：泡泡单词英语版，同时 iOS 正在后台上传）..."
        bash "$SCRIPT_DIR/build-and-upload-huawei.sh" --build-only --skip-tests
        print_succ "华为渠道 APK 构建成功！"
    fi

    if [ "$ENABLE_XIAOMI" = true ]; then
        print_step "3.3 开始构建小米渠道 APK（应用名：泡泡单词，与工信部备案一致）..."
        bash "$SCRIPT_DIR/build-and-upload-xiaomi.sh" --build-only --skip-tests
        print_succ "小米渠道 APK 构建成功！"
    fi

    # --- 阶段 3: 各 Android 渠道后台并发上传 ---
    if [ "$BUILD_ONLY" = false ]; then
        if [ "$ENABLE_HUAWEI" = true ]; then
            local huawei_log="$TMP_DIR/upload_huawei_${timestamp}.log"
            print_info "🚀 触发华为后台并发上传 (日志: $huawei_log)..."
            bash "$SCRIPT_DIR/build-and-upload-huawei.sh" --upload-only > "$huawei_log" 2>&1 &
            BACKGROUND_PIDS+=($!)
            BACKGROUND_NAMES+=("华为应用市场")
            BACKGROUND_LOGS+=("$huawei_log")
        fi

        if [ "$ENABLE_XIAOMI" = true ]; then
            local xiaomi_log="$TMP_DIR/upload_xiaomi_${timestamp}.log"
            print_info "🚀 触发小米后台并发上传 (日志: $xiaomi_log)..."
            bash "$SCRIPT_DIR/build-and-upload-xiaomi.sh" --upload-only > "$xiaomi_log" 2>&1 &
            BACKGROUND_PIDS+=($!)
            BACKGROUND_NAMES+=("小米应用商店")
            BACKGROUND_LOGS+=("$xiaomi_log")
        fi
    fi

    # --- 阶段 4: 等待所有后台上传任务完成 ---
    if [ "$BUILD_ONLY" = false ]; then
        wait_for_uploads
    else
        print_succ "所有平台安装包构建完成 (--build-only 模式，跳过上传)"
    fi
}

# ==============================================================================
# 4. 等待所有并发上传完成并输出状态
# ==============================================================================
wait_for_uploads() {
    local count=${#BACKGROUND_PIDS[@]}
    if [ $count -eq 0 ]; then
        return
    fi

    print_step "4. 等待所有渠道后台上传完成 (当前有 $count 个任务并发上传)..."

    local has_failure=false

    for i in "${!BACKGROUND_PIDS[@]}"; do
        local pid="${BACKGROUND_PIDS[$i]}"
        local name="${BACKGROUND_NAMES[$i]}"
        local log_file="${BACKGROUND_LOGS[$i]}"

        print_info "正在等待 [$name] (PID: $pid) 上传完成..."

        if wait "$pid"; then
            print_succ "[$name] 上传成功！"
        else
            print_error "❌ [$name] 上传失败！请检查日志: $log_file"
            echo "------------------- 日志末尾 30 行 -------------------"
            tail -n 30 "$log_file" 2>/dev/null || true
            echo "----------------------------------------------------"
            has_failure=true
        fi
    done

    # 清空 PID 列表，避免 EXIT trap 误杀
    BACKGROUND_PIDS=()

    if [ "$has_failure" = true ]; then
        print_error "部分渠道上传失败，请根据上方日志排查！"
        exit 1
    fi

    print_succ "全渠道上传全部成功完成！"
}

# ==============================================================================
# 5. 全渠道统一 Git Tag
# ==============================================================================
tag_release() {
    if [ "$TAG_REPO" = false ]; then
        print_info "⏭️  跳过 Git 打标签 (--no-tag)"
        return
    fi
    if [ "$BUILD_ONLY" = true ]; then
        print_info "⏭️  纯构建模式，不打标签"
        return
    fi

    local tag_name="${CUSTOM_TAG_NAME:-v${VERSION}}"
    print_step "5. 统一创建 Git 发布标签: $tag_name"

    cd "$PROJECT_ROOT"
    if git rev-parse "$tag_name" >/dev/null 2>&1; then
        print_warn "标签 $tag_name 已存在，跳过打标签"
        return
    fi

    git tag -a "$tag_name" -m "全平台发布版本 $VERSION"
    print_info "标签 $tag_name 已创建，正在推送到远程 origin..."
    git push --no-verify origin "$tag_name"
    print_succ "标签已成功推送到远程仓库: $tag_name"
}

# ==============================================================================
# 主入口
# ==============================================================================
main() {
    local start_time=$(date +%s)

    echo ""
    echo -e "${CYAN}======================================================${NC}"
    echo -e "${CYAN}    泡泡单词 (NNBDC) 全平台构建与发布流水线             ${NC}"
    echo -e "${CYAN}======================================================${NC}"
    echo ""

    parse_args "$@"
    preflight_check
    run_global_tests
    pipeline_build_and_upload
    tag_release

    local end_time=$(date +%s)
    local total_seconds=$((end_time - start_time))
    local minutes=$((total_seconds / 60))
    local seconds=$((total_seconds % 60))

    echo ""
    echo -e "${GREEN}======================================================${NC}"
    echo -e "${GREEN} 🎉 全流程执行完毕！总耗时: ${minutes}分 ${seconds}秒${NC}"
    echo -e "${GREEN}======================================================${NC}"
    echo ""
}

main "$@"
