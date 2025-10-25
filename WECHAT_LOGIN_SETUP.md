# 微信开放平台登录配置指南

本文档提供微信开放平台登录功能的完整配置步骤。

## 一、微信开放平台注册与配置

### 1. 注册微信开放平台账号

1. 访问 [微信开放平台](https://open.weixin.qq.com/)
2. 点击"注册"，使用微信扫码注册账号
3. 完成企业/个人认证（需要提供营业执照或个人身份信息）
4. 认证费用：企业认证300元/年

### 2. 创建移动应用

1. 登录微信开放平台，进入"管理中心"
2. 点击"创建移动应用"
3. 填写应用基本信息：
   - 应用名称：泡泡单词
   - 应用简介：英语单词学习应用
   - 应用官网：你的应用官网地址
   - 应用图标：上传应用图标
4. 填写平台信息：
   - **Android平台**：
     - 应用签名：从Android Studio获取（见下方说明）
     - 应用包名：`com.yourcompany.nnbdc`（根据实际修改）
   - **iOS平台**：
     - Bundle ID：`com.yourcompany.nnbdc`（根据实际修改）
5. 提交审核，等待微信审核通过（通常1-3个工作日）

### 3. 获取应用配置信息

审核通过后，在应用详情页可以看到：
- **AppID**（应用唯一标识）：`wx1234567890abcdef`
- **AppSecret**（应用密钥）：`1234567890abcdef1234567890abcdef`

**重要：AppSecret必须妥善保管，不能泄露！**

### 4. 获取Android应用签名

```bash
# 方法1：使用keytool（推荐）
keytool -list -v -keystore /path/to/your/keystore.jks

# 方法2：使用微信提供的签名生成工具
# 下载地址：https://developers.weixin.qq.com/doc/oplatform/Downloads/Android_Resource.html
# 安装到手机后，输入应用包名即可获取签名
```

签名示例：`a1b2c3d4e5f6g7h8`

## 二、后端配置

### 1. 配置微信应用信息

编辑 `server/nnbdc-service/src/main/resources/application.properties`，添加：

```properties
# 微信开放平台配置
wechat.app.id=wx1234567890abcdef
wechat.app.secret=1234567890abcdef1234567890abcdef
```

**注意：将上述值替换为你实际的AppID和AppSecret**

### 2. 执行数据库升级

运行数据库升级脚本，添加微信相关字段：

```bash
cd server
mysql -u your_username -p your_database < db-upgrade/upgrade.sql
```

或手动执行SQL：

```sql
-- 添加微信登录相关字段
ALTER TABLE `user` ADD COLUMN wechat_open_id VARCHAR(100) NULL COMMENT '微信OpenID' AFTER email;
ALTER TABLE `user` ADD COLUMN wechat_union_id VARCHAR(100) NULL COMMENT '微信UnionID' AFTER wechat_open_id;
ALTER TABLE `user` ADD COLUMN wechat_nickname VARCHAR(200) NULL COMMENT '微信昵称' AFTER wechat_union_id;
ALTER TABLE `user` ADD COLUMN wechat_avatar VARCHAR(500) NULL COMMENT '微信头像URL' AFTER wechat_nickname;

-- 为wechat_open_id添加唯一索引
CREATE UNIQUE INDEX idx_wechat_open_id ON `user` (wechat_open_id);
```

### 3. 添加Maven依赖

如果使用OkHttp和Jackson（已在项目中），确保pom.xml包含：

```xml
<dependency>
    <groupId>com.squareup.okhttp3</groupId>
    <artifactId>okhttp</artifactId>
    <version>4.10.0</version>
</dependency>
<dependency>
    <groupId>com.fasterxml.jackson.core</groupId>
    <artifactId>jackson-databind</artifactId>
</dependency>
```

### 4. 重启后端服务

```bash
cd server/nnbdc-service
mvn clean package
# 重启Tomcat或Spring Boot应用
```

## 三、前端配置（Flutter）

### 1. 添加微信SDK依赖

编辑 `app/pubspec.yaml`，添加：

```yaml
dependencies:
  # 微信登录SDK
  fluwx: ^4.1.0  # 或使用最新版本
```

然后执行：

```bash
cd app
flutter pub get
```

### 2. Android配置

编辑 `app/android/app/src/main/AndroidManifest.xml`，添加：

```xml
<manifest>
    <application>
        <!-- 其他配置 -->
        
        <!-- 微信登录回调 -->
        <activity
            android:name=".wxapi.WXEntryActivity"
            android:exported="true"
            android:label="@string/app_name"
            android:launchMode="singleTask"
            android:taskAffinity="你的包名">
            <intent-filter>
                <action android:name="android.intent.action.VIEW"/>
                <category android:name="android.intent.category.DEFAULT"/>
                <data android:scheme="你的AppID"/>
            </intent-filter>
        </activity>
    </application>
</manifest>
```

创建 `app/android/app/src/main/kotlin/你的包名路径/wxapi/WXEntryActivity.kt`：

```kotlin
package 你的包名.wxapi

import com.jarvan.fluwx.wxapi.FluwxWXEntryActivity

class WXEntryActivity : FluwxWXEntryActivity()
```

### 3. iOS配置

编辑 `app/ios/Runner/Info.plist`，添加：

```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleTypeRole</key>
        <string>Editor</string>
        <key>CFBundleURLName</key>
        <string>weixin</string>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>你的AppID</string>
        </array>
    </dict>
</array>

<key>LSApplicationQueriesSchemes</key>
<array>
    <string>weixin</string>
    <string>weixinULAPI</string>
</array>
```

### 4. 初始化微信SDK

编辑 `app/lib/main.dart`，在初始化代码中添加：

```dart
import 'package:fluwx/fluwx.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 初始化微信SDK
  await registerWxApi(
    appId: "wx1234567890abcdef",  // 替换为你的AppID
    doOnAndroid: true,
    doOnIOS: true,
    universalLink: "https://你的域名/apple-app-site-association/",  // iOS需要
  );
  
  runApp(MyApp());
}
```

### 5. 实现微信登录功能

在 `app/lib/page/login.dart` 中已经添加了微信登录按钮，需要更新实现：

```dart
import 'package:fluwx/fluwx.dart';

// 微信登录方法
void wechatLoginPressed() async {
  if (!_approved) {
    ToastUtil.error("请先同意[使用协议]和[隐私政策]");
    return;
  }

  setState(() {
    _isLoading = true;
  });

  try {
    // 1. 发起微信授权
    await sendWeChatAuth(
      scope: "snsapi_userinfo",
      state: "wechat_login",
    );

    // 2. 监听微信授权结果
    weChatResponseEventHandler.listen((response) async {
      if (response is WeChatAuthResponse) {
        if (response.code != null) {
          // 3. 使用code调用后端API登录
          Result result = await Api.client.loginByWechat(
            response.code!,
            getClientType().json,
            Global.version,
          );

          if (result.success) {
            // 4. 登录成功，保存用户信息
            final userResult = await UserBo().getLoggedInUser();
            if (userResult.success && userResult.data != null) {
              await Global.setLoggedInUser(userResult.data!);
            }
            Get.offAllNamed('/index');
          } else {
            ToastUtil.error(result.msg ?? '微信登录失败');
          }
        } else {
          ToastUtil.error('微信授权失败');
        }
      }
    });

  } catch (e, stackTrace) {
    ErrorHandler.handleNetworkError(e, stackTrace, api: 'loginByWechat');
  } finally {
    setState(() {
      _isLoading = false;
    });
  }
}
```

### 6. 重新生成数据库代码

由于修改了User表结构，需要重新生成Drift数据库代码：

```bash
cd app
flutter pub run build_runner build --delete-conflicting-outputs
```

## 四、测试

### 1. 测试环境要求

- **Android**：必须在真机上测试（模拟器无法使用微信）
- **iOS**：必须在真机上测试
- 手机必须安装微信客户端

### 2. 测试流程

1. 启动应用，进入登录页面
2. 点击"微信登录"按钮
3. 自动跳转到微信授权页面
4. 在微信中确认授权
5. 自动返回应用，完成登录
6. 检查用户信息是否正确（头像、昵称）

### 3. 常见问题

**问题1：点击微信登录无反应**
- 检查微信是否已安装
- 检查AppID是否配置正确
- 查看Android/iOS配置是否正确

**问题2：授权后返回应用失败**
- Android：检查WXEntryActivity是否正确配置
- iOS：检查URL Scheme和Universal Link配置

**问题3：提示"应用未授权"**
- 检查应用签名是否与微信开放平台配置一致
- 检查应用包名/Bundle ID是否一致

**问题4：后端返回"微信授权失败"**
- 检查后端application.properties中的配置
- 查看后端日志，确认微信API调用情况
- 验证AppSecret是否正确

## 五、上线前检查清单

- [ ] 微信开放平台应用审核通过
- [ ] 后端配置了正确的AppID和AppSecret
- [ ] 数据库已执行升级脚本
- [ ] Android应用签名与微信开放平台一致
- [ ] iOS配置了Universal Link（生产环境必需）
- [ ] 测试了完整的登录流程
- [ ] 测试了新用户注册和老用户登录
- [ ] 测试了用户信息更新（头像、昵称）

## 六、安全建议

1. **AppSecret保护**：
   - 不要将AppSecret提交到代码仓库
   - 使用环境变量或配置文件管理
   - 生产环境使用独立的配置

2. **数据传输**：
   - 确保HTTPS传输
   - code使用后立即失效
   - access_token妥善保管

3. **用户隐私**：
   - 明确告知用户授权获取的信息
   - 遵守隐私政策和用户协议
   - 用户可以随时解除授权

## 七、参考文档

- [微信开放平台官方文档](https://developers.weixin.qq.com/doc/oplatform/Mobile_App/WeChat_Login/Development_Guide.html)
- [Fluwx插件文档](https://pub.dev/packages/fluwx)
- [微信登录接口说明](https://developers.weixin.qq.com/doc/oplatform/Mobile_App/WeChat_Login/Authorized_API_call_UnionID.html)

## 八、技术支持

如遇到问题，可以：
1. 查看微信开放平台FAQ
2. 在微信开放社区提问
3. 查看项目issue和文档

