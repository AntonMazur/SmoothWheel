#!/bin/zsh
set -eu
cd "${0:A:h}"
python3 scripts/generate-design-tokens.py --check
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/smoothwheel-clang-cache"
swift build --disable-sandbox --build-system native --manifest-cache local -c release --scratch-path .build-release
mkdir -p releases
STAGING=$(mktemp -d "${TMPDIR:-/tmp}/smoothwheel-package.XXXXXX")
APP="$STAGING/SmoothWheel.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build-release/release/SmoothWheel "$APP/Contents/MacOS/SmoothWheel"
cp ScrollTest.html "$APP/Contents/Resources/"
cp Resources/*.png "$APP/Contents/Resources/"
swift -module-cache-path "$CLANG_MODULE_CACHE_PATH" scripts/make-icon.swift "$STAGING/AppIcon.iconset"
python3 scripts/make-icns.py "$STAGING/AppIcon.iconset" "$APP/Contents/Resources/SmoothWheelIcon.icns"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>SmoothWheel</string>
<key>CFBundleDisplayName</key><string>SmoothWheel</string>
<key>CFBundleIdentifier</key><string>local.smoothwheel.app</string>
<key>CFBundleVersion</key><string>14</string>
<key>CFBundleShortVersionString</key><string>0.3.11</string>
<key>CFBundleExecutable</key><string>SmoothWheel</string>
<key>CFBundleIconFile</key><string>SmoothWheelIcon.icns</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
xattr -cr "$APP"
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"
ditto -c -k --norsrc --noextattr --keepParent "$APP" "$PWD/releases/SmoothWheel.zip"
printf 'Built %s\nPreview app: %s\n' "$PWD/releases/SmoothWheel.zip" "$APP"
