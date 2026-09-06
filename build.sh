#!/bin/bash
#
# Build NAF Tools as a menu-bar .app (plus naf-tools CLI) and install to ~/Applications.
# Pass --dist to skip install and write a versioned zip under build/.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="NAF Tools"
EXEC="NAFTools"
BUILD="$ROOT/build"
APP="$BUILD/${APP_NAME}.app"
SDK="$(xcrun --show-sdk-path)"
DEST="$HOME/Applications/${APP_NAME}.app"
SIGN_CN="NAF Tools Signing"
SKIP_INSTALL=0
MAKE_ZIP=0

for arg in "$@"; do
  case "$arg" in
    --dist)
      SKIP_INSTALL=1
      MAKE_ZIP=1
      ;;
    --skip-install)
      SKIP_INSTALL=1
      ;;
    *)
      echo "unknown argument: $arg" >&2
      echo "usage: $0 [--dist] [--skip-install]" >&2
      exit 1
      ;;
  esac
done

ensure_codesign_identity() {
  if [[ "${CI:-}" == "true" ]]; then
    echo ""
    return 0
  fi
  if security find-identity -p codesigning 2>/dev/null | grep -F "$SIGN_CN" >/dev/null; then
    echo "$SIGN_CN"
    return 0
  fi

  local work="$BUILD/signing-identity"
  mkdir -p "$work"
  /usr/bin/openssl req -new -x509 -days 3650 -nodes \
    -subj "/CN=$SIGN_CN/" \
    -addext "extendedKeyUsage=codeSigning" \
    -addext "keyUsage=digitalSignature" \
    -keyout "$work/key.pem" -out "$work/cert.pem" >/dev/null 2>&1
  # macOS `security import` rejects OpenSSL 3 AES PKCS#12; use 3DES.
  /usr/bin/openssl pkcs12 -export -inkey "$work/key.pem" -in "$work/cert.pem" \
    -out "$work/naf.p12" -passout pass:naf -name "$SIGN_CN" \
    -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1 >/dev/null 2>&1

  local keychain="$HOME/Library/Keychains/login.keychain-db"
  if [[ ! -f "$keychain" ]]; then
    keychain="$HOME/Library/Keychains/login.keychain"
  fi

  if ! security import "$work/naf.p12" -k "$keychain" -P naf \
      -T /usr/bin/codesign -T /usr/bin/security >/dev/null 2>&1; then
    echo "warning: could not import a stable signing identity; using ad-hoc" >&2
    echo ""
    return 0
  fi

  if security find-identity -p codesigning 2>/dev/null | grep -F "$SIGN_CN" >/dev/null; then
    echo "$SIGN_CN"
  else
    echo ""
  fi
}

mkdir -p "$BUILD"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "→ app icon"
swiftc -O -sdk "$SDK" -framework AppKit \
  -o "$BUILD/make-icon" \
  "$ROOT/scripts/MakeIcon.swift"
"$BUILD/make-icon" "$APP/Contents/Resources/AppIcon.icns"

cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

CORE_SOURCES=("$ROOT"/Sources/Core/*.swift)
APP_SOURCES=("$ROOT"/Sources/App/*.swift)
CLI_SOURCES=("$ROOT"/Sources/CLI/*.swift)
HELPER_SOURCES=("$ROOT"/Sources/Helpers/*.swift)
SWIFTC_COMMON=(
  -parse-as-library -O -swift-version 5
  -target arm64-apple-macosx14.0
  -sdk "$SDK"
  -framework AppKit
  -framework IOKit
  -framework CoreWLAN
  -framework Network
  -framework SystemConfiguration
  -framework CoreGraphics
  -framework ApplicationServices
)

echo "→ compile app"
swiftc "${SWIFTC_COMMON[@]}" \
  -framework SwiftUI \
  -framework ServiceManagement \
  -o "$APP/Contents/MacOS/$EXEC" \
  "${CORE_SOURCES[@]}" "${APP_SOURCES[@]}"

echo "→ compile naf-tools CLI"
swiftc "${SWIFTC_COMMON[@]}" \
  -o "$APP/Contents/MacOS/naf-tools" \
  "${CORE_SOURCES[@]}" "${CLI_SOURCES[@]}"

echo "→ compile naf-tools-scroll helper"
swiftc "${SWIFTC_COMMON[@]}" \
  -o "$APP/Contents/MacOS/naf-tools-scroll" \
  "${CORE_SOURCES[@]}" "${HELPER_SOURCES[@]}"

echo "→ sign"
SIGN_ID="$(ensure_codesign_identity)"
if [[ -n "$SIGN_ID" ]] && codesign --force --sign "$SIGN_ID" --identifier com.alessandro.naf-tools "$APP" >/dev/null 2>&1; then
  echo "  signed with $SIGN_ID"
else
  echo "  signed ad-hoc (rebuilds will need Accessibility toggled again)"
  codesign --force --sign - --identifier com.alessandro.naf-tools "$APP" >/dev/null
fi

if [[ "$MAKE_ZIP" == "1" ]]; then
  VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
  ZIP="$BUILD/NAF-Tools-${VERSION}.zip"
  rm -f "$ZIP"
  ditto -c -k --keepParent "$APP" "$ZIP"
  echo
  echo "Dist: $ZIP"
fi

if [[ "$SKIP_INSTALL" == "1" ]]; then
  echo "Built: $APP"
  exit 0
fi

mkdir -p "$HOME/Applications"
rm -rf "$DEST"
cp -R "$APP" "$DEST"
xattr -cr "$DEST" 2>/dev/null || true
touch "$DEST"

BIN_DIR="$HOME/.local/bin"
mkdir -p "$BIN_DIR"
ln -sf "$DEST/Contents/MacOS/naf-tools" "$BIN_DIR/naf-tools"

echo
echo "Installed: $DEST"
echo "CLI: $BIN_DIR/naf-tools"
echo "Open it from the menu bar (N logo)."
echo "Launch with:  open \"$DEST\""
if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
  echo "Add the CLI to your PATH:  export PATH=\"$BIN_DIR:\$PATH\""
fi
