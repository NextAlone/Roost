# Roost — 设计文档

## 0. 命名与定位

- 项目名：**Roost**（"栖所"，agent 在此驻留）。
- 仓库：`NextAlone/Roost`，工作目录暂沿用 `Pane/`。
- 二进制/crate/配置目录统一用小写 `roost` / `roost-core` / `.roost/`。
- 一句话定位：**macOS 原生、jj 一等公民的多 agent 终端编排器**。
- 不是：不是 Electron 跨平台工具（那是 `Dcouple-Inc/Pane`），不是 git-only（主流已有），不是纯终端原语（那是 `manaflow-ai/cmux`）。
- 差异化：对 `cmux` 增加"编排 + 目录分组"，对 `Dcouple/Pane` 换成"macOS 原生 + jj 原生"，对 `superset` 换成"非 Electron + jj"。

## 1. 目标

并行编排多个 CLI 编码 agent（Claude Code / Codex / Gemini CLI / Cursor Agent 等），每个 agent 跑在独立的 jj workspace 里，macOS 原生 GUI，低内存、快启动。

### 非目标（MVP 阶段）

- 跨平台：仅 macOS。
- git worktree：仅 jj workspace。
- 内置浏览器 / SSH / 远程执行：后续。
- diff viewer / 深度 IDE 集成：后续，先靠 `open -a` 握手。
- 多人协作 / 云同步：不在路线内。

## 2. 架构

```
┌──────────────────────────────────────────────────┐
│  SwiftUI + AppKit (macOS)                        │
│  ┌─────────────┬──────────────────────────────┐ │
│  │ Sidebar     │  Main area                    │ │
│  │ Project A   │  [ws-foo][ws-bar][+]          │ │
│  │  └ ws-foo   │  ┌──────────────────────────┐ │ │
│  │  └ ws-bar ● │  │  libghostty surface      │ │ │
│  │ Project B   │  │  (PTY attached to agent) │ │ │
│  └─────────────┴──────────────────────────────┘ │
│       ▲                                          │
│       │ FFI (swift-bridge)                       │
│       ▼                                          │
└──────────────────────────────────────────────────┘
┌──────────────────────────────────────────────────┐
│  Rust core (staticlib)                           │
│  ├── vcs/          jj CLI wrapper                │
│  ├── workspace/    project → ws → session 模型   │
│  ├── agent/        agent 配置 / 启动参数         │
│  ├── store/        SQLite (sqlx)                 │
│  ├── ipc/          socket API for `roost` CLI    │
│  └── bridge/       swift-bridge 生成的 Swift API │
└──────────────────────────────────────────────────┘
```

### 关键选择

| 决定 | 选择 | 理由 |
|---|---|---|
| 终端渲染 | Swift 侧 libghostty | GPU + VT 兼容性最好 |
| PTY 归属 | Swift 独占 fd | Rust 不碰 I/O 热路径 |
| 状态真相源 | Rust + SQLite | 持久化，CLI / GUI 共享 |
| FFI | `swift-bridge` | 单 Swift 客户端场景更贴切 |
| VCS | jj CLI-only | jj-lib 上游标 unstable |
| 异步 | tokio，单 `current_thread` 运行时 | §4a 详述 |

## 3. 数据模型

```rust
struct Project {
    id: ProjectId,
    name: String,
    root_path: PathBuf,       // 主仓库目录
    vcs: VcsKind,             // MVP: 只有 Jj
    created_at: DateTime,
}

struct Workspace {
    id: WorkspaceId,
    project_id: ProjectId,
    name: String,             // jj workspace name
    path: PathBuf,            // jj workspace 的实际路径
    bookmark: Option<String>, // 见 §5 jj 语义
    status: WorkspaceStatus,  // Active / Archived
    created_at: DateTime,
}

struct AgentSession {
    id: SessionId,
    workspace_id: WorkspaceId,
    agent_kind: AgentKind,    // ClaudeCode / Codex / Gemini / Cursor / Shell
    command: Vec<String>,     // argv
    env: HashMap<String, String>,
    pid: Option<u32>,
    state: SessionState,      // Idle / Running / WaitingInput / Exited
    last_notification: Option<NotificationEvent>,
    created_at: DateTime,
}
```

SQLite 库文件：`~/Library/Application Support/roost/roost.db`。sqlx 使用 offline 模式；`cargo sqlx prepare` 在 CI 和 pre-commit 里强制执行，sqlx metadata 进版本库。

## 4. FFI 契约（swift-bridge）

按命令（verb）设计，对象永远存在 Rust 侧：

```rust
// bridge/src/lib.rs
#[swift_bridge::bridge]
mod ffi {
    extern "Rust" {
        type RoostCore;
        fn init(db_path: String) -> RoostCore;

        fn list_projects(&self) -> Vec<ProjectDto>;
        fn add_project(&self, path: String) -> Result<ProjectDto, String>;
        fn list_workspaces(&self, project_id: String) -> Vec<WorkspaceDto>;
        fn create_workspace(&self, project_id: String, name: String, bookmark: Option<String>) -> Result<WorkspaceDto, String>;
        fn remove_workspace(&self, ws_id: String) -> Result<(), String>;

        fn list_sessions(&self, ws_id: String) -> Vec<SessionDto>;
        fn prepare_session(&self, ws_id: String, agent: String) -> Result<SessionSpec, String>;

        fn report_session_started(&self, session_id: String, pid: u32);
        fn report_session_state(&self, session_id: String, state: String);
        fn report_osc_event(&self, session_id: String, seq: u32, payload: String);
        fn report_session_exited(&self, session_id: String, code: i32);
    }
}
```

`prepare_session` 返回 spawn spec（argv / cwd / env），Swift 侧执行 `posix_spawn` + PTY + libghostty；Swift 解析出的 OSC 9/99/777 事件通过 `report_osc_event` 告知 Rust 更新状态。Rust 从不读 PTY。

## 4a. FFI 线程与 runtime 契约

**决定：Rust 侧的所有 FFI 方法是同步阻塞入口，内部用 `tokio::runtime::Runtime::block_on` 驱动异步。**

理由：
- Swift 调用者只有一个（本应用），不需要 swift-bridge 的 `Future` 跨线程回传复杂度。
- Rust 侧大部分动作（jj CLI exec、sqlx 查询）耗时在几十毫秒级，阻塞主线程可接受；真正长耗操作（创建 workspace、`jj log`）Swift 侧应丢到 `Task.detached` 调用。
- SQLite 本身不支持多 writer 并发，单 runtime 模型反而简化。

约束：
- `RoostCore` 内部持有 `Arc<Runtime>`，方法 `&self`，对 Swift 天然 `Sendable`（swift-bridge 按值引用传递）。
- Rust 侧 runtime 使用 `tokio::runtime::Builder::new_multi_thread().worker_threads(2)`，够跑 jj CLI + sqlx。
- `report_session_*` 系列必须幂等：Swift 可能从多线程调用（xterm 事件线程、PTY 读线程），Rust 侧用 session_id + 序号处理乱序。
- panic 边界：所有 FFI 方法体必须包在 `std::panic::catch_unwind` 里，避免 panic 跨 FFI 未定义行为；panic 转换成 `Result::Err("internal panic: ...")`。

## 5. jj 接入

### CLI 调用（MVP 全部走 `tokio::process::Command`）

| 动作 | 命令 |
|---|---|
| 检测 repo | `jj status`（exit 0） |
| 列 workspace | `jj workspace list --no-graph` |
| 创建 workspace | `jj workspace add <path> --name <name>` |
| 删除 workspace | `jj workspace forget <name>` |
| 当前 revision | `jj log -r @ --no-graph -T '{change_id.short()} {description.first_line()}'` |
| 工作副本状态 | `jj status --color=never` |

- 版本下限：**jj ≥ 0.20**（workspace 子命令在 0.15 前语法不同）；`init` 时执行 `jj --version` 校验，低版本直接报错。
- 所有输出按行解析，失败时 stderr 原样抛给 Swift 展示。
- tag / git push / 远程等 jj 不覆盖的动作，MVP 不做。

### workspace / bookmark 语义（关键）

jj 的 workspace 共享 bookmark：两个 workspace 不能同时 check out 同一 bookmark，第二个会变成 divergent `@`。Roost 的策略：

- **一 workspace 一 bookmark**（硬约定）。`create_workspace` 强制传 `bookmark: Option<String>`：
  - `Some(name)`：在新 workspace 里执行 `jj new <name>` 然后 `jj bookmark set <workspace>-head -r @`。workspace 名与 bookmark 名**不同**，避免混淆（`ws-foo` workspace ↔ `ws-foo-head` bookmark）。
  - `None`：只 `jj new`，不设 bookmark，纯 detached 工作。适合短期探索。
- 数据模型里 `Workspace.bookmark` 记录关联 bookmark 名，删除 workspace 时同步 `jj bookmark forget`。
- 用户手动切 bookmark 导致的不一致，由后台 sync 任务检测并在侧边栏打标"⚠ divergent"。

## 6. Milestones

### M-1：libghostty 可行性 POC（**已通过**，2026-04-20）

**结论**：`GhosttyKit.xcframework` 可用。SwiftUI + libghostty + PTY + 键盘全链路跑通。架构沿此路前进。

**关键实现决定**：
- xcframework 走 `manaflow-ai/ghostty` 的 prebuilt release（tag 按 commit SHA pin，`xcframework-e36dd9d5…`）；上游 `ghostty-org/ghostty` 当前只 release VT 子集（`ghostty-vt.xcframework`），不含 render。
- xcframework 自带 `ghostty.h` + `module.modulemap`，`import GhosttyKit` 开箱即用。
- 链接必须带 `-lc++ -framework Metal -framework QuartzCore -framework IOSurface -framework UniformTypeIdentifiers -framework Carbon`。
- `embed: true` 会让 Xcode 试图 codesign 静态 archive，改 `embed: false link: true`。
- `ghostty_init(argc, argv)` 必须在任何其他 API 之前调一次，否则 `ghostty_config_new` null 崩溃。
- `ghostty_input_key_s.keycode` 填 NSEvent.keyCode（macOS 虚拟键码），**不是** `GHOSTTY_KEY_*` 枚举值。
- 箭头等功能键在 `event.characters` 里是 PUA（U+F700..U+F8FF），必须 strip 再传 `text`，否则 ghostty 不走箭头处理。
- Ctrl+<letter> 正确编码依赖三件事同时满足：(a) `text` 填"去掉 ctrl 后的字符"（`characters(byApplyingModifiers: flags - .control)`）而不是 `\u{03}`；(b) `unshifted_codepoint` = 该字符的 scalar；(c) `mods` 含 `GHOSTTY_MODS_CTRL`。缺 (b) 会导致 Ctrl+C 漏成字面 'c'。
- 跑 agent CLI（非登录 shell）时 `surface_config.wait_after_command = true`，child 退出后 ghostty 保留 surface 并在用户按 Enter 后回调 `close_surface_cb`；否则 PTY 死后键盘无反应。
- 默认 `working_directory` 用 `NSHomeDirectory()`：GUI launch 的进程 cwd 是 `/`，ghostty spawn 的 shell 会落在根目录。

**验证了的架构假设**：
- PTY：libghostty 自己 spawn 登录 shell，`surface_config.command=nil` 即可；Roost 不需要自己做 PTY（但 §4 §6 的"Swift spawn"原计划仍适用于 agent 场景，因为 agent 不是登录 shell）。
- 渲染：libghostty 自己挂 CAMetalLayer 到 NSView，Roost 只提供 NSView 指针。
- 键盘：走 `ghostty_surface_key`（带 keycode + mods + text），不分叉 `ghostty_surface_text`。

**POC 代码位置**：`pocs/libghostty-hello/`（约 180 行 Swift + 1 个 `project.yml` + 2 个 shell 脚本）。

### M0：Walking skeleton（端到端跑一个 agent）

拆成三小步，每步单一未知：

- **M0.0**（**已通过**，2026-04-20）：借 M-1 的 libghostty 路径，改 `surface_config.command` 跑 agent CLI（claude）而不是登录 shell；`wait_after_command=true` + `close_surface_cb` 处理 child 退出。POC：`pocs/libghostty-hello/`。
- **M0.1**（**已通过**，2026-04-20）：Cargo workspace + `crates/roost-bridge` 用 swift-bridge 暴露 `roost_greet` / `roost_bridge_version`。POC：`pocs/swift-bridge-hello/`。踩坑：nix 系统上 `/usr/bin/clang` 必须通过 `.cargo/config.toml` linker 覆盖，否则 `ld: library not found for -liconv`；Xcode PhaseScript 的 PATH 需手动补 `$HOME/.cargo/bin` 等。
- **M0.2**（**已通过**，2026-04-20）：合并 `pocs/libghostty-hello/` 链上 `libroost_bridge.a`，Rust 暴露 `SessionSpec{ command, working_directory, agent_kind }` + `roost_prepare_session(agent)`，Swift 用返回值启 ghostty surface。Rust 负责 agent 二进制解析（遍历 `~/.local/bin` / `/opt/homebrew/bin` / `/usr/local/bin`，落败回退 `zsh -il -c <agent>`）。SQLite 推到 M1。踩坑：cargo 会留多份 `target/.../build/<crate>-<hash>/out`，build-rust.sh 必须按内部 swift 文件的 mtime 选，不能按目录 mtime。

不做：sidebar、多 tab、多 project、jj workspace 创建、OSC 通知 UI、CLI、状态恢复。

### M1+ Backlog

| 编号 | 条目 | 依赖 |
|---|---|---|
| M1 | 多 session tab + 切换（**已通过**，2026-04-20）| M0.2 |
| M2 | jj workspace 创建 / 删除 + bookmark 约定 | M1 |
| M3 | Project 侧边栏（目录分组）| M2 |
| M4 | OSC 9/99/777 → 通知 ring | M1 |
| M5 | setup/teardown 脚本（`.roost/config.json`）| M2 |
| M6 | `roost` CLI + socket API | M3 |
| M7 | IDE 跳转（`open -a`）| M3 |
| M8 | 状态持久化 / 崩溃恢复 | M1 |
| M9 | diff viewer | M2 |
| M10 | git worktree 支持（引入 `trait Vcs`）| M2 |

## 7. 仓库结构

```
Pane/  ← 工作目录，内部项目名 Roost
├── design.md                   # 本文档
├── README.md
├── Cargo.toml                  # workspace
├── crates/
│   ├── roost-core/             # 领域模型 + store + vcs + agent
│   ├── roost-bridge/           # swift-bridge 胶水
│   └── roost-cli/              # `roost` 命令行（M6 之后）
├── apps/
│   └── Roost.xcodeproj/        # SwiftUI app
├── pocs/
│   └── libghostty-hello/       # M-1 POC
└── .roost/                     # 项目级配置（M5）
```

## 8. 风险

| 风险 | 影响 | 缓解 |
|---|---|---|
| libghostty C API 漂移 | 高 | M-1 先验证；CI 每天跑一次编译检查；锁定 Ghostty commit hash |
| swift-bridge 对 `Result` / `Option` / `Vec<Struct>` 支持 | 中 | M0.1 提前踩；若 blocker 回退 `Result` 为 `String` JSON 返回 |
| sqlx offline 缓存漏更新 | 中 | `cargo sqlx prepare` 进 pre-commit + CI gate |
| jj CLI 版本漂移 | 中 | `init` 校验 `jj --version ≥ 0.20`；低版本拒启动 |
| agent 崩溃 / zombie | 中 | Swift 侧拥有 pid，负责回收；`report_session_exited` 幂等 |
| Swift ↔ Rust panic 跨边界 | 低 | 所有 FFI 入口 `catch_unwind` |

## 9. 下一步（一次迭代）

1. **M-1 开跑**：`pocs/libghostty-hello/` 嵌 libghostty + SwiftUI，shell 可交互。
2. M-1 跑通后回本文锁 libghostty 获取方式和版本。
3. M0.1 并行起：建 Cargo workspace + `roost-core` + `roost-bridge` 空壳，swift-bridge hello world。
4. M0.2 接合。

到这里 milestone 0 完成。
