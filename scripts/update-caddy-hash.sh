#!/usr/bin/env bash
# scripts/update-caddy-hash.sh
# Updates the caddy-cloudflare hash in packages/caddy-cloudflare.nix.
# Safe to run when the hash is already correct (no-op).
set -euo pipefail

PKG_FILE="packages/caddy-cloudflare.nix"

echo "Attempting to build caddy-cloudflare to verify hash..."
if nix build .#caddy-cloudflare --no-link 2>/dev/null; then
  echo "caddy-cloudflare hash is already correct, no update needed."
  exit 0
fi

echo "Hash mismatch detected, extracting expected hash..."
BUILD_OUTPUT=$(nix build .#caddy-cloudflare --no-link 2>&1 || true)

# The hash mismatch line looks like:
#   got:    sha256-<base64>
EXPECTED_HASH=$(echo "$BUILD_OUTPUT" | grep -oP '(?<=got:\s{4})sha256-\S+' | head -1)

if [[ -z "$EXPECTED_HASH" ]]; then
  echo "ERROR: Could not extract expected hash from build output."
  echo "$BUILD_OUTPUT"
  exit 1
fi

echo "Updating hash to: $EXPECTED_HASH"
CURRENT_HASH=$(grep -oP '(?<=hash = ")sha256-[^"]+' "$PKG_FILE" | head -1)
sed -i "s|$CURRENT_HASH|$EXPECTED_HASH|" "$PKG_FILE"
echo "Updated $PKG_FILE"
