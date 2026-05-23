#!/bin/bash

#=========================================================
# 🚀 类似 mvn package 的 Flutter 构建脚本
# 工作流：执行 flutter test -> 若成功 -> 执行 flutter build
# 用法：./build.sh [构建类型(apk/ios/web)] [其他参数]
# 示例：./build.sh apk --release
#=========================================================

# 拦截所有错误
set -e

#=========================================================
# 校验版本号格式 (YY.MM.DD+YYMMDDXX)
#=========================================================
validate_version() {
    local PUBSPEC_PATH="pubspec.yaml"
    if [ ! -f "$PUBSPEC_PATH" ]; then
        echo "⚠️  未在当前目录找到 pubspec.yaml，尝试在 app/ 目录下查找..."
        PUBSPEC_PATH="app/pubspec.yaml"
    fi
    
    if [ ! -f "$PUBSPEC_PATH" ]; then
        echo "❌ 错误: 找不到 pubspec.yaml"
        return 1
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
    TOMORROW=$(python3 -c "from datetime import datetime, timedelta; print((datetime.now() + timedelta(days=1)).strftime('%y%m%d'))" 2>/dev/null || \
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

validate_version

echo "=================================================="
echo " 🧪 [1/2] 正在运行单元测试 (flutter test)..."
echo "=================================================="

# 运行所有测试项目，使用 -j 1 防止 GetStorage 等本地文件因为并发写入而抛出异常
flutter test -j 1

# 如果 flutter test 失败了，set -e 会让脚本在这里直接退出，不会继续执行 build。
echo ""
echo "✅ 所有测试用例已通过！"
echo ""

# 检查是否传入了参数，如果有才向后执行 build
if [ $# -eq 0 ]; then
    echo "ℹ️  没有提供构建参数，仅完成了测试环节。"
    exit 0
fi

echo "=================================================="
echo " 📦 [2/2] 开始构建 (flutter build $@)..."
echo "=================================================="

# 将用户传入的参数直接传递给 flutter build
flutter build "$@"

echo "=================================================="
echo " 🎉 构建成功完成！"
echo "=================================================="
