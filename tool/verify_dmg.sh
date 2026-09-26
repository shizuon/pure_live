#!/usr/bin/env bash
# hdiutil can transiently lose access to the just-created image on hosted
# runners. Retry only resource contention; never retry/accept checksum failure.
set -euo pipefail
image="${1:?Usage: verify_dmg.sh image.dmg}"
log="$(mktemp)"
trap 'rm -f "$log"' EXIT
for attempt in 1 2 3; do
  if hdiutil verify "$image" >"$log" 2>&1; then
    cat "$log"
    exit 0
  fi
  cat "$log" >&2
  if ! grep -Eqi 'Resource temporarily unavailable|Resource busy' "$log"; then
    exit 1
  fi
  if [[ "$attempt" == 3 ]]; then exit 1; fi
  sleep "$((attempt * 3))"
done
