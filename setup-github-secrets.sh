#!/bin/bash

# GitHub Actions Secrets 设置脚本
# 此脚本帮助你在 GitHub 仓库中设置必要的 secrets

echo "🔐 GitHub Actions Secrets 设置向导"
echo "=================================="
echo ""

# 检查是否在 Git 仓库中
if [ ! -d ".git" ]; then
    echo "❌ 错误：请在 Git 仓库根目录中运行此脚本"
    exit 1
fi

# 获取仓库信息
REPO_URL=$(git remote get-url origin 2>/dev/null)
if [ -z "$REPO_URL" ]; then
    echo "❌ 错误：无法获取 Git 仓库 URL"
    exit 1
fi

echo "📋 仓库信息："
echo "   URL: $REPO_URL"
echo ""

# 检查是否是 GitHub 仓库
if [[ ! "$REPO_URL" =~ github\.com ]]; then
    echo "❌ 错误：此脚本仅支持 GitHub 仓库"
    exit 1
fi

# 提取仓库名称
REPO_NAME=$(echo "$REPO_URL" | sed -E 's/.*github\.com[:/]([^/]+\/[^/]+)(\.git)?$/\1/')
echo "📦 仓库名称：$REPO_NAME"
echo ""

echo "🔧 需要设置的 GitHub Secrets："
echo "   1. KEYSTORE_PASSWORD - Android keystore 密码"
echo "   2. KEY_PASSWORD - Android key 密码"
echo ""

echo "📝 设置步骤："
echo "   1. 打开 https://github.com/$REPO_NAME/settings/secrets/actions"
echo "   2. 点击 'New repository secret'"
echo "   3. 添加以下 secrets："
echo ""

# 从 .zprofile 读取密码（如果存在）
if [ -f "$HOME/.zprofile" ]; then
    KEYSTORE_PASSWORD=$(grep "KEYSTORE_PASSWORD=" "$HOME/.zprofile" | cut -d'=' -f2)
    KEY_PASSWORD=$(grep "KEY_PASSWORD=" "$HOME/.zprofile" | cut -d'=' -f2)
    
    if [ -n "$KEYSTORE_PASSWORD" ] && [ -n "$KEY_PASSWORD" ]; then
        echo "✅ 从 ~/.zprofile 找到密码："
        echo "   KEYSTORE_PASSWORD: $KEYSTORE_PASSWORD"
        echo "   KEY_PASSWORD: $KEY_PASSWORD"
        echo ""
        echo "💡 你可以直接复制这些值到 GitHub Secrets"
    else
        echo "⚠️  在 ~/.zprofile 中未找到密码，请手动输入："
        echo ""
        read -p "请输入 KEYSTORE_PASSWORD: " KEYSTORE_PASSWORD
        read -p "请输入 KEY_PASSWORD: " KEY_PASSWORD
    fi
else
    echo "⚠️  未找到 ~/.zprofile 文件，请手动输入："
    echo ""
    read -p "请输入 KEYSTORE_PASSWORD: " KEYSTORE_PASSWORD
    read -p "请输入 KEY_PASSWORD: " KEY_PASSWORD
fi

echo ""
echo "📋 需要添加的 Secrets："
echo "   Name: KEYSTORE_PASSWORD"
echo "   Value: $KEYSTORE_PASSWORD"
echo ""
echo "   Name: KEY_PASSWORD"
echo "   Value: $KEY_PASSWORD"
echo ""

echo "🔗 直接链接："
echo "   https://github.com/$REPO_NAME/settings/secrets/actions"
echo ""

echo "✅ 设置完成后，你的 GitHub Actions 将能够："
echo "   - 自动使用环境变量进行 Android 构建"
echo "   - 无需在代码中硬编码密码"
echo "   - 支持安全的 CI/CD 流程"
echo ""

echo "🧪 测试建议："
echo "   1. 设置完 secrets 后，推送代码触发 workflow"
echo "   2. 检查 'Debug Environment Variables' 步骤的输出"
echo "   3. 确认 Android 构建成功"
echo ""

echo "📚 更多信息请查看：GITHUB_ACTIONS_ENV_SETUP.md"
