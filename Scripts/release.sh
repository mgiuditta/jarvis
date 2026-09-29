#!/bin/zsh
# Signed + notarized Jarvis.dmg to hand to other people. Usage: Scripts/release.sh
# Once per Mac:
#   1. Xcode › Settings › Accounts › Manage Certificates › + "Developer ID Application"
#   2. xcrun notarytool store-credentials jarvis --apple-id <apple id> --team-id <team> --password <app-specific password>
#      (app-specific password: account.apple.com › Sign-In and Security)
# Doesn't touch /Applications or the running Jarvis.
set -euo pipefail
cd "${0:A:h}/.."
PROFILE="${NOTARY_PROFILE:-jarvis}"
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | grep -o '"Developer ID Application: [^"]*"' | head -1 | tr -d '"' || true)}"
[[ -n "$IDENTITY" ]] || { echo "Manca il certificato Developer ID Application (vedi l'intestazione dello script)."; exit 1; }
TEAM="${IDENTITY##*\(}"; TEAM="${TEAM%\)}"
xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1 \
  || { echo "Manca il profilo notarytool '$PROFILE' (vedi l'intestazione dello script)."; exit 1; }

NODE_BIN="${NODE_BIN:-$(ls -d ~/.nvm/versions/node/*/bin | sort -V | tail -1)}"
PATH="$NODE_BIN:$PATH" npm --prefix agent ci --omit=optional --ignore-scripts --silent
PATH="$NODE_BIN:$PATH" node --test agent/*.test.mjs
swift test --package-path Tests --scratch-path build/tests --disable-xctest -q

OUT=build/release
rm -rf "$OUT" && mkdir -p "$OUT"
xcodebuild -project Jarvis.xcodeproj -scheme Jarvis -configuration Release -derivedDataPath build/release-dd \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$IDENTITY" DEVELOPMENT_TEAM="$TEAM" PROVISIONING_PROFILE_SPECIFIER= \
  ENABLE_HARDENED_RUNTIME=YES OTHER_CODE_SIGN_FLAGS=--timestamp build | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
APP="$OUT/Jarvis.app"
cp -R build/release-dd/Build/Products/Release/Jarvis.app "$APP"

# Notarization rejects any unsigned Mach-O: sign the native bits in node_modules, then the app again (inside-out).
find "$APP/Contents/Resources" -type f -print0 | while IFS= read -r -d '' f; do
  file -b "$f" | grep -q Mach-O && codesign --force --options runtime --timestamp --sign "$IDENTITY" "$f"
done
codesign --force --options runtime --timestamp --entitlements Scripts/Jarvis.entitlements --sign "$IDENTITY" "$APP"
codesign --verify --strict --deep "$APP"

VERSION=$(defaults read "$PWD/$APP/Contents/Info" CFBundleShortVersionString)
DMG="$OUT/Jarvis-$VERSION.dmg"
STAGE="$OUT/dmg" && mkdir -p "$STAGE" && cp -R "$APP" "$STAGE/" && ln -s /Applications "$STAGE/Applications"
cp LICENSE "$STAGE/LICENSE.txt"
hdiutil create -volname Jarvis -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
codesign --force --timestamp --sign "$IDENTITY" "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"
spctl -a -t open --context context:primary-signature -v "$DMG"
echo "Pronto: $DMG"
