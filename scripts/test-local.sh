#!/usr/bin/env bash
# Runs the SDK checks locally (replaces the GitHub Actions macOS workflow).
#
#   scripts/test-local.sh            # package check, iOS simulator tests, device build
#   scripts/test-local.sh --pod-lint # also run `pod lib lint`
#
# SIMULATOR_ID=<udid> picks a specific simulator; otherwise the newest available
# iPhone for the active Xcode SDK is used (a booted one first) and booted if needed.
set -euo pipefail

cd "$(dirname "$0")/.."

run_pod_lint=false
[[ "${1:-}" == "--pod-lint" ]] && run_pod_lint=true

derived_data="${TMPDIR:-/tmp}/EmbedIOSSDKLocalTests"

echo "==> Validate Swift package"
swift package dump-package > /dev/null

simulator_id="${SIMULATOR_ID:-}"
if [[ -z "$simulator_id" ]]; then
  sdk_major=$(xcrun --sdk iphonesimulator --show-sdk-version | cut -d. -f1)
  simulator_id=$(xcrun simctl list devices available --json | /usr/bin/python3 -c '
import json, sys
major = sys.argv[1]
devices = json.load(sys.stdin)["devices"]
# Prefer an iPhone that is already booted, then the newest runtime.
picks = [(d["state"] == "Booted", runtime, d["name"], d["udid"])
         for runtime, items in devices.items() if f"SimRuntime.iOS-{major}-" in runtime
         for d in items if d["name"].startswith("iPhone")]
print(sorted(picks)[-1][3] if picks else "")
' "$sdk_major")
  if [[ -z "$simulator_id" ]]; then
    echo "No iPhone simulator for iOS $sdk_major; set SIMULATOR_ID." >&2
    exit 1
  fi
fi
echo "==> Using simulator $simulator_id"
xcrun simctl boot "$simulator_id" 2>/dev/null || true
xcrun simctl bootstatus "$simulator_id" -b > /dev/null

echo "==> Run tests on iOS simulator"
xcodebuild test \
  -scheme EmbedIOSSDK \
  -destination "id=$simulator_id" \
  -derivedDataPath "$derived_data/Tests" \
  CODE_SIGNING_ALLOWED=NO \
  -quiet

echo "==> Build for iOS devices"
xcodebuild build \
  -scheme EmbedIOSSDK \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$derived_data/DeviceBuild" \
  CODE_SIGNING_ALLOWED=NO \
  -quiet

if $run_pod_lint; then
  echo "==> Validate podspec"
  pod lib lint EmbedIOSSDK.podspec --allow-warnings
fi

echo "==> All local checks passed"
