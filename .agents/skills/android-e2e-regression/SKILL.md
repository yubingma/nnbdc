---
name: android-e2e-regression
description: 泡泡单词 Android 真机端到端全量自动化回归测试。连接生产环境数据库核验/初始化测试账号 e2etest@nnbdc.com，驱动真实 Android 手机自动完成唤醒、启动、验证码登录、主导航遍历、单词学习流转、端云同步及生成完整测试报告。
whenToUse: 当发布新版本前需要进行回归测试、每次发版前做冒烟验证、排查 Android 端真机核心功能闭环、验证生产库环境链路兼容性时使用。
---

# Android 端到端自动化回归测试 (E2E Regression)

本 Skill 提供针对「泡泡单词」Android 客户端的自动化回归测试方案。测试直接联通**生产环境数据库**，闭环校验真实网络与云端同步链路，并通过 ADB 驱动已连接的 Android 真实手机执行端到端（E2E）核心业务流程，自动输出带关键步骤实机截图的 HTML 测试报告。

---

## 核心设计与数据架构

```mermaid
flowchart TD
    A[执行回归测试] --> B[Step 1: 检查生产数据库]
    B --> C{e2etest@nnbdc.com 是否存在?}
    C -- 否 --> D[自动创建测试用户 + 生词本/学习步骤/泡泡]
    C -- 是 --> E[重置测试用户数据为纯净初始态]
    D --> F[Step 2: 握手 Android 真实手机]
    E --> F
    F --> G[Step 3: 唤醒并启动 com.nn.nnbdc.android]
    G --> H[Step 4: 登录认证链路闭环]
    H --> I[手机点击'获取验证码' -> 生产库抓取最新验证码 -> 自动填入登录]
    I --> J[Step 5: 底部主导航遍历]
    J --> K[Step 6: 单词学习核心流程冒烟]
    K --> L[Step 7: 端云同步校验]
    L --> M[Step 8: 生成 tmp/e2e_report/report.html]
```

### 1. 生产库专属账号安全红线
- **测试专属账号**：`e2etest@nnbdc.com`（用户 ID 必须使用标准 32 位 UUID，严禁拼接）。
- **严格范围隔离**：脚本和 SQL 的任何 `INSERT/UPDATE/DELETE` 操作**强制限定为 `e2etest@nnbdc.com` 或其对应的 `user_id`**，绝对严禁触碰生产库其他真实用户的数据！
- **测试数据纯净性**：测试前自动重置该用户的学习记录、打卡记录、临时生词本，并将魔法泡泡重置为 100，确保每次回归处于确定性的基线状态。
- **验证码全自动拦截**：由于生产环境登录采用邮箱验证码，客户端点击「获取」后，服务端将 6 位验证码写入生产库 `email_verification_code` 表。脚本直接通过只读查询截获最新验证码填入，无需人工收信，实现 100% 全自动化。

---

## 工具脚本一览

所有配套驱动脚本位于当前 Skill 的 `scripts/` 目录下：

| 脚本文件 | 核心职责 | 常用命令 |
|---|---|---|
| `scripts/manage_e2e_account.py` | 生产库账号核验、创建、重置、验证码抓取 | `./scripts/manage_e2e_account.py --ensure`<br>`./scripts/manage_e2e_account.py --reset`<br>`./scripts/manage_e2e_account.py --get-code` |
| `scripts/device_controller.py` | ADB 设备连接、屏幕唤醒解锁、UI 节点 dump 与智能点击 | 模块引用或直接测试连接 |
| `scripts/run_regression.py` | 全量自动化回归执行引擎与 HTML 报告生成器 | `./scripts/run_regression.py` |

---

## 执行模式

### 模式 A：一键全自动回归（推荐）

在终端或由 AI 直接运行回归脚本：
```bash
python3 .agents/skills/android-e2e-regression/scripts/run_regression.py
```
> 若手机上有多个设备或模拟器在线，可通过 `--serial <设备号>` 指定目标设备。

执行完毕后，测试报告将自动保存至：
- **HTML 报告**：`tmp/e2e_report/report.html`
- **全链路实机截图**：`tmp/e2e_report/screenshots/`

---

### 模式 B：AI 交互式单步驱动（用于深度排查与单点调试）

当需要针对特定功能定位异常时，AI 可按以下标准操作程序（SOP）分步驱动：

#### 第 1 步：生产数据库检查与账号初始化
运行：
```bash
.agents/skills/android-e2e-regression/scripts/manage_e2e_account.py --ensure
```
若需要完全重置该账号的学习进度与记录：
```bash
.agents/skills/android-e2e-regression/scripts/manage_e2e_account.py --reset
```

#### 第 2 步：检测手机连接并唤醒
确保手机已开启 USB 调试且已连接：
```bash
adb devices
# 唤醒屏幕
adb shell input keyevent 26
# 上滑解锁
adb shell input swipe 500 1800 500 500 300
```

#### 第 3 步：冷启动泡泡单词 App
```bash
adb shell am force-stop com.nn.nnbdc.android
adb shell monkey -p com.nn.nnbdc.android -c android.intent.category.LAUNCHER 1
```

#### 第 4 步：执行邮箱验证码登录
1. 引导手机进入邮箱登录页；
2. 输入邮箱 `e2etest@nnbdc.com`：
   ```bash
   adb shell input text "e2etest\@nnbdc.com"
   ```
3. 点击「获取」验证码；
4. 立即从生产库获取验证码：
   ```bash
   .agents/skills/android-e2e-regression/scripts/manage_e2e_account.py --get-code
   ```
5. 将输出的 6 位数字输入手机，点击「登录」。

#### 第 5 步：导航遍历与功能交互
- 底部 Tab 切换：点击对应坐标或调用 `device_controller.py` 的 `wait_and_click(text="词表")` 等。
- 启动背单词：点击「开始学习」，在单词页面点击「不认识」或「下一词」，验证释义展现与发音。
- 截图留存：
  ```bash
  adb exec-out screencap -p > tmp/e2e_report/screenshots/step_custom.png
  ```

---

## 核心回归测试用例清单

| 用例编号 | 用例名称 | 核心操作步骤 | 预期通过结果 (Success Criteria) |
|---|---|---|---|
| **TC-01** | 生产库与账号基准 | 检查并重置 `e2etest@nnbdc.com` | 账号存在，生词本、已掌握词书、学习步骤就绪，魔法泡泡为 100 |
| **TC-02** | 真机启动与前台挂载 | 唤醒屏幕，冷启动 `com.nn.nnbdc.android` | App 正常加载并处于前台，无闪退，顺利通过权限引导 |
| **TC-03** | 邮箱验证码闭环登录 | 输入 e2etest 邮箱，点击获取，查库截获填入并登录 | 验证码校验通过，顺利登入并跳转至首页（非游客状态） |
| **TC-04** | 主导航切换冒烟 | 依次点击「词表」「查词」「我」「学习」 | 页面顺利切换无白屏，各模块标题及核心列表正常渲染 |
| **TC-05** | 个人中心属性校验 | 进入「我」页面，核对用户信息 | 显示昵称为「E2E测试用户」，魔法泡泡正常显示 |
| **TC-06** | 单词学习核心流转 | 首页点击「开始学习/继续学习」，交互 2 轮后返回 | 单词音标、释义正常展示，流转按钮可点击，返回主页状态正常保存 |
| **TC-07** | 端云同步无报错 | 触发数据同步，观察界面反馈与日志 | 界面无「同步失败」「网络异常」等红字提示 |

---

## 常见问题与排查指南

1. **`adb devices` 为空或显示 `unauthorized`**：
   - 检查手机屏幕是否弹出了「允许 USB 调试吗？」弹窗，勾选「一律允许」并确认；
   - 尝试执行 `adb kill-server && adb start-server`。
2. **验证码获取失败**：
   - 检查手机网络是否畅通（能否正常访问 `https://back.nnbdc.com`）；
   - 检查 `nnbdc_server_pwd` 环境变量是否配置在 `~/.zprofile` 中；
   - 确保点击手机「获取」按钮后等待 1~2 秒再读取数据库。
3. **Flutter 界面节点 dump 文本为空**：
   - 部分自绘 Canvas 元素可能未导出 Semantics，`device_controller.py` 提供截图捕获能力，结合坐标自适应点击。
