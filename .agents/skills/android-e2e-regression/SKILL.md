---
name: android-e2e-regression
description: 泡泡单词 Android 真机端到端全量自动化回归测试。连接生产环境数据库核验/初始化测试账号 e2etest@nnbdc.com，驱动真实 Android 手机自动完成唤醒、启动、验证码登录、主导航遍历、单词学习流转、端云同步及生成完整测试报告。
whenToUse: 当发布新版本前需要进行回归测试、每次发版前做冒烟验证、排查 Android 端真机核心功能闭环、验证生产库环境链路兼容性时使用。
---

# Android 端到端自动化回归测试 (E2E Regression)

本 Skill 提供针对「泡泡单词」Android 客户端的自动化回归测试方案。测试直接联通**生产环境数据库**，闭环校验真实网络与云端同步链路，并通过 ADB 驱动已连接的 Android 真实手机执行端到端（E2E）核心业务流程，自动输出带关键步骤实机截图的 HTML 测试报告。

---

## 核心设计与纯黑盒端到端原则

```mermaid
flowchart TD
    A[执行回归测试] --> B[Step 1: 连接 Android 真实手机并点亮屏幕]
    B --> C[Step 2: 启动 App 前台校验]
    C --> D[Step 3: 初始纯净状态核验]
    D --> E{是否已处于登录态?}
    E -- 是 --> F[手机端进入设置 -> 注销账号 -> 销毁数据退回登录页]
    E -- 否 --> G[保持欢迎页冷启动]
    F --> G
    G --> H[Step 4: 手机端自主注册与验证码登录]
    H --> I[手机输入邮箱 -> 点击获取 -> 生产库唯一截获验证码 -> 自动填入提交]
    I --> J[Step 5: 底部四大主导航遍历 (词表/查词/我/学习)]
    J --> K[Step 6: 新用户词书配置生效]
    K --> L[Step 7: 学习轨道配置与切换体验]
    L --> M[Step 8: 每日学习计划定制]
    M --> N[Step 9: 单词全流程学习直至触发打卡结算]
    N --> O[Step 10: 主页打卡印章与个人中心状态核验]
    O --> P[Step 11: 端云同步健康度校验]
    P --> Q[Step 12: 测试善后：真机自助注销账号还原未登录态]
    Q --> R[Step 13: 生成 HTML 报告并自动邮件直推]
```

### 1. 纯黑盒端到端测试黄金原则
- **真实客户端注册**：严禁通过后端后门 SQL 直接插入新用户。所有账号由手机端原生登录/注册界面输入邮箱触发，让服务端与客户端完整走通首次注册、配置分发、本地数据库初始化的真实链路。
- **真机自助注销闭环**：回归测试前与测试结束后，若存在旧账号，必须通过手机端自身的**「注销账号」**功能（输入 `okay` 确认）彻底销毁云端与本地的所有学习进度与配置，恢复纯净未登录态，保证每次回归测试 100% 确定且幂等。
- **打卡与学习轨道全流程覆盖**：不仅测试单词交互，还完整回归「学习轨道」展开/折叠与 Tab 切换、每日计划词数定制，以及完整学完当天全部单词直至触发「打卡完成页」，并查验生产库 `daka` 表真实写入。
- **极简唯一后端协同**：整个回归链路中，**只有「从生产库读取验证码」和「核对打卡是否入库」连接后端**（因为自动化测试无法人肉收信，截获验证码是唯一的合理外部辅助），其余所有操作 100% 均为真实手机屏幕上的人机交互。
- **自动化邮件直推**：测试结束自动将内嵌真机截图与状态指标的高清 HTML 测试报告通过阿里云邮件推送直达用户指定邮箱（如 `mmyybb3000@icloud.com`）。
- **安全红线**：严禁波及生产环境其他任何正常用户，测试邮箱固定为 `e2etest@nnbdc.com`。

---

## 工具脚本一览

所有配套驱动脚本位于当前 Skill 的 `scripts/` 目录下：

| 脚本文件 | 核心职责 | 常用命令 |
|---|---|---|
| `scripts/manage_e2e_account.py` | 生产库账号核验、创建、重置、验证码抓取、打卡记录核验 | `./scripts/manage_e2e_account.py --check`<br>`./scripts/manage_e2e_account.py --get-code` |
| `scripts/device_controller.py` | ADB 设备连接、屏幕唤醒解锁、UI 节点 dump 与智能点击 | 模块引用或直接测试连接 |
| `scripts/send_report_email.py` | 阿里云邮件推送 (DirectMail) HTML 报告推送模块 | `./scripts/send_report_email.py --to <邮箱>` |
| `scripts/run_regression.py` | 全量自动化回归执行引擎与 HTML 报告生成器 | `./scripts/run_regression.py --email mmyybb3000@icloud.com` |

---

## 执行模式

### 模式 A：一键全自动回归与邮件直推（推荐）

在终端或由 AI 直接运行回归脚本：
```bash
python3 .agents/skills/android-e2e-regression/scripts/run_regression.py --email mmyybb3000@icloud.com
```
> 若跳过邮件推送，可添加 `--no-email` 参数。若有多个设备，可通过 `--serial <设备号>` 指定。
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
