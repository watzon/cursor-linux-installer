#!/bin/sh
set -eu
# cursor-linux-installer-shim

# Find cursor executable in PATH, excluding the current shim
canonicalize_path() {
  path="$1"

  if command -v realpath >/dev/null 2>&1; then
    realpath "$path" 2>/dev/null && return 0
  fi

  if command -v readlink >/dev/null 2>&1; then
    readlink -f "$path" 2>/dev/null && return 0
  fi

  case "$path" in
    */*)
      dir_part=${path%/*}
      base_part=${path##*/}
      ;;
    *)
      dir_part=.
      base_part=$path
      ;;
  esac

  old_pwd=$(pwd)
  if cd "$dir_part" 2>/dev/null; then
    resolved_dir=$(pwd -P)
    cd "$old_pwd" || exit 1
    printf '%s/%s\n' "$resolved_dir" "$base_part"
    return 0
  fi

  cd "$old_pwd" || exit 1
  printf '%s\n' "$path"
}

same_path() {
  left=$(canonicalize_path "$1" || printf '%s\n' "$1")
  right=$(canonicalize_path "$2" || printf '%s\n' "$2")
  [ "$left" = "$right" ]
}

is_ignored_cursor_path() {
  case "$1" in
    # Ignore transient AppImage runtime mounts; they are not stable CLI installs
    # and can shadow the shim inside terminals launched from Cursor itself.
    /tmp/.mount_*)
      return 0
      ;;
  esac

  return 1
}

SHIM_PATH=$(canonicalize_path "$HOME/.local/bin/cursor" || printf '%s\n' "$HOME/.local/bin/cursor")
case "${0:-}" in
  */*)
    SHIM_PATH=$(canonicalize_path "$0" || printf '%s\n' "$0")
    ;;
esac

find_cursor() {
  old_IFS="$IFS"
  IFS=:
  for dir in $PATH; do
    [ -n "$dir" ] || continue
    cursor_path="$dir/cursor"
    [ -x "$cursor_path" ] || continue

    if is_ignored_cursor_path "$cursor_path"; then
      continue
    fi

    if same_path "$cursor_path" "$SHIM_PATH"; then
      continue
    fi

    IFS="$old_IFS"
    echo "$cursor_path"
    return 0
  done
  IFS="$old_IFS"
  return 1
}

first_arg="${1:-}"
CURSOR_INSTALLER=$(command -v cursor-installer 2>/dev/null || true)
AGENT_BIN="$HOME/.local/bin/agent"

if [ "$first_arg" = "agent" ]; then
  if [ -x "$AGENT_BIN" ]; then
    exec "$AGENT_BIN" "$@"
  fi
  echo "Error: Cursor agent not found at $AGENT_BIN" 1>&2
  exit 1
fi

case "$first_arg" in
  --update|-u|--check|-c|--extract|--no-fuse|--reinstall-desktop)
    if [ -n "${CURSOR_INSTALLER:-}" ]; then
      exec "$CURSOR_INSTALLER" "$@"
    fi
    ;;
esac

OTHER_CURSOR=$(find_cursor || true)

if [ -n "${OTHER_CURSOR:-}" ]; then
  exec "$OTHER_CURSOR" "$@"
fi

if [ -n "${CURSOR_INSTALLER:-}" ]; then
  exec "$CURSOR_INSTALLER" "$@"
fi

echo "Error: No Cursor IDE installation found." 1>&2
echo "Install/update with: cursor-installer --update [stable|latest]" 1>&2
echo "Or, install Cursor at https://cursor.com/download" 1>&2
exit 1
