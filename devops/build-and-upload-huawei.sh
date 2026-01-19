#!/bin/bash
set -e

# Configuration
# Default Client ID from screenshot, but allow override
DEFAULT_CLIENT_ID="116685955"
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$SCRIPT_DIR/../app"
UPLOAD_SCRIPT="$SCRIPT_DIR/upload_huawei.py"
PYTHON_EXEC="$SCRIPT_DIR/../.venv/bin/python"

# Check for Python virtual environment
if [ ! -f "$PYTHON_EXEC" ]; then
    echo "Error: Python ./venv not found at $PYTHON_EXEC"
    exit 1
fi

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
