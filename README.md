# Roost

macOS 原生、jj 一等公民的多 agent 终端编排器。

> Status: **pre-alpha**。单 app 进程形态已可用 — 多 project / jj workspace / 多 session tab / 一键起 Claude Code / Codex / terminal / OSC 通知环 / IME (CJK/Hangul/dead-keys) / 项目拖拽重排。后端 daemon (`roost-hostd`) 重构尚未开始。可在 [`apps/Roost/`](./apps/Roost/) 下 build & run。

## 定位

并行跑多个 CLI 编码 agent（Claude Code / Codex / Gemini CLI / Cursor Agent 等），每个 agent 住在独立的 jj workspace。macOS 原生 UI，libghostty 渲染终端，Rust 后端管状态和编排。

和已有工具的关系：

- 对标 [`manaflow-ai/cmux`](https://github.com/manaflow-ai/cmux)：加目录分组和多 agent 编排视图。
- 对标 [`Dcouple-Inc/Pane`](https://github.com/Dcouple-Inc/Pane)：改成 macOS 原生 + jj 原生，不做跨平台。
- 对标 [`superset-sh/superset`](https://github.com/superset-sh/superset)：沿用分组展示，但抛掉 Electron；未来借鉴其 daemon 持久化路线（见 design.md §5a）。

## 技术栈

- 前端：SwiftUI + AppKit，libghostty 做 GPU VT 渲染，NSTextInputClient 对接系统 IME。
- 后端：Rust（tokio + swift-bridge），负责 jj CLI 调用、agent spawn、`.roost/config.json` hook runner。SQLite / 独立 hostd 进程从 **M6** 开始引入。
- VCS：只支持 [jj](https://github.com/jj-vcs/jj)，`--no-pager` + stdio null 防 GUI 进程 behind `less`。

## Roadmap

见 [`design.md`](./design.md)。当前进度：

**已跑通**

- ✅ **M-1** libghostty + SwiftUI POC
- ✅ **M0.0** agent CLI 在 ghostty surface 里跑通
- ✅ **M0.1** Cargo workspace + swift-bridge FFI
- ✅ **M0.2** Rust `prepare_session` 驱动 ghostty surface
- ✅ **M1** 多 session tab + 切换（⌘W 关当前 tab、⌘1-9 切 tab、⌘[ / ⌘] 相对切换）
- ✅ **M2** jj workspace 创建 / 删除 + bookmark 约定
- ✅ **M3** Project 侧边栏：ScrollView+LazyVStack 自绘、Project/Scratch 分区、DisclosureGroup 会话子行、拖拽重排（含悬停插入线动画）
- ✅ **M4** OSC 9/99/777 → 通知环（session 未激活时 tab 上蓝点 + dock badge）
- ✅ **M5** `.roost/config.json` setup/teardown 脚本（`$SHELL -lc <cmd>`，失败仅侧栏 warning 不阻塞）
- ✅ **M10 (部分)** "Open in IDE" / "Open in Terminal" 右键子菜单，通过 LaunchServices 动态探测已装应用（Cursor/VSCode/Zed/Xcode/… × Ghostty/iTerm/WezTerm/Alacritty/…）
- ✅ 额外：host-level 快捷键 ⌘V/⌘C copy-paste，⌘± 字号调整，⌘T 新 terminal，⌃1 Claude Code，⌃2 Codex
- ✅ 额外：CJK/Hangul/dead-key 输入法支持（NSTextInputClient + `ghostty_surface_preedit` + Carbon TIS 切换检测 → cancel 而非 commit preedit）

**下一步（daemon 重构三步串行）**

- 🚧 **M6** `roost-hostd` daemon 雏形：独立进程 + Unix socket JSON-RPC + swift-bridge 改 thin client + SQLite 迁入
- 🚧 **M7** PTY 归 hostd + `roost-attach` relay 替代直接 spawn
- 🚧 **M8** Manifest pidfile + adopt / spawn 决策 + release/stop quit 模式 + session 恢复 UI

**正交独立，可穿插**

- ⬜ **M9** `roost` CLI (socket client 直连 hostd)
- ⬜ **M10 (剩余)** macOS Services / AppleScript 跳转入口
- ⬜ **M11** diff viewer
- ⬜ **M12** git worktree 支持（引入 `trait Vcs`）
- ⬜ **M13** 远程 hostd（SSH 隧道 UDS）
- ⬜ **M14** 主题 & 字体 UI
- ⬜ **M15** Agent 预设系统（去硬编码 presets）
- ⬜ **M16** 通知偏好（per-agent 声音 / banner 开关）
- ⬜ **M17** 键绑定自定义
- ⬜ **M18** 三层 Sidebar（Project → Workspace → Session）+ workspace 新建 UI（计划等 M6 hostd 合入后开工）

## 仓库结构

```
.
├── Cargo.toml                  # workspace
├── crates/
│   └── roost-bridge/           # Rust staticlib (jj CLI wrapper + hooks + FFI)
│                               # M6 起会拆分为 roost-core / roost-hostd / roost-client / roost-bridge / roost-attach
├── apps/
│   └── Roost/
│       ├── Sources/            # SwiftUI + libghostty 集成
│       │   ├── App/            # RoostApp, RootView, TabBar
│       │   ├── Launcher/       # LauncherSheet, EmptyStateView
│       │   ├── Project/        # Sidebar, IDEOpener, TerminalOpener
│       │   ├── Terminal/       # GhosttyRuntime, TerminalNSView (IME + keyboard)
│       │   └── Bridge/         # RoostBridge facade + GhosttyInfo
│       ├── Assets.xcassets/    # AgentIcons (Claude/Codex SVG, simpleicons CC0)
│       ├── Resources/          # bundled xterm-ghostty terminfo
│       └── project.yml         # XcodeGen
├── pocs/                       # 已冻结的 walking-skeleton POCs
│   ├── libghostty-hello/
│   └── swift-bridge-hello/
├── vendor/                     # gitignored: GhosttyKit.xcframework
└── design.md                   # 设计文档 (含 §10 配置系统、§5a daemon 生命周期)
```

## Build

```bash
# one-time: fetch libghostty
./pocs/libghostty-hello/scripts/fetch-prebuilt-xcframework.sh

# one-time: install XcodeGen
brew install xcodegen

# build + run
cd apps/Roost
./scripts/build-rust.sh      # first run only; Xcode picks this up later
xcodegen generate
open Roost.xcodeproj          # ⌘R
```

## 主要快捷键

| 键 | 动作 |
|---|---|
| **⌘T** | 在当前 bucket 新开 terminal (shell) |
| **⌃1** | 新 Claude Code session |
| **⌃2** | 新 Codex session |
| **⌘1-9** | 切换到第 N 个 tab |
| **⌘[ / ⌘]** | 相对前/后一个 tab |
| **⌘W** | 关闭当前 tab |
| **⌘V / ⌘C** | 终端粘贴 / 复制选区 |
| **⌘+ / ⌘- / ⌘0** | 字号放大 / 缩小 / 重置 |

## License

暂未选择。先 pre-alpha 开发，发第一版前决定（倾向 MIT 或 Apache-2.0）。
