#!/usr/bin/env sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"

BUILD_APP=0
BUILD_PKG=0
SIGN=0
SIGN_APP_IDENTITY=${ELTEN_MACOS_APP_IDENTITY:-${MACOS_APP_IDENTITY:-Developer ID Application}}
SIGN_INSTALLER_IDENTITY=${ELTEN_MACOS_INSTALLER_IDENTITY:-${MACOS_INSTALLER_IDENTITY:-Developer ID Installer}}
NOTARY_PROFILE=${ELTEN_NOTARY_PROFILE:-${NOTARY_PROFILE:-notary}}
NOTARY_APPLE_ID=${ELTEN_NOTARY_APPLE_ID:-}
NOTARY_PASSWORD=${ELTEN_NOTARY_PASSWORD:-}
NOTARY_TEAM_ID=${ELTEN_NOTARY_TEAM_ID:-}
SIGN_ENTITLEMENTS=${ELTEN_MACOS_ENTITLEMENTS:-${MACOS_ENTITLEMENTS:-$ROOT/tools/macos-entitlements.plist}}
BUILD_ID=
CMAKE_ARGS=

while [ "$#" -gt 0 ]; do
  case "$1" in
    --app)
      BUILD_APP=1
      shift
      ;;
    --pkg)
      BUILD_APP=1
      BUILD_PKG=1
      shift
      ;;
    --sign)
      SIGN=1
      shift
      ;;
    --sign-app-identity)
      SIGN_APP_IDENTITY=${2:-}
      shift 2
      ;;
    --sign-app-identity=*)
      SIGN_APP_IDENTITY=${1#*=}
      shift
      ;;
    --sign-installer-identity)
      SIGN_INSTALLER_IDENTITY=${2:-}
      shift 2
      ;;
    --sign-installer-identity=*)
      SIGN_INSTALLER_IDENTITY=${1#*=}
      shift
      ;;
    --notary-profile)
      NOTARY_PROFILE=${2:-}
      shift 2
      ;;
    --notary-profile=*)
      NOTARY_PROFILE=${1#*=}
      shift
      ;;
    --entitlements)
      SIGN_ENTITLEMENTS=${2:-}
      shift 2
      ;;
    --entitlements=*)
      SIGN_ENTITLEMENTS=${1#*=}
      shift
      ;;
    --build-id)
      BUILD_ID=${2:-}
      shift 2
      ;;
    --build-id=*)
      BUILD_ID=${1#*=}
      shift
      ;;
    --)
      shift
      while [ "$#" -gt 0 ]; do
        CMAKE_ARGS="${CMAKE_ARGS} $1"
        shift
      done
      break
      ;;
    *)
      CMAKE_ARGS="${CMAKE_ARGS} $1"
      shift
      ;;
  esac
done

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "$1 not found. Install Xcode Command Line Tools or add it to PATH." >&2
    exit 1
  fi
}

SIGN_CMAKE=OFF
if [ "$SIGN" -eq 1 ]; then
  SIGN_CMAKE=ON
fi

TARGET=EltenLauncher
if [ "$BUILD_PKG" -eq 1 ]; then
  TARGET=EltenPkg
elif [ "$BUILD_APP" -eq 1 ]; then
  TARGET=EltenApp
fi

echo "Build options: target=$TARGET sign=$SIGN"
if [ -n "$BUILD_ID" ]; then
  echo "Build ID: $BUILD_ID"
fi
if [ "$SIGN" -eq 1 ]; then
  echo "App signing identity: $SIGN_APP_IDENTITY"
  if [ "$BUILD_PKG" -eq 1 ]; then
    echo "Installer signing identity: $SIGN_INSTALLER_IDENTITY"
  fi
  echo "Notary profile: $NOTARY_PROFILE"
  echo "Entitlements: $SIGN_ENTITLEMENTS"
fi

require_cmd cmake

cmake --preset osx-arm64 \
  -DELTEN_BUILD_ID="$BUILD_ID" \
  -DELTEN_MACOS_SIGN="$SIGN_CMAKE" \
  -DELTEN_MACOS_APP_IDENTITY="$SIGN_APP_IDENTITY" \
  -DELTEN_MACOS_INSTALLER_IDENTITY="$SIGN_INSTALLER_IDENTITY" \
  -DELTEN_NOTARY_PROFILE="$NOTARY_PROFILE" \
  -DELTEN_NOTARY_APPLE_ID="$NOTARY_APPLE_ID" \
  -DELTEN_NOTARY_PASSWORD="$NOTARY_PASSWORD" \
  -DELTEN_NOTARY_TEAM_ID="$NOTARY_TEAM_ID" \
  -DELTEN_MACOS_ENTITLEMENTS="$SIGN_ENTITLEMENTS" \
  -DELTEN_ZSTD_LIBRARY="$ROOT/build/release/osx/bin/osx/libzstd.dylib" \
  $CMAKE_ARGS

cmake --build --preset osx-arm64-release --target "$TARGET"
