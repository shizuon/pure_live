#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
build="$(mktemp -d)"
trap 'rm -rf "$build"' EXIT
plugin="$root/third_party/media_kit_video/macos/media_kit_video/Sources/media_kit_video/plugin"
xcrun swiftc -frontend -parse "$plugin/TextureHW.swift" "$plugin/common/TextureSW.swift"
xcrun swiftc -swift-version 5 -module-cache-path "$build/module-cache" \
  "$plugin/common/VideoOutput.swift" "$plugin/common/Worker.swift" \
  "$root/test/native/macos_video_frame_delivery/main.swift" -o "$build/frame-delivery-test"
"$build/frame-delivery-test"
