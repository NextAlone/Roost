# Roost

macOS 原生、jj 一等公民的多 agent 终端编排器。

> Status: **pre-alpha** / 设计阶段。没有可用产物。

## 定位

并行跑多个 CLI 编码 agent（Claude Code / Codex / Gemini CLI / Cursor Agent 等），每个 agent 住在独立的 jj workspace。macOS 原生 UI，libghostty 渲染终端，Rust 后端管状态和编排。

和已有工具的关系：

- 对标 [`manaflow-ai/cmux`](https://github.com/manaflow-ai/cmux)：加目录分组和多 agent 编排视图。
- 对标 [`Dcouple-Inc/Pane`](https://github.com/Dcouple-Inc/Pane)：改成 macOS 原生 + jj 原生，不做跨平台。
- 对标 [`superset-sh/superset`](https://github.com/superset-sh/superset)：沿用分组展示，但抛掉 Electron。

## 技术栈

- 前端：SwiftUI + AppKit，libghostty 做 GPU VT 渲染。
- 后端：Rust（tokio + sqlx + swift-bridge），负责 jj workspace、agent 生命周期、状态持久化。
- VCS：只支持 [jj](https://github.com/jj-vcs/jj)。

## Roadmap

见 [`design.md`](./design.md)。当前目标：

- **M-1**：libghostty + SwiftUI POC，验证终端渲染可行。
- **M0**：端到端跑通一个 agent（1 project × 1 workspace × 1 session）。
- **M1+**：多 session tab、jj workspace 管理、目录侧边栏、OSC 通知……

## License

暂未选择。先 pre-alpha 开发，发第一版前决定（倾向 MIT 或 Apache-2.0）。
