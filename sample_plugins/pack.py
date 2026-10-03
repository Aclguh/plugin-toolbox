#!/usr/bin/env python3
"""
sample_plugins/pack.py - 跨平台动态插件打包工具
将各插件目录打包为符合规范的 .ptx (ZIP 压缩包)
用法:
    python sample_plugins/pack.py            # 打包所有插件
    python sample_plugins/pack.py base64_tool # 打包指定插件
"""

import sys
import os
import zipfile
import json

def pack_plugin(plugin_dir: str, output_ptx: str):
    manifest_path = os.path.join(plugin_dir, "plugin.json")
    if not os.path.isfile(manifest_path):
        print(f"  [跳过] 未在 {plugin_dir} 中找到 plugin.json")
        return False

    with open(manifest_path, "r", encoding="utf-8") as f:
        manifest = json.load(f)

    plugin_id = manifest.get("id")
    print(f"  正在打包插件: {manifest.get('name', plugin_id)} (v{manifest.get('version')}) -> {output_ptx} ...")

    with zipfile.ZipFile(output_ptx, "w", compression=zipfile.ZIP_DEFLATED) as zf:
        for root, dirs, files in os.walk(plugin_dir):
            for file in files:
                full_path = os.path.join(root, file)
                rel_path = os.path.relpath(full_path, plugin_dir)
                zf.write(full_path, rel_path)

    size_kb = os.path.getsize(output_ptx) / 1024
    print(f"  [成功] 生成 {output_ptx} ({size_kb:.1f} KB)")
    return True

def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    target_plugin = sys.argv[1] if len(sys.argv) > 1 else None

    print("========================================")
    print(" PluginToolbox 插件打包工具 (pack.py)")
    print("========================================")

    if target_plugin:
        plugin_path = os.path.join(script_dir, target_plugin)
        if not os.path.isdir(plugin_path):
            print(f"错误: 插件目录不存在: {plugin_path}")
            sys.exit(1)
        out_ptx = os.path.join(script_dir, f"{target_plugin}.ptx")
        pack_plugin(plugin_path, out_ptx)
    else:
        packed_count = 0
        for entry in os.listdir(script_dir):
            entry_path = os.path.join(script_dir, entry)
            if os.path.isdir(entry_path):
                out_ptx = os.path.join(script_dir, f"{entry}.ptx")
                if pack_plugin(entry_path, out_ptx):
                    packed_count += 1
        print(f"\n全部完成，共打包 {packed_count} 个插件。")

if __name__ == "__main__":
    main()
