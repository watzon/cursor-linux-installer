#!/bin/sh
set -eu

# Find cursor executable in PATH, excluding the current shim
find_cursor() {
  old_IFS="$IFS"
  IFS=:
  for dir in $PATH; do
    [ -n "$dir" ] || continue
    cursor_path="$dir/cursor"
    if [ "$cursor_path" != "$HOME/.local/bin/cursor" ] && [ -x "$cursor_path" ]; then
      IFS="$old_IFS"
      echo "$cursor_path"
      return 0
    fi
  done
  IFS="$old_IFS"
  return 1
}

OTHER_CURSOR=$(find_cursor || true)
CURSOR_INSTALLER=$(command -v cursor-installer 2>/dev/null || true)
AGENT_BIN="$HOME/.local/bin/agent"

if [ -n "${OTHER_CURSOR:-}" ]; then
  exec "$OTHER_CURSOR" "$@"
fi

first_arg="${1:-}"

if [ "$first_arg" = "agent" ]; then
  if [ -x "$AGENT_BIN" ]; then
    exec "$AGENT_BIN" "$@"
  fi
  echo "Error: Cursor agent not found at $AGENT_BIN" 1>&2
  exit 1
fi

if [ -n "${CURSOR_INSTALLER:-}" ]; then
  exec "$CURSOR_INSTALLER" "$@"
fi

echo "Error: No Cursor IDE installation found." 1>&2
echo "Install/update with: cursor-installer --update [stable|latest]" 1>&2
echo "Or, install Cursor at https://cursor.com/download" 1>&2
exit 1
