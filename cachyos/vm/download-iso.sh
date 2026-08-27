#!/usr/bin/env bash
set -euo pipefail

ISO_CACHE_DIR="${ISO_CACHE_DIR:-$HOME/.cache/cachyos-iso}"
MIRROR_BASE="https://mirror.cachyos.org/ISO/desktop"

mkdir -p "$ISO_CACHE_DIR"

# The desktop ISO directory is versioned (e.g. /ISO/desktop/260628/), and
# the version changes on every CachyOS release. Discover the latest one
# from the directory listing rather than hardcoding a version that will go
# stale.
latest_version=$(curl -fsSL "$MIRROR_BASE/" \
  | grep -oE 'href="[0-9]+/"' \
  | grep -oE '[0-9]+' \
  | sort -n \
  | tail -1)

if [ -z "$latest_version" ]; then
  echo "Could not determine latest CachyOS ISO version from $MIRROR_BASE/" >&2
  exit 1
fi

iso_name="cachyos-desktop-linux-${latest_version}.iso"
iso_url="$MIRROR_BASE/${latest_version}/${iso_name}"
sha_url="${iso_url}.sha256"
iso_path="$ISO_CACHE_DIR/$iso_name"
sha_path="$iso_path.sha256"

verify() {
  (cd "$ISO_CACHE_DIR" && sha256sum -c "$(basename "$sha_path")") >&2
}

if [ -f "$iso_path" ] && [ -f "$sha_path" ] && verify; then
  echo "Using cached, verified ISO: $iso_path" >&2
else
  echo "Downloading $iso_url" >&2
  curl -fsSL -o "$iso_path" "$iso_url"
  curl -fsSL -o "$sha_path" "$sha_url"
  verify
fi

echo "$iso_path"
