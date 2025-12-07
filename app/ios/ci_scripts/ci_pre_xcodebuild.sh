#!/bin/sh

# Xcode Cloud 构建前脚本
# 在 Xcode 构建之前运行 Flutter 命令来生成必要的配置文件

set -e

echo "🔧 开始 Xcode Cloud 构建前准备..."

# 获取 Flutter 路径
# Xcode Cloud 通常会在环境变量中设置 FLUTTER_ROOT
# 如果没有，尝试使用默认路径或从 PATH 中查找
if [ -z "$FLUTTER_ROOT" ]; then
    # 尝试从常见位置查找 Flutter
    if [ -d "$HOME/flutter" ]; then
        export FLUTTER_ROOT="$HOME/flutter"
    elif command -v flutter >/dev/null 2>&1; then
        # 从 flutter 命令推断路径
        FLUTTER_BIN=$(which flutter)
        export FLUTTER_ROOT=$(dirname $(dirname "$FLUTTER_BIN"))
    else
        echo "❌ 错误: 无法找到 Flutter SDK"
        echo "请确保 Flutter 已安装并配置在 PATH 中，或设置 FLUTTER_ROOT 环境变量"
        exit 1
    fi
fi

echo "📦 Flutter SDK 路径: $FLUTTER_ROOT"

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

# 验证 Generated.xcconfig 是否已生成
GENERATED_XCCONFIG="$APP_DIR/ios/Flutter/Generated.xcconfig"
if [ ! -f "$GENERATED_XCCONFIG" ]; then
    echo "❌ 错误: Generated.xcconfig 文件未生成"
    echo "文件路径: $GENERATED_XCCONFIG"
    exit 1
fi

echo "✅ Generated.xcconfig 已生成: $GENERATED_XCCONFIG"

# 显示文件内容的前几行（用于调试）
echo "📄 Generated.xcconfig 内容预览:"
head -5 "$GENERATED_XCCONFIG"

echo "✅ Xcode Cloud 构建前准备完成！"
