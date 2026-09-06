#!/bin/bash
#
# 把 Google ML Kit 的三个 fat framework 重构为「真机片 + 模拟器片」分离的 XCFramework。
#
# 背景/根因:
#   Google 分发的 MLKit*.framework 是单个 fat 二进制: arm64(=真机, platform 2) + x86_64(=模拟器, platform 7)。
#   一个 fat 二进制无法同时容纳 arm64-真机 与 arm64-模拟器 两套片(二者 cputype/cpusubtype 相同，
#   fat 头以 (cputype, cpusubtype) 区分 slice, 无法容纳两个 arm64)，这正是 Apple 引入 XCFramework 的原因。
#   此前 patch_mlkit.py 直接原地把 arm64 真机片的 platform 从 2 改成 7(模拟器)，导致真机归档时
#   链接器看到 "built for iOS-simulator"，最终 build-and-upload-ios.sh 失败。
#
# 本脚本的正确做法: 用 xcodebuild -create-xcframework 生成
#   * ios-arm64               → 真机片(arm64, platform 2)
#   * ios-arm64_x86_64-simulator → 模拟器片(arm64+ x86_64, platform 7)
# 这样真机与 M 系列模拟器都原生可用，且不再对二进制做破坏性原地修改。
#
# 输入: 纯净的 Google fat framework(优先取 Pods 下安装后由旧脚本留下的 .orig 备份，即 Google 原始 fat 二进制)。
# 输出: app/ios/local_mlkit/<Pod>/<Pod>.xcframework (供本地 podspec vendored_frameworks 引用)。
#
# 幂等: 若 xcframework 已存在则跳过。local_mlkit 下的 xcframework 是长期真源(随仓库提交)，日常构建无需运行本脚本；
# 仅在「升级/重建 MLKit」时需要先恢复纯净的 Google fat framework(或 .orig)再运行。本方案已把 MLKit 改为 :path 本地 pod，
# 因此 Pods 下可能无常驻 fat 框架，重建前请先临时恢复之。
#
# 幂等: 若输出 xcframework 已存在且未标记 stale，则跳过。
set -euo pipefail

IOS_DIR="$(cd "$(dirname "$0")" && pwd)"
PODS_DIR="$IOS_DIR/Pods"
LOCAL_DIR="$IOS_DIR/local_mlkit"

FRAMEWORKS=(MLKitCommon MLKitDigitalInkRecognition MLKitMDD)

# 平台翻转 helper: 把(单个架构)二进制的所有 LC_BUILD_VERSION platform 改为模拟器(7)。
# 同时兼容单个 Mach-O 与 ar 归档(静态库)。参考原 patch_mlkit.py 的遍历逻辑，但只作用于副本。
patch_to_sim() {
  python3 - "$1" "$2" <<'PY'
import sys, struct
src, dst = sys.argv[1], sys.argv[2]
data = bytearray(open(src, 'rb').read())

def patch_macho(buf, base):
    """buf: bytearray; base: 本 Mach-O 在 buf 中的起始偏移; 返回本 Mach-O 补丁计数"""
    if len(buf) - base < 32:
        return 0
    magic = struct.unpack_from('<I', buf, base)[0]
    if magic != 0xfeedfacf:
        return 0
    ncmds = struct.unpack_from('<I', buf, base + 16)[0]
    offset = base + 32
    count = 0
    for _ in range(ncmds):
        if offset + 12 > len(buf):
            break
        cmd, cmdsize = struct.unpack_from('<II', buf, offset)
        if cmd == 0x32:  # LC_BUILD_VERSION
            platform = struct.unpack_from('<I', buf, offset + 8)[0]
            if platform in (1, 2):  # 真机 ios / macos -> 模拟器
                struct.pack_into('<I', buf, offset + 8, 7)
                count += 1
        offset += cmdsize
    return count

def patch_input(data):
    """对整个输入做补丁。若为 ar 归档,遍历成员;否则按单个 Mach-O 处理。返回补丁数"""
    if bytes(data[:8]) == b'!<arch>\n':
        pos = 8
        count = 0
        while pos < len(data):
            if pos + 60 > len(data):
                break
            header = data[pos:pos + 60]
            try:
                size = int(header[48:58].strip())
            except ValueError:
                break
            name = bytes(header[:16].strip())
            namelen = 0
            if name.startswith(b'#1/'):
                namelen = int(name[3:])
            member_start = pos + 60 + namelen
            member_size = size - namelen
            member_end = pos + 60 + size
            count += patch_macho(data, member_start)
            pos = member_end + (member_end % 2)
        return count
    return patch_macho(data, 0)

n = patch_input(data)
if n > 0:
    open(dst, 'wb').write(data)
    print(f'    patched {n} LC_BUILD_VERSION -> simulator')
else:
    sys.exit("no LC_BUILD_VERSION found to patch")
PY
}

mkdir -p "$LOCAL_DIR"

for FW in "${FRAMEWORKS[@]}"; do
  FW_DIR="$PODS_DIR/$FW/Frameworks/$FW.framework"
  BIN="$FW_DIR/$FW"
  OUT="$LOCAL_DIR/$FW/$FW.xcframework"

  # 纯净 fat 来源: 优先 .orig(Google 原始备份), 否则当前已安装的二进制(假定未被篡改)
  PRISTINE="$BIN.orig"
  if [ ! -f "$PRISTINE" ]; then
    PRISTINE="$BIN"
  fi
  if [ ! -f "$PRISTINE" ]; then
    echo "❌ 找不到 $FW 的纯净 fat 来源 ($PRISTINE)。请先 pod install 或恢复 .orig。"
    exit 1
  fi

  if [ -d "$OUT" ]; then
    echo "✅ $FW.xcframework 已存在，跳过 ($OUT)"
    continue
  fi

  echo "==> 构建 $FW.xcframework (source: $PRISTINE)"
  WORK="$(mktemp -d)"
  trap 'rm -rf "$WORK"' EXIT
  mkdir -p "$WORK/device/$FW.framework" "$WORK/sim/$FW.framework"

  # 复制 framework 内容(Headers/Modules/资源/PrivacyInfo 等), 去掉 .orig
  cp -R "$FW_DIR/." "$WORK/device/$FW.framework/" 2>/dev/null || true
  cp -R "$FW_DIR/." "$WORK/sim/$FW.framework/" 2>/dev/null || true
  rm -f "$WORK/device/$FW.framework/$FW.orig" "$WORK/sim/$FW.framework/$FW.orig"

  # 真机片: 仅保留 arm64 (platform 2)
  lipo -thin arm64 "$PRISTINE" -output "$WORK/device/$FW.framework/$FW"

  # 模拟器片: arm64(platform 2 -> 7) + x86_64(platform 7)
  lipo -thin arm64 "$PRISTINE" -output "$WORK/arm64.bin"
  patch_to_sim "$WORK/arm64.bin" "$WORK/arm64_sim.bin"
  if lipo -thin x86_64 "$PRISTINE" -output "$WORK/x86.bin" 2>/dev/null; then
    lipo -create "$WORK/arm64_sim.bin" "$WORK/x86.bin" -output "$WORK/sim/$FW.framework/$FW"
  else
    cp "$WORK/arm64_sim.bin" "$WORK/sim/$FW.framework/$FW"
  fi

  echo "  真机片: $(lipo -info "$WORK/device/$FW.framework/$FW" 2>/dev/null | sed 's/.*: //')"
  echo "  模拟片: $(lipo -info "$WORK/sim/$FW.framework/$FW" 2>/dev/null | sed 's/.*: //')"

  mkdir -p "$LOCAL_DIR/$FW"
  xcodebuild -create-xcframework \
    -framework "$WORK/device/$FW.framework" \
    -framework "$WORK/sim/$FW.framework" \
    -output "$OUT" 2>&1 | tail -3

  # 验证 slice
  echo "  输出 slices:"
  plutil -p "$OUT/Info.plist" 2>/dev/null | grep -E 'LibraryIdentifier|SupportedPlatform|variant' | sed 's/^/    /'

  # 拷贝 framework 内嵌的 resource.bundle 到 pod 根目录(如 MLKitDigitalInkRecognition_resource.bundle)，
  # 供本地 podspec 用 s.resources 声明，确保其进入 App 主 bundle(xcframework 内嵌资源不会自动被拷贝)。
  for RB in "$FW_DIR"/*_resource.bundle; do
    if [ -d "$RB" ]; then
      cp -R "$RB" "$LOCAL_DIR/$FW/"
      echo "  已导出资源: $(basename "$RB")"
    fi
  done

  rm -rf "$WORK"
  trap - EXIT
done

echo ""
echo "✅ 完成。XCFramework 位于: $LOCAL_DIR"
