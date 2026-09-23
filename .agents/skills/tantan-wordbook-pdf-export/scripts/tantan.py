#!/usr/bin/env python3
"""炭炭背单词「词书导出为 PDF」驱动。

唯一正确的整本导出入口：
    主学习页 → 抽屉(☰) → 我的内容 → 本书待学 → 点顶部中央标题 → 更多操作 → 导出 PDF

坐标系基于 1080x2280 / 480dpi（见 SKILL.md「设备坐标」）。
"""
import glob
import os
import re
import shutil
import subprocess
import time

import ui

SPLASH = ("com.maimemo.momolist.android/"
          "com.maimemo.momolist.android.feature.activity.splash.SplashActivity")

# --- 设备坐标（1080x2280） -------------------------------------------------
XY_DRAWER = (103, 152)      # 主学习页左上角抽屉
XY_GEAR = (1002, 152)       # 个人中心右上角齿轮
XY_TITLE = (540, 138)       # 「本书待学」页顶部中央标题（带下拉箭头）
XY_MORE = (960, 112)        # 导出设置页右上角 ···
XY_FILTER_CHECKBOX = (999, 290)   # 「过滤熟知词」勾选框
XY_ROW_MORE = 978           # 词书行尾 ··· 的 x
Y_TAB = 269                 # 分类 tab 行
Y_CHIP = 411                # 出版社锚点行
Y_SAFE_TOP, Y_SAFE_BOTTOM = 400, 2050   # 列表中可安全点击的 y 区间


def log(msg):
    print(f"[{time.strftime('%H:%M:%S')}] {msg}", flush=True)


def sh(*args):
    return subprocess.run(["adb", "shell", *args], capture_output=True, text=True)


def head(n=3):
    return [x["text"].strip() for x in ui.dump() if x["text"].strip()][:n]


# --- 页面定位 --------------------------------------------------------------
def ensure_study():
    """确保在主学习页（标题是「Day N」）。已在则零开销返回。"""
    if any(t.startswith("Day") for t in head()):
        return
    sh("am", "start", "-n", SPLASH)
    time.sleep(4.0)
    for _ in range(3):
        if any(t.startswith("Day") for t in head()):
            return
        time.sleep(2)
    raise RuntimeError("未能进入主学习页")


def ensure_changebook():
    """确保在「更换词书」页。"""
    if "更换词书" in head():
        return
    ensure_study()
    ui.tap(*XY_DRAWER, wait=1.5)
    ui.tap(*XY_GEAR, wait=2.0)
    ui.tap_text("更换词书", 2.5)


def _find(text, ymin=0, ymax=99999, visible=False):
    for n in ui.dump():
        if n["text"].strip() != text or not (ymin <= n["cy"] <= ymax):
            continue
        if visible and not (Y_SAFE_TOP < n["cy"] < Y_SAFE_BOTTOM and n["x2"] > 0):
            continue
        return n
    return None


def tap_tab(name):
    """横向可滚动的分类 tab（在学/我的/大学/…/小学/…）。"""
    for rng in ((1000, 100), (100, 1000)):
        for _ in range(8):
            n = _find(name, ymax=330)
            if n:
                ui.tap(n["cx"], n["cy"], 1.8)
                return
            ui.swipe(rng[0], Y_TAB, rng[1], Y_TAB, 300, 0.5)
    raise LookupError(f"tab 未找到: {name}")


def tap_chip(name):
    """横向可滚动的出版社锚点（人教版/北京版/…）。点它会把列表滚到该分组。"""
    for rng in ((1000, 100), (100, 1000)):
        for _ in range(10):
            n = _find(name, ymin=340, ymax=460)
            if n:
                ui.tap(n["cx"], n["cy"], 2.0)
                return
            ui.swipe(rng[0], Y_CHIP, rng[1], Y_CHIP, 300, 0.5)
    raise LookupError(f"分组锚点未找到: {name}")


def dialog_tap(*labels):
    t = ui.texts()
    for lab in labels:
        if lab in t:
            ui.tap_text(lab, 2.0)
            return True
    return False


# --- 词书分组枚举 ----------------------------------------------------------
def _rows():
    """当前屏幕列表区按 y 聚成行：[{'t': 标题, 'n': 词数, 'hdr': 是否分组标题}]。"""
    nodes = [n for n in ui.dump() if n["y1"] >= 450 and n["text"].strip()]
    buckets = []
    for n in sorted(nodes, key=lambda n: n["cy"]):
        if buckets and n["cy"] - buckets[-1][0]["cy"] < 60:
            buckets[-1].append(n)
        else:
            buckets.append([n])
    out = []
    for b in buckets:
        b.sort(key=lambda n: n["x1"])
        title = next((n for n in b if not re.fullmatch(r"\d+", n["text"].strip())), None)
        if not title:
            continue
        cnt = next((n["text"].strip() for n in b
                    if re.fullmatch(r"\d+", n["text"].strip())), "")
        out.append({"t": title["text"].strip(), "n": cnt, "hdr": title["cx"] < 210})
    return out


def _merge(acc, cur):
    for k in range(min(len(acc), len(cur)), 0, -1):
        if [r["t"] for r in acc[-k:]] == [r["t"] for r in cur[:k]]:
            return acc + cur[k:]
    return acc + cur


def collect_group(tab, chip):
    """枚举某分类下某出版社分组的全部词书，返回 [(书名, 词数 int)]。"""
    ensure_changebook()
    tap_tab(tab)
    for _ in range(30):
        ui.swipe(540, 900, 540, 1900, 250, 0.4)      # 回到列表顶部
    acc, stall = [], 0
    for _ in range(200):
        cur = _rows()
        if not cur:
            break
        acc = _merge(acc, cur)
        ui.swipe(540, 1800, 540, 1000, 400, 0.9)
        if _rows() == cur:
            stall += 1
            if stall >= 2:
                break
        else:
            stall = 0
    hs = [i for i, r in enumerate(acc) if r["hdr"]]
    start = next((i for i in hs if acc[i]["t"] == chip), None)
    if start is None:
        raise LookupError(f"分组未找到: {chip}（本分类分组: {[acc[i]['t'] for i in hs]}）")
    end = next((i for i in hs if i > start), len(acc))
    return [(r["t"], int(r["n"] or 0)) for r in acc[start + 1:end]]


# --- 当前在学词书管理 ------------------------------------------------------
def in_study_rows():
    """「在学」列表里当前可见的词书行 [(文本, cy)]（排除「添加词书」等占位行）。"""
    ensure_changebook()
    tap_tab("在学")
    out = []
    for n in ui.dump():
        t = n["text"].strip()
        if (Y_SAFE_TOP < n["cy"] < 2250 and n["x2"] > 0 and t and not t.isdigit()
                and not t.startswith("正在学习") and not t.startswith("点击右上角")
                and "词书将添加" not in t):
            out.append((t, n["cy"]))
    return out


def in_study_count():
    ensure_changebook()
    tap_tab("在学")
    for t in ui.texts():
        m = re.search(r"正在学习（(\d+)/(\d+)）", t)
        if m:
            return int(m.group(1)), int(m.group(2))
    return 0, 10


def drop_first():
    """删掉「在学」第一本以腾位。调用前必须确保 N>=2（App 不允许删空）。"""
    rows = in_study_rows()
    if not rows:
        raise RuntimeError("在学列表没有可删的词书")
    name, cy = rows[0]
    ui.tap(XY_ROW_MORE, cy, 2.0)
    ui.tap_text("删除词书", 2.0)
    dialog_tap("确定", "删除", "确认")
    if "删除失败" in ui.texts():
        ui.tap_text("我知道了", 1.5)
        raise RuntimeError(f"删除失败: {name}")
    log(f"    腾位删除: {name}")
    if "更换词书" not in head():
        ensure_changebook()


def clear_in_study(keep=1):
    """把「在学」删到只剩 keep 本（App 硬性要求至少 1 本）。"""
    while True:
        n, _ = in_study_count()
        if n <= keep:
            log(f"在学已剩 {n} 本")
            return
        try:
            drop_first()
        except Exception as e:
            log(f"停止清理: {e}")
            return


def make_current(name, tab, chip):
    """让某本词书成为当前在学词书：已在「在学」就切换，否则从分组列表添加。"""
    ensure_changebook()
    tap_tab("在学")
    row = _find(name, ymin=Y_SAFE_TOP, ymax=Y_SAFE_BOTTOM, visible=True)
    if row:
        ui.tap(row["cx"], row["cy"], 2.5)          # 「是否切换到《X》继续学习？」
        dialog_tap("切换", "确定", "确认")
        return
    tap_tab(tab)
    tap_chip(chip)
    for _ in range(80):
        n = _find(name, ymin=Y_SAFE_TOP, ymax=Y_SAFE_BOTTOM, visible=True)
        if n:
            ui.tap(n["cx"], n["cy"], 2.5)
            break
        ui.swipe(540, 1800, 540, 1100, 350, 0.7)
    else:
        raise RuntimeError(f"列表未找到: {name}")
    if "开启你的单词记忆之旅" not in ui.texts():
        raise RuntimeError(f"{name} 未进入计划页: {head()}")
    ui.tap_text("开启你的单词记忆之旅", 3.0)
    dialog_tap("确定", "确认", "开启")


# --- 整本导出 --------------------------------------------------------------
def _checked():
    ui.shot("/tmp/_cb.png")
    from PIL import Image
    r, g, b = Image.open("/tmp/_cb.png").convert("RGB").getpixel(XY_FILTER_CHECKBOX)
    return g > 120 and b > 120 and r < 150


def configure(template="中英词表", phonetic=False, columns=1):
    """导出设置：取消「过滤熟知词」是关键（默认勾选会漏词）。"""
    ui.tap(*XY_MORE, wait=1.5)
    if _checked():
        ui.tap(*XY_FILTER_CHECKBOX, wait=1.2)
        if _checked():
            raise RuntimeError("「过滤熟知词」取消失败")
    ui.tap_text(template, 1.5)
    ui.tap_text("显示音标" if phonetic else "隐藏音标", 1.5)
    ui.tap_text(f"{columns} 列", 1.5)


def export_current_book(template="中英词表", phonetic=False, columns=1):
    """对当前在学词书执行整本导出，返回落在手机 /sdcard/Download 的文件名。"""
    ensure_study()
    ui.tap(*XY_DRAWER, wait=1.5)
    ui.tap_text("我的内容", 2.5)
    ui.tap_text("本书待学", 2.5)
    if "本书待学" not in head():
        raise RuntimeError(f"未进入本书待学页: {head()}")
    ui.tap(*XY_TITLE, wait=2.5)                   # 顶部标题 → 更多操作
    if "导出 PDF" not in ui.texts():
        raise RuntimeError(f"未出现导出入口: {ui.texts()[:10]}")
    ui.tap_text("导出 PDF", 4.0)
    configure(template, phonetic, columns)
    ui.tap_text("导出 PDF", 5.0)
    time.sleep(4)
    names = [n["text"].strip() for n in ui.dump() if n["text"].strip().endswith(".pdf")]
    sh("input", "keyevent", "4")                   # 关掉分享面板
    time.sleep(1.5)
    if names:
        return names[0]
    newest = sh("ls", "-t", "/sdcard/Download/*.pdf").stdout.split()
    if not newest:
        raise RuntimeError("未捕获导出文件名")
    return os.path.basename(newest[0])


def pull(name, out_dir):
    os.makedirs(out_dir, exist_ok=True)
    r = subprocess.run(["adb", "pull", f"/sdcard/Download/{name}", out_dir],
                       capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError(f"拉取失败 {name}: {r.stderr.strip()}")
    return os.path.join(out_dir, name)


def verify(path, expect):
    """校验 PDF 的最大序号 == App 标注词数（即整本、无漏词）。"""
    import pypdf
    r = pypdf.PdfReader(path)
    t = "\n".join((p.extract_text() or "") for p in r.pages)
    got = max((int(x) for x in re.findall(r"(?m)^\s*(\d{1,3})\s*$", t)), default=0)
    return len(r.pages), got, got == expect


def export_group(tab, chip, out_dir, template="中英词表",
                 phonetic=False, columns=1, books=None, resume=True):
    """导出某分类下某出版社分组的全部词书。

    books 传 [(书名, 词数)] 可跳过枚举；否则自动枚举。
    resume=True 时已存在 `<书名>_*.pdf` 的词书直接跳过（断点续跑）。
    """
    books = books or collect_group(tab, chip)
    log(f"{tab}/{chip} 共 {len(books)} 本，合计 {sum(n for _, n in books)} 词")
    report = []
    clear_in_study()
    for i, (name, expect) in enumerate(books, 1):
        if resume and glob.glob(os.path.join(out_dir, f"{name}_*.pdf")):
            log(f"[{i}/{len(books)}] 跳过（已导出）: {name}")
            continue
        t0 = time.time()
        try:
            n, cap = in_study_count()
            if n >= cap:
                log(f"    在学已满 {n}/{cap}，腾位")
                drop_first()
            log(f"[{i}/{len(books)}] 导出 {name}（{expect} 词）")
            make_current(name, tab, chip)
            fname = export_current_book(template, phonetic, columns)
            dst = pull(fname, out_dir)
            pages, got, ok = verify(dst, expect)
            report.append((name, expect, got, pages, ok, fname))
            log(f"    {fname} 页={pages} 序号max={got} 期望={expect} "
                f"{'OK' if ok else '!!! 不一致'} 用时{time.time()-t0:.0f}s")
        except Exception as e:
            report.append((name, expect, -1, -1, False, f"ERROR {e}"))
            log(f"    !! 失败: {e}")
            try:
                ensure_changebook()
            except Exception:
                pass
    return report
