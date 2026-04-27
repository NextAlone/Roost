# Phase 2.2e — VCSTabState vcsKind awareness + jj no-op guards

> Continuation slice executed inline. Defensive scope; full jj VCS UI is Phase 5.

**Goal:** Stop VCSTabState from issuing git commands on jj projects. Add a `vcsKind` property derived via `VcsKindDetector` at init, and short-circuit the read entry points (`performRefresh`, `loadBranches`, `loadCommits`) when `vcsKind != .git`. UI gracefully shows empty state for now; Phase 5 fills in jj-native data.

**Architecture:** `VCSTabState` already takes `projectPath` in init. Add stored `private(set) var vcsKind: VcsKind` and resolve it once in init via `VcsKindDetector.detect`. Top-level read methods early-return when not git. Mutating methods (commit / push / pull / cherryPick / revert / branch / tag / checkout) are gated only if their UI is reachable — those typically aren't reachable when reads are empty, so leaving them untouched is safe; if a jj user somehow triggers one, the underlying git service errors and the existing `showStatus` error path surfaces it. Acceptable for this slice.

**Out of scope:**
- Full jj equivalence for branches/commits/status/PR (Phase 5 Changes Panel)
- Mutating-op gates (low risk in practice; covered by view rendering)
- UI label refinement

## Tasks

1. Add `vcsKind` to VCSTabState + init via detector
2. Gate `performRefresh`, `loadBranches`, `loadCommits` early
3. Plan note
