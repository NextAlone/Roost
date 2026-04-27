# Phase 2.2c2 — VcsKindDetector.isVcsRepository

> Continuation slice executed inline (small, established pattern).

**Goal:** Route `isGitRepository` callers (`ExpandedProjectRow:60`, `ProjectRow:61`) through a kind-agnostic disk probe so jj projects get the same UI gating treatment.

**Architecture:** Add `VcsKindDetector.isVcsRepository(at:) -> Bool` that returns true iff either `.jj` or `.git` is present. Two view callers replace `await GitWorktreeService.shared.isGitRepository(...)` with the synchronous helper. Variable `isGitRepo` renames to `isVcsRepo` for accuracy. Slight semantic widening: a path with broken-but-present `.git` previously returned false (per `git rev-parse`); now returns true. Acceptable for sidebar gating; full repo-validity check is a UI concern handled separately when actually invoking VCS commands.

**Out of scope:** `VCSTabState.deleteBranch` (Phase 2.2c3), DTO/UI badges (2.2d).

## Tasks

1. Add `VcsKindDetector.isVcsRepository(at:)` + tests
2. View callers route + rename
3. Plan note
