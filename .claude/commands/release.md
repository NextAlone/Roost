---
allowed-tools: Bash(jj *), Bash(gh *), Bash(perl *), Read, AskUserQuestion
description: 触发 GitHub Actions Release workflow 发布新版本 (默认 patch 自增；可传 X.Y.Z / minor / major / watch)
argument-hint: "[X.Y.Z|patch|minor|major] [watch|nowatch] [draft]"
---

## 说明

Roost 的 release 流程由 `.github/workflows/release.yml` 完全自动化：workflow 自己跑 `scripts/update-release-metadata.sh` 改 `nix/package.nix` (version + sha256)、两个 `Info.plist`、`docs/*`、`RELEASE-CHECKLIST.md`，提交 `chore(release): prepare v<X.Y.Z>` push 回 `main`，再建 `v<X.Y.Z>` tag + GitHub Release。

本命令只负责**前置校验** + **触发 workflow**，不要在本地手动改版本号或 nix hash。

## Context

- 当前 nix 版本: !`grep -E '^\s*version\s*=' nix/package.nix | head -1`
- 当前修订: !`cd "$(jj root --ignore-working-copy 2>/dev/null || pwd)" && jj log -r '@ | @-' --no-graph`
- 工作副本状态: !`cd "$(jj root --ignore-working-copy 2>/dev/null || pwd)" && jj st`
- main bookmark: !`cd "$(jj root --ignore-working-copy 2>/dev/null || pwd)" && jj bookmark list main 2>/dev/null`

## 参数

「$ARGUMENTS」

## Task

### 1. 解析参数

- 版本部分：`X.Y.Z` 直接用；`patch`/无 → 读 `nix/package.nix` 当前版本 patch+1；`minor` → minor+1 patch=0；`major` → major+1 minor=0 patch=0
- `watch`/无 → 后台 watch；`nowatch` → 触发后立即返回
- `draft` → workflow 输入 `draft=true`；无 → `draft=false`

### 2. 前置校验（任何一项失败立即停止，不要尝试自动修）

a. **工作副本干净**：`jj st` 必须显示 `The working copy has no changes`。否则提示用户先 `/commit` + `/push`。

b. **`@-` 必须已描述**：`jj log -r @- -T 'description' --no-graph` 非空。否则提示用户先 `/commit`。

c. **`main` bookmark 已 push 到 origin**：
   ```
   jj git fetch
   jj log -r 'main@origin..main' --no-graph
   ```
   若有输出（本地领先），停止并提示用户先 `/push`。

d. **签名校验**：
   ```
   jj log -r '(main@origin..main | main) & mine()' -T 'change_id.shortest() ++ " " ++ if(signature, signature.status(), "NONE") ++ "\n"'
   ```
   出现 `UNSIGNED` / `NONE` 即停止。不允许改 `signing.behavior` 或 `--no-verify`。

e. **tag 不存在**：
   ```
   gh release view v<X.Y.Z> --repo NextAlone/Roost
   ```
   若返回 0（已存在），停止并报错。

### 3. 发布内容确认（必须执行）

在触发 workflow 前，必须展示本次 release 将基于 `main` 发布的内容，并用 `AskUserQuestion` 让用户确认；用户未确认则停止，不得触发 workflow。

必须运行并汇报：
```
jj log -r 'latest(tags() & ::main, 1)..main' --no-graph -T 'change_id.shortest() ++ " " ++ commit_id.shortest() ++ " " ++ description.first_line() ++ "\n"'
jj diff --git -r 'latest(tags() & ::main, 1)..main' --stat
```

确认问题必须明确包含：
- 目标版本 `<X.Y.Z>`
- workflow ref 是 `main`
- 上面列出的提交摘要
- 若列表为空，必须提示“本次发布没有功能提交差异”，并默认推荐停止

### 4. 触发 workflow

```
gh workflow run Release --repo NextAlone/Roost --ref main \
  -f version=<X.Y.Z> \
  -f draft=<true|false>
```

成功后拿到 run URL：
```
sleep 3
gh run list --workflow Release --repo NextAlone/Roost --limit 1 --json databaseId,url,status,headBranch
```

> 注意：workflow 跑完会**自动 push 一个新的 `chore(release): prepare v<X.Y.Z>` commit 到 main**。本地 `main` 会落后 origin/main 一个 commit，下次开工前先 `jj git fetch && jj retrunk`。

### 5. Watch（默认）

后台跑：
```
gh run watch <run-id> --repo NextAlone/Roost --exit-status
```

用 `run_in_background: true` 启动，告知用户 run URL + 后台 ID，**不要** sleep / poll，完成后系统会自动通知。

`nowatch` 模式跳过此步。

## 安全约束

- **不允许**本地手动改 `nix/package.nix` 版本或 hash；workflow 自己来
- **不允许**本地手动建 `v<X.Y.Z>` git tag；workflow 用 `gh release create` 建
- **不允许** workflow 失败后自动重跑；先汇报失败 stage，让用户决定
- **不允许**为了通过校验 squash / amend 已 push 的修订
