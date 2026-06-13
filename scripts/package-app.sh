#!/bin/sh

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
PROJECT_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
APP_DIR="$PROJECT_ROOT/.build/Macnosis.app"

cd "$PROJECT_ROOT"
swift build

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$PROJECT_ROOT/.build/debug/macnosis" "$APP_DIR/Contents/MacOS/Macnosis"
cp "$PROJECT_ROOT/Packaging/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$PROJECT_ROOT/Packaging/MacnosisIcon.icns" "$APP_DIR/Contents/Resources/MacnosisIcon.icns"
cp "$PROJECT_ROOT/scripts/make-debuggable-app.sh" "$APP_DIR/Contents/Resources/make-debuggable-app.sh"
for bundle in "$PROJECT_ROOT"/.build/debug/macnosis_*.bundle; do
    [ -d "$bundle" ] || continue
    cp -R "$bundle" "$APP_DIR/Contents/Resources/"
done
chmod +x "$APP_DIR/Contents/MacOS/Macnosis"

echo "$APP_DIR"
