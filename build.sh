#!/bin/zsh
# Builds DevBoard.app (+ widget extension) with the Xcode Command Line Tools only (no Xcode needed),
# signs it ad-hoc for local use and installs it to ~/Applications.
#
# Your settings live in ~/.config/devboard/ (created by ./setup.sh) and are copied into the bundle,
# because the sandboxed widget can only read files inside its own bundle:
#   config.json   usernames and options
#   gemini_key    free Gemini API key (optional; enables the AI-written questions)
#   profile.txt   anonymized resume profile (optional; enables resume-based questions)
#
# Override the bundle identifier with BUNDLE_ID=com.example.devboard ./build.sh
set -euo pipefail
cd "${0:A:h}"

CONFIG_DIR=~/.config/devboard
BUNDLE_ID=${BUNDLE_ID:-dev.devboard}
MIN_MACOS=14.0
SDK=$(xcrun --show-sdk-path)
TARGET="$(uname -m)-apple-macos$MIN_MACOS"
OUT=build/DevBoard.app
APPEX=$OUT/Contents/PlugIns/DevBoardWidget.appex
FLAGS=(-sdk "$SDK" -target "$TARGET" -swift-version 5 -O -parse-as-library)

rm -rf build && mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources" "$APPEX/Contents/MacOS" "$APPEX/Contents/Resources"

echo "→ Compiling widget extension"
# Widget extensions must start at _NSExtensionMain (Xcode adds this flag for extension targets).
swiftc "${FLAGS[@]}" -application-extension -module-name DevBoardWidget -Xlinker -e -Xlinker _NSExtensionMain \
  Shared/*.swift Widget/*.swift -o "$APPEX/Contents/MacOS/DevBoardWidget"

echo "→ Compiling app"
swiftc "${FLAGS[@]}" -module-name DevBoard Shared/*.swift App/*.swift -o "$OUT/Contents/MacOS/DevBoard"

cp Support/Widget-Info.plist "$APPEX/Contents/Info.plist"
cp Support/App-Info.plist "$OUT/Contents/Info.plist"
PB=/usr/libexec/PlistBuddy
# Fresh build number each time so macOS drops its cached widget descriptors.
BUILD_NUM=$(date +%s)
for plist in "$APPEX/Contents/Info.plist" "$OUT/Contents/Info.plist"; do
  $PB -c "Set :CFBundleVersion $BUILD_NUM" -c "Set :LSMinimumSystemVersion $MIN_MACOS" "$plist"
done
$PB -c "Set :CFBundleIdentifier $BUNDLE_ID" -c "Set :CFBundleURLTypes:0:CFBundleURLName $BUNDLE_ID" "$OUT/Contents/Info.plist"
$PB -c "Set :CFBundleIdentifier $BUNDLE_ID.widget" -c "Set :originalAppBundleIdentifier $BUNDLE_ID" "$APPEX/Contents/Info.plist"

cp Resources/icons/*.png "$APPEX/Contents/Resources/"
if [[ -s $CONFIG_DIR/config.json ]]; then
  cp "$CONFIG_DIR/config.json" "$APPEX/Contents/Resources/"
  cp "$CONFIG_DIR/config.json" "$OUT/Contents/Resources/"
else
  echo "⚠︎ No $CONFIG_DIR/config.json yet. Run ./setup.sh to add your usernames."
fi
if [[ -s $CONFIG_DIR/gemini_key ]]; then
  cp "$CONFIG_DIR/gemini_key" "$APPEX/Contents/Resources/gemini_key"
else
  echo "⚠︎ No Gemini key; the question widgets will show setup instructions."
fi
[[ -s $CONFIG_DIR/profile.txt ]] && cp "$CONFIG_DIR/profile.txt" "$APPEX/Contents/Resources/profile.txt"

echo "→ Signing (ad-hoc, local only)"
codesign --force --sign - --entitlements Support/Widget.entitlements "$APPEX"
codesign --force --sign - "$OUT"

echo "→ Installing to ~/Applications"
DEST=~/Applications/DevBoard.app
mkdir -p ~/Applications
pkill -x DevBoard 2>/dev/null || true
rm -rf "$DEST" && cp -R "$OUT" "$DEST"
LSREG=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
$LSREG -f -R "$DEST"
pluginkit -a "$DEST/Contents/PlugIns/DevBoardWidget.appex"
killall chronod 2>/dev/null || true # restart the widget daemon so it picks up the new build
echo "✓ Installed. Click the date & time in the menu bar → Edit Widgets → search \"DevBoard\"."
