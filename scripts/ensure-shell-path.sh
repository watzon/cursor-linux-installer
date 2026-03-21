#!/bin/sh
# Ensure supported interactive shells source cursor-installer's PATH helper.
set -eu

ACTION="${1:-ensure}"
LIB_DIR="${HOME}/.local/share/cursor-installer"
SHELL_PATH_SCRIPT="${SHELL_PATH_SCRIPT:-$LIB_DIR/shell-path.sh}"
START_MARKER="# >>> cursor-installer path >>>"
END_MARKER="# <<< cursor-installer path <<<"

build_source_block() {
  cat <<EOF
$START_MARKER
if [ -f "$SHELL_PATH_SCRIPT" ]; then
  . "$SHELL_PATH_SCRIPT"
fi
$END_MARKER
EOF
}

print_target_files() {
  if [ -n "${TARGET_SHELL_FILES:-}" ]; then
    old_IFS="$IFS"
    IFS=:
    for file in $TARGET_SHELL_FILES; do
      [ -n "$file" ] && printf '%s\n' "$file"
    done
    IFS="$old_IFS"
    return 0
  fi

  if [ -n "${TARGET_SHELL_RC:-}" ]; then
    printf '%s\n' "$TARGET_SHELL_RC"
    return 0
  fi

  shell_name=$(basename "${SHELL:-}")
  case "$shell_name" in
    bash)
      printf '%s\n' "$HOME/.bashrc"
      ;;
    zsh)
      printf '%s\n' "$HOME/.zshrc"
      ;;
    sh|dash|ksh)
      printf '%s\n' "$HOME/.profile"
      ;;
    *)
      echo "Skipping shell PATH setup; unsupported shell: ${SHELL:-unknown}" >&2
      return 1
      ;;
  esac
}

strip_managed_block() {
  file="$1"
  tmp="$2"

  if [ -f "$file" ]; then
    awk -v start="$START_MARKER" -v end="$END_MARKER" '
      $0 == start { skip = 1; next }
      skip && $0 == end { skip = 0; next }
      !skip { print }
    ' "$file" > "$tmp"
  else
    : > "$tmp"
  fi
}

ensure_block() {
  file="$1"
  tmp=$(mktemp)
  mkdir -p "$(dirname "$file")"
  strip_managed_block "$file" "$tmp"

  if [ -s "$tmp" ]; then
    printf '\n' >> "$tmp"
  fi

  build_source_block >> "$tmp"

  if [ -f "$file" ] && cmp -s "$tmp" "$file"; then
    rm -f "$tmp"
    echo "Shell PATH setup already present in $file"
    return 0
  fi

  mv "$tmp" "$file"
  echo "Ensured shell PATH setup in $file"
}

remove_block() {
  file="$1"
  [ -f "$file" ] || return 0

  tmp=$(mktemp)
  strip_managed_block "$file" "$tmp"

  if cmp -s "$tmp" "$file"; then
    rm -f "$tmp"
    return 0
  fi

  mv "$tmp" "$file"
  echo "Removed shell PATH setup from $file"
}

if [ "$ACTION" = "ensure" ] && [ ! -f "$SHELL_PATH_SCRIPT" ]; then
  echo "Error: shell-path.sh source not found at $SHELL_PATH_SCRIPT" >&2
  exit 1
fi

if ! target_files=$(print_target_files); then
  exit 0
fi

printf '%s\n' "$target_files" | while IFS= read -r file; do
  [ -n "$file" ] || continue

  case "$ACTION" in
    ensure)
      ensure_block "$file"
      ;;
    --remove|remove)
      remove_block "$file"
      ;;
    *)
      echo "Unknown action: $ACTION" >&2
      exit 1
      ;;
  esac
done
