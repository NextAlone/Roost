# tmux control mode 长连接优化方案 (D)

## 背景

`agent-activity-push-redesign.md` 阶段 3 字面方案 (`pane_last_activity` 短路 capture-pane) 对 claude/codex 场景**无效**:spinner 100ms 重绘持续刷新 `pane_last_activity`, 短路永不触发。

替代实施 C 方案 (状态稳定退避 500ms→2s), 减少 fork/exec ~60-70%。本文档保留 D 方案 (tmux control mode 长连接) 作为后续独立优化。

## 目标

消除 `tmux capture-pane` 每次检测的 fork/exec, 改用单条 tmux control mode 长连接 push 屏幕变化事件。

## 设计

### tmux control mode

`tmux -CC` 或 `attach-session -tcontrol` 进入 control mode:
- daemon 启动一个 tmux client 子进程, stdin/stdout pipe
- 通过 stdin 发命令 (`capture-pane -t roost-<uuid>:0.0 -p`)
- stdout 收结构化 block:
  ```
  %begin <timestamp> <cmdnum> 1
  <command output lines>
  %end <timestamp> <cmdnum> 1
  ```
- 异步 notification:
  ```
  %output %<paneid> <text>
  %pane-died %<paneid>
  %session-changed
  ```

### 架构

```
┌─────────────────────────────────────────┐
│ HostdProcessRegistry                    │
│  ├─ TmuxControlClient (长连接)          │
│  │   ├─ subprocess: tmux -CC           │
│  │   ├─ stdin (FileHandle, write 命令)  │
│  │   ├─ stdout (DispatchSource read)    │
│  │   └─ parser (block / notification)   │
│  └─ runDetectionLoop                    │
│      └─ 订阅 %output 事件 push 到 detector
└─────────────────────────────────────────┘
```

### 数据流

1. daemon 启动 → `TmuxControlClient.connect()` fork 一次 tmux subprocess
2. `subscribeAgentActivity` → 不再每轮 capture-pane, 而是订阅 `%output` 事件
3. tmux 推 `%output %<paneid> <bytes>` → parser 维护每 pane 的 line buffer
4. pane 输出累积 → 触发 `detectAgentActivity(screenContent: buffer.tail(40 lines))`
5. state machine confirm → push `HostdAgentActivityEvent`

### 新增文件

- `RoostHostdCore/HostdTmuxControlClient.swift` (~400 行)
  - `actor TmuxControlClient`
  - `func connect()`, `disconnect()`, `executeCommand(_:)`, `subscribeOutput(paneID:) -> AsyncStream<Data>`
  - 内部:subprocess management, line parser, reconnect on disconnect
- `Tests/MuxyTests/Hostd/HostdTmuxControlClientTests.swift`
  - mock subprocess stdin/stdout, 验证 parser block / notification 分支

### 修改

- `HostdTmuxControlling` 协议保留, `HostdTmuxController` 不动 (用于 launch/kill/sendKeys 等一次性命令)
- `HostdProcessRegistry`:
  - 新增 `controlClient: TmuxControlClient?` 字段
  - `runDetectionLoop` 改为消费 `controlClient.subscribeOutput(paneID:)` 流
  - `subscribeAgentActivity` 触发 `controlClient.connect()` (lazy)
  - 最后一个订阅取消时 `controlClient.disconnect()`

### 协议版本

`HostdDaemonRuntimeIdentity.currentProtocolVersion` 1011 → 1012 (引入 push detection, runtime 行为变化)

## 风险

1. **tmux 子进程崩溃**:`TmuxControlClient` 需检测 EOF/SIGPIPE → 重启 subprocess → 重订阅所有活动 pane
2. **buffer 管理**:每 pane 维护 ring buffer (上限 8KB 或 200 行), 旧数据丢弃
3. **detector 触发频率**:`%output` 高频 push (每 100ms 一次 spinner 重绘 → 流量↑), 需要 debounce 100ms 后才喂 detector
4. **测试改造**:mock 不再是函数桩, 需要伪 subprocess (DispatchSource + Pipe)
5. **跨平台**:tmux control mode 行为在不同版本可能差异 (3.0+ 稳定)

## 工作量估算

- 实现 + 单元测试: 2-3 天
- 集成 + 回归测试: 1 天
- 灰度验证 (DEV_MODE 灰度开关): 1-2 天

## 触发条件

阶段 1+2+3C 上线后, 若线上仍观察到 tmux CPU 占用过高 或 fork/exec 频次告警 → 启动本方案。

## 不在范围

- tmux control mode 之外的 fork 优化 (如 launch / kill 命令仍走单次 subprocess)
- 检测器算法本身的优化 (pattern 匹配性能)
