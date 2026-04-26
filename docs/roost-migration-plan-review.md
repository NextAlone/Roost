# Roost Migration Plan — 审计评审

对 `docs/roost-migration-plan.md` 的两轮独立审计合并结论。第一轮主审（仓库事实 + plan 对照），第二轮独立 reviewer 挑战 + 补漏 + 优先级重排。本文档为最终版。

## 范围确认

仓库实际状态（已通过 `jj st` / `ls` / `grep` 验证）：

- `main` 基于 jj bookmark `vendor/muxy-main`，Roost main 已 fork 出一个修订
- `Muxy/Services/Git/*` 含完整 GitWorktreeService / GitRepositoryService / GitStatusParser / GitDiffParser / GitMetadataCache
- `Muxy/Models/Worktree.swift` 字段：`id, name, path, branch: String?, ownsBranch: Bool, source: WorktreeSource{muxy,external}, isPrimary, createdAt`
- `Muxy/Views/VCS/` 已有 BranchPicker / CreateBranchSheet / CreatePRSheet / CommitHistoryView / DiffViewer / PullRequestsListView
- `.gitignore` 排除 `/target /apps /crates /pocs /vendor /.worktrees`（旧 Roost Rust 产物）
- 旧 Roost 在 `feat-m6` bookmark，是 Rust 实现（roost-hostd）
- CLAUDE.md 强制 `scripts/checks.sh --fix` + jj-only VCS policy

## 🔴 必修 — Phase 0/1 开工前必决

按致命度排序。1–5 不解决会在 Phase 1 第一天踩雷或埋下数据安全隐患。

### 1. jj 自动 snapshot 竞态（产品级数据安全）

**问题**：jj 的 working copy is a commit。UI 任意一次 `jj status` / `jj log` 轮询都会触发 working-copy snapshot，把当前文件状态吞进当前 change。多 agent 在 pane 里写文件时，UI 侧轮询会随时改写当前 change 内容，可能把半写状态、临时文件、merge 中间态固化到历史。

**plan 对此完全没提**。风险表里没有这一条。

**修复方向**：
- Phase 1 service 层所有只读命令默认带 `--ignore-working-copy`
- 状态查询走 `--at-op @-` 或显式 op id，避免隐式 snapshot
- 显式 snapshot 仅在用户动作（保存、commit、新建 change）时触发
- service 层 API 设计要让"是否 snapshot"成为参数，不是默认行为

### 2. Swift 6 concurrency + jj 阻塞 subprocess

**问题**：jj subprocess 阻塞，SwiftUI 主线程直接调会挂。Swift 6 strict concurrency + actor 隔离对此零规划。Phase 1 第一天就会撞上。

**修复方向**：
- `JjProcessRunner` 为 actor 或 `Sendable` 封装，全部 async
- 输出 streaming 用 `AsyncStream<Data>`，不阻塞调用方
- 取消传播：`Task.cancel()` → `Process.terminate()`
- 决定单 actor per repo path 还是全局 actor + 内部串行

### 3. Worktree 模型字段在 jj 下的映射

**问题**：`Worktree` 模型字段全是 git 语义（`branch`、`ownsBranch`、`isPrimary`），plan Phase 2 仅说"加 vcsKind flag"，没定义映射。

**需在 Phase 2 spike 前明确**：
- `branch` → 当前 bookmark 名？默认 workspace 名？工作副本 change id？或留空，新增 `currentBookmark: String?`
- `ownsBranch` → jj 不存在该概念，应退化为"创建时是否同步建 bookmark"或删除
- `isPrimary` → jj 默认 workspace 名 `default`，需说明 primary 判定规则
- `source: external` 已存在，Phase 2 必须处理 import 已存在 jj workspace 的路径

### 4. jj 版本与输出格式锁定（jj 仍 sub-1.0）

**问题**：`bookmark` 是新名（≥ 0.16，旧叫 `branch`），`workspace forget` 跨版本语义有变。`jj log` 默认 graph + color，不强制 `--no-graph -T '<template>'` 解析必碎。

**修复方向**：
- Phase 0 加最低 jj 版本声明（建议 ≥ 0.20）
- Phase 1 `JjProcessRunner` 强制：`--no-pager`、`--color=never`、`--no-graph`、`-T` 模板渲染
- parser 全部驱动自固定 fixture，不靠 live jj 输出
- jj 升级走显式版本矩阵 CI

### 5. subprocess 环境契约

**问题**：plan 说 "Do not inherit GUI tty" 太宽。环境变量未规范，parser 在不同用户 shell 下结果不可预测。

**修复方向**：每次 jj 调用强制：
- `LANG=C.UTF-8`、`LC_ALL=C.UTF-8`
- `NO_COLOR=1`
- `PATH` 显式（不继承用户 shell PATH，避免 shim）
- 关闭 stdin（`process.standardInput = Pipe()` 立即 close，防 hang）
- 清除 `JJ_*` 自定义变量（除显式注入的 `JJ_CONFIG`）
- `HOME` 来自当前用户

### 6. Git→jj 用户数据迁移

**问题**：`projects.json` 里现存的 git Worktree 记录在 Roost 切换后如何处理？plan 零说明。`source: WorktreeSource{muxy,external}` / `ownsBranch` 在 jj 模式下语义未定义，老用户数据可能被 decoder 直接拒绝或静默丢弃。

**修复方向**：
- Phase 0 定义 `projects.json` schema 版本字段
- 写 migration：git-only Worktree 记录在 jj 模式下何种行为（只读？转换？提示用户？）
- 增加 schema 升级单测

### 7. 跨进程 op log 仲裁

**问题**：N agent × N workspace 并发写 backend store。plan 只说"per repo serialize mutating ops"，但 agent 进程独立于 Roost 进程，Roost 的 actor lock 管不到。jj 自身 store lock 行为不能用作 UX 假设。

**修复方向**：
- Phase 1 设计文档说明：jj 自身 store lock 边界 + Roost 端串行边界 + agent 进程在 Roost 之外的并发假设
- 状态推送（#10）依赖此前置：fs watch `.jj/repo/op_heads` 是跨进程感知的唯一手段

### 8. agent ↔ workspace 基数 1:1 vs N:1

**问题**：Phase 3 说"dedicated jj workspace" 暗示 1:1，但用户实际会想"同 workspace 跑 claude + 一个 shell"。基数决定 Phase 3 数据模型与 setup hook 触发时机，**事后改动需要数据迁移**。

**建议**：N:1 默认（多 session 共享同 workspace），1:1 作为 agent preset 可选项。

### 9. hostd 实现栈选型

**问题**：旧 Roost `roost-hostd` 是 Rust。Phase 6 说"introduce hostd behind feature flag"，但 Swift / XPC service / 嵌入 Rust 三路打包/签名/sandbox 完全不兼容，必须 Phase 6 开始前选定。

**需澄清**：
- 实现语言（Swift 重写 vs 嵌入旧 Rust 二进制）
- IPC 形式（XPC 服务 vs Unix socket vs gRPC）
- macOS sandbox + entitlements 影响（XPC 要 entitlement、Unix socket 要 group container）
- notarize / 签名链

### 10. 测试基础设施结构性缺位

**问题**：CLAUDE.md 强制"feature testable 必须写测试"。plan 仅 Near-Term 第 2 条提 parser 单测，缺 fixture 仓库、jj 版本矩阵、集成测试。Phase 1 parser 没 fixture 驱动，每次 jj 升级是黑盒。

**修复方向**：
- `Tests/Fixtures/jj-repos/` 建固定 jj 仓库 tar 包，CI 解压驱动 parser
- jj 版本矩阵跑 fixture（最低支持版 + latest）
- Phase 1 exit 加：parser 单测覆盖率 ≥ X%

### 11. `scripts/checks.sh` 入 phase exit gate

**问题**：CLAUDE.md 强制每任务 `scripts/checks.sh --fix`。plan Near-Term 第 8 条只说 `swift build`。

**修复**：每 phase exit criteria 显式加 "scripts/checks.sh 通过"。Phase 0 加 CI gate。

### 12. Phase 1 命令补基础设施类

**问题**（修订自原 #2）：业务命令（squash/abandon/duplicate/backout/describe/new）在 Phase 5 显式列出，按 phase 分散是合理的。但 Phase 1 缺基础设施类：

- `jj op log`（操作历史，#10 状态推送依赖）
- `jj show`（单 commit 详情）
- `jj resolve`（冲突列举与解决）
- `--at-op` 支持（#1 snapshot 隔离依赖）

## 🟡 应补

13. **vendor/muxy-main 命名歧义**：plan 中是 jj bookmark，磁盘 `/vendor/` 是另一回事且被 .gitignore。在 plan Baseline 显式注明。
14. **mutating 命令 allowlist**：列具体哪些命令进 actor 串行（new/commit/squash/abandon/rebase/describe/bookmark set/git push/op restore），其他只读不卡。
15. **Phase 4 状态推送源**：fs watch `.jj/repo/op_heads` + `jj op log -n1 --no-graph -T id --ignore-working-copy` 轮询，明写实现路径。
16. **Phase 7 `.roost/config.json` schema** 未定。secret 处理只说"avoid logging"，应指明 macOS Keychain 或 chmod 600 file，且不入 jj。
17. **Phase 8 缺**：app entitlements、notarization、Sparkle 老用户 feed 迁移、telemetry opt-in 默认。
18. **每 phase abort criteria**（修订自原 #16）：不需要 LaunchDarkly 式 flag system，但需要一行止损 trigger（"Phase X 跑 2 周不收敛 → 回滚到 git 路径 / 推迟该 phase"）。单人项目尤其需要。
19. **external workspace import 路径**（原 #18）：`source: external` 已在模型里，Phase 2 应顺势处理 import 已存在 jj workspace。

## 🟢 优化

20. **Reference repos pin commit**：upstream 漂移会让引用失效，每条 reference 加 commit-id 或 tag。
21. **风险表补 4 条**：jj sub-1.0 CLI 漂移（已升 🔴 #4）、libghostty ABI 升级、macOS sandbox + spawn 限制、Sparkle 老 feed 兼容。
22. **bookmark delete vs forget 语义**：Phase 5 实现细节，plan 不必教科书化。
23. **Near-Term #5 与 Phase 2 重复**：明确 "Near-Term = Phase 1+2 spike"。

## 🗑️ 已撤回 / 已降级

| 原条目 | 原级别 | 处置 | 理由 |
|--------|--------|------|------|
| Phase 0 exit "Clean jj status" 不满足 | 🔴 | 删 | 混淆 plan 描述与执行状态。Exit criteria 是完成态，不是写 plan 这一刻必须满足 |
| 每 phase 全套 feature flag | 🟡 | 降级为 #18 abort criteria | 单人项目过度工程，但保留止损 trigger |
| Phase 1 一次性补齐所有命令 | 🔴 | 改为 #12 仅基础设施类 | 业务命令按 phase 分散是对的 |
| bookmark delete vs forget | 🟡 | 降为 🟢 #22 | Phase 5 实现细节，plan 层面不必管 |

## 推荐执行顺序

1. **Phase 0 收尾前**：1（snapshot）、2（concurrency）、4（jj 版本锁定）、5（subprocess 环境）、6（数据迁移 schema）、10（测试基础设施）、11（checks.sh gate）落地为 design doc 或代码契约
2. **Phase 1 开工前**：3（Worktree 字段映射）、7（跨进程仲裁）、12（基础设施命令）、14（mutating allowlist）、15（状态推送源）确定
3. **Phase 3 开工前**：8（agent↔workspace 基数）选定
4. **Phase 6 开工前**：9（hostd 栈）选定
5. **Phase 8 前**：17（release 配套）补齐
