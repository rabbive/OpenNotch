#!/bin/sh
# Builds build/OpenNotch.app (arm64, ad-hoc signed) from the Swift package.
set -eu
cd "$(dirname "$0")/.."
swift build -c release --arch arm64 --product OpenNotch
binary="$(swift build -c release --arch arm64 --show-bin-path)/OpenNotch"
app=build/OpenNotch.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp Support/Info.plist "$app/Contents/Info.plist"
cp "$binary" "$app/Contents/MacOS/OpenNotch"

# Xcode 26 and later compile the Liquid Glass icon. Older Xcode cannot read .icon files, so it ships the flat copy.
xcode=$(xcodebuild -version | sed -n 's/^Xcode \([0-9]*\).*/\1/p')
: "${xcode:?build-app: could not read the Xcode version}"
if [ "$xcode" -ge 26 ]; then
    xcrun actool Support/OpenNotch.icon --compile "$app/Contents/Resources" \
        --platform macosx --minimum-deployment-target 14.0 --app-icon OpenNotch \
        --standalone-icon-behavior all --output-partial-info-plist build/OpenNotch-icon.plist >/dev/null
    [ -f "$app/Contents/Resources/Assets.car" ] || { echo "build-app: actool did not compile Support/OpenNotch.icon" >&2; exit 1; }
else
    cp Support/OpenNotch.icns "$app/Contents/Resources/OpenNotch.icns"
fi
codesign --force --sign - "$app"
echo "$app"
