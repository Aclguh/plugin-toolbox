#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
PluginToolbox 插件开发者官方 CLI 脚手架工具 (ptx.py)
用于一键创建插件、合规性语法与安全静态校验 (Lint) 以及跨平台打包。
"""

import argparse
import json
import os
import re
import sys
import zipfile
from pathlib import Path

VALID_ID_PATTERN = re.compile(r'^[a-z0-9_]{3,50}$')
LUA_BYTECODE_HEADER = bytes([0x1B, 0x4C, 0x75, 0x61])  # \x1bLua

TEMPLATE_PLUGIN_JSON = {
    "id": "{plugin_id}",
    "name": "{plugin_name}",
    "version": "1.0.0",
    "description": "基于 PluginToolbox 的轻量动态扩展工具",
    "author": "Plugin Developer",
    "minAppVersion": "0.2.1",
    "type": "lua",
    "category": "utility",
    "permissions": ["clipboard"],
    "entry": "main.lua",
    "ui": "ui/main.ui.json",
    "storageQuotaMb": 20,
    "persistentStates": ["input_text"]
}

TEMPLATE_MAIN_LUA = """--- PluginToolbox 插件入口逻辑
--- 可将 tool/schemas/plugin_api.def.lua 引入当前工作区以获得全套 IDE 代码补全

function onLaunch(data)
  print("[{plugin_id}] 插件已加载启动")
end

function handleAction()
  local text = state.get("input_text") or ""
  if #text == 0 then
    dialog.toast("请输入内容")
    return
  end
  local upper = string.upper(text)
  state.set("output_text", upper)
  dialog.toast("处理完成")
end
"""

TEMPLATE_MAIN_UI_JSON = {
    "type": "SingleChildScrollView",
    "props": {
        "padding": 16.0
    },
    "children": [
        {
            "type": "Card",
            "props": {
                "elevation": 2.0
            },
            "children": [
                {
                    "type": "Padding",
                    "props": {
                        "padding": 16.0
                    },
                    "children": [
                        {
                            "type": "Column",
                            "props": {
                                "crossAxisAlignment": "stretch"
                            },
                            "children": [
                                {
                                    "type": "Text",
                                    "props": {
                                        "text": "{plugin_name}",
                                        "fontSize": 20.0,
                                        "fontWeight": "bold"
                                    }
                                },
                                {
                                    "type": "SizedBox",
                                    "props": {
                                        "height": 12.0
                                    }
                                },
                                {
                                    "type": "TextField",
                                    "props": {
                                        "label": "输入文本",
                                        "stateKey": "input_text",
                                        "hint": "在此输入需要转换的文本..."
                                    }
                                },
                                {
                                    "type": "SizedBox",
                                    "props": {
                                        "height": 12.0
                                    }
                                },
                                {
                                    "type": "Button",
                                    "props": {
                                        "text": "执行转换",
                                        "type": "filled"
                                    },
                                    "events": {
                                        "onPressed": {
                                            "action": "callLua",
                                            "function": "handleAction"
                                        }
                                    }
                                },
                                {
                                    "type": "SizedBox",
                                    "props": {
                                        "height": 16.0
                                    }
                                },
                                {
                                    "type": "CodeView",
                                    "props": {
                                        "text": "{{state.output_text}}",
                                        "language": "plaintext",
                                        "showLineNumbers": False
                                    }
                                }
                            ]
                        }
                    ]
                }
            ]
        }
    ]
}


def cmd_init(args):
    plugin_id = args.id.strip().lower()
    if not VALID_ID_PATTERN.match(plugin_id):
        print(f"❌ 错误: 插件 ID [{plugin_id}] 不合法，仅允许 3-50 位小写字母、数字及下划线")
        sys.exit(1)

    plugin_name = args.name or plugin_id.replace('_', ' ').title()
    target_dir = Path(args.output_dir or plugin_id)

    if target_dir.exists() and any(target_dir.iterdir()):
        print(f"❌ 错误: 目标目录 [{target_dir}] 已存在且非空")
        sys.exit(1)

    target_dir.mkdir(parents=True, exist_ok=True)
    ui_dir = target_dir / "ui"
    ui_dir.mkdir(parents=True, exist_ok=True)

    manifest = json.loads(json.dumps(TEMPLATE_PLUGIN_JSON))
    manifest["id"] = plugin_id
    manifest["name"] = plugin_name
    (target_dir / "plugin.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False), encoding="utf-8")

    lua_code = TEMPLATE_MAIN_LUA.replace("{plugin_id}", plugin_id)
    (target_dir / "main.lua").write_text(lua_code, encoding="utf-8")

    ui_data = json.loads(json.dumps(TEMPLATE_MAIN_UI_JSON).replace("{plugin_name}", plugin_name))
    (ui_dir / "main.ui.json").write_text(json.dumps(ui_data, indent=2, ensure_ascii=False), encoding="utf-8")

    print(f"🎉 成功创建插件脚手架: {target_dir.resolve()}")
    print(f"  ├── plugin.json       (插件元数据与权限)")
    print(f"  ├── main.lua          (业务逻辑与事件函数)")
    print(f"  └── ui/main.ui.json   (声明式动态组件树)")
    print(f"\n下一步:")
    print(f"  运行 `python tool/ptx.py lint {target_dir}` 检查合规性")
    print(f"  运行 `python tool/ptx.py pack {target_dir}` 打包生成 .ptx 文件")


def cmd_lint(args):
    target_dir = Path(args.dir)
    if not target_dir.is_dir():
        print(f"❌ 错误: 目标路径 [{target_dir}] 不是合法目录")
        sys.exit(1)

    manifest_file = target_dir / "plugin.json"
    if not manifest_file.is_file():
        print(f"❌ 错误: 缺少 plugin.json 清单文件")
        sys.exit(1)

    try:
        manifest = json.loads(manifest_file.read_text(encoding="utf-8"))
    except Exception as e:
        print(f"❌ 错误: plugin.json 不是合法 JSON: {e}")
        sys.exit(1)

    plugin_id = manifest.get("id", "")
    if not VALID_ID_PATTERN.match(plugin_id):
        print(f"❌ 错误: 插件 ID [{plugin_id}] 不合法")
        sys.exit(1)

    entry_name = manifest.get("entry", "main.lua")
    entry_file = target_dir / entry_name
    if not entry_file.is_file():
        print(f"❌ 错误: 缺少入口脚本文件: {entry_name}")
        sys.exit(1)

    entry_bytes = entry_file.read_bytes()
    if entry_bytes.startswith(LUA_BYTECODE_HEADER):
        print(f"❌ 错误: 安全策略拦截: 入口脚本禁止使用预编译 Lua 字节码 (以 \\x1bLua 开头)，必须为纯文本源码")
        sys.exit(1)

    ui_name = manifest.get("ui", "ui/main.ui.json")
    ui_file = target_dir / ui_name
    if not ui_file.is_file():
        print(f"❌ 错误: 缺少 UI 描述文件: {ui_name}")
        sys.exit(1)

    try:
        ui_ast = json.loads(ui_file.read_text(encoding="utf-8"))
        if not isinstance(ui_ast, dict) or "type" not in ui_ast:
            print(f"❌ 错误: UI 描述根节点必须包含 'type' 字段的对象")
            sys.exit(1)
    except Exception as e:
        print(f"❌ 错误: UI 描述文件不是合法 JSON: {e}")
        sys.exit(1)

    print(f"✅ 校验通过: 插件 [{plugin_id} v{manifest.get('version', '1.0.0')}] 结构完整且符合全部安全规范！")


def cmd_pack(args):
    target_dir = Path(args.dir)
    if not target_dir.is_dir():
        print(f"❌ 错误: 目标路径 [{target_dir}] 不是合法目录")
        sys.exit(1)

    manifest_file = target_dir / "plugin.json"
    if not manifest_file.is_file():
        print(f"❌ 错误: 缺少 plugin.json 清单文件")
        sys.exit(1)

    try:
        manifest = json.loads(manifest_file.read_text(encoding="utf-8"))
    except Exception as e:
        print(f"❌ 错误: plugin.json 不是合法 JSON: {e}")
        sys.exit(1)

    plugin_id = manifest.get("id", target_dir.name)
    out_dir = Path(args.out) if args.out else target_dir.parent
    out_dir.mkdir(parents=True, exist_ok=True)
    out_file = out_dir / f"{plugin_id}.ptx"

    with zipfile.ZipFile(out_file, "w", zipfile.ZIP_DEFLATED) as zf:
        for root, dirs, files in os.walk(target_dir):
            for file in files:
                if file.endswith(".ptx"):
                    continue
                file_path = Path(root) / file
                rel_path = file_path.relative_to(target_dir).as_posix()
                zf.write(file_path, rel_path)

    print(f"📦 成功打包插件: {out_file.resolve()} ({out_file.stat().st_size} 字节)")


def main():
    parser = argparse.ArgumentParser(description="PluginToolbox 插件开发者脚手架工具")
    subparsers = parser.add_subparsers(dest="command", required=True)

    # init
    p_init = subparsers.add_parser("init", help="初始化创建标准插件工程骨架")
    p_init.add_argument("id", help="插件唯一标识 ID (3-50 位小写字母、数字及下划线)")
    p_init.add_argument("--name", help="插件人类可读显示名称")
    p_init.add_argument("--output-dir", help="目标输出目录 (默认以 ID 为目录名)")
    p_init.set_defaults(func=cmd_init)

    # lint
    p_lint = subparsers.add_parser("lint", help="静态合规性与安全性检查")
    p_lint.add_argument("dir", help="待检查的插件目录")
    p_lint.set_defaults(func=cmd_lint)

    # pack
    p_pack = subparsers.add_parser("pack", help="将插件目录打包为 .ptx 归档包")
    p_pack.add_argument("dir", help="待打包的插件目录")
    p_pack.add_argument("--out", help="打包文件输出目录 (默认与插件目录同级)")
    p_pack.set_defaults(func=cmd_pack)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
