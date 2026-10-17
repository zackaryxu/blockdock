#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

binaries=()
for architecture in arm64 x86_64; do
  triple="${architecture}-apple-macosx13.0"
  swift build -c release --triple "$triple"
  bin_dir=$(swift build -c release --triple "$triple" --show-bin-path)
  binaries+=("$bin_dir/BlockDock")
done
app="dist/BlockDock.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "dist"
/usr/bin/lipo -create "${binaries[@]}" -output "$app/Contents/MacOS/BlockDock"
/usr/bin/strip -S "$app/Contents/MacOS/BlockDock"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>BlockDock</string>
  <key>CFBundleDisplayName</key><string>BlockDock</string>
  <key>CFBundleExecutable</key><string>BlockDock</string>
  <key>CFBundleIdentifier</key><string>org.blockdock.app</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$app"
cp README.md LICENSE THIRD_PARTY_NOTICES.md dist/
rm -f dist/BlockDock-macOS.zip
(cd dist && /usr/bin/zip -qr BlockDock-macOS.zip BlockDock.app README.md LICENSE THIRD_PARTY_NOTICES.md)
rm -f dist/BlockDock-source.zip
/usr/bin/zip -qr dist/BlockDock-source.zip Package.swift build.sh README.md LICENSE THIRD_PARTY_NOTICES.md Sources Tests -x '*/.DS_Store'
echo "Built $app, dist/BlockDock-macOS.zip and dist/BlockDock-source.zip"
