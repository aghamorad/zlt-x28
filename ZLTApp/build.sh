#!/bin/bash
# Builds "ZLT X28.app" — swiftc only, no Xcode project.
# Run from anywhere:  ./build.sh
set -euo pipefail

cd "$(dirname "$0")"
HERE="$PWD"
ROOT="$(cd .. && pwd)"
NAME="ZLT X28"
APP="$HERE/$NAME.app"

if [ -d "$APP" ]; then
    STAMP=$(date +%Y%m%d-%H%M%S)
    mkdir -p "$HOME/.Trash"
    mv "$APP" "$HOME/.Trash/$NAME $STAMP.app"
    echo "Moved the previous build to the Trash."
fi

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/router"

echo "Copying router payloads…"
cp "$ROOT/build/amneziawg-go-linux-arm64" "$APP/Contents/Resources/router/amneziawg-go"
cp "$ROOT/build/awgctl-linux-arm64"        "$APP/Contents/Resources/router/awgctl"
cp "$ROOT/awg/uapipush.linux-arm64"        "$APP/Contents/Resources/router/uapipush"
cp "$ROOT/awg/dotbridge.linux-arm64"       "$APP/Contents/Resources/router/dotbridge"
cp "$ROOT/awg/vpn"                         "$APP/Contents/Resources/router/vpn"
cp "$ROOT/awg/vpn-keepalive"               "$APP/Contents/Resources/router/vpn-keepalive"
cp "$ROOT/awg/amneziawg.init"              "$APP/Contents/Resources/router/amneziawg.init"
cp "$ROOT/awg/singbox.init"                "$APP/Contents/Resources/router/singbox.init"
cp "$ROOT/build/sing-box.gz"               "$APP/Contents/Resources/router/sing-box.gz"
cp "$HERE/Resources/router/install.sh"     "$APP/Contents/Resources/router/install.sh"

echo "Copying the icon…"
cp "$HERE/Resources/AppIcon.icns"          "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>            <string>ZLTX28</string>
    <key>CFBundleIdentifier</key>            <string>com.morad.zltx28</string>
    <key>CFBundleName</key>                  <string>ZLT X28</string>
    <key>CFBundleDisplayName</key>           <string>ZLT X28</string>
    <key>CFBundleIconFile</key>              <string>AppIcon.icns</string>
    <key>CFBundlePackageType</key>           <string>APPL</string>
    <key>CFBundleShortVersionString</key>    <string>1.1.0</string>
    <key>CFBundleVersion</key>               <string>2</string>
    <key>LSMinimumSystemVersion</key>        <string>13.0</string>
    <key>NSHighResolutionCapable</key>       <true/>
    <key>NSPrincipalClass</key>              <string>NSApplication</string>
    <key>NSLocalNetworkUsageDescription</key>
    <string>ZLT X28 talks to your router and serves the VPN engine to it over
    your own local network.</string>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key>    <true/>
    </dict>
</dict>
</plist>
PLIST

echo "Compiling…"
mkdir -p "$HERE/.build"
for arch in arm64 x86_64; do
    swiftc -O \
        -swift-version 5 \
        -parse-as-library \
        -target "$arch-apple-macos13.0" \
        -o "$HERE/.build/ZLTX28-$arch" \
        "$HERE"/Sources/*.swift
done
lipo -create \
    "$HERE/.build/ZLTX28-arm64" \
    "$HERE/.build/ZLTX28-x86_64" \
    -output "$APP/Contents/MacOS/ZLTX28"

echo "Signing…"
codesign --force --sign - "$APP" >/dev/null 2>&1 || {
    echo "codesign failed — the app will not launch on this Mac." >&2
    exit 1
}

echo "Built: $APP"
