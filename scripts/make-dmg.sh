#!/usr/bin/env bash
# Build FocusWork (Release), sign ad-hoc, wrap in a drag-to-Applications DMG.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED="${ROOT}/.build/DerivedData"
APP_NAME="FocusWork.app"
RELEASE_APP="${DERIVED}/Build/Products/Release/${APP_NAME}"
STAGING="${ROOT}/.build/dmg_staging"
DIST="${ROOT}/dist"
DMG_NAME="FocusWork.dmg"

mkdir -p "${DIST}"

echo "==> Building Release (unsigned binary; we sign after stripping xattrs)…"
xcodebuild -project "${ROOT}/FocusWork.xcodeproj" -scheme FocusWork -configuration Release \
  -derivedDataPath "${DERIVED}" -destination 'generic/platform=macOS' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO \
  build ONLY_ACTIVE_ARCH=NO

[[ -d "${RELEASE_APP}" ]] || { echo "Missing ${RELEASE_APP}"; exit 1; }

echo "==> Staging DMG contents…"
rm -rf "${STAGING}"
mkdir -p "${STAGING}"
# Avoid copying HFS+ resource forks / Finder info from the source tree
ditto --norsrc "${RELEASE_APP}" "${STAGING}/${APP_NAME}"

echo "==> Clearing extended attributes (required for codesign on some trees)…"
find "${STAGING}" -print0 | xargs -0 xattr -c 2>/dev/null || true

echo "==> Ad-hoc signing…"
codesign --force --deep --sign - "${STAGING}/${APP_NAME}"

ln -sf /Applications "${STAGING}/Applications"

echo "==> Creating compressed DMG…"
rm -f "${DIST}/${DMG_NAME}"
hdiutil create -volname "FocusWork" -srcfolder "${STAGING}" -ov -format UDZO \
  -imagekey zlib-level=9 "${DIST}/${DMG_NAME}"

echo "Done: ${DIST}/${DMG_NAME}"
