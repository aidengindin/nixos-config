#!/usr/bin/env bash
# scripts/update-claude-desktop.sh
# Updates the pinned version + hash in packages/claude-desktop.nix to the latest
# release in Anthropic's official apt repository. Safe to run when already current (no-op).
set -euo pipefail

PKG_FILE="packages/claude-desktop.nix"
PACKAGES_URL="https://downloads.claude.ai/claude-desktop/apt/stable/dists/stable/main/binary-amd64/Packages"
POOL_BASE="https://downloads.claude.ai/claude-desktop/apt/stable"

echo "Fetching apt package index..."
INDEX=$(curl -fsSL "$PACKAGES_URL")

# The Packages index lists releases oldest-first; take the last stanza's Version + SHA256.
LATEST_VERSION=$(echo "$INDEX" | awk '/^Version:/{v=$2} END{print v}')
LATEST_SHA256_HEX=$(echo "$INDEX" | awk '/^SHA256:/{h=$2} END{print h}')

if [[ -z "$LATEST_VERSION" || -z "$LATEST_SHA256_HEX" ]]; then
  echo "ERROR: could not parse latest version/hash from the apt index." >&2
  exit 1
fi

CURRENT_VERSION=$(grep -oP '(?<=version = ")[^"]+' "$PKG_FILE" | head -1)

if [[ "$CURRENT_VERSION" == "$LATEST_VERSION" ]]; then
  echo "claude-desktop is already at ${LATEST_VERSION}, no update needed."
  exit 0
fi

# The apt index carries the hash in hex; the derivation pins it as SRI.
LATEST_SHA256_SRI=$(nix hash convert --hash-algo sha256 --from base16 "$LATEST_SHA256_HEX")

echo "Updating claude-desktop from ${CURRENT_VERSION} to ${LATEST_VERSION}..."

CURRENT_SRI=$(grep -oP '(?<=hash = ")sha256-[^"]+' "$PKG_FILE" | head -1)

sed -i "s|version = \"${CURRENT_VERSION}\"|version = \"${LATEST_VERSION}\"|" "$PKG_FILE"
sed -i "s|${CURRENT_SRI}|${LATEST_SHA256_SRI}|" "$PKG_FILE"

echo "Updated ${PKG_FILE} to ${LATEST_VERSION} (${LATEST_SHA256_SRI})"
echo "Download URL: ${POOL_BASE}/pool/main/c/claude-desktop/claude-desktop_${LATEST_VERSION}_amd64.deb"
echo "Now run: nix build .#claude-desktop"
