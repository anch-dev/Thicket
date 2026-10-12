#!/usr/bin/env bash
# Build and test Thicket on macOS. Usage:
#   scripts/build.sh            # everything: package tests, simulator tests, device build, .ipa
#   scripts/build.sh test       # SwiftPM + simulator tests only
#   scripts/build.sh device     # unsigned arm64 device build + Thicket-unsigned.ipa
set -euo pipefail
cd "$(dirname "$0")/.."
WHAT="${1:-all}"
DERIVED="build/DerivedData"
mkdir -p build

command -v xcodegen >/dev/null || { echo "Install XcodeGen: brew install xcodegen"; exit 1; }
xcodegen generate --quiet

pick_simulator() {
  # First available iPhone simulator (prefers newer runtimes).
  xcrun simctl list devices available -j | python3 -c '
import json, sys
d = json.load(sys.stdin)["devices"]
best = None
for runtime, devs in d.items():
    if "iOS" not in runtime: continue
    for dev in devs:
        if dev["name"].startswith("iPhone"):
            key = (runtime, dev["name"])
            if best is None or key > best[0]: best = (key, dev["udid"])
print(best[1] if best else "")'
}

if [[ "$WHAT" == "all" || "$WHAT" == "test" ]]; then
  echo "== SwiftPM tests (logic modules) =="
  swift test
  SIM="$(pick_simulator)"
  [[ -n "$SIM" ]] || { echo "No iPhone simulator available"; exit 1; }
  echo "== Simulator tests on $SIM =="
  xcodebuild -project Thicket.xcodeproj -scheme Thicket -configuration Debug \
    -destination "id=$SIM" -derivedDataPath "$DERIVED" \
    CODE_SIGNING_ALLOWED=NO test | tee build/test.log | grep -E "Test (Suite|Case).*(passed|failed)|error:|\*\* TEST" || true
  grep -q "\*\* TEST SUCCEEDED \*\*" build/test.log
fi

if [[ "$WHAT" == "all" || "$WHAT" == "device" ]]; then
  echo "== Simulator app build =="
  xcodebuild -project Thicket.xcodeproj -scheme Thicket -configuration Debug \
    -destination "generic/platform=iOS Simulator" -derivedDataPath "$DERIVED" \
    CODE_SIGNING_ALLOWED=NO build -quiet
  echo "== Unsigned arm64 device build =="
  xcodebuild -project Thicket.xcodeproj -scheme Thicket -configuration Release \
    -sdk iphoneos -destination "generic/platform=iOS" -derivedDataPath "$DERIVED" \
    ARCHS=arm64 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build -quiet
  APP="$DERIVED/Build/Products/Release-iphoneos/Thicket.app"
  file "$APP/Thicket" || true
  rm -rf build/Payload build/Thicket-unsigned.ipa
  mkdir -p build/Payload
  cp -R "$APP" build/Payload/
  (cd build && zip -qry Thicket-unsigned.ipa Payload)
  echo "Wrote build/Thicket-unsigned.ipa (unsigned; re-sign to install)"
fi

if [[ "$WHAT" == "screens" ]]; then
  # Launch the simulator build and capture screenshots (title screen and a round in play).
  SIM="$(pick_simulator)"
  xcrun simctl boot "$SIM" || true
  xcrun simctl bootstatus "$SIM" -b
  xcodebuild -project Thicket.xcodeproj -scheme Thicket -configuration Debug \
    -destination "id=$SIM" -derivedDataPath "$DERIVED" CODE_SIGNING_ALLOWED=NO build -quiet
  APP="$DERIVED/Build/Products/Debug-iphonesimulator/Thicket.app"
  xcrun simctl install "$SIM" "$APP"
  mkdir -p build/screens
  xcrun simctl launch "$SIM" dev.anch.thicket
  sleep 6
  xcrun simctl io "$SIM" screenshot build/screens/title.png
  shot() { # name, launch args...
    local name="$1"; shift
    xcrun simctl terminate "$SIM" dev.anch.thicket || true
    xcrun simctl launch "$SIM" dev.anch.thicket "$@"
    sleep 10
    xcrun simctl io "$SIM" screenshot "build/screens/$name.png"
  }
  shot round3d -autostart round -3d
  shot lesson3d -autostart lesson -3d
  shot round2d -autostart round -pixel
  shot versus3d -autostart versus -3d
  ls -la build/screens
fi
