#!/bin/sh
# Builds build/OpenNotch.app (arm64, ad-hoc signed) from the Swift package.
set -eu
cd "$(dirname "$0")/.."
swift build -c release --arch arm64 --product OpenNotch
binary="$(swift build -c release --arch arm64 --show-bin-path)/OpenNotch"
app=build/OpenNotch.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp Support/Info.plist "$app/Contents/Info.plist"
cp "$binary" "$app/Contents/MacOS/OpenNotch"
codesign --force --sign - "$app"
echo "$app"
