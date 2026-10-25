#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != "Darwin" ]] || ! command -v xcodebuild >/dev/null; then
  echo "iOS simulator tests require a Mac with full Xcode." >&2
  exit 1
fi
if [[ -n "${AETHER_SIMULATOR_ID:-}" ]]; then
  destination="id=$AETHER_SIMULATOR_ID"
else
  destination="id=$(xcrun simctl list devices available --json | python3 -c '
import json,sys
catalog=json.load(sys.stdin)["devices"]
for runtime, devices in reversed(list(catalog.items())):
    if "iOS" not in runtime: continue
    phones=[d for d in devices if d.get("isAvailable") and d["name"].startswith("iPhone")]
    if phones:
        print(phones[0]["udid"]);sys.exit(0)
sys.exit("No available iPhone simulator. Install one in Xcode > Settings > Components.")
')"
fi
mkdir -p build
# Result bundle paths must be new; keep earlier runs intact.
result_path="build/Tests-$(date +%Y%m%d-%H%M%S).xcresult"
xcodebuild -project AetherMedia.xcodeproj -scheme AetherMedia \
  -configuration Debug -destination "$destination" \
  -derivedDataPath build/DerivedData -resultBundlePath "$result_path" \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO test
