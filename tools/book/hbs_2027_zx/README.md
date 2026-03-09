# 2027 考研英语红宝书 (正序版) 处理流程

本项目用于将《2027 考研英语红宝书》PDF 转换为数据库可导入的 SQL。采用全自动流水线，支持词性拆分、生词自动补全及分类挂载。

## 目录结构
- `raw/`: 原始 PDF 文件。
- `scripts/`: 处理脚本（Node.js/Python）。
- `output/`: 产生的中间文本、校验报告及最终 SQL。

## 执行步骤

### 1. 提取 PDF 文本
将 PDF 转换为原始文本流。
```bash
node scripts/step1_extract_pdf.js
```

### 2. 解析与对齐
利用 PDF 中的行号索引，将左右分栏的英文和中文进行精准对齐。
```bash
python3 scripts/step2_parse_text.py
```

### 3. 生成导入 SQL
生成包含所有数据和逻辑的 SQL 脚本。该脚本会自动：
- 拆分 `vi. vt.` 等复合词性。
- 只为数据库中不存在的“生词”创建新释义（存入 `dict_id='0'`）。
- 自动挂载到所有“考研”分组。
```bash
python3 scripts/step3_generate_sql.py
```

### 4. 执行导入
使用 `psql` 将生成的 SQL 导入数据库：
```bash
PGPASSWORD=xxx psql -h 127.0.0.1 -U myb -d bdc -f output/import_2027_hbs.sql
```

## 注意事项
- 本流程具有**幂等性**，可多次运行，会自动清理旧数据。
- 脚本中使用了动态匹配逻辑（如 `WHERE name = '考研'`），无需担心生产环境 ID 不一致。
