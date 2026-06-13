# AGENTS.md

## Project Context

Macnosis is a SwiftUI macOS utility for diagnosing and repairing local `.app` bundles.

The app should feel like a focused desktop tool: clear inspection, explicit local repair actions, and enough macOS-specific detail to explain why a bundle will or will not launch.

## Architecture Guard Rails

- Keep UI and application logic separated. SwiftUI views should compose state and presentation; inspection, command execution, parsing, and repair workflows belong in core/services/model layers.
- Preserve the source layout pattern: `App`, `Models`, `Services`, `UI`, and a separate `MacnosisCore` library.
- Prefer SwiftUI for UI. Use AppKit only as a small, isolated bridge for macOS integration that SwiftUI cannot provide cleanly.
- Treat any repair or re-signing action as explicit and user-triggered. Do not silently modify app bundles during inspection.
- Keep scripts useful independently of the UI. The SwiftUI app can wrap them later, but the shell workflow should remain readable and auditable.

## UX Direction

- First screen should be the usable inspection workspace, not a marketing or onboarding page.
- Favor dense, well-aligned diagnostic panels over decorative cards.
- Make app state legible: architecture, signing identity, entitlements, Gatekeeper assessment, quarantine/provenance attributes, nested-code verification, and repair options.
- Use calm status language: healthy, warning, blocked, repaired, unsigned, quarantined.
- Repair controls should make consequences clear before modifying a bundle.

## Verification

Before finishing behavior changes, run:

```bash
swift build
swift test
git diff --check
scripts/package-app.sh
```
