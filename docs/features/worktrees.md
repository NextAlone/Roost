# Worktrees

Roost is workspace-aware. Every project starts with a primary workspace (the project root) and can have additional jj workspaces or Git worktrees attached. Each workspace has its own tabs, splits, and active selection.

## Worktree picker

When a project is selected, a worktree button appears in the topbar. Click it to:

- See all known worktrees and their branches.
- Create a new git worktree.
- Refresh the list (picks up worktrees created externally with `git worktree add`).

**Switch Worktree:** `Cmd+Shift+O`.

## Creating a worktree

The **New Worktree** sheet asks for:

- **Branch** — existing branch to check out, or a new branch name.
- **Base** — the ref to branch from (when creating a new branch).
- **Path** — where the worktree directory should live on disk.

For Git projects, Roost can run `git worktree add` and then register the new worktree with the project. For jj projects, Roost creates jj workspaces through the jj workspace service.

## Setup commands

If your project has a `.muxy/worktree.json` file with setup commands, they run automatically when a tab is created in a freshly added worktree (e.g. `npm install`, `bundle install`). Use this to bootstrap dependencies for ephemeral worktrees.

## Persistence

Workspace metadata is stored at `~/Library/Application Support/Roost/worktrees/<projectID>.json`. Removing a project also cleans up its workspace records.

## Notes

- Switching worktrees does **not** kill running terminals — they stay alive, you just see a different worktree's tabs.
- The primary workspace (project root) is always present and cannot be deleted from Roost.
