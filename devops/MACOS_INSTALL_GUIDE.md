# macOS 安装指南

## 问题说明

macOS 的 Gatekeeper 安全机制会阻止未经 Apple 签名和公证的应用安装，显示类似以下错误：

- "无法打开，因为它来自身份不明的开发者"
- "无法验证开发者"
- "应用已损坏，无法打开"

## 用户端解决方案

### 方法1：通过系统设置允许（推荐）✅

1. 尝试打开 DMG 或 APP 时，会看到安全提示
2. 打开 **系统设置**（或 **系统偏好设置**）
3. 进入 **隐私与安全性**（或 **安全性与隐私**）
4. 在底部会看到一条消息说应用"已被阻止"
5. 点击 **仍要打开** 按钮
6. 在弹出的确认对话框中再次点击 **打开**

### 方法2：右键打开

1. 右键点击（或 Control + 点击）应用图标
2. 在菜单中选择 **打开**
3. 在弹出的对话框中点击 **打开** 按钮

注意：这种方法比双击打开多了一个选项

### 方法3：命令行移除隔离属性（高级用户）

```bash
# 移除 DMG 文件的隔离属性
xattr -cr ~/Downloads/ppdc.dmg

# 移除应用的隔离属性（安装到 Applications 后）
xattr -cr /Applications/nnbdc.app
```

## 开发者解决方案（永久）

要让用户无需额外操作即可安装，需要进行代码签名和公证。

### 前提条件

1. **Apple Developer 账号**
   - 费用：99 USD/年
   - 注册：https://developer.apple.com/programs/

2. **Developer ID 证书**
   - 在 Apple Developer 后台创建
   - 类型：Developer ID Application

3. **App 专用密码**
   - 在 Apple ID 管理页面创建
   - 链接：https://appleid.apple.com

### 使用签名脚本

项目中提供了自动化签名和公证脚本：

```bash
cd /Users/myb/nnbdc/devops

# 配置脚本中的开发者信息
# 编辑 sign-and-notarize.sh，修改以下变量：
# - DEVELOPER_ID: 证书名称
# - APPLE_ID: Apple ID 邮箱
# - TEAM_ID: 团队 ID
# - APP_PASSWORD: App 专用密码

# 查看使用说明
./sign-and-notarize.sh --help

# 签名并公证应用
./sign-and-notarize.sh ../app/build/macos/Build/Products/Release/nnbdc.app

# 签名并公证 DMG
./sign-and-notarize.sh ../releases/ppdc.dmg
```

### 手动签名流程

如果不使用脚本，可以手动执行：

```bash
# 1. 签名应用
codesign --force --verify --verbose --timestamp \
  --options runtime \
  --sign "Developer ID Application: Your Name (TEAM_ID)" \
  --entitlements macos/Runner/Release.entitlements \
  path/to/nnbdc.app

# 2. 验证签名
codesign --verify --deep --strict --verbose=2 path/to/nnbdc.app

# 3. 创建 DMG
hdiutil create -volname "泡泡单词" \
  -srcfolder path/to/nnbdc.app \
  -ov -format UDZO \
  ppdc_signed.dmg

# 4. 签名 DMG
codesign --force --sign "Developer ID Application: Your Name (TEAM_ID)" ppdc_signed.dmg

# 5. 上传公证
xcrun notarytool submit ppdc_signed.dmg \
  --apple-id your@email.com \
  --team-id TEAM_ID \
  --password app-specific-password \
  --wait

# 6. 装订公证票据
xcrun stapler staple ppdc_signed.dmg

# 7. 验证
xcrun stapler validate ppdc_signed.dmg
spctl -a -vv -t install ppdc_signed.dmg
```

## 下载页面说明

已在 `download.html` 中添加了 macOS 安装说明，用户下载后可以直接看到详细的操作指南。

## 相关链接

- [Apple Developer Program](https://developer.apple.com/programs/)
- [代码签名指南](https://developer.apple.com/support/code-signing/)
- [公证指南](https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution)
- [Gatekeeper 说明](https://support.apple.com/zh-cn/HT202491)

## 常见问题

### Q: 为什么不直接签名和公证？

A: 需要 Apple Developer 账号（99 USD/年），暂未购买。

### Q: 用户反馈说"应用已损坏"怎么办？

A: 这通常是隔离属性导致的，使用 `xattr -cr` 命令可以解决。

### Q: 签名后是否需要每次都公证？

A: 是的，每次构建新版本都需要重新签名和公证。

### Q: 可以使用自签名证书吗？

A: 不可以，必须使用 Apple 颁发的 Developer ID 证书。

## 临时方案

目前采用的方案：
1. ✅ 在下载页面添加详细的安装说明
2. ✅ 提供三种不同的解决方法
3. ⏳ 待申请 Apple Developer 账号后进行签名和公证

## 更新日志

- 2025-10-13: 初始版本，添加用户端解决方案和开发者指南

