#!/bin/sh
# Headless checks for drop classification, temp files, handoff text, hotkey parsing and grab planning.
set -e
cd "$(dirname "$0")/.."
out="${TMPDIR:-/tmp}/nook-capture-selftest"
swiftc -swift-version 5 -o "$out" Scripts/capture-selftest/main.swift \
  Sources/Nook/Capture/DropItems.swift Sources/Nook/Capture/HandoffMessage.swift \
  Sources/Nook/Capture/CarbonHotkeys.swift Sources/Nook/Capture/ScreenGrab.swift Sources/Nook/Capture/MiniPanels.swift
"$out"
