#!/bin/zsh
# Build Release and install into /Applications. Usage: Scripts/install.sh
set -euo pipefail
cd "${0:A:h}/.."
NODE_BIN="${NODE_BIN:-$(ls -d ~/.nvm/versions/node/*/bin | sort -V | tail -1)}"
PATH="$NODE_BIN:$PATH" npm --prefix agent ci --omit=optional --ignore-scripts --silent  # ignore-scripts: koffi (Copilot in-process FFI, unused) would need CMake
PATH="$NODE_BIN:$PATH" node --test agent/*.test.mjs
swift test --package-path Tests --scratch-path build/tests --disable-xctest -q
xcodebuild -project Jarvis.xcodeproj -scheme Jarvis -configuration Release -derivedDataPath build \
  -allowProvisioningUpdates build | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
osascript -e 'quit app "Jarvis"' 2>/dev/null || true
while pgrep -x Jarvis >/dev/null; do sleep 0.2; done
rm -rf /Applications/Jarvis.app
cp -R build/Build/Products/Release/Jarvis.app /Applications/
open /Applications/Jarvis.app
echo "Installato e avviato: /Applications/Jarvis.app"
