#!/bin/bash
# Capture the installed app on a fresh Apple simulator using only the isolated Demo workspace.
set -euo pipefail
project=$(cd "$(dirname "$0")/../.." && pwd)
out=${1:?Specify an output directory for the JPEG files}
mkdir -p "$out"
out=$(cd "$out" && pwd)
command -v xcodegen >/dev/null || { echo 'Install XcodeGen with brew install xcodegen'; exit 1; }
work=$(mktemp -d)
udid=""
cleanup() {
  if [[ -n "$udid" ]]; then xcrun simctl delete "$udid" || true; fi
  rm -rf "$work"
}
trap cleanup EXIT
cp -R "$project/Courier" "$work/Courier"
cp "$project/project.yml" "$work/project.yml"
mkdir "$work/StoreScreens"
cp "$project/store/screenshots/StoreScreens.swift" "$work/StoreScreens/"
cat >>"$work/project.yml" <<'YAML'

  StoreScreens:
    type: bundle.ui-testing
    platform: iOS
    sources: [StoreScreens]
    dependencies:
      - target: Courier
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: ru.mise.courier.StoreScreens
        TEST_TARGET_NAME: Courier
        GENERATE_INFOPLIST_FILE: YES
schemes:
  StoreScreens:
    build:
      targets:
        Courier: all
    test:
      targets: [StoreScreens]
YAML
(cd "$work" && xcodegen generate)
runtime=$(xcrun simctl list runtimes -j | python3 -c 'import json,sys; r=[x for x in json.load(sys.stdin)["runtimes"] if x.get("isAvailable") and ".iOS-" in x["identifier"]]; print(max(r,key=lambda x:tuple(map(int,x["version"].split("."))))["identifier"])')
for model in 'iPhone-17-Pro' 'iPhone-16-Pro' 'iPhone-16' 'iPhone-15-Pro'; do
  if udid=$(xcrun simctl create "Courier Store Capture" "com.apple.CoreSimulator.SimDeviceType.$model" "$runtime" 2>/dev/null); then break; fi
done
test -n "$udid"
xcrun simctl boot "$udid"
xcrun simctl bootstatus "$udid" -b
xcrun simctl status_bar "$udid" override --time 9:41 --batteryState charged --batteryLevel 100
xcrun simctl ui "$udid" appearance light
build=(xcodebuild -quiet -project "$work/Courier.xcodeproj" -scheme StoreScreens -destination "platform=iOS Simulator,id=$udid" -derivedDataPath "$work/Build" -parallel-testing-enabled NO)
"${build[@]}" build-for-testing
xcrun simctl install "$udid" "$work/Build/Build/Products/Debug-iphonesimulator/Курьер.app"
xcrun simctl privacy "$udid" grant location-always ru.mise.courier
if ! "${build[@]}" -resultBundlePath "$work/capture.xcresult" test-without-building 2>&1 | tee "$work/uitest.log"; then
  xcrun xcresulttool get test-results summary --path "$work/capture.xcresult" > "$work/failures.json" || true
  python3 - "$work/failures.json" "$work/uitest.log" <<'PYTHON'
import json,sys
from pathlib import Path
try:
    result=json.loads(Path(sys.argv[1]).read_text())
    for f in result.get('testFailures',[]): print('::error::'+str(f.get('failureText',f))[:1000].replace('%','%25').replace('\n','%0A'))
except (OSError,ValueError): pass
for line in [s for s in Path(sys.argv[2]).read_text().splitlines() if 'error:' in s or 'failed on' in s][-8:]:
    print('::error::'+line[:450])
PYTHON
  exit 1
fi
data="$HOME/Library/Developer/CoreSimulator/Devices/$udid/data/Containers/Data"
for name in 01-orders 02-history; do
  shot=$(find "$data" -type f -path "*/Documents/$name.png" -print -quit)
  test -s "$shot"
  sips -s format jpeg -s formatOptions best "$shot" --out "$out/$name.jpg" >/dev/null
  sips -g pixelWidth -g pixelHeight "$out/$name.jpg"
done
