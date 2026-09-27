#!/usr/bin/env bash
# Compiles only Foundation/CoreVideo/CoreMedia tests, never the application.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
build="$(mktemp -d)"
trap 'rm -rf "$build"' EXIT
plugin="$root/plugins/built_in_kotlin/better_player_plus/ios/better_player_plus/Sources/better_player_plus"
fijk="$root/plugins/flv_lzc/ios/Classes"
xcrun swiftc -frontend -parse "$plugin/BetterPlayer.swift" "$plugin/SwiftBetterPlayerPlugin.swift"
xcrun swiftc "$plugin/BetterPlayerTimeUtils.swift" \
  "$root/test/native/ios_engine_safety/main.swift" -o "$build/time-test"
"$build/time-test"
xcrun clang -fobjc-arc -fblocks -framework Foundation -framework CoreVideo \
  -I "$fijk" "$fijk/FijkPixelBufferMailbox.m" \
  "$root/test/native/ios_engine_safety/mailbox_test.m" -o "$build/mailbox-test"
"$build/mailbox-test"
