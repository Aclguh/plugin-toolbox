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
                                    "ref": "input_text",
                                    "props": {
                                        "label": "输入文本",
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


SCHEMAS_DIR = Path(__file__).resolve().parent / "schemas"
DUI_SCHEMA_FILE = SCHEMAS_DIR / "dui.schema.json"
PLUGIN_SCHEMA_FILE = SCHEMAS_DIR / "plugin.schema.json"


def load_allowed_types():
    if DUI_SCHEMA_FILE.is_file():
        try:
            schema = json.loads(DUI_SCHEMA_FILE.read_text(encoding="utf-8"))
            enums = schema.get("properties", {}).get("type", {}).get("enum", [])
            if enums:
                return set(enums)
        except Exception:
            pass
    return {
        "Container", "Column", "Row", "Stack", "Wrap", "Padding", "Center",
        "Expanded", "SizedBox", "SingleChildScrollView", "Card", "Divider",
        "ListTile", "ListView", "LazyListView", "Repeater", "Text",
        "SelectableText", "Button", "FilledButton", "OutlinedButton",
        "IconButton", "TextField", "Switch", "Slider", "Dropdown",
        "ProgressBar", "Tabs", "TabBar", "Image", "Icon", "MarkdownView",
        "Markdown", "Html", "HtmlView", "DrawingPad", "SignaturePad", "Canvas",
        "PixelGrid", "Chart", "LineChart", "BarChart", "CodeView", "DiffView",
        "TreeView", "ColorPicker"
    }


def load_allowed_permissions():
    if PLUGIN_SCHEMA_FILE.is_file():
        try:
            schema = json.loads(PLUGIN_SCHEMA_FILE.read_text(encoding="utf-8"))
            items = schema.get("properties", {}).get("permissions", {}).get("items", {})
            enums = items.get("enum", [])
            if enums:
                return set(enums)
        except Exception:
            pass
    return {
        "network", "clipboard", "storage", "camera", "location", "sensor",
        "notification", "vibrate", "audio", "microphone", "bluetooth",
        "sqlite", "file_picker", "ipc"
    }


def extract_lua_functions(lua_src: str):
    clean = re.sub(r'--\[\[.*?\]\]', '', lua_src, flags=re.DOTALL)
    clean = re.sub(r'--.*', '', clean)
    clean = re.sub(r'"(?:\\.|[^"])*"', '""', clean)
    clean = re.sub(r"'(?:\\.|[^'])*'", "''", clean)
    clean = re.sub(r'\[\[.*?\]\]', '""', clean, flags=re.DOTALL)

    funcs = set(re.findall(r'(?:local\s+)?function\s+([a-zA-Z0-9_]+)\s*\(', clean))
    funcs.update(re.findall(r'([a-zA-Z0-9_]+)\s*=\s*function\s*\(', clean))
    return funcs


def check_lua_balance(lua_src: str):
    clean = re.sub(r'--\[\[.*?\]\]', '', lua_src, flags=re.DOTALL)
    clean = re.sub(r'--.*', '', clean)
    clean = re.sub(r'"(?:\\.|[^"])*"', '""', clean)
    clean = re.sub(r"'(?:\\.|[^'])*'", "''", clean)
    clean = re.sub(r'\[\[.*?\]\]', '""', clean, flags=re.DOTALL)

    tokens = re.findall(r'\b(?:function|if|while|for|do|end)\b', clean)
    opens = 0
    ends = 0
    loop_open = False
    for t in tokens:
        if t in ('function', 'if'):
            opens += 1
        elif t in ('while', 'for'):
            opens += 1
            loop_open = True
        elif t == 'do':
            if loop_open:
                loop_open = False
            else:
                opens += 1
        elif t == 'end':
            ends += 1
            loop_open = False
    if opens != ends:
        return f"关键字结构不平衡: 开启块 (function/if/while/for/do 共 {opens} 处) 与闭合 end 关键字 (共 {ends} 处) 数量不匹配"
    return None


def lint_ui_node(node, path, allowed_types, referenced_lua_funcs, errors):
    if not isinstance(node, dict):
        errors.append(f"UI 节点 [{path}] 必须为 JSON 对象")
        return
    ntype = node.get("type")
    if not ntype:
        errors.append(f"UI 节点 [{path}] 缺失必填字段 'type'")
        return
    if ntype not in allowed_types:
        errors.append(f"UI 节点 [{path}] 包含未注册的组件类型: [{ntype}]")

    events = node.get("events")
    if isinstance(events, dict):
        for ev_name, ev_body in events.items():
            if isinstance(ev_body, dict):
                if ev_body.get("action") == "callLua":
                    fn = ev_body.get("function") or ev_body.get("func")
                    if fn:
                        referenced_lua_funcs.add((str(fn), f"{path}.events.{ev_name}"))

    if "child" in node and isinstance(node["child"], dict):
        lint_ui_node(node["child"], f"{path}/child", allowed_types, referenced_lua_funcs, errors)
    if "children" in node and isinstance(node["children"], list):
        for i, c in enumerate(node["children"]):
            lint_ui_node(c, f"{path}/children[{i}]", allowed_types, referenced_lua_funcs, errors)
    props = node.get("props")
    if isinstance(props, dict):
        if "child" in props and isinstance(props["child"], dict):
            lint_ui_node(props["child"], f"{path}.props.child", allowed_types, referenced_lua_funcs, errors)
        for list_key in ("children", "tabViews"):
            if list_key in props and isinstance(props[list_key], list):
                for i, c in enumerate(props[list_key]):
                    lint_ui_node(c, f"{path}.props.{list_key}[{i}]", allowed_types, referenced_lua_funcs, errors)


def cmd_lint(args):
    target_dir = Path(args.dir)
    if not target_dir.is_dir():
        print(f"❌ 错误: 目标路径 [{target_dir}] 不是合法目录")
        sys.exit(1)

    errors = []

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
        errors.append(f"插件 ID [{plugin_id}] 不合法，仅允许 3-50 位小写字母、数字及下划线")

    if not manifest.get("name"):
        errors.append("plugin.json 缺少插件名称 'name'")

    version = manifest.get("version", "")
    if not re.match(r"^v?\d+\.\d+(\.\d+)?(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$", version):
        errors.append(f"版本号 '{version}' 不符合语义化版本格式 (如 1.0.0)")

    allowed_permissions = load_allowed_permissions()
    perms = manifest.get("permissions", [])
    if isinstance(perms, list):
        for p in perms:
            if p not in allowed_permissions:
                errors.append(f"plugin.json 包含未声明或未知的权限项: [{p}]")

    entry_name = manifest.get("entry", "main.lua")
    entry_file = target_dir / entry_name
    defined_lua_funcs = set()
    if not entry_file.is_file():
        errors.append(f"缺少入口脚本文件: {entry_name}")
    else:
        entry_bytes = entry_file.read_bytes()
        if entry_bytes.startswith(LUA_BYTECODE_HEADER):
            errors.append("安全策略拦截: 入口脚本禁止使用预编译 Lua 字节码 (以 \\x1bLua 开头)，必须为纯文本源码")
        else:
            try:
                lua_src = entry_file.read_text(encoding="utf-8")
                balance_err = check_lua_balance(lua_src)
                if balance_err:
                    errors.append(f"入口脚本 {entry_name} {balance_err}")
                defined_lua_funcs = extract_lua_functions(lua_src)
            except Exception as e:
                errors.append(f"读取入口脚本 {entry_name} 失败: {e}")

    ui_name = manifest.get("ui", "ui/main.ui.json")
    ui_file = target_dir / ui_name
    referenced_lua_funcs = set()
    if not ui_file.is_file():
        errors.append(f"缺少 UI 描述文件: {ui_name}")
    else:
        try:
            ui_ast = json.loads(ui_file.read_text(encoding="utf-8"))
            allowed_types = load_allowed_types()
            lint_ui_node(ui_ast, "root", allowed_types, referenced_lua_funcs, errors)
        except Exception as e:
            errors.append(f"UI 描述文件不是合法 JSON: {e}")

    for fn, loc in sorted(referenced_lua_funcs):
        if fn not in defined_lua_funcs:
            errors.append(f"UI 事件绑定函数 [{fn}] (位于 {loc}) 在入口脚本 {entry_name} 中未找到定义")

    if errors:
        print(f"❌ 校验失败: 发现 {len(errors)} 处合规性或语法错误:")
        for idx, err in enumerate(errors, 1):
            print(f"  {idx}. {err}")
        sys.exit(1)

    print(f"✅ 校验通过: 插件 [{plugin_id} v{manifest.get('version', '1.0.0')}] 结构完整且符合全部安全规范！")
    print(f"   - 清单规范: 元数据完整，已授权 {len(perms)} 项合法权限")
    print(f"   - 界面组件: DUI AST 组件类型全量合规")
    print(f"   - 事件绑定: {len(referenced_lua_funcs)} 处 callLua 函数均已成功链接至 {entry_name}")
    print(f"   - 脚本语法: {entry_name} 块结构平衡")


def cmd_pack(args):
    target_dir = Path(args.dir)
    if not target_dir.is_dir():
        print(f"❌ 错误: 目标路径 [{target_dir}] 不是合法目录")
        sys.exit(1)

    if not getattr(args, "skip_lint", False):
        print("🔍 打包前自动执行静态合规与语法校验...")
        cmd_lint(args)

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


def cmd_watch(args):
    import time

    target_dir = Path(args.dir)
    if not target_dir.is_dir():
        print(f"❌ 错误: 目标路径 [{target_dir}] 不是合法目录")
        sys.exit(1)

    print(f"👀 正在监听插件目录变更: {target_dir.resolve()} (按 Ctrl+C 退出)")
    cmd_pack(args)
    last_mtime = 0

    try:
        while True:
            max_m = 0
            for root, dirs, files in os.walk(target_dir):
                for f in files:
                    if not f.endswith(".ptx"):
                        p = Path(root) / f
                        try:
                            max_m = max(max_m, p.stat().st_mtime)
                        except OSError:
                            pass
            if last_mtime != 0 and max_m > last_mtime:
                print("🔄 检测到源码变更，正在自动重新打包...")
                cmd_pack(args)
            last_mtime = max_m
            time.sleep(1)
    except KeyboardInterrupt:
        print("\n👋 已停止监听")


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
    p_pack.add_argument("--skip-lint", action="store_true", help="跳过静态校验直接打包")
    p_pack.set_defaults(func=cmd_pack)

    # watch
    p_watch = subparsers.add_parser("watch", help="监听插件目录变更并自动重新打包")
    p_watch.add_argument("dir", help="待监听的插件目录")
    p_watch.add_argument("--out", help="打包文件输出目录 (默认与插件目录同级)")
    p_watch.set_defaults(func=cmd_watch)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
