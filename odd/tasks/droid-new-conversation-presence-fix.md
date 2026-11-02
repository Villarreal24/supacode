# droid-new-conversation-presence-fix

Engram mirror topic: `odd/droid-new-conversation-presence-fix/tasks` (status: synced, observation #1511, project `supacode`)
Branch: `feat/factory-droid-integration`
Plan: `~/.claude/plans/vamos-ahora-a-analizar-foamy-wadler.md`

## Objective
Keep a Factory Droid tab in the Active agents group when the user applies a spec in a NEW conversation.

## Problem
Presence is keyed by `(agent, surface)` plus a pid set, with no session id. The old session's `sessionEnd` removes the pid and deletes the record (`AgentPresenceFeature.swift:201-211`). Later pid-bearing `busy` events cannot re-seed it (`:303`), so the tab stays out of Active until Droid finishes.
Root cause is inferred from code, not confirmed at runtime (Droid's SessionStart/SessionEnd order and ppid are unverified; user chose to skip runtime logging).

## Decision (judgment-day, both judges agree)
Candidate B: Droid `UserPromptSubmit` and empty-matcher `PreToolUse` hooks emit `[.sessionStart, .busy]`, re-establishing presence through the idempotent `applySessionStart`. Droid-scoped, no shared-reducer change.
Rejected: A (re-seed pid-bearing busy in `applyActivity`): changes semantics for all agents, breaks `pidBearingActivityWithoutPresenceDoesNotSeed` and `busyWithoutPresenceIsDropped`, ghost-badge risk.

## Scope
- `SupacodeSettingsShared/BusinessLogic/DroidHookSettings.swift`
- `supacodeTests/DroidSettingsInstallerTests.swift`
- `supacodeTests/AgentPresenceFeatureTests.swift`
- This document.

## Constraints
- No shared reducer change. No push, no PR. Conventional Commits, no AI attribution (user's global CLAUDE.md).
- Stage only touched files. About 400 changed-line heuristic per task is advisory only.
- Delivery strategy: `ask-on-risk`. Forecast is well under 400 authored changed lines.

## Tasks
- [x] T1 RED: add `.droid` reducer tests (end/start orderings) in `AgentPresenceFeatureTests.swift`; run and observe RED, or document the exception.
- [x] T2 GREEN: `[.sessionStart, .busy]` composite on `UserPromptSubmit` and empty-matcher `PreToolUse` in `DroidHookSettings.swift`, header comment, plus installer test fixtures.
- [x] T3 VERIFY: `make test` and `make build-app`; record results here.

## Routes
- T1: inline. One test file, design already understood, no research.
- T2: inline. Two small files, one mechanical change plus fixtures; fewer than 2 non-trivial files, so the writer trigger does not fire.
- T3: inline bash for build/test.
Trigger evidence: no mapping (under 4 files), no broad research.

## Acceptance criteria
- Reducer tests prove the record survives `sessionEnd(P)` followed by `sessionStart(P)+busy`, and re-adds on `sessionEnd(P)` then `sessionStart(P)`.
- Droid installer reports old hooks as outdated and new hooks as installed.
- `make test` and `make build-app` pass.

## RDD ledger
RDD mode: on (global). Review boundary for this feature: `d84431bc` (HEAD before this feature's first commit; the 9 earlier commits on the branch belong to other work).
- Work unit 1 (`725e0c81`, T1-T3): `gentle-ai review assess --committed-only --base-ref HEAD~1` with `--untracked-scope=exclude` (user chose to exclude `.atl/` and `odd/tasks/supacode-upstream-sync.md`): tier medium (`executable_change`), 4 paths, 134 changed lines, `review_due=false`, reason `under_budget`. Outcome: no review now; stays pending in the slice. Boundary not advanced.
- First assess without the untracked declaration failed as `unassessable` (treated as high/due); resolved by the declaration above.

## Commits
- `725e0c81` fix(droid): re-register presence on prompt and tool hooks (T1, T2, T3)

## Progress
- Document created; Engram mirror #1511 synced.
- T1 done: RED observed (run 2): only `promptAndToolHooksReestablishPresenceBeforeBusy` failed. Characterization tests `droidSessionStartAfterSessionEndReregistersSameProcessPid` and `droidBusyAfterSessionEndWithoutStartStaysDropped` passed.
- T2 done: `presenceAndBusy` composite (`[.sessionStart, .busy]`) on `UserPromptSubmit` and empty-matcher `PreToolUse` in `DroidHookSettings.swift`; header comment updated.
- T3 done: tests, lint and app build green.

## Verification evidence
- `make test` run 1: runners hung before connecting (macOS permission dialog for Supacode not yet approved by the user); no assertions ran. Not a RED.
- `make test` run 2 (RED): `TEST FAILED`, exactly 1 failure, the new installer test.
- `make test` run 3 (GREEN): `TEST SUCCEEDED`; the 3 new tests pass.
- `swift-format lint` on the 3 changed files: clean. `make build-app`: Build Succeeded.
- Not verified: real Droid runtime behavior (SessionStart/SessionEnd order, ppid). Needs manual run after reinstalling Droid hooks.

## Next step
Manual validation in the app: reinstall Droid hooks in Settings (old hooks show outdated), run a spec and apply it in a new conversation; the tab must stay in Active. If the tab still flickers, capture hook order/pids (residual risk: old SessionEnd landing after new-session events).
