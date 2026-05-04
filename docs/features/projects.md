# Projects

A project in Roost is a directory on disk plus a bit of metadata (name, icon, color, last-used IDE). Projects are how Roost groups tabs, splits, and workspaces.

## Adding a project

- Click **+** at the bottom of the sidebar, or use **File → Open Project…** (`Cmd+O`).
- Drag a folder onto the Roost dock icon.
- From a shell: `roost /path/to/project` (after **Roost → Install CLI**).
- Via URL scheme: `roost://open?path=/path/to/project`.

All entry points dedupe — opening the same path twice just activates the existing project.

## Customising appearance

Right‑click a project in the sidebar to:

- **Rename** the project (display name only — does not move the folder).
- **Change icon**: emoji logo or letter badge.
- **Change color**: pick from the preset palette.
- **Remove** the project from Roost (does not delete the folder).

## Switching projects

- **Next / Previous:** `Ctrl+]` / `Ctrl+[`.
- **Project 1–9:** `Ctrl+1…9`.
- Click any project in the sidebar.

Each project keeps its own tabs, splits, and active tab in memory while the app is running.

## Open in IDE

Roost auto-discovers IDE-like apps installed on your Mac (VS Code, Zed, Sublime, JetBrains IDEs, Cursor, ...). The **Open in IDE** topbar button and **File → Open in IDE** menu show what was found and remember your last choice. If an editor tab is active, the IDE is launched at that file's line and column when supported.

## CLI and URL scheme

The bundled `roost` wrapper is installed via **Roost → Install CLI**:

```bash
roost .
roost /Users/me/projects/api
```

URL scheme handler:

```
roost://open?path=/percent-encoded/path
```

Both routes call the same internal handler, so behaviour is identical.

## Persistence

Projects are stored as JSON at `~/Library/Application Support/Roost/projects.json`. Tabs and splits are persisted through Roost's workspace snapshots, and [Layouts](layouts.md) can define a reproducible workspace.

## Settings

- **General → Keep projects open after closing all tabs** keeps an empty project visible in the sidebar after its last tab is closed.
- **General → Auto‑expand worktrees on project switch** opens the worktree list when you switch to a project.
