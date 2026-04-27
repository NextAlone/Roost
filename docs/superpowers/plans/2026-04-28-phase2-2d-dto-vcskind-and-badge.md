# Phase 2.2d — WorktreeDTO carries vcsKind + sidebar jj badge

> Continuation slice executed inline.

**Goal:** Mobile IPC + UI surface jj awareness. Move `VcsKind` to MuxyShared (DTO needs it); add `vcsKind` field to `WorktreeDTO`; update converter; add a small "jj" badge to `ExpandedProjectRow` worktree row when `vcsKind == .jj`.

**Architecture:** `VcsKind` becomes `public` in `MuxyShared/Vcs/VcsKind.swift`. The 7 existing Roost-target files that reference it gain `import MuxyShared`. `WorktreeDTO` adds `vcsKind: VcsKind` with tolerant `decodeIfPresent` defaulting to `.git`. `Worktree.toDTO` passes through. The badge is a minimal SF-Symbol or text indicator next to the worktree name when its kind is jj.

**Out of scope:** UI label refinements ("branch" → "bookmark" for jj), full VCSTabState read-side abstraction.

## Tasks

1. Relocate VcsKind to MuxyShared
2. WorktreeDTO gains vcsKind + tolerant decode
3. toDTO converter + round-trip test
4. Sidebar jj badge
5. Plan note
