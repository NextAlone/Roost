---
allowed-tools: Bash(scripts/build-release.sh:*), Bash(grep:*), Bash(uname:*), Bash(jj st), Bash(open:*), Bash(ls:*), Read, AskUserQuestion
description: 本地打 .app/.zip 包 (默认 release; 传 dev 走 ad-hoc 签名 + DEV_MODE bundle id)
argument-hint: "[dev] [X.Y.Z] [arm64|x86_64] [zip|dmg]"
---

## 说明

本命令调 `scripts/build-release.sh` 在本地 `build/` 产出 `Roost.app` + `Roost-<version>-<arch>[-dev].<zip|dmg>`。

- **release** (默认): 走 strip 符号表, 无签名（除非传 `--sign-identity`, 本命令不做）。bundle id `app.roost.mac`, daemon socket `/tmp/roost-hostd-daemon-$uid.sock`。
- **dev**: `-Xswiftc -DDEV_MODE` + ad-hoc 签名, bundle id `app.roost.mac.dev`, XPC `app.roost.mac.hostd-dev`, daemon socket `/tmp/roost-hostd-daemon-dev-$uid.sock`, 应用名 "Roost Dev"。可与正式版同时安装。

不触发 GitHub Actions workflow, 也不动版本号/nix hash。要发版走 `/release`。

## Context

- 当前 Info.plist 版本: !`grep -A1 CFBundleShortVersionString Muxy/Info.plist | tail -1 | sed -E 's/.*<string>(.*)<\/string>.*/\1/'`
- 主机架构: !`uname -m`
- 工作副本状态: !`jj st`

## 参数

「$ARGUMENTS」

## Task

### 1. 解析参数

按 token 顺序无关地匹配（每个 token 任意位置）:

| token | 含义 | 默认 |
|-------|------|------|
| `dev` | 走 dev 模式 (`--dev`) | release |
| `X.Y.Z` 或 `X.Y.Z-beta.N` 或 `X.Y.Z-dev[.N]` | 传给 `--version` | 读上方 Info.plist 版本; dev 模式且版本不带 `-dev`/`-beta` 后缀时, 自动追加 `-dev` |
| `arm64` / `x86_64` | 传给 `--arch` | 主机 `uname -m` (Apple Silicon → `arm64`, Intel → `x86_64`) |
| `zip` / `dmg` | 包格式 | `zip` |

参数歧义或冲突时 (例: 传两个版本号) → 停下用 `AskUserQuestion` 问用户。

### 2. 执行

```
scripts/build-release.sh \
  --arch <ARCH> \
  --version <VERSION> \
  [--dev] \
  [--zip|--dmg]
```

build 中可能耗时数分钟 (release 编译 + Sparkle.framework 嵌入 + 图标编译)。**不要中断**。

### 3. 完成后

build 成功后:

- 报告产物路径: `build/Roost.app` 和 `build/Roost-<version>-<arch>[-dev].<zip|dmg>`
- `ls -lh build/Roost-<version>-<arch>*.<ext>` 输出实际大小确认
- 若 dev 模式, 提示用户:
  - 包与正式版可共存（不同 bundle id）
  - 安装/运行前先 `kill <旧 daemon pid>` + `rm -f /tmp/roost-hostd-daemon-dev-$(id -u).sock`，否则旧 daemon 拦截连接
  - 走 dev socket 路径: `/tmp/roost-hostd-daemon-dev-<uid>.sock`
- 不要 `open build/Roost.app` 自动启动, 让用户自己开
- 不要自动签名/上传; 用户没要求就不做

### 4. 失败处理

- `Sparkle.framework not found`: 跑 `scripts/setup.sh` 拉依赖
- `version must be ...` 校验失败: 检查 release 模式不接受 `-dev` 后缀, 仅接受 `X.Y.Z` / `X.Y.Z-beta.N`; dev 模式才接受 `-dev`/`-dev.N`
- swift build 编译报错: 不要尝试自动修, 汇报报错位置让用户决定
