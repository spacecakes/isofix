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

# Ad-hoc signature: every rebuild is a new identity, so macOS will ask for
# Input Monitoring again after reinstalling.
codesign --force --sign - "$APP"

if [[ "${1:-}" == install ]]; then
  pkill -x ISOFix || true
  rm -rf /Applications/ISOFix.app
  cp -R "$APP" /Applications/
  open /Applications/ISOFix.app
fi
