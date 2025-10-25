#!/bin/bash

# macOS 应用签名和公证脚本
# 用途：对 macOS 应用进行代码签名和公证，以通过 Gatekeeper 检查

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 配置（需要根据实际情况修改）
DEVELOPER_ID="开发者ID应用证书名称"  # 例如: "Developer ID Application: Your Name (TEAM_ID)"
APP_PATH="$1"
APPLE_ID="your-apple-id@example.com"
TEAM_ID="YOUR_TEAM_ID"
APP_PASSWORD="app-specific-password"  # App 专用密码

# 显示使用说明
show_usage() {
    echo "用法: $0 <app路径> [选项]"
    echo ""
    echo "参数:"
    echo "  app路径           要签名的 .app 或 .dmg 文件路径"
    echo ""
    echo "选项:"
    echo "  --skip-sign      跳过签名步骤"
    echo "  --skip-notarize  跳过公证步骤"
    echo "  --help           显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0 build/macos/Build/Products/Release/nnbdc.app"
    echo "  $0 releases/ppdc.dmg"
    echo ""
    echo "配置说明:"
    echo "  1. 需要 Apple Developer 账号 (https://developer.apple.com)"
    echo "  2. 需要创建 Developer ID 证书"
    echo "  3. 需要创建 App 专用密码 (https://appleid.apple.com)"
    echo "  4. 修改脚本中的 DEVELOPER_ID, APPLE_ID, TEAM_ID, APP_PASSWORD"
}

# 检查是否有 Apple Developer 证书
check_certificate() {
    print_info "检查 Apple Developer 证书..."
    
    if ! security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
        print_error "未找到 Developer ID Application 证书"
        print_warn "请访问 https://developer.apple.com 申请 Developer 账号并创建证书"
        print_warn "证书类型: Developer ID Application"
        exit 1
    fi
    
    print_info "找到可用的签名证书"
    security find-identity -v -p codesigning | grep "Developer ID Application"
}

# 签名应用
sign_app() {
    local app_path="$1"
    
    print_info "开始签名应用..."
    
    # 签名所有嵌入的框架和库
    if [ -d "${app_path}/Contents/Frameworks" ]; then
        print_info "签名嵌入的框架..."
        find "${app_path}/Contents/Frameworks" -name "*.dylib" -o -name "*.framework" | while read framework; do
            codesign --force --verify --verbose --timestamp \
                --options runtime \
                --sign "${DEVELOPER_ID}" \
                "${framework}"
        done
    fi
    
    # 签名应用本身
    print_info "签名应用主体..."
    codesign --force --verify --verbose --timestamp \
        --options runtime \
        --sign "${DEVELOPER_ID}" \
        --entitlements "macos/Runner/Release.entitlements" \
        "${app_path}"
    
    # 验证签名
    print_info "验证签名..."
    codesign --verify --deep --strict --verbose=2 "${app_path}"
    
    if [ $? -eq 0 ]; then
        print_info "✅ 签名成功"
    else
        print_error "❌ 签名验证失败"
        exit 1
    fi
}

# 创建 DMG（如果输入是 .app）
create_dmg_if_needed() {
    local app_path="$1"
    
    if [[ "${app_path}" == *.app ]]; then
        print_info "创建签名后的 DMG..."
        local dmg_name="${app_path%.*}_signed.dmg"
        
        hdiutil create -volname "泡泡单词" \
            -srcfolder "${app_path}" \
            -ov -format UDZO \
            "${dmg_name}"
        
        # 签名 DMG
        print_info "签名 DMG..."
        codesign --force --sign "${DEVELOPER_ID}" "${dmg_name}"
        
        echo "${dmg_name}"
    else
        # 如果已经是 DMG，直接签名
        print_info "签名 DMG..."
        codesign --force --sign "${DEVELOPER_ID}" "${app_path}"
        echo "${app_path}"
    fi
}

# 公证应用
notarize_app() {
    local dmg_path="$1"
    
    print_info "开始公证应用..."
    print_warn "公证可能需要几分钟到几小时，请耐心等待..."
    
    # 上传到 Apple 进行公证
    print_info "上传应用到 Apple..."
    xcrun notarytool submit "${dmg_path}" \
        --apple-id "${APPLE_ID}" \
        --team-id "${TEAM_ID}" \
        --password "${APP_PASSWORD}" \
        --wait
    
    if [ $? -eq 0 ]; then
        print_info "✅ 公证成功"
        
        # 装订公证票据
        print_info "装订公证票据..."
        xcrun stapler staple "${dmg_path}"
        
        # 验证装订
        print_info "验证公证票据..."
        xcrun stapler validate "${dmg_path}"
        
        print_info "🎉 应用已完成签名和公证！"
        print_info "用户现在可以直接安装，无需额外操作"
    else
        print_error "❌ 公证失败"
        print_warn "请检查 Apple ID、Team ID 和 App 专用密码是否正确"
        exit 1
    fi
}

# 简易说明（无需签名的情况）
show_user_guide() {
    print_warn "============================================"
    print_warn "当前应用未进行签名和公证"
    print_warn "用户安装时需要执行以下操作之一："
    print_warn "============================================"
    echo ""
    echo "方法1: 通过系统设置允许"
    echo "  1. 尝试打开应用时，会看到安全提示"
    echo "  2. 打开 系统设置 → 隐私与安全性"
    echo "  3. 点击 '仍要打开' 按钮"
    echo ""
    echo "方法2: 右键打开"
    echo "  1. 右键点击应用"
    echo "  2. 选择 '打开'"
    echo "  3. 确认打开"
    echo ""
    echo "方法3: 命令行移除隔离属性"
    echo "  xattr -cr /Applications/ppdc.app"
    echo ""
    print_info "============================================"
    print_info "建议：申请 Apple Developer 账号进行签名和公证"
    print_info "费用：99 USD/年"
    print_info "链接：https://developer.apple.com/programs/"
    print_info "============================================"
}

# 主函数
main() {
    print_info "======== macOS 应用签名和公证工具 ========"
    echo ""
    
    # 解析参数
    SKIP_SIGN=false
    SKIP_NOTARIZE=false
    
    if [ -z "$1" ] || [ "$1" == "--help" ]; then
        show_usage
        exit 0
    fi
    
    for arg in "$@"; do
        case $arg in
            --skip-sign)
                SKIP_SIGN=true
                ;;
            --skip-notarize)
                SKIP_NOTARIZE=true
                ;;
        esac
    done
    
    if [ ! -e "${APP_PATH}" ]; then
        print_error "文件不存在: ${APP_PATH}"
        exit 1
    fi
    
    # 检查是否配置了开发者信息
    if [[ "${DEVELOPER_ID}" == "开发者ID应用证书名称" ]]; then
        print_warn "未配置 Apple Developer 信息"
        show_user_guide
        exit 0
    fi
    
    # 执行签名和公证
    if [ "$SKIP_SIGN" = false ]; then
        check_certificate
        sign_app "${APP_PATH}"
        DMG_PATH=$(create_dmg_if_needed "${APP_PATH}")
    else
        DMG_PATH="${APP_PATH}"
    fi
    
    if [ "$SKIP_NOTARIZE" = false ]; then
        notarize_app "${DMG_PATH}"
    fi
    
    print_info "✅ 完成！"
    print_info "输出文件: ${DMG_PATH}"
}

main "$@"

