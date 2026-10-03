<div align="center">

<img src="app/assets/icons/plugin-toolbox-icon.png" width="128" alt="PluginToolbox Icon" />

# PluginToolbox

**Everything is a Plugin — A modern Android toolbox powered by sandboxed runtimes and declarative dynamic UI.**

A decoupled, fully offline, and hot-pluggable toolbox application for Android. Users can install and execute brand-new tools instantly via `.ptx` plugin packages without recompiling the host app.

[![Flutter](https://img.shields.io/badge/Flutter-3.29+-02569B?logo=flutter)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.7+-0175C2?logo=dart)](https://dart.dev)
[![Platform](https://img.shields.io/badge/Platform-Android-3DDC84?logo=android)](#installation--usage)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Architecture](https://img.shields.io/badge/Architecture-Monorepo-orange.svg)](#architecture)

[简体中文](README.md) · **English**

</div>

---

## Core Features

- **Hot-Pluggable Plugin Ecosystem**:
  - Powered by the `.ptx` (Plugin Toolbox Extension) standard zip archive format for one-click installation, immediate activation, and safe uninstallation.
  - Each dynamic plugin operates within an isolated sandbox directory to guarantee file and data boundaries.
- **Declarative Dynamic UI (DUI)**:
  - Component trees defined purely in JSON (`ui.json`), translated natively into high-performance Flutter widgets at runtime.
  - Reactive data binding via `${state.key}` and event dispatchers without convoluted front-end boilerplate.
- **Sandboxed Scripting Engine**:
  - Embedded Lua 5.1/LuaJIT runtime (`entry.lua`) providing lightweight, deterministic business logic execution.
  - Secure host API bridges: clipboard (`toolbox.clipboard`), sandbox storage (`toolbox.storage`), cryptographic primitives, and structured logging.
- **Unified Drag Reordering & Management**:
  - **Home Screen**: Clean, category-free responsive grid with long-press drag-to-reorder support.
  - **Plugin Manager**: Instant enable/disable switches, long-press card deletion protection, and left-handle drag sorting in real-time sync with the home grid.
- **Dedicated Brand Theme**:
  - Brand identity derived directly from the vector app icon: deep navy background (`#26366A`) with crisp ice-blue typography (`#B4C9FF`, contrast > 7.4:1, exceeding WCAG AAA).
  - Built-in Brand Dark, Crisp Light, and Follow System modes, plus optional Material You wallpaper dynamic color extraction.
- **Responsive Layout & Gesture Protection**:
  - Defaults to portrait orientation with a gravity auto-rotation setting toggle.
  - Predictive back navigation gesture protection on Android 13+ prevents accidental app termination from sub-pages.

---

## Architecture

This project is organized as a clean Monorepo with strict unidirectional dependencies:

```
plugin-toolbox/
├── app/                  # Android Flutter shell application
│   ├── lib/              # Pages, routing (go_router), global state (Riverpod)
│   └── test/             # Widget tests & end-to-end integration tests
├── packages/
│   ├── core/             # Core domain: models, registry, installer, sandbox storage (Pure Dart)
│   ├── lua/              # Script execution: Lua engine & safe host API bindings
│   ├── dui/              # Declarative UI engine: JSON AST -> Flutter Widget rendering
│   └── ui/               # Shared presentation: AppTheme design system & reusable widgets
├── sample_plugins/       # Official reference plugins with packing scripts
│   ├── base64_tool/      # Base64 encoder/decoder plugin
│   └── hash_tool/        # MD5 / SHA-1 / SHA-256 hash calculator plugin
└── AGENTS.md             # Developer & AI Agent engineering standards
```

---

## `.ptx` Plugin Specification

A valid `.ptx` package is a standard ZIP archive containing:

```
my_plugin.ptx
├── manifest.json         # Plugin manifest and metadata (required)
├── entry.lua             # Logic and event handling script (required)
├── ui.json               # Declarative UI component tree (required)
└── icon.png              # Plugin icon, recommended 128x128 (optional)
```

### 1. `manifest.json`

```json
{
  "id": "base64_tool",
  "name": "Base64 Codec",
  "version": "1.0.0",
  "description": "Base64 text encoder and decoder utility",
  "author": "PluginToolbox Team",
  "type": "lua",
  "category": "utility",
  "entry": "entry.lua",
  "ui": "ui.json",
  "permissions": ["storage", "clipboard"]
}
```

### 2. Packing a Plugin

Run the included packing script in the sample plugin directory:

```bash
python pack.py
# Generates <plugin_id>.ptx in dist/
```

---

## Installation & Usage

### Building from Source

Prerequisites:
- Flutter SDK 3.29+ / Dart SDK 3.7+
- Android SDK (API 34+), Java 17+
- Python 3.10+ (for packing scripts)

```bash
# Clone the repository
git clone https://github.com/Aclguh/plugin-toolbox.git
cd plugin-toolbox

# Fetch dependencies
cd app && flutter pub get

# Run on a connected device
flutter run
```

### Generating Split Release APKs

```bash
cd app
flutter build apk --release --split-per-abi
# Artifacts:
# - build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
# - build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk
# - build/app/outputs/flutter-apk/app-x86_64-release.apk
```

---

## Testing & Quality Gates

Strict automated gates are enforced before completion (see [AGENTS.md](AGENTS.md)):

```bash
# 1. Static analysis (0 errors, 0 warnings)
dart analyze

# 2. UI package tests
cd packages/ui && flutter test

# 3. Host shell & widget tests
cd ../../app && flutter test

# 4. End-to-end .ptx plugin workflow tests
flutter test test/ptx_integration_test.dart
```

---

## Contributing & Agent Guidelines

Before contributing or refactoring, please read:

👉 **[AGENTS.md (Developer & AI Agent Guidelines)](AGENTS.md)**

---

## License

Distributed under the [MIT License](LICENSE).
