# AGENTS.md

## Project Context

Macnosis is a SwiftUI macOS utility for diagnosing and repairing local `.app` bundles.

Treat it as a focused desktop diagnostic tool first. The primary UX goal is calm, immediate situational awareness about why a local app bundle will or will not launch, with explicit repair actions available only when useful.

## Architecture Guard Rails

- Keep UI and application logic separated. SwiftUI views should compose state and presentation, while inspection, command execution, parsing, caching, settings persistence, repair workflows, and shell wrapping live in core/services/model layers.
- Preserve the source layout pattern: `App`, `Models`, `Services`, `UI`, and the separate `MacnosisCore` library.
- Prefer SwiftUI for all UI. Use AppKit only as a small, isolated bridge for macOS integration that SwiftUI cannot provide cleanly.
- Treat any repair, quarantine removal, entitlement change, or re-signing action as explicit and user-triggered. Do not silently modify app bundles during inspection.
- Keep scripts useful independently of the UI. The SwiftUI app can wrap them, but the shell workflow should remain readable, auditable, and runnable on its own.
- Avoid scattering command-line behavior in views. If a diagnostic or repair command matters, give it a small service/core API.

## Performance Guard Rails

- The app must remain usable while inspection is running. Do not block the window, sidebar selection, detail pane, or repair controls on slow diagnostics.
- Show app metadata as soon as it is available, then fill in diagnostics incrementally as commands finish.
- If one command is slow, timed out, unavailable, or failed, degrade only that section. Continue showing all other available information.
- Run app inspections concurrently. Avoid global serialization unless a specific command requires it for correctness, and prefer per-section pending states over blocking.
- Timeouts are diagnostic facts, not fatal app states. Surface them in technical logs and keep the rest of the report usable.
- Directory intake should be resilient: recursively find `.app` bundles, de-duplicate them, and silently ignore unsupported files.
- Keep filesystem scanning bounded and memory-conscious. Do not load large directory trees or command outputs into memory without a clear need.
- Make slow diagnostics identifiable by app name/path and command, not only by exit code.

## Diagnostic UX

- First screen should be the usable inspection workspace, not a marketing or onboarding page.
- Favor dense, well-aligned diagnostic panels over decorative cards.
- Make app state legible: architecture, signing identity, Developer ID, entitlements, debug attachability, Gatekeeper assessment, quarantine/provenance attributes, nested-code verification, and repair options.
- Use calm status language: checking, healthy, warning, blocked, repaired, unsigned, quarantined, debuggable, non-debuggable.
- Missing information should read as `Checking`, `Unknown`, or `Pending`, never as a failure unless the command actually failed.
- Repair controls should make consequences clear before modifying a bundle.
- Keep technical logs available, but behind disclosure or detail affordances so the primary diagnostic page remains readable.
- Use icons as compact state carriers, but pair them with text in detail panels and provide hover detail for compact badges.

## Information Hierarchy

- Use the inspected app name and icon as the primary identity. Show full package names where ambiguity is likely.
- Keep the sidebar for switching among inspected app bundles. It should stay responsive during inspection and repair work.
- Put high-level diagnosis in panels before raw command output.
- Keep full paths, command lines, exact exit codes, and dense logs in secondary surfaces.
- If a row has only partial data, show whichever completed signals are available and leave unfinished signals out or marked pending.

## Hover And Tooltip Behavior

- Use hover for supplemental detail, not for primary information required to operate the app.
- Prefer calm, delayed, lightweight detail reveals over large system tooltip balloons.
- Cancel delayed hover work when the pointer leaves, and hide hover state on focus loss.
- Tooltips and popovers must work in both light and dark themes with readable contrast.
- Avoid oversized pointer callouts that cover the content the user is inspecting.

## Visual Style

- Calm beats clever. Use restraint, alignment, and spacing before adding decoration.
- The app should feel like a polished macOS utility: dense enough to be useful, quiet enough to leave open.
- Avoid noisy cards, nested cards, large rounded blocks, ornamental backgrounds, and layout jiggle.
- Use a harmonious diagnostic palette. Warning colors should escalate without looking random or harsh.
- Keep light and dark themes equally designed; do not treat light mode as an afterthought.
- Text must never overlap, clip awkwardly, or escape its intended area.
- Align peer controls and diagnostic panels precisely. Small width and spacing mismatches are visible in a utility UI.
- Use subtle animation only when it improves continuity. Remove animations that cause reflow, popup repositioning, or delayed comprehension.

## Accessibility And Localization

- Do not rely on color alone for meaning where text, icon shape, or status wording can clarify the state.
- Keep hit targets comfortable for sidebar rows, toolbar icons, repair actions, and disclosure controls.
- Provide useful labels/tooltips for icon-only actions.
- Keep visible strings consistent and ready to localize. If localization resources are introduced, all new UI text should go through them rather than being scattered through views.

## Verification

Before finishing behavior changes, run:

```bash
swift build
swift test
git diff --check
scripts/package-app.sh
```

For app UI changes, use the packaged app for the edit-check loop:

```bash
scripts/package-app.sh
pkill -x Macnosis || true
open .build/Macnosis.app
sleep 1
pgrep -x Macnosis
```

Inspect the real app after relaunch for layout-sensitive SwiftUI changes. Do not rely only on code review for spacing, hover states, icon rendering, text clipping, overlap, focus highlights, resizable split views, light/dark contrast, or incremental loading behavior.
