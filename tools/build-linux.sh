#!/usr/bin/env sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
RELEASE_DIR=${ELTEN_LINUX_RELEASE_DIR:-"$ROOT/build/release/linux"}
DIST_DIR=${ELTEN_LINUX_DIST_DIR:-"$ROOT/dist/linux"}
BUILD_PKG=0
BUILD_ZST=0

usage() {
  cat <<EOF
Usage: tools/build-linux.sh (--pkg | --zst) [options]

Options:
  --pkg                 Create dist/linux/elten-linux.run
  --zst                 Create dist/linux/elten-linux.tar.zst
  --release-dir DIR     Multiarch release root (default: $RELEASE_DIR)
  --dist-dir DIR        Output directory (default: $DIST_DIR)
  -h, --help            Show this help

Both --pkg and --zst may be selected in one invocation.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --pkg)
      BUILD_PKG=1
      shift
      ;;
    --zst)
      BUILD_ZST=1
      shift
      ;;
    --release-dir)
      [ "$#" -ge 2 ] || { echo "--release-dir requires a value" >&2; exit 2; }
      RELEASE_DIR=$2
      shift 2
      ;;
    --release-dir=*)
      RELEASE_DIR=${1#*=}
      shift
      ;;
    --dist-dir)
      [ "$#" -ge 2 ] || { echo "--dist-dir requires a value" >&2; exit 2; }
      DIST_DIR=$2
      shift 2
      ;;
    --dist-dir=*)
      DIST_DIR=${1#*=}
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [ "$BUILD_PKG" -eq 0 ] && [ "$BUILD_ZST" -eq 0 ]; then
  echo "Select --pkg, --zst, or both." >&2
  usage >&2
  exit 2
fi

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "$1 not found." >&2
    exit 1
  fi
}

for command_name in tar sha256sum mktemp wc tr tail head basename; do
  require_command "$command_name"
done
if [ "$BUILD_PKG" -eq 1 ]; then
  require_command gzip
fi
if [ "$BUILD_ZST" -eq 1 ]; then
  require_command zstd
fi

FACADE_SOURCE="$ROOT/tools/linux-facade.sh"
[ -f "$FACADE_SOURCE" ] || { echo "Missing Linux facade template: $FACADE_SOURCE" >&2; exit 1; }
[ -d "$RELEASE_DIR/data" ] || { echo "Missing release data: $RELEASE_DIR/data" >&2; exit 1; }
for architecture in arm64 x64 x86; do
  [ -x "$RELEASE_DIR/elten-$architecture" ] ||
    { echo "Missing release launcher: $RELEASE_DIR/elten-$architecture" >&2; exit 1; }
  [ -d "$RELEASE_DIR/bin/linux-$architecture" ] ||
    { echo "Missing release runtime: $RELEASE_DIR/bin/linux-$architecture" >&2; exit 1; }
done
[ -f "$ROOT/tools/elten.desktop" ] || { echo "Missing tools/elten.desktop" >&2; exit 1; }

# A platform release deliberately has no unsuffixed launcher. Only a verified
# three-architecture assembly receives the public facade.
cp "$FACADE_SOURCE" "$RELEASE_DIR/elten"
chmod 0755 "$RELEASE_DIR/elten"

mkdir -p "$DIST_DIR"
TEMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/elten-linux-package.XXXXXX")
RUN_TEMP="$DIST_DIR/.elten-linux.run.$$"
ZST_TEMP="$DIST_DIR/.elten-linux.tar.zst.$$"
trap 'rm -rf "$TEMP_ROOT"; rm -f "$RUN_TEMP" "$ZST_TEMP"' EXIT HUP INT TERM

copy_common_release_files() {
  destination=$1
  for source_path in "$RELEASE_DIR"/*; do
    name=$(basename "$source_path")
    case "$name" in
      bin|elten|elten-arm64|elten-x64|elten-x86) ;;
      *) cp -a "$source_path" "$destination/" ;;
    esac
  done
}

prepare_payload() {
  architecture=$1
  stage="$TEMP_ROOT/stage-$architecture"
  app_dir="$stage/opt/elten"
  payload="$TEMP_ROOT/payload-$architecture.tar.gz"

  mkdir -p "$app_dir/bin" "$stage/usr/share/applications"
  copy_common_release_files "$app_dir"
  cp -a "$RELEASE_DIR/bin/linux-$architecture" "$app_dir/bin/"
  cp "$RELEASE_DIR/elten-$architecture" "$app_dir/elten"
  chmod 0755 "$app_dir/elten"
  cp "$ROOT/tools/elten.desktop" "$stage/usr/share/applications/elten.desktop"
  tar -czpf "$payload" -C "$stage" opt usr
}

write_run_header() {
  header=$1
  arm64_start=$2
  arm64_size=$3
  arm64_sha=$4
  x64_start=$5
  x64_size=$6
  x64_sha=$7
  x86_start=$8
  x86_size=$9
  shift 9
  x86_sha=$1

  cat > "$header" <<'RUN_HEADER'
#!/bin/sh
set -eu
RUN_HEADER
  cat >> "$header" <<RUN_VALUES
PAYLOAD_ARM64_START=$arm64_start
PAYLOAD_ARM64_SIZE=$arm64_size
PAYLOAD_ARM64_SHA256='$arm64_sha'
PAYLOAD_X64_START=$x64_start
PAYLOAD_X64_SIZE=$x64_size
PAYLOAD_X64_SHA256='$x64_sha'
PAYLOAD_X86_START=$x86_start
PAYLOAD_X86_SIZE=$x86_size
PAYLOAD_X86_SHA256='$x86_sha'
RUN_VALUES
  cat >> "$header" <<'RUN_HEADER'

usage() {
  cat <<'EOF'
Elten Linux installer

Usage: elten-linux.run [options]

Options:
  --install-root DIR   Install below DIR instead of / (for testing/chroots)
  --silent             Suppress informational messages
  -h, --help           Show this help
EOF
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Elten installer: $1 not found." >&2
    exit 1
  fi
}

self_path=$0
command_path=$(command -v "$self_path" 2>/dev/null) && self_path=$command_path
case "$self_path" in
  /*) ;;
  *) self_path=$PWD/$self_path ;;
esac
resolved_path=$(readlink -f "$self_path" 2>/dev/null) && self_path=$resolved_path

install_root=/
silent=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --install-root)
      [ "$#" -ge 2 ] || { echo "--install-root requires a value" >&2; exit 2; }
      install_root=$2
      shift 2
      ;;
    --install-root=*)
      install_root=${1#*=}
      shift
      ;;
    --silent)
      silent=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

architecture=$(uname -m 2>/dev/null) ||
  { echo "Elten installer: cannot detect the system architecture." >&2; exit 1; }
case "$architecture" in
  aarch64|arm64)
    payload_start=$PAYLOAD_ARM64_START
    payload_size=$PAYLOAD_ARM64_SIZE
    payload_sha256=$PAYLOAD_ARM64_SHA256
    payload_arch=arm64
    ;;
  x86_64|amd64)
    payload_start=$PAYLOAD_X64_START
    payload_size=$PAYLOAD_X64_SIZE
    payload_sha256=$PAYLOAD_X64_SHA256
    payload_arch=x64
    ;;
  i386|i486|i586|i686|x86)
    payload_start=$PAYLOAD_X86_START
    payload_size=$PAYLOAD_X86_SIZE
    payload_sha256=$PAYLOAD_X86_SHA256
    payload_arch=x86
    ;;
  *)
    echo "Elten installer: unsupported system architecture: $architecture" >&2
    exit 1
    ;;
esac

if [ "$install_root" = "/" ] && [ "$(id -u)" -ne 0 ]; then
  if [ -d /opt/elten ] && [ -w /opt/elten ] && [ -w /usr/share/applications ]; then
    :
  elif command -v pkexec >/dev/null 2>&1; then
    if [ "$silent" -eq 1 ]; then
      exec pkexec "$self_path" --silent --install-root /
    else
      exec pkexec "$self_path" --install-root /
    fi
  else
    echo "Elten installer: root privileges are required; run it with sudo." >&2
    exit 1
  fi
fi

for command_name in tar gzip sha256sum mktemp wc tr tail head; do
  require_command "$command_name"
done

mkdir -p "$install_root"
payload_file=$(mktemp "${TMPDIR:-/tmp}/elten-payload.XXXXXX")
trap 'rm -f "$payload_file"' EXIT HUP INT TERM

tail -c "+$payload_start" "$self_path" | head -c "$payload_size" > "$payload_file"
actual_size=$(wc -c < "$payload_file")
actual_size=$(printf '%s' "$actual_size" | tr -d ' ')
if [ "$actual_size" != "$payload_size" ]; then
  echo "Elten installer: truncated $payload_arch payload." >&2
  exit 1
fi
actual_sha256=$(sha256sum "$payload_file")
actual_sha256=${actual_sha256%% *}
if [ "$actual_sha256" != "$payload_sha256" ]; then
  echo "Elten installer: invalid $payload_arch payload checksum." >&2
  exit 1
fi

[ "$silent" -eq 1 ] || echo "Installing Elten for $payload_arch..."
tar -xzpf "$payload_file" -C "$install_root"

for stale_arch in arm64 x64 x86; do
  rm -f "$install_root/opt/elten/elten-$stale_arch"
  if [ "$stale_arch" != "$payload_arch" ]; then
    rm -rf "$install_root/opt/elten/bin/linux-$stale_arch"
  fi
done

[ -x "$install_root/opt/elten/elten" ] ||
  { echo "Elten installer: installed launcher is missing." >&2; exit 1; }

if [ "$install_root" = "/" ] && command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database /usr/share/applications 2>/dev/null || true
fi

[ "$silent" -eq 1 ] || echo "Elten installed in $install_root/opt/elten."
exit 0
RUN_HEADER
}

create_run() {
  for architecture in arm64 x64 x86; do
    prepare_payload "$architecture"
  done

  arm64_payload="$TEMP_ROOT/payload-arm64.tar.gz"
  x64_payload="$TEMP_ROOT/payload-x64.tar.gz"
  x86_payload="$TEMP_ROOT/payload-x86.tar.gz"
  arm64_size=$(wc -c < "$arm64_payload" | tr -d ' ')
  x64_size=$(wc -c < "$x64_payload" | tr -d ' ')
  x86_size=$(wc -c < "$x86_payload" | tr -d ' ')
  arm64_sha=$(sha256sum "$arm64_payload"); arm64_sha=${arm64_sha%% *}
  x64_sha=$(sha256sum "$x64_payload"); x64_sha=${x64_sha%% *}
  x86_sha=$(sha256sum "$x86_payload"); x86_sha=${x86_sha%% *}

  header="$TEMP_ROOT/run-header"
  header_size=0
  attempt=0
  while :; do
    arm64_start=$((header_size + 1))
    x64_start=$((header_size + arm64_size + 1))
    x86_start=$((header_size + arm64_size + x64_size + 1))
    write_run_header "$header" \
      "$arm64_start" "$arm64_size" "$arm64_sha" \
      "$x64_start" "$x64_size" "$x64_sha" \
      "$x86_start" "$x86_size" "$x86_sha"
    new_header_size=$(wc -c < "$header" | tr -d ' ')
    [ "$new_header_size" = "$header_size" ] && break
    header_size=$new_header_size
    attempt=$((attempt + 1))
    [ "$attempt" -lt 10 ] ||
      { echo "Could not stabilize .run header offsets." >&2; exit 1; }
  done

  cat "$header" "$arm64_payload" "$x64_payload" "$x86_payload" > "$RUN_TEMP"
  chmod 0755 "$RUN_TEMP"
  mv -f "$RUN_TEMP" "$DIST_DIR/elten-linux.run"
  echo "Built $DIST_DIR/elten-linux.run"
}

create_zst() {
  stage="$TEMP_ROOT/zst-stage"
  mkdir -p "$stage/opt" "$stage/usr/share/applications"
  cp -a "$RELEASE_DIR" "$stage/opt/elten"
  cp "$ROOT/tools/elten.desktop" "$stage/usr/share/applications/elten.desktop"
  tar --zstd -cpf "$ZST_TEMP" -C "$stage" opt usr
  mv -f "$ZST_TEMP" "$DIST_DIR/elten-linux.tar.zst"
  echo "Built $DIST_DIR/elten-linux.tar.zst"
}

[ "$BUILD_PKG" -eq 0 ] || create_run
[ "$BUILD_ZST" -eq 0 ] || create_zst

rm -f \
  "$DIST_DIR/elten-linux-arm64.tar.zst" \
  "$DIST_DIR/elten-linux-x64.tar.zst" \
  "$DIST_DIR/elten-linux-x86.tar.zst"
rm -rf "$DIST_DIR/stage"
