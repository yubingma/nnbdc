#!/bin/bash
set -e
START_TIME=$SECONDS

# ==============================================================================
# 泡泡单词 Android APK 构建与小米应用商店发布
#
# 小米走「应用自动发布接口」：
#   查询应用  POST https://api.developer.xiaomi.com/devupload/dev/query
#   推送应用  POST https://api.developer.xiaomi.com/devupload/dev/push
# 接口会先查询本账号下的包名状态，再自动决定推送方式：
#   允许版本更新 -> synchroType=1（只传 APK）
#   只允许新增   -> synchroType=0（还要传图标、至少 3 张手机截图与上架文案）
#
# 凭证三件套（小米开放平台 → 管理中心 → 自动发布接口）：
#   XIAOMI_DEV_ACCOUNT      登录小米开放平台的邮箱
#   XIAOMI_DEV_PRIVATE_KEY  该页面获取/重置得到的私钥（访问密码，不是登录密码）
#   XIAOMI_DEV_PUBLIC_KEY   该页面下载的公钥证书文件（.cer）路径
# ==============================================================================

# Resolve symlinks to find the real script directory (works on macOS and Linux)
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do
  DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
PROJECT_ROOT="$SCRIPT_DIR/../app"
UPLOAD_SCRIPT="$SCRIPT_DIR/upload_xiaomi.py"
PYTHON_EXEC="$SCRIPT_DIR/../.venv/bin/python"

# 包名以 Android 工程为准，避免两处各写一份
PACKAGE_NAME=$(grep -m1 "applicationId" "$PROJECT_ROOT/android/app/build.gradle" | sed -E 's/.*"([^"]+)".*/\1/')
if [ -z "$PACKAGE_NAME" ]; then
    echo "❌ 错误: 无法从 $PROJECT_ROOT/android/app/build.gradle 解析出 applicationId"
    exit 1
fi

# ==============================================================================
# 渠道应用名：小米用品信部备案登记的「泡泡单词」，即仓库里 strings.xml 的默认值。
# 华为渠道包在 build-and-upload-huawei.sh 里被临时改成「泡泡单词英语版」（华为重名），
# 所以这里必须先断言名字没被上一次中断的构建改脏，否则会被备案名称校验驳回。
# 每个渠道各自产出一份独立 APK，避免两个渠道互相覆盖同一个文件。
# ==============================================================================
CHANNEL_APP_NAME="泡泡单词"
STRINGS_FILE="$PROJECT_ROOT/android/app/src/main/res/values/strings.xml"
CHANNEL_APK="$PROJECT_ROOT/build/app/outputs/flutter-apk/app-release-xiaomi.apk"

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

    echo "✅ 版本号校验通过: $VERSION"

    #=========================================================
    # 校验 min_ver_code 格式 (YYMMDDXX)
    #=========================================================
    local MIN_VER_CODE=$(grep "^min_ver_code:" "$PUBSPEC_PATH" | awk '{print $2}')
    if [ -n "$MIN_VER_CODE" ]; then
        if [[ ! $MIN_VER_CODE =~ ^[0-9]{8}$ ]]; then
            echo "❌ 错误: $PUBSPEC_PATH 中的 min_ver_code 格式必须为 YYMMDDXX (例如: 26051101)"
            echo "当前 min_ver_code: $MIN_VER_CODE"
            exit 1
        fi

        local BUILD_NUMBER=$(echo $VERSION | cut -d'+' -f2)
        if [ "$MIN_VER_CODE" -gt "$BUILD_NUMBER" ]; then
            echo "❌ 错误: min_ver_code ($MIN_VER_CODE) 不能大于当前构建号 ($BUILD_NUMBER)"
            exit 1
        fi

        echo "✅ min_ver_code 校验通过: $MIN_VER_CODE"
    fi
}

# Flags & Variables
BUILD_ONLY=false
UPLOAD_ONLY=false
SKIP_TESTS=false
QUERY_ONLY=false
CUSTOM_APK_PATH=""
ACCOUNT=""
PRIVATE_KEY=""
PUBLIC_KEY=""
UPDATE_DESC="优化学习体验，修复已知问题"

# ==============================================================================
# 首次新增应用（synchroType=0）用的上架素材
#
# 只在小米商店第一次收录这个包名时用得到（接口查询回 create=true、updateVersion=false）。
# 一旦首个版本提交成功，这个包名此后只会走「更新版本」，本节内容不再参与。
# 小米的硬性规格：图标 512×512 PNG 且与 APK 内图标一致；手机截图 1080×1920、
# 平板截图 1536×2048，均至少 4 张、最多 5 张、单张不超过 5MB、不得重复。
# ==============================================================================
STORE_ASSET_DIR="$SCRIPT_DIR/应用上架资源/xiaomi"
APP_NAME="泡泡单词"                                              # 必须与 APK 内 strings.xml 的 app_name 及工信部备案名称一致
CATEGORY="12"                                                   # 12 = 学习教育
KEYWORDS="背单词 英语单词 四六级 考研 雅思 默写 词库"              # 最多 8 个，每个不超过 5 个汉字
BRIEF="以输出为核心的背单词应用"                                  # 5~16 个字符
PRIVACY_URL="https://www.nnbdc.com/privacy_android.html"
ICON="$STORE_ASSET_DIR/icon-512x512.png"
SUITABLE_TYPE="2"                                               # 0=手机 1=平板 2=手机和平板
MOBILE_SHOT_DIR="$STORE_ASSET_DIR/手机"
PAD_SHOT_DIR="$STORE_ASSET_DIR/平板"
# 截图上限 5 张，按文件名顺序取前 5 张（渲染脚本产出 7 张，供人工挑选）
MOBILE_SHOTS_ALL=( "$MOBILE_SHOT_DIR"/*.png )
PAD_SHOTS_ALL=( "$PAD_SHOT_DIR"/*.png )
SCREENSHOTS=( "${MOBILE_SHOTS_ALL[@]:0:5}" )
PAD_SCREENSHOTS=( "${PAD_SHOTS_ALL[@]:0:5}" )
SHOTS_FROM_CLI=false
PAD_SHOTS_FROM_CLI=false
APP_DESC=$(cat <<'EOF'
产品定位
泡泡单词是一款以"输出"为核心的英语单词学习应用。我们不做"看图选词"式的选择题记忆，而是要求用户在每一个单词上完成真实的产出——把英文写出来、把释义写出来、把单词念出来，以此确认自己是否真的记住。
记忆方式
· 英译汉 / 汉译英：看英文写中文释义，看中文拼写英文单词。
· 例句英译汉 / 例句汉译英：在句子语境中理解单词，而不是孤立记词。
· 手写默写：支持在屏幕上直接手写中文释义或英文单词，兼容键盘与手写混合输入。判题时对大小写、标点、连字符等形式差异予以容错，对释义内容严格判定。
· 语音答题：支持语音输入作答与跟读评分，可切换单词发音口音。
复习机制
· FSRS 智能复习：基于自由间隔重复算法，为每个单词单独计算复习时间，并根据你的作答反馈动态调整。
· 复习分布图：把每天的复习量摊平展示，帮助避免复习任务堆积。
学习规划
· 每日学习计划：可自定义每日新词数量、每批单词数量与学习环节组合。
· 三十天打卡记录：以日历形式记录每日学习情况。
· 生词本：答错的单词自动进入生词本，便于集中巩固。
词库
· 内置中高考、四六级、考研、托福、雅思等常用词库。
· 支持导入自定义词表，可按需建立个人专属词库。
其他功能
· 闲时听雨：以音频形式连续播放词单，适合通勤、运动等场景。
· 单词 PK：实时对战答题模式，答错的单词自动加入生词本。
· 荣耀勋章墙：记录学习成就，支持生成成就海报。
· 自测默写本：支持将词单导出为 PDF，用于打印或在平板上复习。
· 深色 / 浅色主题、字体大小调节。
· 支持多设备登录与学习数据同步。
适用人群
准备中高考、四六级、考研及出国留学考试的学生，以及需要长期积累专业词汇的学习者。学习数据仅用于学习进度与统计展示，具体见隐私政策。
关于收费
泡泡单词免费下载使用，基础功能免费。会员可用于解除每日学习词量上限、解锁全部官方词库及词库导入等功能。具体权益以应用内购买页面说明为准。
EOF
)

show_usage() {
    cat << EOF
用法: $0 [选项]

凭证选项:
  --account EMAIL         小米开放平台登录邮箱 (默认取 XIAOMI_DEV_ACCOUNT)
  --private-key KEY       自动发布接口私钥 (默认取 XIAOMI_DEV_PRIVATE_KEY)
  --public-key PATH       公钥证书 .cer 文件路径 (默认取 XIAOMI_DEV_PUBLIC_KEY)

发布选项:
  --apk PATH              指定 APK 路径 (默认: build/app/outputs/flutter-apk/app-release.apk)
  --update-desc TEXT      更新说明 (默认: $UPDATE_DESC)
  --query-only            只查询该包名在本账号下的状态，不推送
  --skip-tests            跳过单元测试步骤
  --build-only            仅构建 APK，不上传
  --upload-only           仅推送已有 APK，不重新构建与测试
  --help, -h              显示此帮助信息

首次新增应用 (synchroType=0) 才需要的上架素材:
  --app-name NAME         应用名称
  --category ID           应用分类 id (见接口 /dev/category)
  --keywords TEXT         搜索关键字，空格分隔
  --desc TEXT             应用介绍
  --brief TEXT            一句话简介
  --privacy-url URL       隐私政策链接
  --icon PATH             应用图标文件
  --screenshot PATH       手机截图文件，至少 4 张，可重复传入
  --suitable-type N       设备发布类型: 0=手机 1=平板 2=手机和平板 (默认: $SUITABLE_TYPE)
  --pad-screenshot PATH   平板截图文件，含平板时至少 4 张，可重复传入
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --account)        ACCOUNT="$2"; shift 2 ;;
            --private-key)    PRIVATE_KEY="$2"; shift 2 ;;
            --public-key)     PUBLIC_KEY="$2"; shift 2 ;;
            --apk)            CUSTOM_APK_PATH="$2"; shift 2 ;;
            --update-desc)    UPDATE_DESC="$2"; shift 2 ;;
            --app-name)       APP_NAME="$2"; shift 2 ;;
            --category)       CATEGORY="$2"; shift 2 ;;
            --keywords)       KEYWORDS="$2"; shift 2 ;;
            --desc)           APP_DESC="$2"; shift 2 ;;
            --brief)          BRIEF="$2"; shift 2 ;;
            --privacy-url)    PRIVACY_URL="$2"; shift 2 ;;
            --icon)           ICON="$2"; shift 2 ;;
            --screenshot)
                # 命令行给了截图就整批用命令行的，不与默认的那 5 张混在一起
                if [ "$SHOTS_FROM_CLI" = false ]; then SCREENSHOTS=(); SHOTS_FROM_CLI=true; fi
                SCREENSHOTS+=("$2"); shift 2
                ;;
            --suitable-type)  SUITABLE_TYPE="$2"; shift 2 ;;
            --pad-screenshot)
                if [ "$PAD_SHOTS_FROM_CLI" = false ]; then PAD_SCREENSHOTS=(); PAD_SHOTS_FROM_CLI=true; fi
                PAD_SCREENSHOTS+=("$2"); shift 2
                ;;
            --query-only)     QUERY_ONLY=true; shift ;;
            --skip-tests)     SKIP_TESTS=true; shift ;;
            --build-only)     BUILD_ONLY=true; shift ;;
            --upload-only)    UPLOAD_ONLY=true; shift ;;
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
echo "   Build and Upload to Xiaomi GetApps"
echo "======================================"
echo "包名: $PACKAGE_NAME"

# 1. 凭证检查 (仅在需要推送时严格检查)
gather_credentials() {
    ACCOUNT=${ACCOUNT:-$XIAOMI_DEV_ACCOUNT}
    PRIVATE_KEY=${PRIVATE_KEY:-$XIAOMI_DEV_PRIVATE_KEY}
    PUBLIC_KEY=${PUBLIC_KEY:-$XIAOMI_DEV_PUBLIC_KEY}

    if [ -n "$ACCOUNT" ]; then echo " - XIAOMI_DEV_ACCOUNT: $ACCOUNT"; else echo " - XIAOMI_DEV_ACCOUNT: [NOT FOUND]"; fi
    if [ -n "$PRIVATE_KEY" ]; then echo " - XIAOMI_DEV_PRIVATE_KEY: [FOUND]"; else echo " - XIAOMI_DEV_PRIVATE_KEY: [NOT FOUND]"; fi
    if [ -n "$PUBLIC_KEY" ]; then echo " - XIAOMI_DEV_PUBLIC_KEY: $PUBLIC_KEY"; else echo " - XIAOMI_DEV_PUBLIC_KEY: [NOT FOUND]"; fi

    if [ -z "$ACCOUNT" ]; then
        read -p "Enter 小米开发者账号邮箱: " ACCOUNT
    fi
    if [ -z "$PRIVATE_KEY" ]; then
        read -sp "Enter 自动发布接口私钥: " PRIVATE_KEY
        echo ""
    fi
    if [ -z "$PUBLIC_KEY" ]; then
        read -p "Enter 公钥证书 .cer 文件路径: " PUBLIC_KEY
    fi

    if [ -z "$ACCOUNT" ] || [ -z "$PRIVATE_KEY" ] || [ -z "$PUBLIC_KEY" ]; then
        echo "❌ Error: 账号邮箱、私钥、公钥证书缺一不可。"
        exit 1
    fi
    if [ ! -f "$PUBLIC_KEY" ]; then
        echo "❌ Error: 找不到公钥证书文件: $PUBLIC_KEY"
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

    # 4. Modify config to use 'prod'，并断言应用名就是备案登记的那个
    sed 's/static String profileName = ".*";/static String profileName = "prod";/' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"

    if ! grep -q "<string name=\"app_name\">${CHANNEL_APP_NAME}</string>" "$STRINGS_FILE"; then
        echo "❌ 错误: $STRINGS_FILE 里的应用名不是「${CHANNEL_APP_NAME}」。"
        echo "   小米会拿包体内的应用名与工信部备案名称比对，不一致会被驳回。"
        echo "   若上一次华为渠道构建被中断，strings.xml 可能留在「泡泡单词英语版」，请检查后重试。"
        exit 1
    fi

    echo "Configuration switched to 'prod'; app name confirmed as '${CHANNEL_APP_NAME}'."

    echo ""
    echo "Building Flutter APK (Release)..."
    cd "$PROJECT_ROOT"
    flutter build apk --release

    APK_PATH="$PROJECT_ROOT/build/app/outputs/flutter-apk/app-release.apk"
    if [ ! -f "$APK_PATH" ]; then
        echo "❌ Error: APK not found at $APK_PATH"
        exit 1
    fi

    # 5. 另存一份小米渠道产物：华为渠道会用不同的应用名再构建一次，同一个文件名会互相覆盖
    cp "$APK_PATH" "$CHANNEL_APK"

    echo "✅ Build successful: $CHANNEL_APK"

    # 构建完成安全恢复配置
    restore_config
    trap - EXIT INT TERM
}

# 4. Upload APK
upload_apk() {
    gather_credentials

    local target_apk="${CUSTOM_APK_PATH:-$CHANNEL_APK}"
    if [ ! -f "$target_apk" ]; then
        echo "❌ Error: APK not found at $target_apk"
        exit 1
    fi

    local extra_args=()
    if [ -n "$APP_NAME" ];    then extra_args+=(--app-name "$APP_NAME"); fi
    if [ -n "$CATEGORY" ];    then extra_args+=(--category "$CATEGORY"); fi
    if [ -n "$KEYWORDS" ];    then extra_args+=(--keywords "$KEYWORDS"); fi
    if [ -n "$APP_DESC" ];    then extra_args+=(--desc "$APP_DESC"); fi
    if [ -n "$BRIEF" ];       then extra_args+=(--brief "$BRIEF"); fi
    if [ -n "$PRIVACY_URL" ]; then extra_args+=(--privacy-url "$PRIVACY_URL"); fi
    if [ -n "$ICON" ];        then extra_args+=(--icon "$ICON"); fi
    for shot in "${SCREENSHOTS[@]}"; do
        extra_args+=(--screenshot "$shot")
    done
    extra_args+=(--suitable-type "$SUITABLE_TYPE")
    for shot in "${PAD_SCREENSHOTS[@]}"; do
        extra_args+=(--pad-screenshot "$shot")
    done

    echo ""
    if [ "$QUERY_ONLY" = true ]; then
        echo "查询小米应用商店该包名状态..."
        "$PYTHON_EXEC" "$UPLOAD_SCRIPT" \
            --account "$ACCOUNT" \
            --private-key "$PRIVATE_KEY" \
            --public-key "$PUBLIC_KEY" \
            --package-name "$PACKAGE_NAME" \
            --query-only
        return
    fi

    echo "Uploading to Xiaomi GetApps ($target_apk)..."
    "$PYTHON_EXEC" "$UPLOAD_SCRIPT" \
        --account "$ACCOUNT" \
        --private-key "$PRIVATE_KEY" \
        --public-key "$PUBLIC_KEY" \
        --package-name "$PACKAGE_NAME" \
        --apk "$target_apk" \
        --update-desc "$UPDATE_DESC" \
        "${extra_args[@]}"
    echo "✅ Xiaomi Upload Done!"
}

# --- 执行流程 ---
if [ "$UPLOAD_ONLY" = true ]; then
    echo "▶️ 模式: 仅推送已有 APK"
    upload_apk
elif [ "$BUILD_ONLY" = true ]; then
    echo "▶️ 模式: 仅构建 APK"
    run_unit_tests
    build_apk
elif [ "$QUERY_ONLY" = true ]; then
    echo "▶️ 模式: 仅查询小米应用商店包名状态"
    upload_apk
else
    echo "▶️ 模式: 完整构建并推送"
    gather_credentials
    run_unit_tests
    build_apk
    upload_apk
fi

ELAPSED_TIME=$(($SECONDS - $START_TIME))
echo "Total time: $(($ELAPSED_TIME / 60)) minutes and $(($ELAPSED_TIME % 60)) seconds."
