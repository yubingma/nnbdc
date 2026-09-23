---
name: tantan-wordbook-pdf-export
description: 把「炭炭背单词」(Android, com.maimemo.momolist.android) 里某个「分类 tab + 出版社分组」下的全部词书，批量导出为**整本** PDF 并落到 tools/book/<分类>/。当需要为词书库补充或重导词书（例如「小学-北京版」「初中-人教版」「高中-外研版」）时使用。
whenToUse: 用户说"把炭炭背单词里 XX 版的所有词书导出成 PDF"、"再导一批词书进 tools/book/"、"重导某个分组的词书"、"这个分组怎么导出"等情况。
---

# 炭炭背单词 词书 PDF 批量导出

## 0. 一句话定位

> 唯一正确的**整本**导出入口是：
> **主学习页 → 抽屉(☰) → 我的内容 → 本书待学 → 点顶部中央标题 → 更多操作 → 导出 PDF**
>
> 主学习页**左下角长按 `List1`** 也能看到「导出 PDF」，但那是**按 List 导出**（产物名 `List 1_2026....pdf`，只有几十词、带 List 分节头）。**不要用那条路。**

## 1. 环境与前提

| 项 | 值 |
|---|---|
| 包名 | `com.maimemo.momolist.android`（v5.8.6） |
| 设备 | Android 10 / SDK 29，1080×2280 / 480dpi（坐标系强依赖，换机需重测） |
| 连接 | USB + `adb devices` 可见；**手机必须解锁**（adb 不能代指纹/密码） |
| Python | 用项目 venv `/Volumes/ssd/ppdc/.venv/bin/python`（`pypdf` 装在这里） |
| 产物 | `tools/book/<分类>/<书名>_<yyyyMMdd_HHmmss>.pdf`（文件名由 App 生成） |

**明确不可行、别再试的路线**（都验证过）：
- 直接 `adb pull /data/data/...`：无 root、不可调试。
- `adb backup`：能拿到 112MB 包，但主库 `db/momolist_main_23.db` 是 **SQLCipher 全库加密**（熵 7.999），密钥在 360 加固后的 dex 里，不值得逆向。
- 直接 `am start ...ExportPdfActivity` / `MyContentActivity`：均 `exported=false`，shell 无权限。
- 爬 UI 词表：`本书待学` 页每屏 ~9 词，还要处理滚动重叠；官方导出一键整本，别绕。

## 2. 快速开始

```bash
cd .agents/skills/tantan-wordbook-pdf-export/scripts
PY=/Volumes/ssd/ppdc/.venv/bin/python

# 1) 先枚举清单和词数，确认分组对不对
$PY collect_group.py 初中 人教版 -o books.json

# 2) 批量导出（自动：腾位 → 添加/切换 → 导出 → adb pull → 校验）
$PY export_group.py 初中 人教版

# 想带音标 / 双列 / 换目录
$PY export_group.py 高中 外研版 --out /Volumes/ssd/ppdc/tools/book/高中 --phonetic
```

`export_group.py` **默认跳过已存在的 `<书名>_*.pdf`**（断点续跑），中断后直接重跑即可。
单本约 **100–140 秒**，20 本约 40 分钟，用后台任务跑。

## 3. 交互路径与坐标（1080×2280）

```
① 主学习页(标题是 "Day N")            ← am start SplashActivity 最稳
② 点 (103,152) 抽屉
③ 点 (1002,152) 齿轮 → 设置页 → 点「更换词书」     [换词书时用]
   或 抽屉里直接点「我的内容」                      [导出时用]
④ 我的内容 → 点「本书待学」            (TobeLearnedActivity)
⑤ 点顶部中央标题 (540,138)  →  底部弹出面板
⑥ 面板里点「导出 PDF」                 (ExportPdfActivity，「预览 PDF」页)
⑦ 右上角 (960,112) ···  → 取消勾选「过滤熟知词」(999,290)   ★关键
⑧ 点「中英词表」→「隐藏音标」→「1 列」
⑨ 点底部「导出 PDF」→ 出现分享面板，读完文件名后按 BACK 关掉
```

- 词书库既有 90 个 PDF 的统一格式是 **中英词表 / 隐藏音标 / 1 列**，默认照此对齐。
- 面板文案：`单词显示 / 单词排序 / 更多操作`，其中「更多操作」下才是「导出 PDF / 批量熟知」。

## 4. 五个必踩的坑

### 4.1 「过滤熟知词」默认是**勾选**的
会让 PDF 漏掉熟知词。每本都要在 `···` 里取消。脚本里用截图像素判断勾选态（青色实心 = 选中），不要靠猜。

### 4.2 「在学」上限 10 本、**下限 1 本**
- 删到只剩 1 本时再删 → 弹「删除失败 / 「在学」中至少要有一本词书哦」。
- 满 10 本再加 → 必须**先删一本腾位**。
- 脚本用滚动窗口：`count>=10 → drop_first()`，并且 `clear_in_study()` 只清到剩 1 本。

### 4.3 列表里只有「当前选中分组」的行可点
`更换词书` 页的分类 tab 是**锚点**不是筛选器：列表是「某分类下所有出版社」的连续长列表，点分组 chip 才会把该分组滚到当前并**激活**。**没激活的分组的行点了完全没反应**（这就是为什么必须先 `tap_chip()`）。

### 4.4 落在屏幕最底边的行点了没反应
RecyclerView 会把屏幕外的行报成 `bounds=[0,0][0,0]`，而贴底的行（`cy≈2270`）点下去也不生效。
点击前必须把行滚进 **`400 < cy < 2050`** 的安全带（`open_book` / `_find(..., visible=True)` 已内置）。

### 4.5 已在「在学」的词书，在分类列表里**不可点**
它的行是惰性的。要把它设为当前词书，得去 **「在学」tab 点该行 → 弹「是否切换到《X》继续学习？」→ 点「切换」**。
`make_current()` 已按「先在学列表找，找不到再去分类列表添加」处理。

## 5. 校验（必做，别只看文件存在）

App 标注的词书词数 == PDF 里的最大序号，才算整本无漏词：

```bash
cd /Volumes/ssd/ppdc && .venv/bin/python - <<'PY'
import glob, os, re, pypdf
for f in sorted(glob.glob('tools/book/小学/北京版*.pdf')):
    r = pypdf.PdfReader(f)
    t = "\n".join((p.extract_text() or '') for p in r.pages)
    got = max((int(x) for x in re.findall(r'(?m)^\s*(\d{1,3})\s*$', t)), default=0)
    print(f"{os.path.basename(f):52} 页{len(r.pages):2} 序号max={got}")
PY
```

反面判据：文件名是 `List N_...`、或正文里有重复的 `List 1` 页眉、或序号 max 明显小于词书词数 → 走错入口了。

## 6. 故障排查

| 现象 | 原因 / 处置 |
|---|---|
| dump 出来是锁屏（`使用指纹或上滑解锁`） | 手机锁了，叫人解锁 |
| `未进入计划页: ['更换词书','导入',...]` | 该行在未激活分组或贴底 → `tap_chip()` 后重试（脚本已按安全带找行） |
| `未出现导出入口` | 标题没点到 / 不在 `本书待学` 页；确认 `head()[0] == '本书待学'` |
| 导出后没文件名 | 分享面板还没出；等 4s 再 dump，或 `ls -t /sdcard/Download/*.pdf` 取最新 |
| 词数对不上 | 十有八九是「过滤熟知词」没取消，或这本词书已有学习进度（`本书待学` 只剩未学部分） |
| 反复失败同一本 | 单独重跑 `make_current` + `export_current_book`，单本定位 |

## 7. 其他

- 导出成功后 App 会把 PDF 落在 **`/sdcard/Download/`**，同时弹分享面板。脚本直接 `adb pull`，不用走微信/网盘。
- 分享面板里如果要用「保存为 PDF」：进 `打印` → 右上角 `更多` → `保存为 PDF`（会另存一份到 Download，非必需）。
- 用户对词书列表的增删是无所谓的（他为导出才装这个 App），但**改动仍会同步到服务器**，动手前确认一次。
- 本次已知分组规模：小学-北京版 20 本 / 1778 词；初中-人教版 10 本 / 5848 词。
