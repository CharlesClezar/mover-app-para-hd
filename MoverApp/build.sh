#!/bin/bash
# Compila o app (Intel + Apple Silicon, macOS 13+) e gera "Mover App para HD.app"
set -e
cd "$(dirname "$0")"
APP="../Mover App para HD.app"
B=$(mktemp -d)
for arch in x86_64 arm64; do
  swiftc -O -parse-as-library -target $arch-apple-macos13.0 Sources/main.swift -o "$B/m-$arch"
done
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create "$B/m-x86_64" "$B/m-arm64" -output "$APP/Contents/MacOS/MoverApp"
swiftc icon.swift -o "$B/icon" && "$B/icon" "$B/AppIcon.iconset" && iconutil -c icns "$B/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<P
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Mover App para HD</string>
<key>CFBundleDisplayName</key><string>Mover App para HD</string>
<key>CFBundleIdentifier</key><string>local.mover-app-para-hd</string>
<key>CFBundleExecutable</key><string>MoverApp</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>2.0</string>
<key>CFBundleVersion</key><string>2</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>CFBundleDocumentTypes</key><array><dict>
<key>CFBundleTypeName</key><string>Aplicativo</string>
<key>CFBundleTypeRole</key><string>Viewer</string>
<key>LSItemContentTypes</key><array><string>com.apple.application-bundle</string></array>
</dict></array>
</dict></plist>
P
codesign --force --deep -s - "$APP"
echo "Pronto: $APP"; lipo -archs "$APP/Contents/MacOS/MoverApp"
