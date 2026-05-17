# herdr vs Roost 对比分析

## 一、Agent 检测架构对比

herdr 采用**三层递进式**检测，Roost 只有**单层**。

```
herdr:
  Layer 1: 进程树检测 (identity/liveness) ─── 权威来源
  Layer 2: Hook Socket API (semantic state) ─── 精确但可选
  Layer 3: 终端屏幕启发式 (fallback state) ─── 零配置兜底

Roost:
  Layer 1: Hook 脚本 + Unix Socket ─── 唯一来源
  (无进程检测，无屏幕分析)
```

## 二、进程检测（herdr 有，Roost 无）

`src/detect.rs` 从 shell PID 出发，读取前台进程组，遍历进程树识别 agent 二进制。

| 技巧 | 实现 |
|------|------|
| 泛型运行时穿透 | `sh/bash/zsh/fish/node/bun/python` 包装时，解析 cmdline 找真实 agent 名 |
| nix wrapper 处理 | `.claude-code-wrapped` → 从 cmdline 提取 `claude-code` |
| 多进程打分 | `process_priority()` — 直接匹配 > cmdline argv0 > 泛型运行时 |
| 确认窗口 | 连续 6 次探测为 None 才清空 agent 身份，防抖动 |
| 前台 shell 保护 | 当前台进程就是 shell 自身且状态为 Working 时，不清空 agent |

Roost 的 AgentKind 在创建 tab 时由用户选择，之后不再验证。无法检测：
- 用户在同一 pane 内手动启动了不同 agent
- Agent 进程已退出但 pane 还在
- Shell wrapper 包装的 agent（nix、docker 等）

## 三、屏幕启发式检测（herdr 有，Roost 无）

`src/detect.rs` 为每个 agent 实现独立的 `detect_<agent>(content: &str) -> AgentState` 函数。

### Claude Code（最复杂）

```
策略:
1. 先找 prompt box（两行 ─── 边框 + ❯）
2. 提取 prompt box 上方的输出区域
3. 在输出区域检测 Working 信号:
   - "esc to interrupt" / "ctrl+c to interrupt"
   - spinner 字符 (✽✲✳✴✵✶...) + 空格 + 单词 + …
4. 在全文检测 Blocked 信号:
   - "Do you want to proceed?" + Yes/No 选项
   - "waiting for permission"
   - "Tab to amend" / "Ctrl+E to explain"
   - 排除非阻塞的 settings 菜单（Hooks、Theme 等只读菜单返回 Idle）
5. 默认 Idle

状态稳定化: Working 状态 sticky 1.2s，防 spinner 帧间闪烁
```

### 其他 Agent 检测信号

| Agent | Working | Blocked |
|-------|---------|---------|
| Codex | `• Working (Ns • esc…` header, `esc to interrupt` | `press enter to confirm`, `allow command? [y/n]`, `enter to submit answer` |
| Gemini | `esc to cancel` | `waiting for user confirmation`, `│ Apply this change` 框线提示 |
| OpenCode | `esc to interrupt` | `△ Permission required`, `esc dismiss` + `enter confirm` + `↑↓ select` |
| Droid | braille spinner `⠋-⠏` + `esc to stop` | `EXECUTE` + `> Yes, allow` 选择 UI |
| Amp | `esc to cancel` | `waiting for approval` + `Approve` + `Allow all for this session` |
| Cursor | spinner `⬡`/`⬢` + `ing` 动词, `ctrl+c to stop` | `allow …(y)`, `keep (n)`, `skip (esc or n)` |
| Cline | 默认 Working（与其他相反） | `let cline use this tool`, `[act mode]` + `yes` |
| GitHub Copilot | `esc to cancel` | `│ do you want`, `confirm with …enter` |
| Kimi | `thinking`/`processing`/`generating` | `allow?`/`confirm?`/`approve?`/`[y/n]` |
| Pi | `Working...` | (不支持) |

Roost 完全没有终端输出分析。Agent 没有安装 hook 就完全没有状态追踪。即使有 hook，hook 失败时静默降级，无 fallback。

## 四、Hook 权威模型对比

### herdr 设计 (`pane/state.rs`)

```
优先级: Hook 权威 > 屏幕启发式
但: 进程检测永远拥有身份/存活判定权
```

| 特性 | 实现 |
|------|------|
| 序列号去重 | `HookReportSequences` 按 source 跟踪 seq，拒绝乱序/重复消息 |
| Agent 释放 | `HookAgentReleased` 清空 agent 身份，`PendingAgentRelease` 抑制重获取 |
| 身份一致性 | 进程检测到 agent 变化时，自动清除匹配的 hook 权威 |
| 非匹配 hook 保留 | 进程检测清空时 hook 权威不丢（如自定义 agent label） |

### Roost 设计

收到 hook 消息 → `AgentActivitySocketEvent.parse` → `updateAgentActivity`。无去重、无释放、无身份校验。

### herdr 的 Claude hook 事件映射

| Hook 事件 | → 状态 |
|-----------|--------|
| `UserPromptSubmit` | working |
| `PreToolUse` | working |
| `PermissionRequest` | blocked |
| `PostToolUse` | working |
| `PostToolUseFailure` | working |
| `SubagentStop` | working |
| `Stop` | idle |
| `SessionEnd` | release |

## 五、通知系统对比

| 维度 | herdr | Roost |
|------|-------|-------|
| 触发条件 | 状态变化事件 | 状态变化 + OSC 9/777 + hook 消息 |
| 声音 | 二进制内嵌 mp3（Done + Request），`afplay` 播放 | 系统通知声音（UserNotifications） |
| Toast | 终端内 toast（TUI 渲染） | SwiftUI toast overlay |
| "已读"追踪 | `PaneState.seen: bool`，区分 Idle vs Done(unseen) | completed 只靠 acknowledge |
| 配置 | `config.toml` + 应用内设置 + `HERDR_DISABLE_SOUND` env | `.roost/config.json` 项目级 + Settings 全局 |
| Agent 间通知 | Socket API 可让 agent 等待另一 pane 状态 | 间接（通过 socket API 读输出） |

## 六、Agent 支持矩阵

| Agent | herdr 检测 | herdr Hook | Roost 检测 | Roost Hook |
|-------|-----------|------------|------------|------------|
| Claude Code | 屏幕+进程 | ✓ | — | ✓ |
| Codex | 屏幕+进程 | ✓ | — | ✓ |
| Gemini CLI | 屏幕+进程 | — | — | — |
| OpenCode | 屏幕+进程 | ✓ | — | ✓ |
| Pi | 屏幕+进程 | ✓ | — | — |
| Droid | 屏幕+进程 | — | — | — |
| Amp | 屏幕+进程 | — | — | — |
| Cursor | 屏幕+进程 | — | — | — |
| Cline | 屏幕+进程 | — | — | — |
| GitHub Copilot | 屏幕+进程 | — | — | — |
| Kimi | 屏幕+进程 | — | — | — |

## 七、改进建议（按优先级）

### 高价值

1. **终端屏幕启发式检测** — 周期性采样 Ghostty surface 底部 40 行可见文本，实现 per-agent 模式匹配。新增 agent 时只需加匹配规则，无需等 hook 支持。
2. **进程树 Agent 检测** — 利用 macOS `libproc` API 从 pane 的 shell PID 读取子进程树，自动发现运行中的 agent 二进制，处理 nix/store 路径、shell wrapper 场景。

### 中等价值

3. **声音通知映射** — `Done` ↔ `completed`、`Request` ↔ `awaiting`，在 `updateAgentActivity` 中加声音触发，区分"用户正在看"和"后台发生"。
4. **Hook 序列号去重** — 防止 hook 消息乱序/重复。
5. **扩展 AgentKind** — 加 pi、droid、amp、cursor、cline、kimi、copilot。

### 低价值

6. **Claude Working sticky** — 1.2s 粘滞防止 spinner 帧间闪烁。
7. **"已读/未读" pane 状态** — 跟踪用户是否看过该 pane 的最新完成状态，侧边栏区分 Idle vs Done(unseen)。
