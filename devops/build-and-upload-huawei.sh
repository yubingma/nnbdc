#!/bin/bash
set -e
START_TIME=$SECONDS

# Configuration
# Default Client ID from screenshot, but allow override
DEFAULT_CLIENT_ID="116685955"
# Resolve symlinks to find the real script directory (works on macOS and Linux)
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do
  DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
PROJECT_ROOT="$SCRIPT_DIR/../app"
UPLOAD_SCRIPT="$SCRIPT_DIR/upload_huawei.py"
PYTHON_EXEC="$SCRIPT_DIR/../.venv/bin/python"

# Check for Python virtual environment
if [ ! -f "$PYTHON_EXEC" ]; then
    echo "Error: Python ./venv not found at $PYTHON_EXEC"
    exit 1
fi

#=========================================================
# 校验版本号格式 (YY.MM.DD+YYMMDDXX)
#=========================================================
validate_version() {
    local PUBSPEC_PATH="$PROJECT_ROOT/pubspec.yaml"
    if [ ! -f "$PUBSPEC_PATH" ]; then
        echo "❌ 错误: 找不到 pubspec.yaml 在 $PUBSPEC_PATH"
        exit 1
    fi

    local VERSION=$(grep "^version:" "$PUBSPEC_PATH" | awk '{print $2}')
    
    # 正则表达式验证: YY.MM.DD+YYMMDDXX
    if [[ ! $VERSION =~ ^[0-9]{2}\.[0-9]{2}\.[0-9]{2}\+[0-9]{6}[0-9]{2}$ ]]; then
        echo "❌ 错误: $PUBSPEC_PATH 中的版本号格式必须为 YY.MM.DD+YYMMDDXX (例如: 26.05.23+26052301)"
        echo "当前版本号: $VERSION"
        exit 1
    fi
    
    # 验证日期一致性
    local DATE_DOTS=$(echo $VERSION | cut -d'+' -f1)
    local DATE_NUM=$(echo $VERSION | cut -d'+' -f2 | cut -c1-6)
    local DATE_DOTS_STRIPPED=$(echo $DATE_DOTS | tr -d '.')
    
    if [ "$DATE_DOTS_STRIPPED" != "$DATE_NUM" ]; then
        echo "❌ 错误: 版本名称中的日期 ($DATE_DOTS) 与构建号中的日期 ($DATE_NUM) 不一致"
        exit 1
    fi

    # 验证月份和日期范围
    local MM=$(echo $DATE_DOTS | cut -d'.' -f2)
    local DD=$(echo $DATE_DOTS | cut -d'.' -f3)
    if [ $((10#$MM)) -lt 1 ] || [ $((10#$MM)) -gt 12 ]; then
        echo "❌ 错误: 月份 ($MM) 无效"
        exit 1
    fi
    if [ $((10#$DD)) -lt 1 ] || [ $((10#$DD)) -gt 31 ]; then
        echo "❌ 错误: 日期 ($DD) 无效"
        exit 1
    fi

    # 验证日期不晚于明天
    TOMORROW=$($PYTHON_EXEC -c "from datetime import datetime, timedelta; print((datetime.now() + timedelta(days=1)).strftime('%y%m%d'))" 2>/dev/null || \
               python3 -c "from datetime import datetime, timedelta; print((datetime.now() + timedelta(days=1)).strftime('%y%m%d'))" 2>/dev/null || \
               python -c "from datetime import datetime, timedelta; print((datetime.now() + timedelta(days=1)).strftime('%y%m%d'))" 2>/dev/null)
    if [ -n "$TOMORROW" ]; then
        if [ "$DATE_NUM" -gt "$TOMORROW" ]; then
            echo "❌ 错误: 版本日期 ($DATE_NUM) 不能超过明天 ($TOMORROW)"
            exit 1
        fi
    fi

    echo "✅ 版本号校验通过: $VERSION"

    #=========================================================
    # 校验 min_ver_code 格式 (YYMMDDXX)
    #=========================================================
    local MIN_VER_CODE=$(grep "^min_ver_code:" "$PUBSPEC_PATH" | awk '{print $2}')
    if [ -n "$MIN_VER_CODE" ]; then
        # 正则表达式验证: YYMMDDXX
        if [[ ! $MIN_VER_CODE =~ ^[0-9]{8}$ ]]; then
            echo "❌ 错误: $PUBSPEC_PATH 中的 min_ver_code 格式必须为 YYMMDDXX (例如: 26051101)"
            echo "当前 min_ver_code: $MIN_VER_CODE"
            exit 1
        fi

        # 验证 min_ver_code 不大于当前 build number
        local BUILD_NUMBER=$(echo $VERSION | cut -d'+' -f2)
        if [ "$MIN_VER_CODE" -gt "$BUILD_NUMBER" ]; then
            echo "❌ 错误: min_ver_code ($MIN_VER_CODE) 不能大于当前构建号 ($BUILD_NUMBER)"
            exit 1
        fi
        
        # 验证 min_ver_code 的日期部分合法性
        local MIN_MM=$(echo $MIN_VER_CODE | cut -c3-4)
        local MIN_DD=$(echo $MIN_VER_CODE | cut -c5-6)
        if [ $((10#$MIN_MM)) -lt 1 ] || [ $((10#$MIN_MM)) -gt 12 ]; then
            echo "❌ 错误: min_ver_code 中的月份 ($MIN_MM) 无效"
            exit 1
        fi
        if [ $((10#$MIN_DD)) -lt 1 ] || [ $((10#$MIN_DD)) -gt 31 ]; then
            echo "❌ 错误: min_ver_code 中的日期 ($MIN_DD) 无效"
            exit 1
        fi
        
        echo "✅ min_ver_code 校验通过: $MIN_VER_CODE"
    fi
}

# Flags & Variables
BUILD_ONLY=false
UPLOAD_ONLY=false
SKIP_TESTS=false
CUSTOM_APK_PATH=""

show_usage() {
    cat << EOF
用法: $0 [选项]

选项:
  --client-id ID          Huawei Client ID
  --client-secret SECRET  Huawei Client Secret
  --app-id ID             Huawei App ID
  --apk PATH              指定 APK 路径 (默认: build/app/outputs/flutter-apk/app-release.apk)
  --skip-tests            跳过单元测试步骤
  --build-only            仅构建 APK，不上传
  --upload-only           仅上传已有 APK，不重新构建与测试
  --help, -h              显示此帮助信息
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --client-id)
                CLIENT_ID="$2"
                shift 2
                ;;
            --client-secret)
                CLIENT_SECRET="$2"
                shift 2
                ;;
            --app-id)
                APP_ID="$2"
                shift 2
                ;;
            --apk)
                CUSTOM_APK_PATH="$2"
                shift 2
                ;;
            --skip-tests)
                SKIP_TESTS=true
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
            --help|-h)
                show_usage
                exit 0
                ;;
            *)
                echo "❌ 未知选项: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

parse_args "$@"

validate_version

echo "======================================"
echo "   Build and Upload to Huawei AppGallery"
echo "======================================"

# 1. 凭证检查 (仅在需要上传时严格检查)
gather_credentials() {
    # Resolve Client Secret
    CLIENT_SECRET=${CLIENT_SECRET:-${HUAWEI_API_CLIENT_SECRET:-$HUAWEI_CLIENT_SECRET}}

    # Resolve App ID
    APP_ID=${APP_ID:-${HUAWEI_PPDC_APP_ID:-$HUAWEI_APP_ID}}

    # Resolve Client ID
    CLIENT_ID=${CLIENT_ID:-${HUAWEI_API_CLIENT_ID:-${HUAWEI_CLIENT_ID:-$DEFAULT_CLIENT_ID}}}

    echo "DEBUG: Checking credentials..."
    if [ -n "$CLIENT_SECRET" ]; then echo " - HUAWEI_API_CLIENT_SECRET: [FOUND]"; else echo " - HUAWEI_API_CLIENT_SECRET: [NOT FOUND]"; fi
    if [ -n "$CLIENT_ID" ]; then echo " - HUAWEI_API_CLIENT_ID: $CLIENT_ID"; else echo " - HUAWEI_API_CLIENT_ID: [NOT FOUND]"; fi
    if [ -n "$APP_ID" ]; then echo " - HUAWEI_PPDC_APP_ID: $APP_ID"; else echo " - HUAWEI_PPDC_APP_ID: [NOT FOUND]"; fi

    if [ -z "$CLIENT_SECRET" ] && [ "$CLIENT_ID" == "$DEFAULT_CLIENT_ID" ] && [ -z "$HUAWEI_API_CLIENT_ID" ] && [ -z "$HUAWEI_CLIENT_ID" ]; then
        read -p "Enter Client ID [$DEFAULT_CLIENT_ID]: " INPUT_CLIENT_ID
        CLIENT_ID=${INPUT_CLIENT_ID:-$DEFAULT_CLIENT_ID}
    fi

    if [ -z "$CLIENT_SECRET" ]; then
        read -sp "Enter Client Secret: " CLIENT_SECRET
        echo ""
    fi

    if [ -z "$APP_ID" ]; then
        read -p "Enter App ID: " APP_ID
    fi

    if [ -z "$CLIENT_SECRET" ] || [ -z "$APP_ID" ]; then
        echo "❌ Error: Client Secret and App ID are required."
        exit 1
    fi
}

# 2. Run Unit Tests
run_unit_tests() {
    if [ "$SKIP_TESTS" = true ]; then
        echo "⏭️  跳过单元测试 (--skip-tests)"
        return
    fi
    echo ""
    echo "=================================================="
    echo " 🧪 正在运行单元测试 (flutter test)..."
    echo "=================================================="
    cd "$PROJECT_ROOT"
    flutter test -j 1
    echo "✅ 所有测试用例已通过！"
}

# 3. Build APK
build_apk() {
    CONFIG_FILE="$PROJECT_ROOT/lib/config.dart"
    BACKUP_CONFIG_FILE="${CONFIG_FILE}.bak"

    echo ""
    echo "Preparing configuration..."

    # 1. Backup original config
    cp "$CONFIG_FILE" "$BACKUP_CONFIG_FILE"

    # 2. Define cleanup function to restore config
    restore_config() {
        if [ -f "$BACKUP_CONFIG_FILE" ]; then
            echo ""
            echo "Restoring original configuration..."
            mv "$BACKUP_CONFIG_FILE" "$CONFIG_FILE"
        fi
    }

    # 3. Register cleanup to run on exit or error
    trap restore_config EXIT INT TERM

    # 4. Modify config to use 'prod'
    sed 's/static String profileName = ".*";/static String profileName = "prod";/' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"

    echo "Configuration switched to 'prod'."

    echo ""
    echo "Building Flutter APK (Release)..."
    cd "$PROJECT_ROOT"
    flutter build apk --release

    APK_PATH="$PROJECT_ROOT/build/app/outputs/flutter-apk/app-release.apk"
    if [ ! -f "$APK_PATH" ]; then
        echo "❌ Error: APK not found at $APK_PATH"
        exit 1
    fi

    echo "✅ Build successful: $APK_PATH"

    # 构建完成安全恢复配置
    restore_config
    trap - EXIT INT TERM
}

# 4. Upload APK
upload_apk() {
    gather_credentials

    local target_apk="${CUSTOM_APK_PATH:-$PROJECT_ROOT/build/app/outputs/flutter-apk/app-release.apk}"
    if [ ! -f "$target_apk" ]; then
        echo "❌ Error: APK not found at $target_apk"
        exit 1
    fi

    echo ""
    echo "Uploading to Huawei AppGallery ($target_apk)..."
    "$PYTHON_EXEC" "$UPLOAD_SCRIPT" \
        --client-id "$CLIENT_ID" \
        --client-secret "$CLIENT_SECRET" \
        --app-id "$APP_ID" \
        --file "$target_apk"
    echo "✅ Huawei Upload Done!"
}

# --- 执行流程 ---
if [ "$UPLOAD_ONLY" = true ]; then
    echo "▶️ 模式: 仅上传已有 APK"
    upload_apk
elif [ "$BUILD_ONLY" = true ]; then
    echo "▶️ 模式: 仅构建 APK"
    run_unit_tests
    build_apk
else
    echo "▶️ 模式: 完整构建并上传"
    gather_credentials
    run_unit_tests
    build_apk
    upload_apk
fi

ELAPSED_TIME=$(($SECONDS - $START_TIME))
echo "Total time: $(($ELAPSED_TIME / 60)) minutes and $(($ELAPSED_TIME % 60)) seconds."
