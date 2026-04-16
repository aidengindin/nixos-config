#!/usr/bin/env bash
# scripts/update-ublock-hash.sh
# Updates the uBlock Origin version and hash in linux/chromium.nix.
# Safe to run when already up to date (no-op).
set -euo pipefail

CHROMIUM_FILE="linux/chromium.nix"

LATEST_TAG=$(gh api repos/gorhill/uBlock/releases/latest --jq '.tag_name')
LATEST_VERSION="${LATEST_TAG#v}"  # strip leading 'v' if present
DOWNLOAD_URL="https://github.com/gorhill/uBlock/releases/download/${LATEST_TAG}/uBlock0_${LATEST_VERSION}.chromium.zip"

CURRENT_VERSION=$(grep -oP '(?<=uBlock/releases/download/)[^/]+(?=/uBlock0_)' "$CHROMIUM_FILE" | head -1)

if [[ "$CURRENT_VERSION" == "$LATEST_TAG" ]]; then
  echo "uBlock Origin is already at ${LATEST_TAG}, no update needed."
  exit 0
fi

echo "Updating uBlock Origin from ${CURRENT_VERSION} to ${LATEST_TAG}..."

NIX32_HASH=$(nix-prefetch-url --unpack "$DOWNLOAD_URL" 2>/dev/null)
NEW_HASH=$(nix hash convert --hash-algo sha256 --from nix32 "$NIX32_HASH")

CURRENT_URL=$(grep -oP 'https://github\.com/gorhill/uBlock/releases/download/[^"]+' "$CHROMIUM_FILE" | head -1)
CURRENT_HASH=$(grep -A2 'gorhill/uBlock' "$CHROMIUM_FILE" | grep -oP '(?<=sha256 = ")sha256-[^"]+' | head -1)

sed -i "s|$CURRENT_URL|$DOWNLOAD_URL|" "$CHROMIUM_FILE"
sed -i "s|$CURRENT_HASH|$NEW_HASH|" "$CHROMIUM_FILE"

echo "Updated uBlock Origin to ${LATEST_TAG} (${NEW_HASH})"
