#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Android 真机屏幕壁纸抓取与状态栏自动切除工具
- 自动检测并连接通过 ADB 连线的 Android 真实设备
- 自动获取设备系统状态栏高度 (status_bar_height)，精确切除顶部的系统文字、时间、电量、WiFi/信号图标
- 高保真输出到 app/assets/images/wallpaper/<name>.jpg
- 可选将壁纸自动注册到 app/lib/page/today_plan.dart 壁纸选项列表中
"""

import argparse
import os
import re
import subprocess
import sys
from PIL import Image

WORKSPACE_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "../../../../"))
APP_DIR = os.path.join(WORKSPACE_ROOT, "app")
WALLPAPER_DIR = os.path.join(APP_DIR, "assets/images/wallpaper")
TODAY_PLAN_DART = os.path.join(APP_DIR, "lib/page/today_plan.dart")


def run_adb(cmd_args, serial=None):
    cmd = ["adb"]
    if serial:
        cmd.extend(["-s", serial])
    cmd.extend(cmd_args)
    res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if res.returncode != 0:
        raise RuntimeError(f"ADB 命令执行失败 ({' '.join(cmd)}): {res.stderr.strip() or res.stdout.strip()}")
    return res.stdout.strip()


def get_connected_device(serial=None):
    if serial:
        return serial
    lines = run_adb(["devices"]).splitlines()
    devices = []
    for line in lines[1:]:
        parts = line.strip().split()
        if len(parts) >= 2 and parts[1] == "device":
            devices.append(parts[0])
    if not devices:
        raise ConnectionError("未检测到已连接并授权的 Android 设备！请检查 USB 连线并允许 USB 调试。")
    return devices[0]


def get_status_bar_height(serial):
    """通过 dumpsys window 获取真实系统状态栏像素高度"""
    try:
        out = run_adb(["shell", "dumpsys", "window", "windows"], serial=serial)
        # 寻找 StatusBar 对应的 fillxH 或 mContentInsets=[0,H]
        match = re.search(r"mContentInsets=\[0,(\d+)\]", out)
        if match:
            return int(match.group(1))
        match2 = re.search(r"StatusBar.*?fillx(\d+)", out, re.DOTALL)
        if match2:
            return int(match2.group(1))
    except Exception as e:
        print(f"⚠️ 无法自动探测状态栏高度 ({e})，采用默认 75px。")
    return 75


def capture_and_crop(name, title=None, serial=None, crop_top=None, crop_bottom=0, update_code=False):
    device = get_connected_device(serial)
    print(f"📱 目标设备: {device}")

    # 获取状态栏切除高度
    if crop_top is None:
        sb_height = get_status_bar_height(device)
        # 加 3px 安全裕度彻底消除抗锯齿边缘
        crop_top = sb_height + 3
        print(f"📏 自动检测状态栏高度: {sb_height}px, 裁切顶部: {crop_top}px")
    else:
        print(f"📏 手动指定裁切顶部: {crop_top}px")

    os.makedirs(WALLPAPER_DIR, exist_ok=True)
    tmp_raw_png = os.path.join(WORKSPACE_ROOT, "tmp", f"raw_screen_{name}.png")
    os.makedirs(os.path.dirname(tmp_raw_png), exist_ok=True)

    # 抓取原图
    print("📸 正在截取手机屏幕...")
    screencap_cmd = ["adb", "-s", device, "exec-out", "screencap", "-p"]
    with open(tmp_raw_png, "wb") as f:
        res = subprocess.run(screencap_cmd, stdout=f, stderr=subprocess.PIPE)
        if res.returncode != 0:
            raise RuntimeError(f"截屏失败: {res.stderr.decode('utf-8', errors='ignore')}")

    img = Image.open(tmp_raw_png)
    w, h = img.size
    print(f"🖼️ 原图尺寸: {w} × {h}")

    bottom = h - crop_bottom
    if crop_top >= bottom:
        raise ValueError(f"切除参数非法: crop_top={crop_top}, crop_bottom={crop_bottom}, 高度={h}")

    cropped = img.crop((0, crop_top, w, bottom))
    print(f"✂️ 裁切后尺寸: {cropped.size} (切除顶部 {crop_top}px, 底部 {crop_bottom}px)")

    target_jpg = os.path.join(WALLPAPER_DIR, f"{name}.jpg")
    cropped.convert("RGB").save(target_jpg, "JPEG", quality=95, optimize=True)
    file_size_kb = os.path.getsize(target_jpg) / 1024
    print(f"✅ 壁纸已保存: {target_jpg} ({file_size_kb:.1f} KB)")

    rel_asset_path = f"assets/images/wallpaper/{name}.jpg"

    # 若需要自动更新代码
    if update_code and title and os.path.exists(TODAY_PLAN_DART):
        update_today_plan_options(name, title, rel_asset_path)

    return target_jpg


def update_today_plan_options(name, title, asset_path):
    with open(TODAY_PLAN_DART, "r", encoding="utf-8") as f:
        content = f.read()

    if asset_path in content:
        print(f"ℹ️ {asset_path} 已存在于 today_plan.dart 中，跳过注入。")
        return

    # 查找 options 数组
    marker = "{'name': '旷野', 'path': 'assets/images/wallpaper/tree.jpg'},"
    if marker in content:
        new_entry = f"\n                            {{'name': '{title}', 'path': '{asset_path}'}},"
        new_content = content.replace(marker, marker + new_entry)
        with open(TODAY_PLAN_DART, "w", encoding="utf-8") as f:
            f.write(new_content)
        print(f"🎉 已成功将「{title}」({asset_path}) 注入今日计划壁纸列表！")
    else:
        print(f"⚠️ 未找到注入锚点，请手动在 today_plan.dart 中添加壁纸选项。")


def main():
    parser = argparse.ArgumentParser(description="Android 真机屏幕壁纸抓取与状态栏自动切除工具")
    parser.add_argument("--name", required=True, help="壁纸文件名标识（英文，例如 bamboo、mountains）")
    parser.add_argument("--title", default=None, help="App界面中显示的中文名称（例如 竹韵、青峰）")
    parser.add_argument("--serial", default=None, help="指定 ADB 设备序列号（多设备时）")
    parser.add_argument("--crop-top", type=int, default=None, help="自定义顶部裁切像素高度（默认自动探测状态栏）")
    parser.add_argument("--crop-bottom", type=int, default=0, help="自定义底部裁切像素高度（默认0）")
    parser.add_argument("--update-code", action="store_true", help="是否自动注入 today_plan.dart 的 options")

    args = parser.parse_args()
    try:
        capture_and_crop(
            name=args.name,
            title=args.title,
            serial=args.serial,
            crop_top=args.crop_top,
            crop_bottom=args.crop_bottom,
            update_code=args.update_code,
        )
    except Exception as e:
        print(f"❌ 执行失败: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
