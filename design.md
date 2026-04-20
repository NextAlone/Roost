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
┌────────────────────────────────────────────────────┐
│  Roost.app (SwiftUI + AppKit client)               │
│  ┌──────────┬──────────────────────────────────┐  │
│  │ Sidebar  │ Tabs                              │  │
│  │ Proj A   │ ┌────libghostty surface─────────┐ │  │
│  │  └ ws-a  │ │  child: roost-attach <sid>    │ │  │
│  │  └ ws-b● │ │   ↕ unix socket (fd-relay)    │ │  │
│  │ Proj B   │ └───────────────────────────────┘ │  │
│  └──────────┴──────────────────────────────────┘  │
│       ▲                                            │
│       │ RPC (Unix socket; JSON over newline frames)│
│       ▼                                            │
└────────────────────────────────────────────────────┘
┌────────────────────────────────────────────────────┐
│  roost-hostd (Rust daemon, outlives app)           │
│  ├── rpc/         JSON-RPC / tarpc over UDS        │
│  ├── pty/         portable-pty + tokio (owns fd)   │
│  ├── session/     agent 进程 + PTY master 生命周期 │
│  ├── vcs/         jj CLI wrapper                   │
│  ├── workspace/   project → ws → session 模型      │
│  ├── agent/       agent 配置 / 启动参数            │
│  └── store/       SQLite (sqlx)                    │
│  Writes ~/Library/Application Support/roost/       │
│   hostd/manifest.json = {pid, socket, token, ver} │
└────────────────────────────────────────────────────┘
```

App 是 client；agent 的 PTY master fd **始终**在 `roost-hostd` 内存里。libghostty surface 的 child 是一个小 relay binary `roost-attach`，它通过 Unix socket 把自己的 stdio 桥到 hostd 里对应 session 的 PTY byte stream。

### 关键选择

| 决定 | 选择 | 理由 |
|---|---|---|
| 终端渲染 | Swift 侧 libghostty | GPU + VT 兼容性最好 |
| Agent 进程托管 | **独立 daemon `roost-hostd`** | App 崩 / ⌘Q 不丢 agent；天然支持 M9 `roost` CLI 共用 server；为 M13 远程 hostd 铺路（参考 Superset `HOST_SERVICE_ARCHITECTURE.md`）|
| PTY 归属 | hostd 持 master fd，`roost-attach` relay 穿透 | libghostty 不暴露"外部 fd 接入"API，relay 是最稳的桥；agent 死亡不连带 app |
| 状态真相源 | hostd 内存（活 session）+ SQLite（metadata/历史）| app 只作 client；CLI 走同一协议 |
| App ↔ hostd 协议 | 本地 Unix domain socket，JSON-RPC（tarpc/jsonrpsee 二选）| 本地即可，不走 HTTP；fd-passing 能力后续可加（SCM_RIGHTS） |
| FFI | swift-bridge 保留为 RPC 客户端 thin SDK | 过渡期复用已有 surface；将来可整体砍掉 |
| VCS | jj CLI-only | jj-lib 上游标 unstable |
| 异步 | hostd 用 tokio multi-thread (worker=2) | §4a 详述 |

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
    pid: Option<u32>,         // agent 进程 pid（在 hostd 里记录）
    state: SessionState,      // Idle / Running / WaitingInput / Exited
    last_notification: Option<NotificationEvent>,
    created_at: DateTime,
    started_at: Option<DateTime>,
    exited_at: Option<DateTime>,
    exit_code: Option<i32>,
}
```

运行时状态（PTY master fd、ring buffer、输入 sender）只在 `roost-hostd` 内存，**不进 SQLite**。App 侧数据模型是 hostd RPC 返回值的纯镜像。

SQLite 库文件：`~/Library/Application Support/roost/roost.db`，**由 hostd 独占访问**。sqlx 使用 offline 模式；`cargo sqlx prepare` 在 CI 和 pre-commit 里强制执行，sqlx metadata 进版本库。

## 4. App ↔ hostd RPC 契约

### 传输

- Unix domain socket，路径 `~/Library/Application Support/roost/hostd/hostd.sock`（由 manifest 记录）。
- 协议：JSON-RPC 2.0（`\n` 分隔帧）；二进制字节流（PTY 数据）走独立的 byte-stream 子连接，见 §5a。
- 鉴权：manifest 里记一串 32 字节随机 `auth_token`；客户端首帧 `hello {token}`，错就断开。
- 版本：`hello` 带 `client_version`；hostd 拒绝 major 不匹配，minor 不匹配打警告。

### RPC surface（现阶段预估，实际以 crate 源为准）

```rust
// 领域命令
rpc list_projects() -> Vec<ProjectDto>;
rpc add_project(path: String) -> Result<ProjectDto, RpcError>;
rpc list_workspaces(project_id: String) -> Vec<WorkspaceDto>;
rpc create_workspace(project_id, name, bookmark: Option<String>) -> Result<WorkspaceDto, RpcError>;
rpc remove_workspace(ws_id: String) -> Result<(), RpcError>;

// session 生命周期
rpc list_sessions(ws_id: String) -> Vec<SessionDto>;
rpc create_session(ws_id, agent: String) -> Result<SessionDto, RpcError>;
rpc kill_session(session_id: String, signal: Signal) -> Result<(), RpcError>;
rpc resize_session(session_id, rows: u16, cols: u16) -> Result<(), RpcError>;

// daemon 管理
rpc host_info() -> HostInfo;          // version, uptime, active sessions
rpc shutdown(mode: ShutdownMode);     // release (ignore, app exit) | stop (SIGTERM all)

// 事件（server push；客户端 subscribe 后走同一 socket 的事件通道）
event session_state { session_id, state }
event session_osc   { session_id, seq, payload }   // OSC 9/99/777 原样
event session_exited { session_id, code }
```

App 不再通过 FFI "准备 spec 然后自己 spawn"；`create_session` 在 hostd 侧直接 spawn agent 并占 PTY master，返回 `session_id`。App 收到 `session_id` 后让 libghostty spawn `roost-attach <session_id>` 作为 surface 的 child，relay 把 PTY byte stream 透回 libghostty。

### swift-bridge 的角色（过渡期）

`roost-bridge` crate 变成 hostd 的 Rust 客户端 SDK：内部维护 socket 连接 + JSON-RPC 调度，把 RPC 调用封装成同步 `Result<T, String>` 给 Swift。App 现有 `RoostBridge` facade 接口不动，实现换成调 SDK。M9 CLI 也用同一个 SDK，绕开 swift-bridge 直接 Rust client。将来 Swift 侧若用 Network.framework 原生写 JSON-RPC 客户端，swift-bridge 可整体砍。

## 4a. hostd 运行时契约

**决定：`roost-hostd` 是单可执行长驻进程，内部 `tokio::runtime::Builder::new_multi_thread().worker_threads(2)`，所有 RPC 和 PTY I/O 都在这个 runtime 里。**

约束：
- 所有可变状态（`HashMap<SessionId, SessionState>`、sqlx pool）用 `tokio::sync::Mutex` / `Arc<RwLock<_>>` 包裹；单 runtime 足够，不分 worker。
- RPC handler 必须幂等：client 重连（adopt / network blip）会重试；`kill_session` / `resize_session` 多次无副作用。
- panic 边界：任何 RPC handler `catch_unwind` → `RpcError::InternalPanic(msg)`；一个 session 的 PTY read loop panic 不许炸整个 daemon。
- PTY 读线程：每个 session 起一个 `tokio::task` 读 PTY master，输出 fan-out 到 (a) 向 attach relay 的 socket 写，(b) ring buffer（按 §5a "粘滞 scrollback"），(c) OSC 解析器。
- SQLite：单写多读，所有写都走同一个 `SqlitePool`，没有跨进程写竞争（除非出现 orphan hostd，见 §5a quit 模式）。

## 5a. `roost-hostd` daemon 生命周期

**决定：hostd 是独立长驻进程，app 是 client；app 崩 / ⌘Q 时 hostd 继续跑，agent 不死。参考 Superset `HOST_SERVICE_LIFECYCLE.md`，但职责更窄（单用户、无远程 auth）。**

### 进程结构

```
roost-hostd (pid N)
├── RPC listener (UDS hostd.sock)
├── session-1
│   ├── agent child (pid, group leader)
│   └── pty read task ──► ring buffer + attached client
├── session-2
│   └── ...
└── SQLite write task
```

`roost-attach <sid>`（app-spawned）：
```
roost-attach
├── connect hostd.sock, auth, subscribe to session byte stream
├── stdin  → socket  → hostd.pty_master.write
├── socket → stdout  → libghostty
└── SIGWINCH → RPC resize_session
```

libghostty 看到一个持续活着的 child（relay），不知道背后是 daemon。App 崩时 libghostty 和 relay 一起死，hostd 那边把 session 标为 "detached"，PTY 仍持有，下次 re-attach 继续。

### Manifest

`~/Library/Application Support/roost/hostd/manifest.json`，由 hostd 启动时写，0600：

```json
{
  "pid": 12345,
  "socket": "~/Library/Application Support/roost/hostd/hostd.sock",
  "auth_token": "base64...",
  "version": "0.1.0",
  "started_at": "2026-04-21T..."
}
```

### Quit 模式（三选一）

| 模式 | 触发 | 行为 |
|---|---|---|
| **release**（默认） | 用户 ⌘Q 时 hostd 里还有活 session | app 断开 RPC、退出；hostd 继续跑；manifest 留盘；agent 继续跑 |
| **stop** | 菜单 "Quit & stop all agents"，或 CLI `roost stop` | app 发 `shutdown(stop)` → hostd SIGTERM 所有 session（5s grace）→ SIGKILL → 删 manifest → 退出 |
| **implicit** | ⌘Q，**无**活 session | 直接 `shutdown(stop)` 等价 |

macOS 下不加 tray；代替方案：dock icon 菜单"Resume hostd session" + 主窗关后 app 可保活不退（如用户偏好）。release 模式下再次启动 app 会直接 adopt 已存在的 hostd。

### App 启动 / Adopt 流程

1. 读 manifest（若不存在 → 直接 spawn hostd）
2. connect socket，发 `hello {auth_token, client_version}`
3. RPC `host_info()` 超时 2s → 健康
4. **健康**：`list_sessions()`，用返回值恢复 Tab / Sidebar
5. **不健康**（socket refuse / timeout / version mismatch major）：
   - 若 `pid` 还活着（`kill(pid, 0) == 0`）→ 视为卡死，弹 "Stale hostd? [Kill & restart / Keep & inspect / Cancel]"
   - 否则删 manifest，spawn 新 hostd
6. Hostd 退出（release quit 后被用户手动 `kill`，或 OOM）：下次 adopt 失败走 spawn；已存的 SQLite 元数据 + workspace metadata 足以重建 sidebar，只是所有 session 都会显示 `Exited (hostd lost)`。

### Orphan 识别

- SQLite 里 `state=Running` 但 hostd 内存里没 → 启动时 reconcile，标 `Exited`（exit_code=`None` 表示丢失）
- hostd 内存里有但 SQLite 没的（开发时升级 schema 导致）→ 写回 DB，state=`Running`

### Hostd 崩溃的下限

hostd 崩 → 所有 PTY master fd 关闭 → agent 进程收 SIGHUP → agent 死。这是可接受下限（和 Superset 同等）。缓解靠 Sentry-ish panic 上报 + Rust `#[panic_handler]` 打 minidump。**不**试图用 double-fork / setsid 让 agent 活过 hostd 崩（session 和 agent 间的 IPC 语义会丢）。

### Hostd 二进制的分发

- Debug：`cargo build -p roost-hostd` 产物在 `target/debug/roost-hostd`，app 通过 `Bundle.main` + `../../../target/debug/` 兜底路径查找。
- Release：`roost-hostd` 二进制打进 `Roost.app/Contents/MacOS/roost-hostd`，`spawn` 时优先用 bundle 内版本；CLI `roost` 则从 `PATH` 找 `roost-hostd`（brew / `cargo install`）。
- 版本：hostd 和 app 的 `CARGO_PKG_VERSION` 必须精确对齐；major 漂移时 app 拒绝 adopt 并强制 stop + respawn。

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
- M2 踩坑（jj / swift-bridge / PATH）：
  - `jj workspace list` template context 是 `WorkspaceRef`，只有 `.name()` 和 `.target() -> Commit`；`.path()` 不存在，需要按 `<repo>/.worktrees/<name>` 约定反推。
  - jj template 字符串只识 `\n \t \r \\ \" \0`，`\u{1f}` 会被 parser 拒；用 `\0` 作字段分隔符。
  - swift-bridge 0.1.59 对 `Vec<SharedStruct>`（WorkspaceEntry 等）codegen 输出无 `Vectorizable` conformance；`Result<T, String>` + `&str` 参数组合还会让 `toRustStr` 闭包带 `throws` 但 closure 签名不含 `rethrows`，编译失败。workaround：`Vec<SharedStruct>` 改为「\n 分隔 + \u{1f} 字段」flat string，`Result` 返回函数把 `&str` 参数改成 owned `String`。
  - GUI 启动的 app 继承 launchd 的瘦 PATH；Rust 里 spawn `jj` 要按候选目录（`~/.local/bin`、`/etc/profiles/per-user/$USER/bin` 等）解析绝对路径。agent 子进程同理：走 `$SHELL -l -c <agent>` 而不是直接 exec，拿用户 `.zprofile/.bash_profile` 里设置的 PATH。
  - `close_surface_cb(void*, bool)` 的 `userdata` 就是 `surface_config.userdata`（我们塞进去的 NSView 指针），由此可反查出 session UUID 去关 tab。

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
| M2 | jj workspace 创建 / 删除 + bookmark 约定（**已通过**，2026-04-20）| M1 |
| M3 | Project 侧边栏（目录分组）（**已通过**，2026-04-20）| M2 |
| M4 | OSC 9/99/777 → 通知 ring（**已通过**，2026-04-20）| M1 |
| M5 | setup/teardown 脚本（`.roost/config.json`）（**已通过**，2026-04-21）| M2 |
| **M6** | `roost-hostd` daemon 雏形：拆出独立进程 + Unix socket JSON-RPC + swift-bridge 改 thin client + SQLite 迁入 hostd | M4 |
| **M7** | PTY 归 hostd + `roost-attach` relay binary + libghostty spawn relay（替换直接 spawn agent） | M6 |
| **M8** | Manifest pidfile + adopt / spawn 决策 + release/stop quit 模式 + session 恢复 UI | M7 |
| **M9** | `roost` CLI（socket client 直连 hostd，复用 SDK）| M6 |
| **M10** | IDE 跳转（`open -a`）| M3 |
| **M11** | diff viewer | M2 |
| **M12** | git worktree 支持（引入 `trait Vcs`）| M2 |
| **M13** | 远程 hostd（SSH 隧道 UDS；hostd 参数化工作根目录）| M8 |
| **M14** | 主题 & 字体设置 UI | M6 |
| **M15** | Agent 预设系统（`.roost/config.json` 扩展 agents 段 + 全局 presets）| M5 + M6 |
| **M16** | 通知偏好（声音 / banner / per-agent 开关）| M4 + M6 |
| **M17** | 键绑定自定义 | M6 |

M6-M8 是 daemon 迁移的**三步串行**，不要并行；M5 / M10 / M11 / M12 与它们正交，可穿插。M14-M17 都独立可做，但**依赖 M6 hostd**——配置真相源必须落 hostd，否则 app 和 CLI 看到不同的值。

### M5：`.roost/config.json` setup / teardown（**已通过**，2026-04-21）

**Schema**（均可选，缺省视为空数组；`.roost/config.json` 不存在等同于空配置）：

```json
{ "setup":    ["pnpm install", "direnv allow"],
  "teardown": ["rm -rf node_modules"] }
```

**语义**：
- `setup`：`jj workspace add` 成功后**在新 workspace 路径**顺序执行。
- `teardown`：调用方在 `jj workspace forget` **之前**顺序执行（当前没有 UI 触发点，`RootView.deleteWorkspaceFlow` 为将来接入准备）。
- 每条命令跑在 `$SHELL -lc <cmd>` 下，cwd = workspace 路径，继承 agent 解析用的登录 shell PATH（和 `roost_prepare_session` 逻辑一致）。
- 失败**不阻塞** workspace 操作：任一步非零 exit 仅作为侧边栏 ⚠ warning（`ProjectSidebar` `hookWarning`），workspace 创建 / 删除继续。
- 进度复用 M4 notification ring：FFI 返回每步的 `(phase, idx, total, exit_code, cmd, stderr_tail)`，Swift 逐条 post `.roostHookProgress`（`RoostNotificationKey.projectID / phase / index / total / success / title / body`），`RootView` 消费并记录最后失败。
- 配置 JSON 格式错误 / 读错误 → FFI 返回 `Result::Err`，Swift 把错误文本当作 hook 失败 post 一次 warning。

**实现位置**：
- `crates/roost-bridge/src/hooks.rs`（`load_config` / `run_setup` / `run_teardown` / `serialize`）。
- `crates/roost-bridge/src/lib.rs` 暴露 `roost_run_setup_hooks` / `roost_run_teardown_hooks`（Result<String, String>，内部用 `\u{1f}` 分隔字段、`\n` 分隔行）。
- `apps/Roost/Sources/Bridge/Bridge.swift` 新增 `HookStepResult` + `RoostBridge.runSetupHooks` / `runTeardownHooks`。
- `apps/Roost/Sources/App/RootView.swift` `runHooksAsync(phase:projectID:projectRoot:workspaceDir:)` dispatch off main；`deleteWorkspaceFlow(...)` 作为将来 delete UI 的 orchestrator。

### M6：`roost-hostd` daemon 雏形（架构重构）

**目标**：把 `roost-bridge` crate 内部拆成 `roost-hostd` 可执行 + `roost-bridge` 瘦 SDK，但**不动** PTY 路径（M7 再做）。app 行为肉眼无变化，只是后台多一个进程。

步骤：
1. 新 crate `roost-hostd`（bin），搬 jj / workspace / agent / store 模块进来。暂时**不处理 session PTY**，`prepare_session` 仍返回 argv 让 Swift 自己 spawn。
2. hostd 起 Unix socket listener，JSON-RPC handler 封装现有领域命令（list_workspaces / create_workspace / ...）。
3. 新 crate `roost-client`（lib），暴露同步 Rust API，内部连 hostd.sock。
4. `roost-bridge` 改成"swift-bridge facade → roost-client"，对 Swift 的 API 不变。
5. SQLite 文件迁入 hostd，app 不再持有 `sqlx::Pool`；`target/...` 下的 DB 迁入 `~/Library/Application Support/roost/roost.db`。
6. Xcode pre-build：`build-rust.sh` 除了 `libroost_bridge.a`，再 build `roost-hostd` 可执行并拷进 `Roost.app/Contents/MacOS/roost-hostd`。
7. app 启动：RoostBridge init 时先 `ensure_hostd()` = 检查 manifest → adopt 或 spawn。

出站：app 能正常 list/create workspace、open session，只不过底下走了 socket 一跳。不含 adopt / quit 模式（M8）。

### M7：PTY 迁入 hostd + `roost-attach` relay

**目标**：agent 的 PTY master 从 libghostty child 变成 hostd 内 task；libghostty 的 child 改为 `roost-attach <sid>`。

步骤：
1. hostd 加 `create_session` RPC：`portable-pty` 开 PTY，`tokio::process` spawn agent；pty master 入 `HashMap<SessionId, PtyState>`；起读任务 → ring buffer + subscribers。
2. 新 crate `roost-attach`（bin）：connect hostd.sock → RPC `attach_session(sid)` → 进入 byte-stream 子协议（简化 "MUX one conn per direction"：相同 socket 顺序发 `{type:"attach", sid}`，后续切换成裸字节直到断开）；自己的 stdin 喂给 socket，socket 数据写 stdout；捕获 SIGWINCH → RPC `resize_session`。
3. app 改：`create_session` 拿到 `session_id` 后，`surface_config.command = "/path/to/roost-attach"`，`command_argv = [session_id]`，`surface_config.env` 加 `ROOST_HOSTD_SOCKET=...`。
4. 断开语义：roost-attach 退出（libghostty close surface、关窗、app 崩）→ hostd 把 session 标 `detached` 不杀；下次 attach 继续。
5. OSC 穿透：hostd 的 PTY read task 边喂 attach 边解析 OSC 9/99/777，直接触发 `session_osc` 事件（避免 libghostty 的 OSC handler 线程里再解一遍；但保留 libghostty 解析作 fallback）。

出站：agent 进程活在 hostd，app 重启（直接 kill Roost.app）不打断 agent；但"关了再开"还没 UI 恢复（M8）。

### M8：Adopt + quit 模式 + session 恢复

**目标**：app 重启能把已有 session 补回 Tab；⌘Q 对 agent 友好。

步骤：
1. hostd 启动时写 manifest 0600。退出时（包括 panic）best-effort 删 manifest。
2. app 启动先 `discover_and_adopt()`：读 manifest → connect → `host_info` + version check → 通过则 `list_sessions` 驱动 UI。
3. 每个恢复的 session 直接 `spawn roost-attach <sid>` 塞进 libghostty surface；ring buffer 回放最后 N KB 让用户看到上下文。
4. Quit 流：监听 `NSApplicationWillTerminate`，按 "活 session 数 > 0 && 用户未明确 stop" → RPC `shutdown(release)` 并 exit；"Quit & stop all agents" 菜单项 → `shutdown(stop)` 并 5s 超时。
5. 孤儿 hostd 处理：见 §5a "App 启动 / Adopt 流程"。
6. UI：侧边栏活 session 数徽章；hostd status 行（pid、uptime）在 About 窗口；menu 项 "Resume from hostd" / "Quit & stop all agents"。

出站：从启动 → 创建 session → ⌘Q → 重开 → session 继续运行，UI 自然恢复。

## 7. 仓库结构

```
Roost/                          # 工作目录
├── design.md                   # 本文档
├── README.md
├── Cargo.toml                  # workspace
├── crates/
│   ├── roost-core/             # 领域模型 + store + vcs + agent（M6 从 bridge 搬出）
│   ├── roost-hostd/            # bin：长驻 daemon，持 PTY / SQLite / RPC listener（M6+）
│   ├── roost-client/           # lib：同步 RPC client SDK（Rust）
│   ├── roost-bridge/           # swift-bridge facade，内部用 roost-client
│   ├── roost-attach/           # bin：libghostty child；socket↔stdio relay（M7）
│   └── roost-cli/              # bin：`roost` 命令行，也用 roost-client（M9）
├── apps/
│   └── Roost/                  # SwiftUI app（XcodeGen）
├── pocs/                       # 已冻结的 walking-skeleton POC
│   ├── libghostty-hello/
│   └── swift-bridge-hello/
├── vendor/                     # gitignored: GhosttyKit.xcframework
└── .roost/                     # 项目级配置（M5）
```

## 8. 风险

| 风险 | 影响 | 缓解 |
|---|---|---|
| libghostty C API 漂移 | 高 | M-1 已验证；CI 每天跑一次编译检查；锁定 Ghostty commit hash |
| libghostty 不接外部 PTY fd（必须走 relay）| 高 | M7 `roost-attach` relay 方案；若将来 libghostty 开 `ghostty_surface_attach_fd` API 可砍掉 relay |
| swift-bridge 对 `Result` / `Option` / `Vec<Struct>` 支持 | 中 | 已踩坑（M0.1）；M6 后 swift-bridge 只做 thin facade，复杂类型在 roost-client Rust 侧处理 |
| hostd ↔ app 版本漂移 | 中 | `hello` 帧 major 不匹配拒 adopt；menu 提示 "Stop & upgrade hostd" |
| Orphan hostd 卡死（无响应但 pid 活）| 中 | adopt 时 2s ping 超时 → 弹 "kill & restart" 交互；`roost` CLI 提供 `roost hostd doctor` |
| hostd 崩溃连带 agent 死 | 中 | 接受为下限；上报 panic + sentry；SQLite 记 `Exited(hostd lost)` |
| RPC 协议破坏向下兼容 | 中 | `version` 字段 + additive field 约定；breaking change bump major，走 stop+respawn 迁移 |
| sqlx offline 缓存漏更新 | 中 | `cargo sqlx prepare` 进 pre-commit + CI gate |
| jj CLI 版本漂移 | 中 | hostd 启动校验 `jj --version ≥ 0.20`；低版本拒启动 |
| agent 崩溃 / zombie | 中 | hostd 拥有 pid，`session_exited` 事件幂等；UI 显示 exit code |
| Rust panic 跨 FFI / RPC 边界 | 低 | FFI 入口和 RPC handler 都 `catch_unwind` |
| Socket 权限 / 多用户共享机 | 低 | socket 路径在用户 Library 目录，0700；不设多 host；暂无跨用户支持 |

## 9. 下一步（一次迭代，从当前分支出发）

当前已跑到 M4（OSC 通知 ring）。daemon 迁移是下一阶段的架构重构，分三步：

1. **M6**：拆 `roost-hostd` + `roost-client` + socket RPC；app 行为不变，只是多一跳。重点验证：adopt / spawn 决策在**无活 session**的平凡路径走通，JSON-RPC 协议选型（jsonrpsee vs tarpc vs 手写 newline-JSON）定案。
2. **M7**：PTY 迁入 hostd + `roost-attach` relay；端到端 agent 启动改为 `hostd create_session` + `libghostty spawn roost-attach`。重点验证：resize / Ctrl+C / OSC passthrough / agent 自然退出四条路径。
3. **M8**：manifest + quit 模式 + 重启 session 恢复。重点验证：app kill -9 → restart 能 adopt，agent 不断。

M5 (`.roost/config.json` setup/teardown) 是纯粹项目配置，和 daemon 路径正交，随时插入。**推荐**：M5 和 M6 并行（不同 crate，无冲突），M7 / M8 串行跟在 M6 后。

## 10. 配置系统

三层由粗到细，每层覆盖下一层。hostd 是唯一真相源（M6 后），app 和 CLI 通过 RPC `get_config` / `set_config` 读写。

| 层 | 物理位置 | 范围 | 生命周期 | 主要字段 |
|---|---|---|---|---|
| **global** | `~/Library/Application Support/roost/config.json` | 所有 project + scratch | 跨重启 | 字体 family/size, 主题, 键绑定, 通知偏好, agent 全局预设 |
| **per-project** | `<project>/.roost/config.json` | 该 project 下所有 session | 跟 repo 走 (建议 commit) | setup/teardown (M5), agent 覆盖, IDE 首选, workspace 模板 |
| **per-session** | hostd 内存 | 单 session | runtime | 当前字号（⌘±）、滚屏偏移、视图状态 |

### 合并优先级

读取顺序：global → per-project override → per-session transient。如 global 设 font_size=13、project override=14、session 内用户按 ⌘+ 升到 15，显示 15；关掉 session 重开回 14；换 project 回 13。

### Schema 草案 (global)

```jsonc
{
  "font": {
    "family": "SF Mono",
    "size": 13,
    "variant": "regular"        // regular | nerd-font | custom-bundle-id
  },
  "theme": {
    "mode": "system",           // system | light | dark
    "palette": "default"        // default | solarized-dark | ... | custom JSON
  },
  "notifications": {
    "osc9": true,
    "osc99": true,
    "osc777": true,
    "sound": "funk",            // macOS system sound name | "none"
    "banner": true,             // NSUserNotification / UNUserNotification
    "per_agent": {
      "claude": { "sound": "glass", "banner": true },
      "shell":  { "sound": "none",  "banner": false }
    }
  },
  "keybindings": {              // flat override of host-level shortcuts
    "quick_terminal": "cmd+t",
    "new_claude":     "ctrl+1",
    "new_codex":      "ctrl+2",
    "close_tab":      "cmd+w"
  },
  "agents": {                    // named presets; LauncherView picker + ⌃N maps
    "claude":    { "argv": ["claude"] },
    "codex":     { "argv": ["codex"] },
    "shell":     { "argv": ["$SHELL", "-l"] },
    "claude-4":  { "argv": ["claude", "--model", "claude-opus-4-7"] }
  }
}
```

### Schema 草案 (per-project) — M5 基础上扩展

```jsonc
{
  "setup":    ["pnpm install"],     // M5 (稳定)
  "teardown": ["rm -rf node_modules"],
  "agents": {                        // M15: project-local agent override
    "claude": {
      "argv": ["claude", "--model", "sonnet-4-6"],
      "env":  { "ANTHROPIC_API_BASE": "https://..." }
    }
  },
  "ide": "cursor"                    // 默认 "Open in IDE" 跳 Cursor
}
```

### hostd 集成

- M6 加 `get_config(path_query: String) -> Value` / `set_config(path: String, value: Value)` RPC，JSON-Pointer 风格 path。
- 写入时 hostd 原子替换文件 + broadcast `config_changed` 事件给所有 client。
- `per-session transient` 不落盘，保留在 `SessionState` 结构里；app 崩溃 / hostd 崩溃时丢失是可接受的。
- 配置校验在 hostd 侧（schema + 类型），错误字段**单点回退**到默认值，不整体拒绝。

### 何时实施

- **M14**: 先把 global font / theme UI 搭起来，驱动 `config.font` / `config.theme` 字段。
- **M15**: agents 预设系统 — 去除 `LauncherView.presets = ["claude", "codex", "shell"]` 硬编码，改从 config 读。per-project override 复用 M5 文件。
- **M16**: 通知偏好 UI + per-agent 开关。
- **M17**: 键绑定自定义。各快捷键先声明成 `config.keybindings.*`，UI 做 recorder 允许重绑。

四者都依赖 M6（hostd 作真相源）。M5 的 `.roost/config.json` reader 在 M15 扩展 schema 前保持向后兼容（忽略未知字段）。

