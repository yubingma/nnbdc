#!/bin/sh

# Xcode Cloud 构建前脚本
# 在 Xcode 构建之前运行 Flutter 命令来生成必要的配置文件

set +e

log() {
  printf "%s\n" "$*"
}

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
log "📋 环境信息:"
log "  - 当前目录: $PWD"
log "  - 用户: $(whoami)"
log "  - HOME: $HOME"
log "  - PATH: $PATH"
log "  - XCODE_CLOUD_WORKFLOW: ${XCODE_CLOUD_WORKFLOW:-<未设置>}"
log "  - CI: ${CI:-<未设置>}"
log "  - 脚本路径: $0"

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
  if [ -z "$FLUTTER_ROOT" ] && [ -d "$HOME/flutter" ]; then
    export FLUTTER_ROOT="$HOME/flutter"
  fi

  if [ -n "$FLUTTER_ROOT" ] && [ -x "$FLUTTER_ROOT/bin/flutter" ]; then
    return 0
  fi

  if command -v flutter >/dev/null 2>&1; then
    # 从 flutter 命令推断路径
    FLUTTER_BIN=$(command -v flutter 2>/dev/null)
    if [ -n "$FLUTTER_BIN" ]; then
      export FLUTTER_ROOT=$(dirname "$(dirname "$FLUTTER_BIN")")
      return 0
    fi
  fi

  log "🔍 未找到 Flutter SDK，开始自动安装..."
  export GIT_TERMINAL_PROMPT=0
  command -v git >/dev/null 2>&1 || fail "git 不存在，无法自动安装 Flutter（请在 Xcode Cloud 环境中确保 git 可用）"
  log "🧰 git 版本: $(git --version 2>/dev/null || echo "<未知>")"

  export FLUTTER_ROOT="${FLUTTER_ROOT:-$HOME/flutter}"
  if [ ! -d "$FLUTTER_ROOT/.git" ]; then
    log "⬇️  克隆 Flutter SDK 到: $FLUTTER_ROOT"
    # 使用 shallow clone 提升 Xcode Cloud 首次构建速度；如需指定 revision，则后续再 fetch 单个 commit
    CLONE_REF="${FLUTTER_CHANNEL:-stable}"
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

cd "$APP_DIR" || fail "无法进入应用目录: $APP_DIR"

# 预缓存 iOS 相关产物，避免首次构建下载导致失败/超时
run_cmd "运行 flutter precache --ios" flutter precache --ios
PRECACHE_EXIT_CODE=$?
if [ $PRECACHE_EXIT_CODE -ne 0 ]; then
  fail "flutter precache --ios 执行失败"
fi

# 运行 flutter pub get 生成 Generated.xcconfig
log "📥 运行 flutter pub get..."
flutter pub get
PUB_GET_EXIT_CODE=$?

if [ $PUB_GET_EXIT_CODE -ne 0 ]; then
    log "调试信息:"
    log "  - Flutter 路径: $FLUTTER_ROOT"
    log "  - 应用目录: $APP_DIR"
    log "  - pubspec.yaml 存在: $([ -f "$APP_DIR/pubspec.yaml" ] && echo "是" || echo "否")"
    exit "$PUB_GET_EXIT_CODE"
fi

log "✅ flutter pub get 执行成功"

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
    log "📦 运行 pod install..."
    cd "$IOS_WORKDIR" || fail "无法进入 iOS 目录: $IOS_WORKDIR"
    pod install
    POD_EXIT_CODE=$?
    if [ $POD_EXIT_CODE -ne 0 ]; then
      fail "pod install 执行失败 (退出码: $POD_EXIT_CODE)"
    fi
    cd "$APP_DIR" || fail "无法返回应用目录: $APP_DIR"
  else
    log "⚠️  未找到 pod 命令，跳过 pod install（如后续构建失败，请在 Xcode Cloud 镜像中安装 CocoaPods）"
  fi
fi

log ""
log "✅ Xcode Cloud 构建前准备完成！"
