# Macnosis

Macnosis is a SwiftUI macOS utility for diagnosing and repairing local `.app` bundles.

The first version is intentionally small: a normal main-window app that can inspect core macOS bundle state and a set of command-line scripts/docs for the repair and debugging workflows already explored.

## Current Scope

- Inspect app bundle identity from `Info.plist`.
- Detect main executable architecture through `/usr/bin/file`.
- Read code-signing metadata, entitlements, and strict verification output through `codesign`.
- Read Gatekeeper assessment through `spctl`.
- Detect quarantine/provenance extended attributes through `xattr`.
- Keep repair workflows in `scripts/make-debuggable-app.sh`.

## Requirements

- macOS 14 or newer
- Swift 6.3 or newer
- Xcode command line tools

## Run

```bash
swift run macnosis
```

Package and open the app bundle:

```bash
scripts/package-app.sh
open .build/Macnosis.app
```

## Scripts

Create a debuggable copy of an app:

```bash
scripts/make-debuggable-app.sh SomeGame.app
```

Repair a local app that macOS reports as damaged:

```bash
scripts/make-debuggable-app.sh --repair-damaged SomeGame.app
```

## Documentation

- `docs/README_HARDENING.md`: developer notes for signing, notarization, Hardened Runtime, and tamper protection.
- `docs/README_TAMPER_DETECTION_CHECKS.md`: practical indicators for finding tamper-detection mechanisms in a macOS app.

## Project Layout

- `Sources/macnosis/App`: SwiftUI app entry point.
- `Sources/macnosis/Models`: observable app state.
- `Sources/macnosis/UI`: SwiftUI views and visual styling.
- `Sources/MacnosisCore/Models`: inspection result models.
- `Sources/MacnosisCore/Services`: app bundle inspection service.
- `Packaging`: app bundle metadata used by `scripts/package-app.sh`.
- `scripts`: local repair/signing helper scripts.
- `docs`: reference notes and operational documentation.

## Development

```bash
swift build
swift test
git diff --check
scripts/package-app.sh
```
