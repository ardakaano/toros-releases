#!/usr/bin/env bash
# Installs the latest Toros release into /Applications.
#
#   curl -fsSL https://raw.githubusercontent.com/ardakaano/toros-releases/main/install.sh | bash
#
# What it does: downloads the DMG and its SHA-256, verifies the checksum, copies Toros.app to
# /Applications (replacing an older one), and opens it. It never uses sudo.
# Files fetched with curl are not quarantine-flagged, so the ad-hoc signed build opens without a
# Gatekeeper prompt. (A browser download of an un-notarized build would be blocked.)
#
# Options (environment variables):
#   TOROS_VERSION=v0.1.0   install a specific release instead of the newest
#   TOROS_DEST=~/Applications   install somewhere other than /Applications
#   TOROS_NO_OPEN=1        don't launch it afterwards
#   TOROS_NO_GH=1          use plain curl even if the GitHub CLI is available
set -euo pipefail

REPO="${TOROS_REPO:-ardakaano/toros-releases}"
DEST="${TOROS_DEST:-/Applications}"
TMP="$(mktemp -d)"
MNT=""
cleanup() { [ -n "$MNT" ] && hdiutil detach "$MNT" -quiet 2>/dev/null || true; rm -rf "$TMP"; }
trap cleanup EXIT

[ "$(uname -s)" = Darwin ] || { echo "Toros is a macOS app."; exit 1; }
[ "$(sw_vers -productVersion | cut -d. -f1)" -ge 14 ] || { echo "Toros needs macOS 14 or newer."; exit 1; }

echo "==> Looking up the latest Toros release in $REPO"
# `releases/latest` ignores pre-releases, so ask for the newest release of any kind.
if [ -z "${TOROS_NO_GH:-}" ] && command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  TAG="${TOROS_VERSION:-$(gh release list --repo "$REPO" --limit 1 --json tagName --jq '.[0].tagName')}"
  [ -n "$TAG" ] || { echo "No release found in $REPO."; exit 1; }
  echo "==> Downloading $TAG"
  gh release download "$TAG" --repo "$REPO" --pattern 'Toros-*.dmg*' --dir "$TMP"
else
  TAG="${TOROS_VERSION:-$(curl -fsSL "https://api.github.com/repos/$REPO/releases?per_page=1" | grep -m1 '"tag_name"' | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/')}"
  [ -n "$TAG" ] || { echo "No release found in $REPO."; exit 1; }
  echo "==> Downloading $TAG"
  base="https://github.com/$REPO/releases/download/$TAG"
  ver="${TAG#v}"
  curl -fsSL -o "$TMP/Toros-$ver.dmg" "$base/Toros-$ver.dmg"
  curl -fsSL -o "$TMP/Toros-$ver.dmg.sha256" "$base/Toros-$ver.dmg.sha256"
fi

DMG="$(ls "$TMP"/Toros-*.dmg | head -1)"
if [ -f "$DMG.sha256" ]; then
  echo "==> Verifying checksum"
  (cd "$TMP" && shasum -a 256 -c "$(basename "$DMG").sha256")
fi

echo "==> Installing to $DEST"
MNT="$(hdiutil attach "$DMG" -nobrowse -readonly | grep -o '/Volumes/.*' | tail -1)"
[ -n "$MNT" ] || { echo "Could not mount the disk image."; exit 1; }
[ -d "$MNT/Toros.app" ] || { echo "Toros.app not found in the disk image."; exit 1; }
if pgrep -f "$DEST/Toros.app/Contents/MacOS/Toros" >/dev/null; then echo "    Toros is running; quit it first (⌘Q), then run this again."; exit 1; fi
rm -rf "$DEST/Toros.app"
cp -R "$MNT/Toros.app" "$DEST/Toros.app"
xattr -dr com.apple.quarantine "$DEST/Toros.app" 2>/dev/null || true

echo "==> Installed $(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$DEST/Toros.app/Contents/Info.plist") → $DEST/Toros.app"
[ -n "${TOROS_NO_OPEN:-}" ] || open "$DEST/Toros.app"
