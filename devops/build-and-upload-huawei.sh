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

# 1. Gather Credentials

# Resolve Client ID
# Check HUAWEI_PPDC_CLIENT_ID (if user adds it later), then HUAWEI_CLIENT_ID, then default
CLIENT_ID=${HUAWEI_PPDC_CLIENT_ID:-${HUAWEI_CLIENT_ID:-$DEFAULT_CLIENT_ID}}

if [ "$CLIENT_ID" == "$DEFAULT_CLIENT_ID" ] && [ -z "$HUAWEI_PPDC_CLIENT_ID" ] && [ -z "$HUAWEI_CLIENT_ID" ]; then
    # Only prompt if no environment variable provided at all
    read -p "Enter Client ID [$DEFAULT_CLIENT_ID]: " INPUT_CLIENT_ID
    CLIENT_ID=${INPUT_CLIENT_ID:-$DEFAULT_CLIENT_ID}
fi

# Resolve Client Secret
CLIENT_SECRET=${HUAWEI_PPDC_CLIENT_SECRET:-$HUAWEI_CLIENT_SECRET}

if [ -z "$CLIENT_SECRET" ]; then
    read -sp "Enter Client Secret: " CLIENT_SECRET
    echo ""
fi

# Resolve App ID
APP_ID=${HUAWEI_PPDC_APP_ID:-$HUAWEI_APP_ID}

if [ -z "$APP_ID" ]; then
    read -p "Enter App ID: " APP_ID
fi

if [ -z "$CLIENT_SECRET" ] || [ -z "$APP_ID" ]; then
    echo "Error: Client Secret and App ID are required."
    exit 1
fi

# 2. Build APK
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
