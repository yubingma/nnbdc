# 泡泡单词 - 预置数据库制作指南

为了提升用户安装后的首屏体验，我们采用“预置 SQLite 数据库”方案，避免用户首次启动时需要下载巨大的通用词典文件。

本指南介绍如何制作这个“黄金母版”数据库（Initial Database）。

## 📁 相关文件

*   **脚本路径**: `devops/golden_db_maker/make_golden_db.sh`
*   **清理逻辑**: `devops/golden_db_maker/clean_db.sql`
*   **产物位置**: `app/assets/db/initial.sqlite`

## 🛠 制作步骤

### 1. 准备数据源

运行mac桌面版泡泡单词(如果不是全新安装, 则先要在"我"页面, 清理本地数据库, 然后重新启动), 确保系统自动下载并导入了通用词典。然后关闭应用。

### 2. 执行制作脚本

直接运行脚本即可。脚本会自动检测常见路径下的数据库文件，如果找不到，请手动作为参数传入。

```bash
# 赋予执行权限 (仅需一次)
chmod +x devops/golden_db_maker/make_golden_db.sh

# 运行脚本 (自动检测源文件)
./devops/golden_db_maker/make_golden_db.sh

# 或者手动指定源文件路径
# ./devops/golden_db_maker/make_golden_db.sh /path/to/your/db.sqlite
```

脚本会自动执行以下操作：
1.  在临时目录中复制源数据库（**不污染当前目录**）。
2.  执行 `clean_db.sql` 清理用户数据及 `VACUUM` 压缩。
3.  自动将生成的 `initial.sqlite` 部署到 `app/assets/db/` 目录。


### 4. 验证

重新运行 App（模拟全新安装），观察控制台日志：

```text
I/flutter: 📦 检测到全新安装，正在寻找预置数据库...
I/flutter: 📦 发现预置数据库，正在部署...
I/flutter: ✅ 预置数据库部署成功！
```

如果出现上述日志且无需下载词典，即表示成功。

## ⚠️ 注意事项

* **版本同步**: 预置数据库的 schema 版本必须与当前代码中的 `MyDatabase.schemaVersion` 兼容（或更低，触发自动升级）。
* **定期更新**: 当通用词典内容有重大更新时，建议重新制作母版，以便新用户能直接用上最新词典。
