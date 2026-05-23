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
}

validate_version

echo "======================================"
echo "   Build and Upload to Huawei AppGallery"
echo "======================================"

# Reason for restoring: Shell variables defined in the terminal (like `VAR=val`) are NOT visible
# to scripts (child processes) unless they are `export`ed (like `export VAR=val`).
# Loading the .env file here ensures the script can see them without requiring you to type `export` manually.



echo "DEBUG: Checking credentials..."
# DEBUG: Print status of variables (masking secret)
if [ -n "$HUAWEI_API_CLIENT_SECRET" ]; then echo " - HUAWEI_API_CLIENT_SECRET: [FOUND]"; else echo " - HUAWEI_API_CLIENT_SECRET: [NOT FOUND]"; fi
if [ -n "$HUAWEI_API_CLIENT_ID" ]; then echo " - HUAWEI_API_CLIENT_ID: $HUAWEI_API_CLIENT_ID"; else echo " - HUAWEI_API_CLIENT_ID: [NOT FOUND]"; fi
if [ -n "$HUAWEI_PPDC_APP_ID" ]; then echo " - HUAWEI_PPDC_APP_ID: $HUAWEI_PPDC_APP_ID"; else echo " - HUAWEI_PPDC_APP_ID: [NOT FOUND]"; fi

# 1. Gather Credentials

# Resolve Client Secret
CLIENT_SECRET=${HUAWEI_API_CLIENT_SECRET:-$HUAWEI_CLIENT_SECRET}

# Resolve App ID
APP_ID=${HUAWEI_PPDC_APP_ID:-$HUAWEI_APP_ID}

# Resolve Client ID
# Check HUAWEI_API_CLIENT_ID (if user adds it later), then HUAWEI_CLIENT_ID, then default
CLIENT_ID=${HUAWEI_API_CLIENT_ID:-${HUAWEI_CLIENT_ID:-$DEFAULT_CLIENT_ID}}

# Logic: If we have the SECRET (via Env) and we are using the Default Client ID, assume the user accepts the default to allow automation.
# Only prompt if we DON'T have a secret (interactive mode) AND explicit Client ID override is missing.
if [ -z "$CLIENT_SECRET" ] && [ "$CLIENT_ID" == "$DEFAULT_CLIENT_ID" ] && [ -z "$HUAWEI_API_CLIENT_ID" ] && [ -z "$HUAWEI_CLIENT_ID" ]; then
    # Only prompt if no environment variable provided at all AND we are likely in interactive mode (no secret)
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
    echo "Error: Client Secret and App ID are required."
    exit 1
fi

# 2. Prepare Config & Build APK
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
trap restore_config EXIT

# 4. Modify config to use 'prod'
# Use sed to replace profileName = "..." with profileName = "prod"
# Using a temp file for compatibility with both GNU and BSD sed
sed 's/static String profileName = ".*";/static String profileName = "prod";/' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"

echo "Configuration switched to 'prod'."

echo ""
# 5. Build

echo ""
echo "Building Flutter APK (Release)..."
cd "$PROJECT_ROOT"
flutter build apk --release

# Find the built APK
APK_PATH="$PROJECT_ROOT/build/app/outputs/flutter-apk/app-release.apk"

if [ ! -f "$APK_PATH" ]; then
    echo "Error: APK not found at $APK_PATH"
    exit 1
fi

echo "Build successful: $APK_PATH"

# 3. Upload
echo ""
echo "Uploading to Huawei AppGallery..."
"$PYTHON_EXEC" "$UPLOAD_SCRIPT" \
    --client-id "$CLIENT_ID" \
    --client-secret "$CLIENT_SECRET" \
    --app-id "$APP_ID" \
    --file "$APK_PATH"

echo "Done!"
ELAPSED_TIME=$(($SECONDS - $START_TIME))
echo "Total time: $(($ELAPSED_TIME / 60)) minutes and $(($ELAPSED_TIME % 60)) seconds."
