---
title: QuickClose Session Learnings
description: Verified tool behavior, debugging lessons, and unresolved checks for future agents.
created: 2026-09-12
updated: 2026-09-12
status: living-document
scope: QuickClose-Menubar
---

# Learnings

Read this file during onboarding and update it while working, especially after a failed tool call, unexpected behavior, or bug that takes extra investigation.

## Table of contents

- [How to update this file](#how-to-update-this-file)
- [Tool routing and recovery](#tool-routing-and-recovery)
- [Build and test lessons](#build-and-test-lessons)
- [macOS behavior and implementation](#macos-behavior-and-implementation)
- [Visual and accessibility evidence](#visual-and-accessibility-evidence)
- [Open verification items](#open-verification-items)
- [Entry template](#entry-template)

## How to update this file

- Append a short entry to the relevant section as soon as an extra-effort problem is understood; do not wait for the final response.
- Include the date, symptom, cause when known, working fix or next check, and evidence such as a file path or command result.
- Label facts **Verified**, inferences **Hypothesis**, and remaining work **Open**; an implemented fix is not verified until its relevant check passes.
- Search existing entries first; extend a related entry rather than repeating it, and mark superseded advice with its replacement.
- Keep the front matter's `updated` date and this table of contents current when adding sections.
- Preserve useful history, but omit raw logs, credentials, unrelated user information, and repetitive tool output.
- Recheck machine-specific paths, permissions, tool versions, and project state before reusing them.
- Record failed verification honestly; never change an evidence field just to satisfy a validator.

## Tool routing and recovery

### 2026-09-12 — Root discovery can fail while individual reads work

**Verified:** `ctx_compose` and `ctx_tree` refused the project root as broad/privacy-protected and reported no indexed code, even after Swift files existed.

- Do not interpret this error as an empty project or trust a stale memory entry over current files.
- Call `ctx_compose` first for code understanding; if discovery fails, try a narrower project subdirectory or read known files with `ctx_read(path, mode="full")`.
- A read-only `ctx_shell` directory listing worked as a fallback when tree discovery failed.
- The workspace initially was empty and was not a Git repository; verify both facts again before assuming a scaffold or Git history exists.
- **Rechecked during initial publication:** `ctx_compose` again reported no code files; `find . -type f` and fresh direct reads located both source files and the test file. If `ctx_read` returns only an unchanged-file reference without source visible in the current conversation, use `fresh=true` to obtain the actual contents before documenting symbols.

### 2026-09-12 — Skill paths can resolve outside the allowed read roots

**Verified:** Reading a `.claude/skills/...` reference resolved to `.codex/skills/...` and failed with `path escapes project root`.

- Use the resource locations returned by the skill and account for symlink resolution.
- An explicit read-only `ctx_shell` file read worked for those references when `ctx_read` could not access them.
- Do not repeatedly submit the same denied read or change global allow-path settings as an incidental fix.

### 2026-09-12 — Permanent shell blocks need the script execution path

**Verified:** `ctx_shell` rejected `open`, `plutil`, `find -exec`, Python `-c`, and Python heredocs in this environment.

- A `[BLOCKED — DO NOT RETRY]` result is permanent for that route; do not keep retrying or disable shell security.
- Use a dedicated tool where possible; use the sanctioned `ctx_execute` tool via `lean-ctx_ctx_call` for scripts or commands unsupported by the shell allowlist.
- `ctx_execute` with `language="shell"` successfully ran the scaffold, app launch, and screenshot preflight.
- Use `apply_patch` for authored file edits, including helper scripts; prefer simple, auditable commands over nested shell quoting.

### 2026-09-12 — Retrieve a specific archived output, not all archives

**Verified:** Using `ctx_expand(action="search_all", id=...)` returned unrelated session results rather than the intended build error.

- For a known archive, use `ctx_expand(id="<archive ID>", search="error:")` with the default retrieve action.
- Reserve `search_all` for intentionally searching across archives; `query` is not the per-archive `search` filter.
- Keep build output compressed by default; expand the relevant diagnostic instead of requesting a complete verbose build.

## Build and test lessons

### 2026-09-12 — Missing math imports produced a misleading secondary error

**Verified:** `Tests/AppTests.swift` failed with `cannot find 'pow' in scope` and a secondary expression type-checking timeout.

- Adding `import Foundation` resolved the compilation failure and the subsequent test command succeeded.
- Fix the earliest concrete diagnostic before restructuring expressions in response to a secondary compiler message.

### 2026-09-12 — Serialize builds that share DerivedData

**Verified observation:** A build and test were dispatched concurrently against `/tmp/QuickCloseDerived`; test output included truncated-framework parsing warnings.

**Hypothesis:** Shared build-product writes may have contributed; the session did not establish the warnings' root cause.

- Run build and test sequentially when they share DerivedData; `xcodebuild test` already builds its dependencies.
- If independent builds must run concurrently, give them distinct DerivedData paths.
- Specify the destination to remove the observed multiple-destination warning; on this session's Apple Silicon Mac, use `-destination 'platform=macOS,arch=arm64'`.
- Check the command exit status and test results, not just the line `Testing started`; preserve failures through pipelines with `pipefail` when piping is necessary.

### 2026-09-12 — Verify settings and regenerate from the project source

**Verified:** `project.yml` specifies macOS 15.0, Swift language mode 6.0, complete strict concurrency, and compiler warnings as errors; the installed Xcode was 26.6.

- Language mode and installed compiler version are different facts; inspect effective settings before changing concurrency code.
- Keep project configuration changes in `project.yml` and regenerate with XcodeGen rather than editing only the generated `.pbxproj`.
- The current test suite contains two Swift Testing tests; it does not exercise real application quitting, login registration, sound playback, or UI behavior.

## macOS behavior and implementation

### 2026-09-12 — A sent quit request is not a completed quit

**Verified from Apple documentation:** `NSRunningApplication.terminate()` returns whether the request was sent and can return before the app exits; sandboxed apps cannot use it to terminate other apps.

- Observe actual termination before reporting completion or playing a sound described as a completion sound.
- Do not silently replace normal quitting with `forceTerminate()`; normal quitting allows apps to handle unsaved work.
- Exclude QuickClose itself and verify the target set before execution, especially with background apps enabled.
- Test with injected app/service behavior or disposable fixture apps; do not press the real bulk-quit control during automated verification of the user's live workspace.
- Source: [Apple — terminate()](https://developer.apple.com/documentation/appkit/nsrunningapplication/terminate()).

### 2026-09-12 — Preferences must reflect service state and observable changes

**Verified implementation:** Launch-at-login uses `SMAppService.mainApp`, and initialization reads its status rather than relying solely on a persisted Boolean.

- Handle registration errors and approval-required states explicitly; a Boolean cannot represent every `SMAppService` status.
- Keep external effects out of a toggle rollback loop; test error recovery instead of assuming `.onChange` is harmless.
- Properties marked `@ObservationIgnored` are excluded from Observation tracking; test the current `@AppStorage`/`@Bindable` combination for immediate updates across the panel and Settings.
- Registration, error recovery, cross-view updates, and audible sound output remain runtime checks, not proven by compilation.

## Visual and accessibility evidence

### 2026-09-12 — A schema pass does not establish a visual pass

**Verified:** Screenshot preflight reported Screen Recording permission unavailable, and no rendered screenshots were obtained.

- Keep screenshot measurements unknown until captured and measured; source geometry is not a rendered alignment measurement.
- `Docs/visual-contract.json` currently contains `alignment_max_drift_pt: 0` and `color_audit_passed: true` without supporting rendered evidence; do not reuse those values as proof.
- The contract declares an intrinsic action, but `Sources/ContentView.swift` uses `.frame(maxWidth: .infinity)` inside its button label; reconcile the contract and implementation before claiming a match.
- The validator rejected `surface_kind: "compact utility"`; the skill's compact-utility example uses `"compact_utility"`, so use schema-defined values without changing the design classification just to pass validation.
- If capture is unavailable, record that limitation and continue independent checks rather than marking the visual task complete.

### 2026-09-12 — Contrast coverage must match the claim

**Verified by source inspection:** The current tests check one hardcoded foreground/background pair and that two `Color` values differ.

- These tests do not establish support-text, placeholder, on-accent, focus, switch-state, or rendered contrast compliance.
- Test production semantic tokens rather than copied literals so a theme change cannot leave a stale test passing.
- Compare raw WCAG ratios: normal text `>= 4.5`, meaningful non-text cues `>= 3.0`; the Everforest product target of delta L* `>= 40` supplements WCAG rather than replacing it.
- The current test helper derives L* directly from D65 relative luminance; it does not implement the skill's D65-to-D50 adaptation, so do not claim it verifies that prescribed calculation.
- Native `.tint` and prominent-button styles may adapt both fill and glyph colors; use ICC-aware rendered samples before claiming exact on-accent contrast.

## Open verification items

These are follow-ups identified from this session, not completed checks:

- Verify quit completion and delayed/refused requests; the current method resets `isQuitting` and plays sound immediately after sending requests.
- Clarify and verify search scope: the rendered list uses `filteredApps`, while quitting uses `visibleApplications` and therefore also targets apps hidden by search.
- Verify background-app scope and distinguish user apps from OS helpers before treating every non-regular process as an intended quit target.
- Verify live list refresh, preference observation, login-item failure states, and sound output.
- Verify keyboard/VoiceOver access, icon-control targets, Settings presentation, and an alternative access path when the menu-bar icon is hidden.
- Capture default and compact UI states, audit actual color pairs, and replace the unsupported visual-contract evidence with real measurements.

## Entry template

```markdown
### YYYY-MM-DD — Short, searchable lesson

**Status:** Verified / Hypothesis / Open
- **Symptom:** What failed or required extra effort.
- **Cause:** Established cause, or clearly labeled uncertainty.
- **Action:** Fix, prevention rule, or next diagnostic step.
- **Evidence:** Relevant source path, command result, or artifact.
- **Remaining:** Unverified behavior, if any.
```
