#!/bin/zsh
# Usage: ./build.sh            -> build/ISOFix.app
#        ./build.sh install    -> also copy to /Applications and launch
set -euo pipefail
cd "${0:A:h}"

APP=build/ISOFix.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/"
[[ -f Resources/AppIcon.icns ]] || swift tools/make-icon.swift
cp Resources/AppIcon.icns "$APP/Contents/Resources/"

swiftc -O -swift-version 5 -target arm64-apple-macos13.0 \
  Sources/*.swift -o "$APP/Contents/MacOS/ISOFix"

# macOS ties the Input Monitoring grant to the signing identity. A self-signed
# "ISOFix Signing" certificate keeps that identity across rebuilds; an ad-hoc
# signature changes on every build, so macOS asks for the grant again.
IDENTITY="ISOFix Signing"
if security find-identity -p codesigning | grep -q "\"$IDENTITY\""; then
  codesign --force --sign "$IDENTITY" "$APP"
else
  codesign --force --sign - "$APP"
fi

if [[ "${1:-}" == install ]]; then
  pkill -x ISOFix || true
  rm -rf /Applications/ISOFix.app
  cp -R "$APP" /Applications/
  open /Applications/ISOFix.app
fi
