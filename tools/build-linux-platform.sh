#!/usr/bin/env sh
set -eu

if [ -z "${ELTEN_LINUX_ARCH:-}" ]; then
  echo "ELTEN_LINUX_ARCH is not set." >&2
  exit 2
fi

case "$ELTEN_LINUX_ARCH" in
  arm64|x64|x86) ;;
  *)
    echo "Unsupported Linux architecture: $ELTEN_LINUX_ARCH" >&2
    exit 2
    ;;
esac

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
BUILD_ID=${ELTEN_BUILD_ID:-}
JOBS=${ELTEN_LINUX_JOBS:-1}
BUILD_DIR=${ELTEN_LINUX_BUILD_DIR:-"$ROOT/build/launcher-linux-$ELTEN_LINUX_ARCH"}
GENERATOR=${ELTEN_CMAKE_GENERATOR:-"Unix Makefiles"}

usage() {
  cat <<EOF
Usage: tools/build-linux-$ELTEN_LINUX_ARCH.sh [options] [-- CMake arguments]

Options:
  --build-id ID       Embed ID in the launcher
  -j, --jobs N        Parallel build jobs (default: $JOBS)
  -h, --help          Show this help
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --build-id)
      [ "$#" -ge 2 ] || { echo "--build-id requires a value" >&2; exit 2; }
      BUILD_ID=$2
      shift 2
      ;;
    --build-id=*)
      BUILD_ID=${1#*=}
      shift
      ;;
    -j|--jobs)
      [ "$#" -ge 2 ] || { echo "$1 requires a value" >&2; exit 2; }
      JOBS=$2
      shift 2
      ;;
    --jobs=*)
      JOBS=${1#*=}
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    *)
      break
      ;;
  esac
done

case "$JOBS" in
  ''|*[!0-9]*|0)
    echo "jobs must be a positive integer" >&2
    exit 2
    ;;
esac

for command_name in cmake file; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "$command_name not found." >&2
    exit 1
  fi
done

echo "Configuring Elten launcher linux-$ELTEN_LINUX_ARCH..."
cmake -S "$ROOT" -B "$BUILD_DIR" -G "$GENERATOR" \
  -DCMAKE_BUILD_TYPE=Release \
  -DELTEN_BUILD_ID="$BUILD_ID" \
  -DELTEN_LINUX_ARCH="$ELTEN_LINUX_ARCH" \
  "$@"

echo "Building Elten release linux-$ELTEN_LINUX_ARCH..."
cmake --build "$BUILD_DIR" --target EltenApp --parallel "$JOBS"

RELEASE_DIR="$ROOT/build/release/linux"
LAUNCHER="$RELEASE_DIR/elten-$ELTEN_LINUX_ARCH"
RUNTIME_DIR="$RELEASE_DIR/bin/linux-$ELTEN_LINUX_ARCH"

[ -x "$LAUNCHER" ] || { echo "Missing executable: $LAUNCHER" >&2; exit 1; }
[ -d "$RUNTIME_DIR" ] || { echo "Missing runtime: $RUNTIME_DIR" >&2; exit 1; }
if [ -e "$RELEASE_DIR/elten" ] || [ -L "$RELEASE_DIR/elten" ]; then
  echo "Platform release unexpectedly contains the multiarch facade: $RELEASE_DIR/elten" >&2
  exit 1
fi

DESCRIPTION=$(file "$LAUNCHER")
case "$ELTEN_LINUX_ARCH" in
  arm64)
    echo "$DESCRIPTION" | grep -q "ELF 64-bit" && echo "$DESCRIPTION" | grep -q "ARM aarch64" ||
      { echo "Unexpected arm64 launcher: $DESCRIPTION" >&2; exit 1; }
    ;;
  x64)
    echo "$DESCRIPTION" | grep -q "ELF 64-bit" && echo "$DESCRIPTION" | grep -q "x86-64" ||
      { echo "Unexpected x64 launcher: $DESCRIPTION" >&2; exit 1; }
    ;;
  x86)
    echo "$DESCRIPTION" | grep -q "ELF 32-bit" && echo "$DESCRIPTION" | grep -q "Intel 80386" ||
      { echo "Unexpected x86 launcher: $DESCRIPTION" >&2; exit 1; }
    ;;
esac

echo "Built $LAUNCHER"
