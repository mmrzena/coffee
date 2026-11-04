#!/usr/bin/env bash
# Builds Coffee.app (universal: Apple Silicon + Intel, macOS 12+) into ~/Applications
# and restarts it so the new code is what's running.
set -euo pipefail
cd "$(dirname "$0")"

APP="$HOME/Applications/Coffee.app"
MIN_MACOS=12.0
BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$BUILD_DIR"' EXIT

pids=()
for arch in arm64 x86_64; do
	swiftc -O -target "$arch-apple-macos$MIN_MACOS" -o "$BUILD_DIR/Coffee-$arch" Coffee.swift &
	pids+=($!)
done
for pid in "${pids[@]}"; do wait "$pid"; done # set -e doesn't see background failures; wait does

# Wait for the old instance to actually exit, or `open` may just re-activate it.
pkill -x Coffee || true
while pgrep -xq Coffee; do sleep 0.1; done

mkdir -p "$APP/Contents/MacOS"
lipo -create -output "$APP/Contents/MacOS/Coffee" "$BUILD_DIR/Coffee-arm64" "$BUILD_DIR/Coffee-x86_64"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleIdentifier</key><string>local.coffee</string>
	<key>CFBundleName</key><string>Coffee</string>
	<key>CFBundleExecutable</key><string>Coffee</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>1.1</string>
	<key>CFBundleVersion</key><string>$(date +%Y%m%d%H%M)</string>
	<key>LSUIElement</key><true/>
	<key>LSMinimumSystemVersion</key><string>$MIN_MACOS</string>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP"

open "$APP"
echo "Built and restarted $APP"
