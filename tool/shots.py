"""从连接的 Android 设备抓取截图, 裁掉系统栏并压缩到 README 用尺寸。

用法:
    python tool/shots.py [--device ID] [--top-inset N] [--bottom-inset N] NAME [NAME ...]

每个 NAME 形如 01-home, 会:
  1. adb shell screencap 抓当前屏幕;
  2. 裁掉顶部状态栏与底部导航栏, 只保留应用内容;
  3. 缩放到 540px 宽并保存为 docs/screenshots/NAME.png。

系统栏 inset 默认运行时从 dumpsys 读取 (不同设备高度不同, 不能写死);
老设备解析失败时可用 --top-inset / --bottom-inset 显式指定。
多设备并存时可用 --device 或环境变量 ANDROID_SERIAL 选择设备。
"""

import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile

from PIL import Image

# 输出目录锚定到脚本所在仓库根, 允许从任意工作目录执行截图脚本
OUT_DIR = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "docs", "screenshots",
)

# README 中图片按 260px-270px 显示, 540px 宽相当于 2x, 足够清晰且体积小。
TARGET_WIDTH = 540


def resolve_adb() -> str:
    """环境变量 ADB 优先, 否则在 PATH 中查找 adb。"""
    adb = os.environ.get("ADB") or shutil.which("adb")
    if not adb:
        sys.exit("未找到 adb: 请把 platform-tools 加入 PATH, 或用环境变量 ADB 指定 adb 完整路径")
    return adb


def run_adb(adb: str, device_id: str | None, *args: str) -> str:
    cmd = [adb]
    if device_id:
        cmd.extend(["-s", device_id])
    cmd.extend(args)
    result = subprocess.run(cmd, check=True, capture_output=True, text=True, encoding="utf-8", errors="replace")
    return result.stdout


def detect_insets(adb: str, device_id: str | None) -> tuple[int, int]:
    """从 dumpsys 读取状态栏/导航栏高度 (物理像素)。

    竖屏假设: 状态栏 frame 形如 [0,0][1080,94], 导航栏 frame 形如 [0,2356][1080,2400]。
    任一方向解析失败即按 0 处理并显式警告 —— 宁可不裁, 不拿别的设备的固定值裁错。
    """
    try:
        dump = run_adb(adb, device_id, "shell", "dumpsys", "window")
    except subprocess.CalledProcessError as e:
        print(f"警告: dumpsys 读取失败, 不裁剪系统栏 ({e})", file=sys.stderr)
        return 0, 0

    m_status = re.search(r"type=statusBars.*?frame=\[0,0\]\[\d+,(\d+)\]", dump)
    if not m_status:
        m_status = re.search(r"StatusBar.*?frame=\[0,0\]\[\d+,(\d+)\]", dump)

    m_nav = re.search(r"type=navigationBars.*?frame=\[0,(\d+)\]\[\d+,(\d+)\]", dump)
    if not m_nav:
        m_nav = re.search(r"NavigationBar.*?frame=\[0,(\d+)\]\[\d+,(\d+)\]", dump)

    top = int(m_status.group(1)) if m_status else 0
    bottom = (int(m_nav.group(2)) - int(m_nav.group(1))) if m_nav else 0
    if not (m_status and m_nav):
        print("提示: 未能从 dumpsys 精确解析出系统栏高度, 缺省不裁 (可用 --top-inset / --bottom-inset 指定)", file=sys.stderr)
    return top, bottom


def capture(adb: str, device_id: str | None, top_inset: int, bottom_inset: int, name: str) -> None:
    with tempfile.TemporaryDirectory() as tmp:
        raw = os.path.join(tmp, "raw.png")
        remote = "/sdcard/_shot.png"
        try:
            run_adb(adb, device_id, "shell", "screencap", "-p", remote)
            run_adb(adb, device_id, "pull", remote, raw)
        finally:
            # 设备端临时文件用完即清
            run_adb(adb, device_id, "shell", "rm", "-f", remote)

        img = Image.open(raw).convert("RGB")
        w, h = img.size

        # 只保留应用自身内容, 去掉状态栏与导航栏
        bottom_pos = h - bottom_inset if (h - bottom_inset) > top_inset else h
        cropped = img.crop((0, top_inset, w, bottom_pos))

        # 等比缩放到目标宽度
        cw, ch = cropped.size
        scale = TARGET_WIDTH / cw
        resized = cropped.resize(
            (TARGET_WIDTH, round(ch * scale)),
            Image.LANCZOS,
        )

        os.makedirs(OUT_DIR, exist_ok=True)
        out = os.path.join(OUT_DIR, name + ".png")
        resized.save(out, "PNG", optimize=True)
        print(f"  {name}.png -> {resized.size[0]}x{resized.size[1]} ({os.path.getsize(out) // 1024} KB)")


def main() -> None:
    parser = argparse.ArgumentParser(description="抓取 Android 设备截图并裁剪压缩到 README 用尺寸")
    parser.add_argument("names", nargs="+", help="截图名, 如 01-home (不含扩展名)")
    parser.add_argument("--device", "-s", type=str, default=os.environ.get("ANDROID_SERIAL"), help="设备 ID")
    parser.add_argument("--top-inset", type=int, default=None, help="状态栏高度 (物理像素), 缺省从 dumpsys 读取")
    parser.add_argument("--bottom-inset", type=int, default=None, help="导航栏高度 (物理像素), 缺省从 dumpsys 读取")
    args = parser.parse_args()

    adb = resolve_adb()
    top, bottom = detect_insets(adb, args.device)
    if args.top_inset is not None:
        top = args.top_inset
    if args.bottom_inset is not None:
        bottom = args.bottom_inset
    print(f"裁切系统栏设置: 顶部 {top}px / 底部 {bottom}px")

    for name in args.names:
        capture(adb, args.device, top, bottom, name)


if __name__ == "__main__":
    main()
