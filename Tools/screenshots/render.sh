#!/bin/zsh
# Regenerates docs/screenshots/*.png from demo data.
# Widget code is compiled into a tiny offscreen renderer; Link views are swapped for plain views because
# ImageRenderer can't draw them.
set -euo pipefail
cd "${0:A:h}/../.."

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
APP="$WORK/Render.app/Contents"
mkdir -p "$APP/MacOS" "$APP/Resources" docs/screenshots
cp Resources/icons/*.png "$APP/Resources/"
print -r -- '<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>dev.devboard.render</string><key>CFBundleExecutable</key><string>render</string></dict></plist>' > "$APP/Info.plist"

sed -e 's/^@main$//' -e 's/Link(destination:/PlainLink(destination:/g' Widget/DevBoardWidget.swift > "$WORK/Widget.swift"
# ImageRenderer draws ScrollView as empty and can't draw borderless buttons, so swap them in the copy only.
sed -e 's/^@main$//' -e 's/            ScrollView {/            VStack {/' -e 's/\.buttonStyle(\.borderless)//' \
  App/DevBoardApp.swift > "$WORK/App.swift"
cat >> "$WORK/Widget.swift" <<'EOF'
struct PlainLink<Content: View>: View {
    let destination: URL
    @ViewBuilder let label: () -> Content
    var body: some View { label() }
}
EOF

swiftc -sdk "$(xcrun --show-sdk-path)" -target "$(uname -m)-apple-macos14.0" -swift-version 5 -parse-as-library -O \
  Shared/*.swift "$WORK/Widget.swift" "$WORK/App.swift" Tools/screenshots/Render.swift -o "$APP/MacOS/render"
"$APP/MacOS/render" "$PWD/docs/screenshots"
