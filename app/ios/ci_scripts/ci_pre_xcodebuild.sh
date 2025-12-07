#!/bin/sh

# Xcode Cloud 构建前脚本
# 在 Xcode 构建之前运行 Flutter 命令来生成必要的配置文件

# 不要使用 set -e，以便更好地处理错误和提供调试信息
set +e

echo "🔧 开始 Xcode Cloud 构建前准备..."
echo "📋 环境信息:"
echo "  - 当前目录: $PWD"
echo "  - 用户: $(whoami)"
echo "  - HOME: $HOME"
echo "  - PATH: $PATH"

# 获取 Flutter 路径
# Xcode Cloud 通常会在环境变量中设置 FLUTTER_ROOT
# 如果没有，尝试使用默认路径或从 PATH 中查找
if [ -z "$FLUTTER_ROOT" ]; then
    echo "🔍 FLUTTER_ROOT 未设置，尝试自动查找..."
    
    # 尝试从常见位置查找 Flutter
    if [ -d "$HOME/flutter" ]; then
        export FLUTTER_ROOT="$HOME/flutter"
        echo "✅ 在 $HOME/flutter 找到 Flutter"
    elif command -v flutter >/dev/null 2>&1; then
        # 从 flutter 命令推断路径
        FLUTTER_BIN=$(which flutter 2>/dev/null)
        if [ -n "$FLUTTER_BIN" ]; then
            export FLUTTER_ROOT=$(dirname $(dirname "$FLUTTER_BIN"))
            echo "✅ 从 PATH 中找到 Flutter: $FLUTTER_ROOT"
        fi
    else
        echo "⚠️  未找到 Flutter SDK"
        echo "尝试的路径:"
        echo "  - $HOME/flutter"
        echo "  - PATH 中的 flutter 命令"
        echo ""
        echo "❌ 错误: 无法找到 Flutter SDK"
        echo ""
        echo "解决方案:"
        echo "1. 在 Xcode Cloud 工作流设置中添加环境变量 FLUTTER_ROOT"
        echo "2. 或者在脚本中安装 Flutter SDK"
        echo ""
        echo "当前环境变量:"
        env | grep -i flutter || echo "  无 Flutter 相关环境变量"
        exit 1
    fi
else
    echo "✅ 使用环境变量 FLUTTER_ROOT: $FLUTTER_ROOT"
fi

# 验证 Flutter 路径
if [ ! -d "$FLUTTER_ROOT" ]; then
    echo "❌ 错误: Flutter SDK 路径不存在: $FLUTTER_ROOT"
    exit 1
fi

if [ ! -f "$FLUTTER_ROOT/bin/flutter" ]; then
    echo "❌ 错误: Flutter 可执行文件不存在: $FLUTTER_ROOT/bin/flutter"
    exit 1
fi

echo "📦 Flutter SDK 路径: $FLUTTER_ROOT"
echo "📦 Flutter 版本:"
"$FLUTTER_ROOT/bin/flutter" --version || echo "  ⚠️  无法获取 Flutter 版本"

# 添加 Flutter 到 PATH
export PATH="$FLUTTER_ROOT/bin:$PATH"

# 进入应用目录（相对于脚本位置）
# Xcode Cloud 的工作目录通常是项目根目录（包含 .xcodeproj 的目录）
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
IOS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_DIR="$(cd "$IOS_DIR/.." && pwd)"

# 验证是否在正确的目录
if [ ! -f "$APP_DIR/pubspec.yaml" ]; then
    echo "⚠️  警告: 未找到 pubspec.yaml，尝试从当前工作目录查找..."
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
    echo "❌ 错误: 无法找到 pubspec.yaml 文件"
    echo "当前目录: $PWD"
    echo "尝试的路径: $APP_DIR"
    exit 1
fi

cd "$APP_DIR"
echo "📂 应用目录: $APP_DIR"

# 运行 flutter pub get 生成 Generated.xcconfig
echo "📥 运行 flutter pub get..."
flutter pub get
PUB_GET_EXIT_CODE=$?

if [ $PUB_GET_EXIT_CODE -ne 0 ]; then
    echo "❌ 错误: flutter pub get 执行失败 (退出码: $PUB_GET_EXIT_CODE)"
    echo ""
    echo "调试信息:"
    echo "  - Flutter 路径: $FLUTTER_ROOT"
    echo "  - 应用目录: $APP_DIR"
    echo "  - pubspec.yaml 存在: $([ -f "$APP_DIR/pubspec.yaml" ] && echo "是" || echo "否")"
    exit $PUB_GET_EXIT_CODE
fi

echo "✅ flutter pub get 执行成功"

# 验证 Generated.xcconfig 是否已生成
GENERATED_XCCONFIG="$APP_DIR/ios/Flutter/Generated.xcconfig"
if [ ! -f "$GENERATED_XCCONFIG" ]; then
    echo "❌ 错误: Generated.xcconfig 文件未生成"
    echo "文件路径: $GENERATED_XCCONFIG"
    echo ""
    echo "调试信息:"
    echo "  - ios/Flutter 目录存在: $([ -d "$APP_DIR/ios/Flutter" ] && echo "是" || echo "否")"
    if [ -d "$APP_DIR/ios/Flutter" ]; then
        echo "  - ios/Flutter 目录内容:"
        ls -la "$APP_DIR/ios/Flutter" || true
    fi
    exit 1
fi

echo "✅ Generated.xcconfig 已生成: $GENERATED_XCCONFIG"

# 显示文件内容的前几行（用于调试）
echo "📄 Generated.xcconfig 内容预览:"
head -10 "$GENERATED_XCCONFIG" || echo "  ⚠️  无法读取文件内容"

echo ""
echo "✅ Xcode Cloud 构建前准备完成！"
