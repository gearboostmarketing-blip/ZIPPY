#!/bin/bash
# Builds "Zip Receipt.app" from ZipReceipt.swift + ../index.html.
#   ./build.sh                 build for this Mac into mac/build/
#   ./build.sh --install       build, then copy into /Applications and open it
#   ./build.sh --universal     build one app that runs on Apple silicon AND Intel Macs
#   ./build.sh --dmg           also make mac/build/Zip-Receipt.dmg (drag-to-Applications installer)
# Flags can be combined. Needs Apple's command line tools:  xcode-select --install
set -euo pipefail
cd "$(dirname "$0")"

INSTALL=0; UNIVERSAL=0; DMG=0
for a in "$@"; do
  case "$a" in
    --install) INSTALL=1 ;;
    --universal) UNIVERSAL=1 ;;
    --dmg) DMG=1 ;;
    *) echo "Unknown option: $a"; exit 1 ;;
  esac
done

command -v swiftc >/dev/null || { echo "swiftc not found. Run: xcode-select --install"; exit 1; }

APP="build/Zip Receipt.app"
BIN="$APP/Contents/MacOS/ZipReceipt"
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

compile() {  # $1 = arch, $2 = output
  echo "Compiling for $1…"
  swiftc -O -parse-as-library -swift-version 5 -target "$1-apple-macos11.0" \
    -framework Cocoa -framework WebKit ZipReceipt.swift -o "$2"
}

if [ "$UNIVERSAL" = 1 ]; then
  compile arm64 build/ZipReceipt-arm64
  compile x86_64 build/ZipReceipt-x86_64
  lipo -create -output "$BIN" build/ZipReceipt-arm64 build/ZipReceipt-x86_64
  rm build/ZipReceipt-arm64 build/ZipReceipt-x86_64
else
  compile "$(uname -m)" "$BIN"
fi

cp Info.plist "$APP/Contents/Info.plist"
cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp ../index.html "$APP/Contents/Resources/index.html"

# Ad-hoc signature: required to run on Apple silicon.
codesign --force --deep --sign - "$APP"
echo "Built mac/$APP"

if [ "$DMG" = 1 ]; then
  STAGE="build/dmg"
  mkdir -p "$STAGE"
  cp -R "$APP" "$STAGE/"
  ln -s /Applications "$STAGE/Applications"
  hdiutil create -volname "Zip Receipt" -srcfolder "$STAGE" -ov -format UDZO "build/Zip-Receipt.dmg" >/dev/null
  rm -rf "$STAGE"
  echo "Built mac/build/Zip-Receipt.dmg"
fi

if [ "$INSTALL" = 1 ]; then
  osascript -e 'quit app "Zip Receipt"' 2>/dev/null || true
  rm -rf "/Applications/Zip Receipt.app"
  cp -R "$APP" /Applications/
  echo "Installed to /Applications/Zip Receipt.app"
  open "/Applications/Zip Receipt.app"
fi
