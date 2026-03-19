#!/bin/sh
# Install or update ~/.local/bin/cursor shim. Skips if existing file is already our shim.
set -eu

TARGET_SHIM="${TARGET_SHIM:-$HOME/.local/bin/cursor}"
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
LIB_DIR="${HOME}/.local/share/cursor-installer"

SOURCE_SHIM="${SOURCE_SHIM:-}"
if [ -z "$SOURCE_SHIM" ]; then
  if [ -f "$LIB_DIR/shim.sh" ]; then
    SOURCE_SHIM="$LIB_DIR/shim.sh"
  elif [ -f "$SCRIPT_DIR/shim.sh" ]; then
    SOURCE_SHIM="$SCRIPT_DIR/shim.sh"
  elif [ -f "$SCRIPT_DIR/../shim.sh" ]; then
    SOURCE_SHIM="$SCRIPT_DIR/../shim.sh"
  fi
fi

if [ -z "$SOURCE_SHIM" ] || [ ! -f "$SOURCE_SHIM" ]; then
  echo "Error: shim.sh source not found." >&2
  exit 1
fi

is_shim() {
  file="$1"
  [ -f "$file" ] || return 1
  first_line=$(head -n 1 "$file" 2>/dev/null || true)
  case "$first_line" in
    "#!/bin/sh"|\
    "#!/usr/bin/env sh"|\
    "#!/bin/bash"|\
    "#!/usr/bin/env bash")
      ;;
    *)
      return 1
      ;;
  esac
  if grep -q "Find cursor executable in PATH" "$file" 2>/dev/null; then
    return 0
  fi
  if grep -q "cursor-installer" "$file" 2>/dev/null; then
    return 0
  fi
  return 1
}

is_current_shim() {
  is_shim "$TARGET_SHIM" || return 1
  cmp -s "$SOURCE_SHIM" "$TARGET_SHIM"
}

if is_current_shim; then
  echo "Cursor shim already installed; skipping."
  exit 0
fi

if [ ! -e "$TARGET_SHIM" ]; then
  mkdir -p "$(dirname "$TARGET_SHIM")"
  cp "$SOURCE_SHIM" "$TARGET_SHIM"
  chmod +x "$TARGET_SHIM"
  echo "Installed cursor shim at $TARGET_SHIM"
  exit 0
fi

if ! is_shim "$TARGET_SHIM"; then
  echo "Skipping shim update; existing cursor is not a shim: $TARGET_SHIM"
  exit 0
fi

cp "$SOURCE_SHIM" "$TARGET_SHIM"
chmod +x "$TARGET_SHIM"
echo "Updated cursor shim at $TARGET_SHIM"
