#!/usr/bin/env sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ELTEN_LINUX_ARCH=x86
export ELTEN_LINUX_ARCH
exec /bin/sh "$SCRIPT_DIR/build-linux-platform.sh" "$@"
