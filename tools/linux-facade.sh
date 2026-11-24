#!/bin/sh
set -eu

machine=$(uname -m) || {
  echo "Elten: cannot detect the Linux architecture." >&2
  exit 127
}

case "$machine" in
  aarch64|arm64) binary=elten-arm64 ;;
  x86_64|amd64) binary=elten-x64 ;;
  i386|i486|i586|i686|x86) binary=elten-x86 ;;
  *)
    echo "Elten: unsupported Linux architecture: $machine" >&2
    exit 127
    ;;
esac

facade=$(readlink -f -- "$0") || {
  echo "Elten: cannot resolve the facade path." >&2
  exit 127
}
launcher=${facade%/*}/$binary

if [ ! -x "$launcher" ]; then
  echo "Elten: missing executable for $machine: $launcher" >&2
  exit 127
fi

exec "$launcher" "$@"
