#!/bin/sh

# Xcode Cloud 构建前脚本
# 在 Xcode 构建之前运行 Flutter 命令来生成必要的配置文件

set +e

log() {
  printf "%s\n" "$*"
}

SCRIPT_VERSION="2025-12-14.1"

fail() {
  log ""
  log "❌ 错误: $*"
  exit 1
}

run_cmd() {
  # 用法: run_cmd "描述" command...
  DESC="$1"
  shift
  log ""
  log "▶️  $DESC"
  log "    命令: $*"
  "$@"
  CODE=$?
  if [ $CODE -ne 0 ]; then
    log "❌ 命令失败 (退出码: $CODE): $DESC"
    return $CODE
  fi
  return 0
}

log "🔧 开始 Xcode Cloud 构建前准备..."
log "🧾 脚本版本: $SCRIPT_VERSION"
log "📋 环境信息:"
log "  - 当前目录: $PWD"
log "  - 用户: $(whoami)"
log "  - HOME: $HOME"
log "  - PATH: $PATH"
log "  - XCODE_CLOUD_WORKFLOW: ${XCODE_CLOUD_WORKFLOW:-<未设置>}"
log "  - CI: ${CI:-<未设置>}"
log "  - 脚本路径: $0"

is_flutter_healthy() {
  # 返回 0 表示可用；1 表示不可用（比如 0.0.0-unknown）
  if [ -z "$FLUTTER_ROOT" ] || [ ! -x "$FLUTTER_ROOT/bin/flutter" ]; then
    return 1
  fi
  VER_OUT=$("$FLUTTER_ROOT/bin/flutter" --version 2>/dev/null)
  CODE=$?
  if [ $CODE -ne 0 ]; then
    return 1
  fi
  # Xcode Cloud 上经常会出现某个“残缺 Flutter”导致版本显示 unknown/unknown source，
  # 这会导致 flutter pub get 把 Flutter 版本当作 0.0.0-unknown 进而解析失败。
  echo "$VER_OUT" | grep -q "0.0.0-unknown" && return 1
  # 正常情况下第一行会包含语义化版本号，例如：Flutter 3.32.5 • channel stable • ...
  echo "$VER_OUT" | head -n 1 | grep -Eq 'Flutter[[:space:]]+[0-9]+\.[0-9]+\.[0-9]+' || return 1
  return 0
}

decode_base64() {
  # macOS 的 base64 参数在不同环境可能不同，直接用 python3 解码更稳
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import base64,sys; print(base64.b64decode(sys.argv[1]).decode("utf-8", "ignore"))' "$1" 2>/dev/null
    return $?
  fi
  # fallback：兼容 GNU/macOS base64
  echo "$1" | base64 --decode 2>/dev/null || echo "$1" | base64 -D 2>/dev/null
}

detect_flutter_version_from_project() {
  # 尝试从 ios/Flutter/flutter_export_environment.sh 中解析 DART_DEFINES 里的 FLUTTER_VERSION
  # 该文件在 Flutter 构建流程中常见（本仓库也存在），可用来锁定稳定的 Flutter 发布版本
  ENV_SH="$APP_DIR/ios/Flutter/flutter_export_environment.sh"
  if [ ! -f "$ENV_SH" ]; then
    return 1
  fi
  DART_DEFINES_LINE=$(grep '^export "DART_DEFINES=' "$ENV_SH" 2>/dev/null | head -n 1)
  if [ -z "$DART_DEFINES_LINE" ]; then
    return 1
  fi
  # 提取引号内内容
  DART_DEFINES=$(echo "$DART_DEFINES_LINE" | sed -n 's/^export "DART_DEFINES=\(.*\)"$/\1/p')
  if [ -z "$DART_DEFINES" ]; then
    return 1
  fi
  for seg in $(echo "$DART_DEFINES" | tr ',' ' '); do
    decoded=$(decode_base64 "$seg")
    case "$decoded" in
      FLUTTER_VERSION=*)
        echo "${decoded#FLUTTER_VERSION=}"
        return 0
        ;;
    esac
  done
  return 1
}

ensure_flutter_version_known() {
  # 某些情况下 shallow clone + 未拉取 tags 会导致 flutter --version 显示 0.0.0-unknown
  if is_flutter_healthy; then
    return 0
  fi

  log "🩺 检测到 Flutter 版本异常（可能是 0.0.0-unknown 或无法识别语义版本），尝试修复（拉取 tags / 补全历史）..."
  cd "$FLUTTER_ROOT" || fail "无法进入 Flutter 目录: $FLUTTER_ROOT"

  # Flutter 版本信息可能被缓存为 unknown，先清理缓存文件
  if [ -f "$FLUTTER_ROOT/bin/cache/flutter.version.json" ]; then
    log "🧹 清理 Flutter 版本缓存: $FLUTTER_ROOT/bin/cache/flutter.version.json"
    rm -f "$FLUTTER_ROOT/bin/cache/flutter.version.json"
  fi

  # 先拉取 tags（大多数情况下即可恢复正常版本号）
  run_cmd "git fetch --tags --force（用于恢复 flutter --version）" git fetch --tags --force || true
  # 触发 Flutter 重新生成版本信息
  "$FLUTTER_ROOT/bin/flutter" --version >/dev/null 2>&1 || true

  if is_flutter_healthy; then
    return 0
  fi

  # 再尝试补全 shallow 仓库（unshallow），避免 git describe 找不到版本
  run_cmd "git fetch --unshallow（补全 shallow 历史）" git fetch --unshallow || true
  run_cmd "git fetch --tags --force（再次拉取 tags）" git fetch --tags --force || true
  "$FLUTTER_ROOT/bin/flutter" --version >/dev/null 2>&1 || true

  if is_flutter_healthy; then
    return 0
  fi

  # 仍然 unknown，直接报错并提示如何处理
  VER_OUT=$("$FLUTTER_ROOT/bin/flutter" --version 2>/dev/null || true)
  log "⚠️  当前 flutter --version 输出:"
  log "$VER_OUT"

  log ""
  log "🔎 Flutter Git 诊断信息:"
  if [ -d "$FLUTTER_ROOT/.git" ]; then
    log "  - is-shallow: $(git -C "$FLUTTER_ROOT" rev-parse --is-shallow-repository 2>/dev/null || echo "<未知>")"
    log "  - head: $(git -C "$FLUTTER_ROOT" rev-parse --short HEAD 2>/dev/null || echo "<未知>")"
    log "  - describe: $(git -C "$FLUTTER_ROOT" describe --tags --always --dirty 2>/dev/null || echo "<失败>")"
    log "  - tag count: $(git -C "$FLUTTER_ROOT" tag -l 2>/dev/null | wc -l | tr -d ' ')"
  else
    log "  - 不是 git 仓库: $FLUTTER_ROOT/.git 不存在"
  fi

  fail "Flutter 版本仍为 unknown（通常是仓库 tags/历史未完整，或网络受限导致 fetch 失败）。可在 Xcode Cloud Workflow 设置 FLUTTER_GIT_URL 为可访问镜像后重试。"
}

# 进入应用目录（相对于脚本位置）
# Xcode Cloud 的工作目录通常是项目根目录（包含 .xcodeproj 的目录）
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
IOS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_DIR="$(cd "$IOS_DIR/.." && pwd)"

# 验证是否在正确的目录
if [ ! -f "$APP_DIR/pubspec.yaml" ]; then
    log "⚠️  警告: 未找到 pubspec.yaml，尝试从当前工作目录查找..."
    # 尝试从当前目录向上查找
    CURRENT_DIR="$PWD"
    while [ "$CURRENT_DIR" != "/" ]; do
        if [ -f "$CURRENT_DIR/pubspec.yaml" ]; then
            APP_DIR="$CURRENT_DIR"
            break
        fi
        CURRENT_DIR=$(dirname "$CURRENT_DIR")
    done
fi

if [ ! -f "$APP_DIR/pubspec.yaml" ]; then
    fail "无法找到 pubspec.yaml 文件。当前目录: $PWD，尝试的路径: $APP_DIR"
fi

log "📂 应用目录: $APP_DIR"

# 从 .metadata 推断 Flutter channel/revision（用于 Xcode Cloud 自动安装 Flutter，避免版本漂移）
METADATA_FILE="$APP_DIR/.metadata"
METADATA_REVISION=""
METADATA_CHANNEL=""
if [ -f "$METADATA_FILE" ]; then
  METADATA_REVISION=$(sed -n 's/^[[:space:]]*revision:[[:space:]]*"\(.*\)".*/\1/p' "$METADATA_FILE" | head -n 1)
  METADATA_CHANNEL=$(sed -n 's/^[[:space:]]*channel:[[:space:]]*"\(.*\)".*/\1/p' "$METADATA_FILE" | head -n 1)
fi

# 允许通过环境变量覆盖（优先级更高）
FLUTTER_GIT_URL="${FLUTTER_GIT_URL:-https://github.com/flutter/flutter.git}"
FLUTTER_GIT_REVISION="${FLUTTER_GIT_REVISION:-$METADATA_REVISION}"
FLUTTER_CHANNEL="${FLUTTER_CHANNEL:-$METADATA_CHANNEL}"

if [ -n "$FLUTTER_GIT_REVISION" ]; then
  log "📌 Flutter 期望 revision: $FLUTTER_GIT_REVISION${FLUTTER_CHANNEL:+ (channel: $FLUTTER_CHANNEL)}"
else
  log "⚠️  未从 .metadata 解析到 Flutter revision，将使用已安装 Flutter 或下载 stable 最新。"
fi

install_flutter_if_needed() {
  # Xcode Cloud 默认不会预装 Flutter，找不到时自动下载到 $HOME/flutter（可复用缓存）
  # 默认使用 $HOME/flutter（可写），避免 /Users/local/flutter 这类不可控/残缺的 Flutter
  # 注意：Xcode Cloud 的 HOME 可能就是 /Users/local，历史上这里可能存在一个“0.0.0-unknown”的残缺 Flutter；
  # 为避免与系统/历史目录冲突，默认安装到隐藏目录（可通过环境变量覆盖）。
  MANAGED_FLUTTER_ROOT="${MANAGED_FLUTTER_ROOT:-$HOME/.nnbdc_flutter}"

  if [ -z "$FLUTTER_ROOT" ] && [ -d "$HOME/flutter" ]; then
    export FLUTTER_ROOT="$HOME/flutter"
  fi

  # 若外部环境已经设置了 FLUTTER_ROOT，但 Flutter 版本是 unknown，则忽略并切换到可控目录
  if [ -n "$FLUTTER_ROOT" ] && [ -x "$FLUTTER_ROOT/bin/flutter" ]; then
    if is_flutter_healthy; then
      return 0
    fi
    if [ -z "$NNBDC_RESPECT_FLUTTER_ROOT" ]; then
      log "⚠️  检测到现有 Flutter 不可用（版本 unknown 或执行失败）：$FLUTTER_ROOT"
      log "➡️  将改用可控的 Flutter 目录：$MANAGED_FLUTTER_ROOT"
      export FLUTTER_ROOT="$MANAGED_FLUTTER_ROOT"
    else
      fail "现有 FLUTTER_ROOT 指向的 Flutter 不可用: $FLUTTER_ROOT（已设置 NNBDC_RESPECT_FLUTTER_ROOT，拒绝自动切换）"
    fi
  fi

  # 若切换后的 FLUTTER_ROOT 已存在 flutter，可用则直接用；不可用则继续走“修复/重装”逻辑
  if [ -n "$FLUTTER_ROOT" ] && [ -x "$FLUTTER_ROOT/bin/flutter" ]; then
    if is_flutter_healthy; then
      return 0
    fi
    log "⚠️  检测到当前 Flutter 不可用（版本 unknown 或执行失败）：$FLUTTER_ROOT"
    log "➡️  将尝试修复或重新安装"
  fi

  if command -v flutter >/dev/null 2>&1; then
    # 从 flutter 命令推断路径
    FLUTTER_BIN=$(command -v flutter 2>/dev/null)
    if [ -n "$FLUTTER_BIN" ]; then
      export FLUTTER_ROOT=$(dirname "$(dirname "$FLUTTER_BIN")")
      if is_flutter_healthy; then
        return 0
      fi
      # PATH 里的 flutter 也可能是“残缺版”，同样忽略
      if [ -z "$NNBDC_RESPECT_FLUTTER_ROOT" ]; then
        log "⚠️  PATH 中的 flutter 不可用（版本 unknown 或执行失败）：$FLUTTER_ROOT"
        log "➡️  将改用可控的 Flutter 目录：$MANAGED_FLUTTER_ROOT"
        export FLUTTER_ROOT="$MANAGED_FLUTTER_ROOT"
      else
        fail "PATH 中的 flutter 不可用且已设置 NNBDC_RESPECT_FLUTTER_ROOT，无法继续"
      fi
    fi
  fi

  # 如果目标目录已存在 flutter，但版本 unknown，优先尝试修复（拉 tags / unshallow）
  if [ -n "$FLUTTER_ROOT" ] && [ -x "$FLUTTER_ROOT/bin/flutter" ]; then
    ensure_flutter_version_known
    return 0
  fi

  log "🔍 未找到 Flutter SDK，开始自动安装..."
  export GIT_TERMINAL_PROMPT=0
  command -v git >/dev/null 2>&1 || fail "git 不存在，无法自动安装 Flutter（请在 Xcode Cloud 环境中确保 git 可用）"
  log "🧰 git 版本: $(git --version 2>/dev/null || echo "<未知>")"

  export FLUTTER_ROOT="${FLUTTER_ROOT:-$MANAGED_FLUTTER_ROOT}"

  # 优先从项目解析 Flutter 发布版本号（例如 3.32.5），用 tag clone 能避免版本 unknown
  if [ -z "$FLUTTER_TAG" ]; then
    DETECTED_VER=$(detect_flutter_version_from_project 2>/dev/null || true)
    if [ -n "$DETECTED_VER" ]; then
      FLUTTER_TAG="$DETECTED_VER"
      log "🏷️  从项目解析到 Flutter 版本: $FLUTTER_TAG（将优先使用该 tag）"
    fi
  fi

  # 若目标目录存在但不完整（不是 git 仓库），可能是历史残留/下载中断导致，先清理再装
  if [ -d "$FLUTTER_ROOT" ] && [ ! -d "$FLUTTER_ROOT/.git" ]; then
    log "🧹 检测到 Flutter 目录存在但不是 git 仓库，将清理后重新安装：$FLUTTER_ROOT"
    rm -rf "$FLUTTER_ROOT"
  fi

  if [ ! -d "$FLUTTER_ROOT/.git" ]; then
    log "⬇️  克隆 Flutter SDK 到: $FLUTTER_ROOT"
    # 使用 shallow clone 提升 Xcode Cloud 首次构建速度
    # 如果已解析到 Flutter 发布版本（tag），优先按 tag clone，可避免 flutter --version 为 unknown
    if [ -n "$FLUTTER_TAG" ]; then
      CLONE_REF="$FLUTTER_TAG"
    else
      CLONE_REF="${FLUTTER_CHANNEL:-stable}"
    fi
    git clone --depth 1 --branch "$CLONE_REF" "$FLUTTER_GIT_URL" "$FLUTTER_ROOT"
    CLONE_CODE=$?
    if [ $CLONE_CODE -ne 0 ]; then
      log ""
      log "❌ 克隆 Flutter 仓库失败 (退出码: $CLONE_CODE)"
      log "  - 仓库地址: $FLUTTER_GIT_URL"
      log "  - 分支/频道: $CLONE_REF"
      log ""
      log "可能原因/解决方案:"
      log "1) Xcode Cloud 构建机无法访问该地址（网络限制/DNS/需要代理）"
      log "   - 可在 Workflow 环境变量中设置 FLUTTER_GIT_URL 为可用镜像"
      log "2) 你已在 Workflow 配置了 FLUTTER_ROOT，但路径不正确"
      log "   - 请确保 FLUTTER_ROOT/bin/flutter 存在且可执行"
      exit $CLONE_CODE
    fi
  else
    log "✅ 已存在 Flutter SDK: $FLUTTER_ROOT"
  fi

  cd "$FLUTTER_ROOT" || fail "无法进入 Flutter 目录: $FLUTTER_ROOT"
  # 尽量 checkout 到 .metadata 的 revision，确保与本地一致
  if [ -n "$FLUTTER_GIT_REVISION" ]; then
    log "🔁 切换 Flutter 到 revision: $FLUTTER_GIT_REVISION"
    # shallow clone 场景下，先尝试 fetch 单个 commit
    git fetch --depth 1 origin "$FLUTTER_GIT_REVISION" || git fetch origin "$FLUTTER_GIT_REVISION" || true
    git checkout "$FLUTTER_GIT_REVISION" || fail "无法 checkout Flutter revision: $FLUTTER_GIT_REVISION（可能是网络导致 fetch 不到该 commit）"
  elif [ -n "$FLUTTER_CHANNEL" ]; then
    log "🔁 切换 Flutter 到 channel: $FLUTTER_CHANNEL"
    git fetch origin "$FLUTTER_CHANNEL" || true
    git checkout "$FLUTTER_CHANNEL" || true
  fi

  # 确保 flutter --version 不为 0.0.0-unknown，否则 pub 解析依赖会失败
  ensure_flutter_version_known
}

# 获取 Flutter 路径
# Xcode Cloud 通常会在环境变量中设置 FLUTTER_ROOT
# 如果没有，尝试使用默认路径或从 PATH 中查找
if [ -z "$FLUTTER_ROOT" ]; then
    log "🔍 FLUTTER_ROOT 未设置，尝试自动查找..."
    
    # 尝试从常见位置查找 Flutter
    if [ -d "$HOME/flutter" ]; then
        export FLUTTER_ROOT="$HOME/flutter"
        log "✅ 在 $HOME/flutter 找到 Flutter"
    elif command -v flutter >/dev/null 2>&1; then
        # 从 flutter 命令推断路径
        FLUTTER_BIN=$(which flutter 2>/dev/null)
        if [ -n "$FLUTTER_BIN" ]; then
            export FLUTTER_ROOT=$(dirname $(dirname "$FLUTTER_BIN"))
            log "✅ 从 PATH 中找到 Flutter: $FLUTTER_ROOT"
        fi
    else
        log "⚠️  未找到 Flutter SDK（将尝试自动安装）"
    fi
else
    log "✅ 使用环境变量 FLUTTER_ROOT: $FLUTTER_ROOT"
fi

# 找不到则自动安装
install_flutter_if_needed

# 验证 Flutter 路径
if [ ! -d "$FLUTTER_ROOT" ]; then
    fail "Flutter SDK 路径不存在: $FLUTTER_ROOT"
fi

if [ ! -f "$FLUTTER_ROOT/bin/flutter" ]; then
    fail "Flutter 可执行文件不存在: $FLUTTER_ROOT/bin/flutter"
fi

log "📦 Flutter SDK 路径: $FLUTTER_ROOT"
log "📦 Flutter 版本:"
"$FLUTTER_ROOT/bin/flutter" --version || log "  ⚠️  无法获取 Flutter 版本"

# 添加 Flutter 到 PATH
export PATH="$FLUTTER_ROOT/bin:$PATH"
hash -r 2>/dev/null || true

log "🔎 Flutter 自检（用于定位 0.0.0-unknown）:"
log "  - which flutter: $(command -v flutter 2>/dev/null || echo "<未找到>")"
log "  - flutter --version: $("$FLUTTER_ROOT/bin/flutter" --version 2>/dev/null | head -n 1 || echo "<失败>")"
if [ -d "$FLUTTER_ROOT/.git" ]; then
  log "  - git describe: $(git -C "$FLUTTER_ROOT" describe --tags --always --dirty 2>/dev/null || echo "<失败>")"
  log "  - is-shallow: $(git -C "$FLUTTER_ROOT" rev-parse --is-shallow-repository 2>/dev/null || echo "<未知>")"
fi

cd "$APP_DIR" || fail "无法进入应用目录: $APP_DIR"

# 预缓存 iOS 相关产物，避免首次构建下载导致失败/超时
run_cmd "运行 flutter precache --ios" "$FLUTTER_ROOT/bin/flutter" precache --ios
PRECACHE_EXIT_CODE=$?
if [ $PRECACHE_EXIT_CODE -ne 0 ]; then
  fail "flutter precache --ios 执行失败"
fi

# 运行 flutter pub get 生成 Generated.xcconfig
log "📥 运行 flutter pub get..."
"$FLUTTER_ROOT/bin/flutter" pub get
PUB_GET_EXIT_CODE=$?

if [ $PUB_GET_EXIT_CODE -ne 0 ]; then
    log "调试信息:"
    log "  - Flutter 路径: $FLUTTER_ROOT"
    log "  - flutter --version: $("$FLUTTER_ROOT/bin/flutter" --version 2>/dev/null | head -n 1 || echo "<失败>")"
    log "  - 应用目录: $APP_DIR"
    log "  - pubspec.yaml 存在: $([ -f "$APP_DIR/pubspec.yaml" ] && echo "是" || echo "否")"
    exit "$PUB_GET_EXIT_CODE"
fi

log "✅ flutter pub get 执行成功"

# 运行代码生成（retrofit/json_serializable/drift 等）
# Xcode Cloud 环境不会自动生成，缺失会导致编译失败（例如 lib/api/api.g.dart 不存在）
log "🛠️  运行 build_runner 生成代码..."
"$FLUTTER_ROOT/bin/flutter" pub run build_runner build --delete-conflicting-outputs
BUILD_RUNNER_EXIT_CODE=$?
if [ $BUILD_RUNNER_EXIT_CODE -ne 0 ]; then
    fail "build_runner 执行失败 (退出码: $BUILD_RUNNER_EXIT_CODE)"
fi

# 关键生成文件校验（避免后续 archive 才报错）
if [ ! -f "$APP_DIR/lib/api/api.g.dart" ]; then
    fail "代码生成后仍未找到文件: $APP_DIR/lib/api/api.g.dart（请检查 retrofit_generator/build_runner 配置）"
fi
log "✅ build_runner 生成完成"

# 验证 Generated.xcconfig 是否已生成
GENERATED_XCCONFIG="$APP_DIR/ios/Flutter/Generated.xcconfig"
if [ ! -f "$GENERATED_XCCONFIG" ]; then
    log "调试信息:"
    log "  - ios/Flutter 目录存在: $([ -d "$APP_DIR/ios/Flutter" ] && echo "是" || echo "否")"
    if [ -d "$APP_DIR/ios/Flutter" ]; then
        log "  - ios/Flutter 目录内容:"
        ls -la "$APP_DIR/ios/Flutter" || true
    fi
    fail "Generated.xcconfig 文件未生成，路径: $GENERATED_XCCONFIG"
fi

log "✅ Generated.xcconfig 已生成: $GENERATED_XCCONFIG"

# 显示文件内容的前几行（用于调试）
log "📄 Generated.xcconfig 内容预览:"
head -10 "$GENERATED_XCCONFIG" || log "  ⚠️  无法读取文件内容"

# 预先执行 pod install（Xcode Cloud 不一定会自动执行，且 Flutter 的 Podfile 依赖 Generated.xcconfig）
IOS_WORKDIR="$APP_DIR/ios"
if [ -d "$IOS_WORKDIR" ]; then
  if command -v pod >/dev/null 2>&1; then
    log "📦 CocoaPods 版本: $(pod --version 2>/dev/null || echo "<未知>")"
    # Xcode Cloud 环境下可能无法解析 dldir1.qq.com，导致 WechatOpenSDK-XCFramework 下载失败。
    # 本仓库已提交 Pods（包含 WechatOpenSDK.xcframework），因此在 CI 下优先复用已存在的 Pods，避免联网下载。
    PODS_DIR="$IOS_WORKDIR/Pods"
    WECHAT_POD_XCFRAMEWORK="$PODS_DIR/WechatOpenSDK-XCFramework/WechatOpenSDK.xcframework"

    if [ "${CI:-}" = "TRUE" ] && [ -d "$WECHAT_POD_XCFRAMEWORK" ] && [ -f "$PODS_DIR/Manifest.lock" ] && [ "${NNBDC_FORCE_POD_INSTALL:-}" != "1" ]; then
      log "✅ 检测到已提交的 Pods 且包含 WechatOpenSDK，跳过 pod install（避免 dldir1.qq.com DNS 失败）"
      log "  - Pods: $PODS_DIR"
      log "  - WechatOpenSDK: $WECHAT_POD_XCFRAMEWORK"
      log "  - 如需强制执行 pod install，可设置环境变量 NNBDC_FORCE_POD_INSTALL=1"
    else
      if [ "${NNBDC_FORCE_POD_INSTALL:-}" = "1" ]; then
        log "⚙️  已设置 NNBDC_FORCE_POD_INSTALL=1，将强制执行 pod install"
      fi
      
      # Fix Xcode Cloud SQLite and WeChat SDK download timeout issue by manually resolving the IP
      log "🔧 配置 curl 绕过 www.sqlite.org 和 dldir1.qq.com 的 DNS 解析问题..."
      echo "--resolve www.sqlite.org:443:194.195.208.62" >> ~/.curlrc
      echo "--resolve www.sqlite.org:80:194.195.208.62" >> ~/.curlrc
      echo "--resolve dldir1.qq.com:443:118.123.208.150" >> ~/.curlrc
      echo "--resolve dldir1.qq.com:80:118.123.208.150" >> ~/.curlrc
      
      log "📦 运行 pod install..."
      cd "$IOS_WORKDIR" || fail "无法进入 iOS 目录: $IOS_WORKDIR"
      pod install
      POD_EXIT_CODE=$?
      if [ $POD_EXIT_CODE -ne 0 ]; then
        fail "pod install 执行失败 (退出码: $POD_EXIT_CODE)"
      fi
      cd "$APP_DIR" || fail "无法返回应用目录: $APP_DIR"
    fi
  else
    log "⚠️  未找到 pod 命令，跳过 pod install（如后续构建失败，请在 Xcode Cloud 镜像中安装 CocoaPods）"
  fi
fi

log ""
log "✅ Xcode Cloud 构建前准备完成！"
