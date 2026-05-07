# Stable Pane Host Layer 设计文档

## 一、需求背景

### 问题

Roost 当前 split / 重排 tab 等操作会导致 SwiftUI 拆/重 mount `NSViewRepresentable`,
引发 `dismantleNSView` → 释放底层 NSView, 用户层面表现为：

| Pane 类型 | NSView 持的状态 | split 丢什么 | 严重度 |
|---|---|---|---|
| TerminalPane (terminal kind) | ghostty surface + PTY | shell 进程死, 在跑命令死, scrollback 丢, cwd/env reset | **P0 灾难** |
| TerminalPane (agent kind) | ghostty surface, tmux client | 仅闪屏重连, 进程不死 | 轻 (现已 OK) |
| EditorPane | NSScrollView+NSTextView+NSTextStorage | undo/redo history 全丢, IME 状态丢, 滚动 reset | **P1 中** |
| DiffViewerPane | DiffContentNSView+DiffGutterNSView | 滚动位置/选区/hover reset | P2 轻 |

### 根因

`PaneNode.swift:21-56` 在 `node` 从 `.tabArea(area)` 变成 `.split(branch{first: .tabArea(area), second: .tabArea(new)})` 时, `body` switch 分支翻转,
SwiftUI 视图身份按结构位置追踪 → 老 subtree 拆除 → `TerminalBridge.dismantleNSView` 触发 → `tearDown()` → `ghostty_surface_free()` → PTY/进程死.

CLAUDE.md `## NSViewRepresentable Pitfalls` 节已记录此 pitfall, 提示唯一修法是
"keep the `NSViewRepresentable` mounted in the view tree rather than conditionally removing it".

### 目标

- P0: split/重排不再杀 terminal pane 的 PTY 进程
- P1: split/重排不再清空 EditorPane 的 undo 栈
- 不引入 tmux 包裹 terminal 这种症状级 workaround
- 保持现有 split tree 数据模型 (`SplitNode`/`SplitBranch`) 不变, 仅改视图层
- 保持 tab 切换、focus border、drop zone、search overlay、divider 拖拽等行为不变

### 非目标

- 不在本次改 DiffViewerPane / VCSTabView 的 NSView 寿命 (P2 后续单独评估)
- 不改 `SplitNode` 数据结构与 reducer
- 不引入 NSSplitView 替换 SwiftUI HStack/VStack
- 不改 `TerminalViewRegistry` 的 cache 语义 (它仍按 paneID 持有 NSView, 只是不再被 SwiftUI 反复 dismantle)

---

## 二、核心原则

1. **NSView 永驻**: 凡持昂贵 NSView 状态的 pane (terminal/editor), NSView 在 SwiftUI tree 中仅由**唯一一个稳定挂载点**持有, 跨越 split/tab 重排不变.
2. **数据模型不动**: `SplitNode`/`SplitBranch` reducer 路径完全不变, 改造仅限视图层.
3. **Chrome 与 Content 分离**: tab strip / divider / focus border / drop zone (chrome) 跟随 split tree 重建, NSView (content) 不重建.
4. **位置由 frame 决定, 不由结构决定**: 用 `SplitNode.areaFrames(in:)` (现有 API, SplitNode.swift:167) 计算每个 area 的归一化 rect, 在 host layer 内用 `.frame()`+`.offset()` 摆位.
5. **可逆**: 改造分阶段提交, 每个阶段独立可 ship 可 revert.

---

## 三、架构设计

### 当前架构

```
TerminalArea
└─ PaneNode(node: .split | .tabArea)
   ├─ case .tabArea: TabAreaView(area)
   │   └─ ZStack { ForEach(tabs) { TabContentView } }
   │      └─ TerminalPane / EditorPane / VCSTabView / DiffViewerPane
   │         └─ TerminalBridge / CodeEditorRepresentable / ... [NSViewRep]
   └─ case .split: SplitContainer(branch)
      └─ HStack/VStack { child(branch.first); divider; child(branch.second) }
         └─ child(node) = PaneNode(node) ← 递归
```

split → `node` 从 `.tabArea` 变 `.split` → PaneNode body switch 切分支 → 老 TabAreaView subtree 被 dismantle → 内部 NSViewRep 全 dismantle.

### 新架构

```
TerminalArea
└─ ZStack {
     // Chrome layer: 跟随 split tree 重建, 无 NSView
     PaneNodeChrome(node: root)
        ├─ case .tabArea: TabAreaChrome(area)        ← 仅 tab strip + 占位 + 边框 + drop zone
        └─ case .split:   SplitChromeContainer       ← 仅 divider + 递归 chrome

     // Content layer: 稳定挂载, NSView 永驻
     ContentHostLayer(panes: visiblePanes(root), frames: root.areaFrames(in: viewSize))
        └─ ForEach(panes, id: \.id) { pane in
             switch pane.kind {
             case .terminal: TerminalBridge(state: pane.state)
                                .frame(...)
                                .offset(...)
                                .id(pane.id)
             case .editor:   CodeEditorRepresentable(state: pane.state)
                                .frame(...)
                                .offset(...)
                                .id(pane.id)
             case .vcs:      VCSTabView(state: pane.state)              ← 暂留旧路径
             case .diff:     DiffViewerPane(state: pane.state)          ← 暂留旧路径
             }
           }
   }
```

split 时:
- Chrome layer 跟着 split tree 重建 (无伤大雅, chrome 没昂贵状态)
- Content layer 的 ForEach 仍然 iterate 同一组 panes (id 不变), 仅 frame 数值变 → SwiftUI 仅触发 `updateNSView` (调整 size/position), **不**触发 `dismantleNSView`/`makeNSView`

### 关键不变量

1. **Pane 实例稳定**: `TerminalPaneState` / `EditorTabState` 都是 `@Observable class`, split 时 reducer 不会重建实例 (验证: `SplitReducer.splitArea` 仅修改 `state.workspaceRoots`, 不动 area.tabs)
2. **paneID 稳定**: `state.id: UUID` 在 init 时分配, 不变
3. **`areaFrames(in:)` 已存在**: SplitNode.swift:167-185 已实现归一化 rect 计算, 可直接复用

---

## 四、详细设计

### 4.1 数据流

```
SplitNode (reducer 已维护)
    ↓ areaFrames(in: containerSize)
[UUID: CGRect] (areaID → 归一化 rect)
    ↓ TabArea.activeTab.content.pane (按 area 取当前可见 pane)
[(paneID, paneState, frame)] (扁平列表)
    ↓ ContentHostLayer.body
ForEach { TerminalBridge / CodeEditorRepresentable }
```

### 4.2 TerminalPane chrome 拆分

当前 `TerminalPane` (TerminalPane.swift:5-84) 是 ZStack, 内含 4 类元素, 改造时分配如下:

| 元素 | 内容 | 改造后位置 | 数据依赖 |
|---|---|---|---|
| `TerminalBridge` | NSViewRepresentable, 持 ghostty surface | **Content layer** | `TerminalPaneState` (paneID 锚定) |
| `HostdAttachPlaceholder` | hostd attach 状态占位 (preparing/failed) | **Chrome layer** (覆盖在 layer frame 同位置) | `state.hostdAttachState` |
| `RemoteControlledPlaceholder` | "Controlled by iPhone X" 提示 | **Chrome layer** | `PaneOwnershipStore.shared.owner(for:)` |
| `TerminalSearchBar` | 顶部搜索条 | **Chrome layer** (alignment .top) | `TerminalPaneState.searchState` + `TerminalViewRegistry.shared.existingView(for:)` 调 NSView API |

实现要点:
- chrome 的占位 view 需要拿到 layer 同一区域的 frame (复用 `areaFrames`).
- search bar 通过 `TerminalViewRegistry.shared.existingView(for: paneID)` 调用 layer 内 NSView 的 `startSearch / endSearch / sendSearchQuery / navigateSearch` (这些 API 当前已存在).
- `shouldMountTerminalBridge` (现 TerminalPane.swift:81-83) 的逻辑保留, 但作用在 chrome 上 (决定显示 placeholder 还是 layer 透出); layer 始终持有 NSView, chrome 决定可见性.

> 这是**唯一**让 NSView 永驻同时保留 placeholder 模态切换的做法. 若把 placeholder 也放 layer, 切换 placeholder ↔ NSView 会触发 dismantle, 等于没改.

### 4.3 ContentHostLayer 接口

```swift
struct ContentHostLayer: View {
    let root: SplitNode
    let focusedAreaID: UUID?
    let isActiveProject: Bool
    let projectID: UUID
    @Environment(AppState.self) private var appState

    var body: some View {
        GeometryReader { geo in
            let frames = root.areaFrames(in: CGRect(origin: .zero, size: geo.size))
            ZStack(alignment: .topLeading) {
                ForEach(visibleEntries(in: root, frames: frames), id: \.paneID) { entry in
                    paneView(for: entry)
                        .frame(width: entry.frame.width, height: entry.frame.height)
                        .offset(x: entry.frame.minX, y: entry.frame.minY)
                        .id(entry.paneID)
                }
            }
        }
    }

    private struct Entry {
        let paneID: UUID
        let areaID: UUID
        let content: TerminalTab.Content
        let frame: CGRect
    }

    private func visibleEntries(in node: SplitNode, frames: [UUID: CGRect]) -> [Entry] {
        node.allAreas().compactMap { area in
            guard let frame = frames[area.id], let activeTab = area.activeTab else { return nil }
            return Entry(paneID: activeTab.id, areaID: area.id, content: activeTab.content, frame: frame)
        }
    }

    @ViewBuilder
    private func paneView(for entry: Entry) -> some View {
        switch entry.content {
        case let .terminal(pane):
            TerminalBridge(state: pane, focused: ..., areaID: entry.areaID, ...)
        case let .editor(state):
            CodeEditorWrapper(state: state, focused: ...)
        case let .vcs(state):
            VCSTabView(state: state, focused: ..., onFocus: ...)  // 旧路径, 不上 layer
        case let .diff(state):
            DiffViewerPane(state: state, focused: ..., onFocus: ...)  // 旧路径, 不上 layer
        }
    }
}
```

> **设计抉择**: VCS/Diff 暂留旧路径, 即在 Content layer 内被切换式渲染, 仍可能 dismantle. 因 P2 影响小, 后续单独迁移避免本次 PR 过大.

### 4.5 active tab 切换语义

当前 `TabAreaView` (TabAreaView.swift:91-130) 用 `ZStack { ForEach(tabs) { TabContentView } .opacity(isActive ? 1 : 0) }` 渲染所有 tab, 仅 active 可见.

**问题**: 如果 layer 为每个 area 仅渲染 active tab, 切 tab 时 active pane 变 → ForEach diff 时**会** dismantle 老 active pane 的 NSView. 切 tab 也会丢状态.

**方案**: layer 内对每个 area 渲染**所有 tab**, 通过 opacity/zIndex/`.allowsHitTesting` 切换可见性 — 同 TabAreaView 现有做法.

```swift
private func visibleEntries(...) -> [Entry] {
    node.allAreas().flatMap { area in
        area.tabs.map { tab in
            Entry(paneID: tab.id, areaID: area.id, content: tab.content,
                  frame: frames[area.id] ?? .zero,
                  isActiveInArea: tab.id == area.activeTabID)
        }
    }
}

// 渲染时:
paneView(for: entry)
    .frame(...)
    .offset(...)
    .opacity(entry.isActiveInArea ? 1 : 0)
    .allowsHitTesting(entry.isActiveInArea)
    .zIndex(entry.isActiveInArea ? 1 : 0)
    .id(entry.paneID)
```

→ 切 tab 不重建 NSView. 但**所有 tab** 的 NSView 都要永久持有 (内存代价: 每个隐藏 terminal 仍持 ghostty surface, 每个隐藏 editor 仍持 NSTextView+NSTextStorage). 这是符合用户预期的 (现状就是隐藏 tab 也持有, 因为 ZStack ForEach 已这样做了).

### 4.6 Chrome layer 结构

```swift
struct PaneNodeChrome: View {
    let node: SplitNode
    var body: some View {
        switch node {
        case let .tabArea(area): TabAreaChrome(area: area, ...)
        case let .split(branch): SplitChromeContainer(branch: branch, ...)
        }
    }
}

struct TabAreaChrome: View {
    let area: TabArea
    var body: some View {
        VStack(spacing: 0) {
            if showTabStrip { PaneTabStrip(...); Divider }
            Color.clear
                .preference(key: AreaFramePreferenceKey.self, value: [area.id: ...])
                .overlay { paneOverlay(for: area.activeTab) }  // placeholder / search bar / drop zone
        }
        .overlay { focusBorder }
    }

    @ViewBuilder
    private func paneOverlay(for tab: TerminalTab?) -> some View {
        if let pane = tab?.content.pane {
            if let owner = PaneOwnershipStore.shared.owner(for: pane.id), case let .remote(_, name) = owner {
                RemoteControlledPlaceholder(deviceName: name) { ... }
            } else if pane.hostdRuntimeOwnership == .hostdOwnedProcess, pane.hostdAttachState != .ready {
                HostdAttachPlaceholder(agentName: pane.title, state: pane.hostdAttachState)
            }
            if pane.searchState.isVisible {
                TerminalSearchBar(searchState: pane.searchState, ...)
            }
        }
    }
}
```

### 4.7 事件路由

| 事件 | 当前路径 | 改造后 |
|---|---|---|
| 点击 pane → focus area | `TerminalBridge.onFocus` 上抛 | 不变, layer 内的 NSViewRep 仍接 `onFocus`, 通过 `appState.dispatch(.focusArea)` |
| split request | `TerminalBridge.onSplitRequest` 上抛 | 不变 |
| process exit | 同上 | 不变 |
| drop zone 命中检测 | `TabAreaView` 用 `AreaFramePreferenceKey` 上报 frame, dragCoordinator 命中检测 | TabAreaChrome 仍上报 frame (TabAreaView 现有路径不动), 命中后命中的是 chrome 上的 area (chrome 跟 layer frame 重合), 行为一致 |
| search overlay (`TerminalSearchBar`) | 在 `TerminalPane` 内 ZStack 顶层 | layer 内 TerminalBridge 之上加 overlay, 或保留在 chrome 层做绝对定位 |
| focus border | TabAreaView overlay | TabAreaChrome overlay (位置同) |

> **风险点**: search bar 位于 layer 内 NSView 上方时, NSView 抢 hit-testing 优先级可能影响; 已有逻辑用 `allowsHitTesting(remoteOwnerName == nil)` 等控制, 需复测.

### 4.8 SwiftUI identity 验证

ContentHostLayer 内的 ForEach 用 `.id(entry.paneID)` 显式锚定身份. 即便 split 后 frame 变化, 同一 paneID 的 view 不会被 SwiftUI 视为新 view → 仅 `updateNSView` 不 `makeNSView`.

但 `id(_:)` 仅在**同一 ForEach 上下文**有效. 不能跨容器移动 view. 我们的设计始终在同一 ZStack 内, 满足.

---

## 五、影响范围

| 模块 | 文件 | 改动类型 | 说明 |
|---|---|---|---|
| Workspace 视图 | `Muxy/Views/Workspace/Workspace.swift` (TerminalArea) | 重构 | 拆 chrome 与 layer, 引入 ContentHostLayer |
| Pane 路由 | `Muxy/Views/Workspace/PaneNode.swift` | 重命名+裁剪 | 改成 PaneNodeChrome, 移除 TabContentView 渲染 |
| Split 容器 | `Muxy/Views/Workspace/SplitContainer.swift` | 裁剪 | 改成 SplitChromeContainer, 仅留 divider |
| Tab 区域 | `Muxy/Views/Workspace/TabAreaView.swift` | 拆分 | 抽出 TabAreaChrome (无 ForEach NSView), 保留 TabContentView 给 VCS/Diff 旧路径 |
| Layer 新增 | `Muxy/Views/Workspace/ContentHostLayer.swift` | 新增 | 稳定挂载 TerminalBridge / CodeEditor |
| Editor wrapper | `Muxy/Views/Editor/CodeEditorRepresentable.swift` | 不动内部, 调用方迁移 | EditorPane 内的 chrome (breadcrumb/loader/error/search bar) 留 chrome 层, NSView 上 layer |
| Terminal wrapper | `Muxy/Views/Terminal/TerminalPane.swift` | 拆分 | 把 TerminalBridge 提到 layer, search bar / placeholder 留 chrome |
| 测试 | `Tests/MuxyTests/` | 新增 | UI 行为快照: split 前后 paneID/进程 PID 一致性 |

### Project / Worktree 生命周期边界 (advisor flagged, 已核实)

`MainWindow.swift:117-129` 用 `ForEach(mountedTerminalWorktrees)` 渲染所有 mounted TerminalArea, opacity 0 隐藏非 active. `MountedTerminalWorktreePolicy.displayKeys` (MountedTerminalWorktreePolicy.swift:4-21) = `remembered ∪ active ∪ agentBearing`, 与 `available` 取交.

| 操作 | TerminalArea 命运 | NSView (本次改造后) |
|---|---|---|
| 同 project 内 split / 切 tab / 重排 area | mounted 不变 | **稳定** ✓ |
| 切 project (在 remembered 内) | mounted, opacity 切换 | **稳定** ✓ |
| 切到首次访问的 project | 新 mount | 新建 (符合预期) |
| 关 project / 移除 worktree | unmount → prune | NSView 死 (符合预期, 用户期望关闭即清理) |
| App 重启 (hostd 模式) | 新 mount | agent pane tmux session 重 attach (现行) |

**结论**: host layer 在 TerminalArea 层级足够覆盖 P0 (split) + P1 (重排), 不需要提到 MainWindow 层. 关 project 引发的 NSView 销毁是预期行为, 不在本次 scope.

### VCSTabView NSView 占用 (advisor flagged, 已核实)

`grep -n "Representable\|NSView\|NSTextView" Muxy/Views/VCS/VCSTabView.swift` → 0 命中. 内嵌 diff 走 `appState.openDiffViewer(...)` 开独立 tab (VCSTabView.swift:719). VCSTabView 本身**确认是纯 SwiftUI**, 不在本次改造范围.

### 风险评估

| 风险 | 影响 | 缓解 |
|---|---|---|
| Drop zone 坐标系错乱 | 拖 tab 重排不准 | 坐标计算复用现有 `AreaFramePreferenceKey`, chrome frame = layer frame |
| Search overlay z-order/hit-testing | 用户搜索失灵 | 在 chrome 层渲染 search bar, 通过 NotificationCenter 触发已有 view 的 search API (TerminalViewRegistry.shared.existingView) |
| Focus first responder 时序 | 输入焦点丢 | 现有 `DispatchQueue.main.asyncAfter` 路径已处理时序, 验证 layer 重排不破坏 |
| 隐藏 tab 占内存 | terminal/editor 进程数翻倍 | 现有 ZStack ForEach 已隐藏持有, 内存量级不变 |
| SwiftUI 在某些 OS 版本对 frame+offset 巨变仍重 mount | 修不彻底 | macOS 14+ 已验证 ForEach + .id() 稳定身份; 必要时降级用 `Layout` protocol 自实现 |
| Editor undo 栈跨 split 保留破坏现有 "重置 undo" 假设 | 行为变更 | 这是修 bug, 不破坏 UX. PR 描述里说明 |
| VCS panel 和 layer 共存 z-order | 视觉 bug | VCS/Diff 暂留旧路径, 在 chrome 内同位置渲染 (z-order 同 layer) |

---

## 六、迁移步骤 (1 spike + 4 PR)

### PR-0 (architecture spike, 已完成)

**结果 (本机 macOS 26.5)**:

| 维度 | Spike A (Host Layer) | Spike B (Registry-defang) |
|---|---|---|
| 结构变化 5x sibling toggle | make=2, dismantle=0 ✓ | make=2, dismantle=10 ✗ |
| 顺序反转 3x | make=2, dismantle=0 ✓ | n/a |
| 真添加/移除 1 个 pane | make=3, dismantle=1 (符合预期) | n/a |
| 布局父切换 (VStack↔HStack) 5x | n/a | NSView 仍 attached, 但 SwiftUI dismantle/make 频繁 |

**结论**: Spike A 通过, 选定. Spike B 虽 NSView 实例存活但 SwiftUI 仍频繁 dismantle/make → Coordinator 反复重建 / callback 反复重绑 → 真 ghostty 上风险点多, 不采纳.

**原始 spike 实现** (已删除): `pocs/pane-host-spike/` (StubNSViewRep + 两个 harness, 跑 ~30s 出表).

> **不验证更低 OS 版本**: 项目已决定不考虑 macOS 14/15 兼容性回归, 以本机 OS 行为为准.

---

#### Spike A: Host Layer (本 doc 主方案)

#### Spike A: Host Layer (本 doc 主方案)

证明: `ForEach` + `.id(paneID)` 在 ZStack 内, 周围 sibling 结构变化时, NSViewRepresentable 不会 dismantle.

- 临时 view: ZStack 内 `ForEach([id1, id2]) { id in StubNSViewRep().id(id) }`
- StubNSViewRep 的 `makeNSView` / `dismantleNSView` 各打 log 计数
- 外层 `@State` toggle 加/减 sibling view 模拟 split 的结构性变化
- 切换前后 dismantle 计数应保持 0

#### Spike B: Registry-defang (替代方案)

证明: `TerminalViewRegistry.view(for:)` 改成 idempotent (existing 直接返回) + `dismantleNSView` 不调 `tearDown()`, NSView 跨 SwiftUI 重 mount 由 registry 持有, 行为正确无副作用.

- 改 `view(for:)`: existing != nil → 直接返回 existing, **不**新建/不 tearDown
- 改 `dismantleNSView`: 仅 `unregister`, 不 `tearDown`
- 显式 `removeView(paneID:)` 仅在 tab close / project close 时调用 (paneIDsToRemove 路径已存在)
- StubNSViewRep 同 Spike A 计数, 验证 makeNSView 仅首次调用, 后续 SwiftUI 重 mount 不会再走 makeNSView (或走但拿到的是 existing)
- **重点测项**: 重 mount 后 NSView 的 first responder / focus / 键盘事件是否仍 work. CLAUDE.md `## NSViewRepresentable Pitfalls` 警告 "can break silently" — 必须实证.

> Spike B 直接违反 CLAUDE.md 文档化的 anti-pattern. 选择 B 意味着团队接受推翻该 anti-pattern, 同时改 CLAUDE.md (将该段标注为"pre-host-layer era").

#### 决策准则

按优先级 (前者满足直接定):

1. **正确性**: 哪种通过 dismantle 计数器 (split 5x + 切 tab 5x + 跨 split drag 5x → 计数应为 0)
2. **跨 OS**: macOS 14 / 15 / 26 全部 OS 版本验证. 任一失败则该方案在该版本上不可用.
3. **键盘焦点 / 输入**: 重 mount 后 first responder 行为, 输入是否丢/IME 是否破
4. **工时估算**: A=3-5 天, B=1-2 天 (含改 CLAUDE.md 与 review 阻力)
5. **维护成本**: A 引入 chrome/content 双层但符合 CLAUDE.md; B 单层但需团队接受 anti-pattern 翻案

| 准则 | A 通过, B 通过 → 选 | A 通过, B 失败 → 选 | A 失败, B 通过 → 选 | 都失败 → |
|---|---|---|---|---|
| 结果 | **B** (工时优先) | A | B (改 CLAUDE.md) | pivot 到 NSSplitView 或 Layout protocol |

> 跳过此 spike 风险: 可能写完 4 PR 才发现 dismantle 仍触发, 或选错路径多花 2-3 天. 双 spike ~2h 是稳赚.

### PR-1: ContentHostLayer 骨架 + Terminal 单 area
- 引入 `ContentHostLayer.swift`, 仅 terminal pane, 仅单 area (root 是 .tabArea, 无 split)
- TerminalArea 改为 ZStack(chrome + layer), chrome 是现有 PaneNode (单 area 时无影响)
- 验证: 不 split 场景下 terminal 行为完全等价 (smoke test)

### PR-2: 支持 split tree
- ContentHostLayer 用 `areaFrames(in:)` 摆位
- PaneNode/SplitContainer 改成 chrome-only
- **必须同 PR 删除 TabAreaView 内 TerminalPane 渲染分支** (subagent #10): 否则双挂触发 registry tearDown, P0 即时复发
- 验证: dismantle 计数器为 0 (主), split agent pane PID 不变 (辅), split terminal pane shell PID 不变 + scrollback 保留

### PR-3: Editor 上 layer
- CodeEditorRepresentable 进 layer, EditorPane 拆 chrome (breadcrumb/loader/search) 与 NSScrollView
- 验证: split 后 undo 栈保留 (输入文字 → split → cmd+z 撤销到原状态)

### PR-4: 收尾 / 重构验证
- 删除 TabAreaView 内 ForEach 对 terminal/editor pane 的渲染分支 (避免双挂)
- 增加 UI 测试 / 文档更新 (architecture.md 同步)

每个 PR 独立可 ship, 测试通过即合.

> **工时**: spike + 4 PR + 接线 + 回归 = **3-5 天**. 主要消耗在 drop zone 命中检测、search overlay 时序、跨 OS 版本回归. 比初版"1.5-2 天"估计悲观一倍, 留 buffer.

---

## 七、测试要点

### 单元 / 集成
- [ ] `WorkspaceReducerTests`: 现有 reducer 测试全部通过 (本次不动 reducer)
- [ ] `ContentHostLayerTests` (新增):
  - [ ] `areaFrames(in:)` × ContentHostLayer 输出的 entries 一一对应
  - [ ] split 前后 `entry.paneID` 集合不变
  - [ ] tab 切换时 hidden tab 的 entry 仍存在 (active 标志变)

### 手动 UI 测试 (CLAUDE.md 要求 UI 改动须手测)
- [ ] **核心证据 (PR-2 之前)**: 给 `GhosttyTerminalNSView` (或 `TerminalBridge`) 加 mount/dismantle 计数器 (临时 debug build), split / 切 tab / 跨 area 拖 tab 各 5 次后, dismantle 计数应保持 0. 仅"PID 不变"不够, 因为 ghostty surface 重建仍可能 reattach 到同一 PID 的 tmux session, 假象式通过.
- [ ] **P0 验证**: terminal pane 跑 `sleep 9999`, `pgrep -f sleep` 记录 PID, split → 同位置 `pgrep` PID 不变
- [ ] **Project lifecycle 验证**: 多 project 场景 → 切走 → 切回, 同 PID. 关 project → 重开 → 新 PID (预期).
- [ ] **跨 split 拖 tab 验证**: 4 路 split, 把 area A 的 tab 拖到 area D, 验证 NSView 不 dismantle, 进程/undo 全保留.
- [ ] **P0 验证**: terminal pane scrollback 1000 行 → split → 上滚仍可见原历史
- [ ] **P0 验证**: agent pane 在 Claude 对话中 → split → 对话历史和当前 prompt 全保留
- [ ] **P1 验证**: editor 输入 "hello" → split → cmd+z 可撤销到空文件
- [ ] **回归**: 关 area / 关 tab / 重排 tab / 拖 tab 跨 area 行为不变
- [ ] **回归**: drop zone 拖拽命中准确
- [ ] **回归**: focus border / 多 split 间 focus 切换 (cmd+w 等快捷键)
- [ ] **回归**: search overlay (cmd+f) 可见且可用
- [ ] **回归**: VCS / Diff pane (旧路径) 显示正常

### 性能
- [ ] split 触发的 layout 不掉帧 (60fps)
- [ ] 多 split (4+ 区域) 切 tab 流畅

---

## 八、Open Questions

1. **VCS/Diff 是否本次也上 layer?** 默认否 (P2 后续). 但若实施过程中发现 chrome layer 路径已能轻松接入, 可顺便迁移. 决策点: PR-3 完成后评估.
2. **Editor undo 栈跨 split 保留, 是否会引入新的 undo 范围 bug?** 现行 `removeAllActions` 是悲观清理. 改后 undo 栈跨 SwiftUI 重 mount 保留, 但 `EditorTabState.backingStore` 若被外部 reload (文件被外部修改 → 重新 load), undo 应否清? 现有逻辑如何处理? 须查 EditorTabState.replaceContents / reload 路径.
3. **`AreaFramePreferenceKey` 是否仍可靠?** 当前由 TabAreaView 上报 (TabAreaView.swift:184-193). 改成 chrome 上报后, chrome 的 frame 与 layer 内 entry frame 是同一计算 (areaFrames + GeometryReader), 应一致. 但需测试.
4. **macOS 14 / 15 / Sequoia 行为差异**: `.id()` 在 ForEach 内对 NSViewRepresentable 的稳定性是否所有 OS 版本一致? 需在最低支持版本 (macOS 14) 上手测.

---

## 八之二、Subagent review 待处理项 (post-spike)

### 选 Spike A (Host Layer) 后必须处理

- **#2 areaFrames divider 厚度**: `SplitContainer.swift:23-25` 子区宽 = `total*ratio - 0.5`, 但 `SplitNode.areaFrames(in:)` (SplitNode.swift:172-184) 直接用 ratio 切, **不减 divider 厚度**. 两层 split 后累加偏移. 修法: 加 `areaFrames(in:dividerThickness:)` overload, chrome 与 layer 共用同一计算; 或 chrome 也用 frame+offset 不再 HStack/VStack.
- **#5 EditorPane 内部 if/else 切换**: EditorPane.swift:15-23 按 `awaitingLargeFileConfirmation/isLoading/errorMessage/editorContentLayer` 切换. 上 layer 后内部切换仍触发 dismantle. 必须把 NSScrollView 移出 EditorPane.editorContentLayer, chrome 只渲染状态壳.
- **#6 showTabStrip 翻转致 layer 偏移**: Workspace.swift:31 当 root 从 `.tabArea` → `.split` 时 showTabStrip 由 false 变 true, chrome 多出 29px tab strip 高度但 layer 不感知. chrome 与 layer 必须共用同一外层 GeometryReader 后再扣 strip 高度.

### 选 Spike B (Registry-defang) 后必须处理

- **#1 显式不变量**: registry MUST 保证 `view(for:)` idempotent, makeNSView 永远拿到 existing. 必须把这条作为 load-bearing invariant 写入 registry 文件头注释 (本 codebase 默认 no comments, 此处例外因维护性远大于规则).
- **CLAUDE.md 改文**: `## NSViewRepresentable Pitfalls` 节需重写, 把"never return cached/reused NSView"改成"the cache is the lifecycle owner, makeNSView intentionally returns existing".

### 双方均需处理

- **#4 MarkdownWebView (`Muxy/Views/Markdown/MarkdownTabView.swift:17`)**: WKWebView NSViewRep, EditorPane.swift:90-105 三态切 `code/preview/split` 时 dismantle WebView → JS state / scroll / image cache 全丢. 本 doc §一表未列, 必须显式声明为 P3 (后续) 或本次 P1 顺带.
- **#7 测试加权**: dismantle 计数器升级为 **primary gate**, "PID 不变"降为辅证 (因 agent pane 重 attach tmux 在同 PID 是假象通过). 加 cross-area drag 测试 (TerminalPane.swift:167 areaID + TerminalPane.swift:252 闭包重绑验证). macOS 14/15/26 矩阵从 Open Q 升入测试 row.
- **PR-1 价值**: subagent #9 指出单 area 场景"不 dismantle"无意义, 因为没结构变化本来就不 dismantle. 建议 **合并 PR-1 进 PR-2**, 直接在 split 场景交付价值.

## 九、实施进度

- ✓ **PR-2 (P0)**: Terminal pane 上 layer. `ContentHostLayer` + `TerminalPaneChrome` 拆分, 验证通过.
- ✓ **PR-3 (P1)**: Editor pane 上 layer. CodeEditor + EditorPane chrome 拆分, undo 栈跨 split 保留.
- ✓ **P2**: DiffViewerPane 上 layer. 滚动位置/选区跨 split 保留.
- ✓ **P3**: MarkdownWebView 上 layer. `MarkdownPaneContent` 把 CodeEditor 和 MarkdownWebView 共置 ZStack, 模式切换走 frame/opacity 不 dismantle. JS state / scroll / image cache 跨 split 与 mode 切换保留.

## 十、Out-of-scope (后续)

- VCSTabView 仍纯 SwiftUI, 不需上 layer (确认无 NSViewRep 内嵌).
- markdown split mode 用户拖动调整比例: 当前固定 50/50, 失去 HSplitView 旧的 drag 行为. 后续可加 `state.markdownSplitRatio` + 自定义 drag handle.
- TerminalViewRegistry cache 语义优化 (现行 `view(for:)` 仍 tearDown 旧 view; 但本次改造后该路径不再被 SwiftUI dismantle 触发, 仅在 explicit `removeView` 时调用, 影响面缩小)
- 引入 NSSplitView 重写 SplitContainer (替代方案, 已评估后否决)
