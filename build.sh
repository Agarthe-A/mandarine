#!/bin/zsh
# Compile Mandarine et fabrique Mandarine.app (signature ad-hoc)
set -e
cd "$(dirname "$0")"
swift build -c release
APP=build/Mandarine.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Mandarine "$APP/Contents/MacOS/Mandarine"
FF=${FFMPEG:-$HOME/.hermes/tools/ffmpeg-9.0.1-darwin-arm64/ffmpeg}
[ -x "$FF" ] && cp "$FF" "$APP/Contents/Resources/ffmpeg"
cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Mandarine</string>
<key>CFBundleIdentifier</key><string>fr.julian.mandarine</string>
<key>CFBundleExecutable</key><string>Mandarine</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>0.1</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
EOF
codesign --force --deep -s - "$APP"
echo "OK -> $PWD/$APP"
