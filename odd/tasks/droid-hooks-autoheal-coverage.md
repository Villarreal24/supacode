# droid-hooks-autoheal-coverage

Engram mirror topic: `odd/droid-hooks-autoheal-coverage/tasks` (status: pending until first save is read back)
Branch: `feat/factory-droid-integration`
Plan: `~/.claude/plans/vamos-ahora-a-analizar-foamy-wadler.md`
Related: `odd/tasks/droid-new-conversation-presence-fix.md` (commit `725e0c81` changed the Droid hook shape).

## Objective
Lock the guarantee that Droid's previously installed hooks are detected as outdated and healed automatically, like Claude's, so the presence fix reaches existing installs.

## Problem
The user asked for Droid hooks to install automatically when Droid is detected, "like Claude". Verified: Claude does not auto-install on detection either. The only automatic path is generic (`SettingsFeature.swift:550-599`): an `.outdated` integration is re-installed once per session per target. Fresh installs are manual. Droid already goes through this path (`AgentIntegrationFactory.swift:28`, `DroidSettingsInstaller.installState()`), but no test covers a Droid drift heal. On this machine the running app (`/Applications/supacode.app`) predates `725e0c81`, so `~/.factory/hooks.json` still has the old hook shape.

## Decision (user)
Scope = cover what exists. No behavior change; no fresh-install auto-install.

## Scope
- `supacodeTests/DroidSettingsInstallerTests.swift`
- `supacodeTests/SkillAgentTests.swift`
- This document.

## Constraints
- No production code change. No push, no PR. Conventional Commits, no AI attribution (user's global CLAUDE.md).
- Stage only touched files. Never touch `odd/tasks/droid-new-conversation-presence-fix.md` content beyond reading, nor `supacode-upstream-sync.md`.
- About 400 changed-line heuristic per task is advisory only. Forecast: under 100 lines.
- Delivery strategy: `ask-on-risk`.

## Tasks
- [x] T1 characterization test in `DroidSettingsInstallerTests.swift`: pre-fix hooks read `.outdated`, `installAllHooks()` heals them, user hook survives.
- [x] T2 factory-level test in `SkillAgentTests.swift`: `AgentIntegrationFactory.make(for: .droid, ...)` drifted hooks -> `.outdated` -> install -> `.installed`.
- [x] T3 verify: `make test`, `make build-app`, `swift-format lint`.
- [ ] T4 manual validation (user-run): build containing `725e0c81`, open app, `~/.factory/hooks.json` `UserPromptSubmit` gets `session_start`.

## Routes
- T1, T2: inline. Two small test files, design understood, no research; fewer than 2 non-trivial files of production code.
- T3: inline bash.
- T4: user.
Trigger evidence: no mapping (under 4 files), no broad research.

## ODD test-first exception
Behavior already exists (outdated detection and heal). T1 and T2 are regression coverage and are expected to pass on first run; no RED is invented. If one fails, investigate before touching production code.

## Acceptance criteria
- T1 and T2 pass; whole suite green; build and lint clean.
- Drift heal verified for Droid at installer and factory level, preserving user hooks.

## RDD ledger
RDD mode: on (global). Last reviewed boundary: `d84431bc` (nothing reviewed yet; boundary not advanced).
- Work unit (`948451ca`): assess `--committed-only --base-ref a282fc26` with `--untracked-scope=exclude` (user chose to exclude `.atl/` and `odd/tasks/supacode-upstream-sync.md`): tier medium (`executable_change`, test file), 3 paths, 164 changed lines, `review_due=false`, `under_budget`.
- Accumulated slice since `d84431bc` (both features): 6 paths, 299 changed lines, medium, `review_due=false`, `under_budget`. Next commit that reaches ~400 lines makes the slice due.

## Commits
- `948451ca` test(droid): cover outdated hook heal on install (T1, T2, T3)

## Progress
- Document created; Engram mirror #1513 synced.
- T1 done: `preFixPromptHooksReadOutdatedAndHealOnInstallKeepingUserHooks` (DroidSettingsInstallerTests). Passed on first run, as expected (ODD exception: behavior already existed).
- T2 done: `integrationFactoryHealsDriftedDroidHooksThroughInstall` (SkillAgentTests). Passed on first run.
- T3 done: full suite, lint and app build green.
- T4 pending (user-run).

## Verification evidence
- `make test`: `TEST SUCCEEDED`; both new tests passed.
- `swift-format lint` on the 2 touched files: clean. `make build-app`: Build Succeeded.
- Not verified: real app behavior (T4); Droid reading hooks.json at startup.

## Next step
T4 (user): run a build containing `725e0c81`/this commit, open the app, then `jq '.UserPromptSubmit' ~/.factory/hooks.json` must contain `session_start`; restart any running Droid session.
