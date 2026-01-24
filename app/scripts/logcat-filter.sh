#!/bin/bash

# Android Logcat 过滤器 - 排除 ImageDecoder 错误
# 用法: ./logcat-filter.sh

echo "🔍 启动 Android Logcat 过滤器"
echo "📱 应用: com.nn.nnbdc"
echo "🚫 排除: ImageDecoder 相关错误"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# 检查 ADB 是否可用
if ! command -v adb &> /dev/null; then
    echo "❌ 错误: ADB 未找到"
    echo "请确保 Android SDK 已安装并添加到 PATH"
    exit 1
fi

# 检查设备连接
DEVICES=$(adb devices | grep -v "List" | grep "device$" | wc -l)
if [ "$DEVICES" -eq 0 ]; then
    echo "❌ 错误: 没有连接的 Android 设备"
    echo "请连接设备或启动模拟器"
    exit 1
fi

echo "✅ 已连接设备数: $DEVICES"
echo ""

# 清除旧日志（可选）
# adb logcat -c

# 启动过滤后的 logcat
adb logcat -v color | \
  grep --line-buffered -v "ImageDecoder" | \
  grep --line-buffered -v "Failed to decode image" | \
  grep --line-buffered -v "DecodeException"
