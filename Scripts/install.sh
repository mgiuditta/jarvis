#!/bin/zsh
# Build Release and install into /Applications. Usage: Scripts/install.sh
set -euo pipefail
cd "${0:A:h}/.."
if pgrep -x Jarvis >/dev/null; then echo "Jarvis è aperto: chiudilo dal menu bar (Esci) e rilancia lo script."; exit 1; fi
NODE_BIN="${NODE_BIN:-$(ls -d ~/.nvm/versions/node/*/bin | sort -V | tail -1)}"
PATH="$NODE_BIN:$PATH" npm --prefix agent ci --omit=optional --silent
PATH="$NODE_BIN:$PATH" node --test agent/*.test.mjs
mkdir -p build && swiftc -parse-as-library Jarvis/Intent.swift Scripts/IntentCheck.swift -o build/intentcheck && build/intentcheck
xcodebuild -project Jarvis.xcodeproj -scheme Jarvis -configuration Release -derivedDataPath build \
  -allowProvisioningUpdates build | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
rm -rf /Applications/Jarvis.app
cp -R build/Build/Products/Release/Jarvis.app /Applications/
echo "Installato in /Applications/Jarvis.app: aprilo da Launchpad o Spotlight."
