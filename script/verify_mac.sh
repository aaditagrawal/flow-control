#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_DIR="$ROOT_DIR/mac"
MODE="unit"
REPEAT=1

usage() {
  cat <<'USAGE'
usage: ./script/verify_mac.sh [--live-read|--live-write] [--repeat COUNT]

  --live-read   Run the complete wired-keyboard readback test after unit tests.
  --live-write  Also run both reversible lighting write/readback/restore tests.
  --repeat N    Repeat live hardware tests N times to expose intermittent USB failures.

The Flow Control app must be closed while live tests own the HID interface.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --live-read)
      MODE="read"
      shift
      ;;
    --live-write)
      MODE="write"
      shift
      ;;
    --repeat)
      if [[ $# -lt 2 || ! "$2" =~ ^[1-9][0-9]*$ ]]; then
        echo "--repeat requires a positive integer." >&2
        exit 2
      fi
      REPEAT="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
done

swift test --package-path "$PACKAGE_DIR"

if [[ "$MODE" == "unit" ]]; then
  exit 0
fi

if pgrep -x FlowControl >/dev/null; then
  echo "Quit Flow Control before running live HID verification." >&2
  exit 1
fi

for ((iteration = 1; iteration <= REPEAT; iteration++)); do
  echo "Live Flow Lite verification $iteration/$REPEAT"
  FLOW_HID_INTEGRATION=1 swift test \
    --package-path "$PACKAGE_DIR" \
    --filter FlowHIDIntegrationTests/testConnectedFlowLiteCanReadItsCompleteConfiguration

  if [[ "$MODE" == "write" ]]; then
    FLOW_HID_LIGHTING_WRITE_INTEGRATION=1 swift test \
      --package-path "$PACKAGE_DIR" \
      --filter FlowHIDIntegrationTests/testLightingLevelsCanRoundTripAndRestore
    FLOW_HID_LIGHTING_MATRIX_INTEGRATION=1 swift test \
      --package-path "$PACKAGE_DIR" \
      --filter FlowHIDIntegrationTests/testLightingModeStateTimeoutAndRapidWritesCanRestore
    FLOW_HID_SINE_WRITE_INTEGRATION=1 swift test \
      --package-path "$PACKAGE_DIR" \
      --filter FlowHIDIntegrationTests/testSineWaveModeSelectionCanRoundTripAndRestore
  fi
done
