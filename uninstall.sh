#!/usr/bin/env bash

set -e

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_OWNER=${REPO_OWNER:-watzon}
REPO_BRANCH=${REPO_BRANCH:-main}
REPO_NAME=${REPO_NAME:-cursor-linux-installer}
BASE_RAW_URL="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${REPO_BRANCH}"
LIB_DIR="$HOME/.local/share/cursor-installer"
LIB_PATH="$SCRIPT_DIR/lib.sh"
SHARED_LIB="$LIB_DIR/lib.sh"
LIB_URL="$BASE_RAW_URL/lib.sh"

# Source shared helpers (local repo, installed lib, or download)
if [ -f "$LIB_PATH" ]; then
    # shellcheck disable=SC1090
    source "$LIB_PATH"
elif [ -f "$SHARED_LIB" ]; then
    # shellcheck disable=SC1090
    source "$SHARED_LIB"
else
    mkdir -p "$LIB_DIR"
    curl -fsSL "$LIB_URL" -o "$SHARED_LIB" || {
        echo "Failed to download lib.sh from GitHub" >&2
        exit 1
    }
    # shellcheck disable=SC1090
    source "$SHARED_LIB"
fi

CLI_NAME="cursor-installer"
CLI_PATH="$HOME/.local/bin/$CLI_NAME"
LEGACY_CLI="$HOME/.local/bin/cursor"

log_step "Uninstalling Cursor..."

# Remove the Cursor AppImage
cursor_appimage=$(find_cursor_appimage)
if [ -n "$cursor_appimage" ]; then
    log_step "Removing Cursor AppImage..."
    safe_remove "$cursor_appimage" "Cursor AppImage"
else
    log_warn "Cursor AppImage not found."
fi

# Remove the cursor-installer script from ~/.local/bin
log_step "Removing cursor-installer script..."
safe_remove "$CLI_PATH" "cursor-installer script"

# Remove shared lib (installed by installer)
safe_remove "$SHARED_LIB" "cursor-installer lib"
if [ -d "$LIB_DIR" ] && [ -z "$(ls -A "$LIB_DIR")" ]; then
    rmdir "$LIB_DIR" 2>/dev/null || true
fi

# Remove legacy installer CLI if present
if [ -f "$LEGACY_CLI" ] && grep -q "install_cursor_extracted" "$LEGACY_CLI" 2>/dev/null; then
    log_step "Removing legacy cursor installer script..."
    safe_remove "$LEGACY_CLI" "legacy cursor installer script"
fi

# Remove icons
log_step "Removing Cursor icons..."
# Remove any 'cursor' or legacy 'co.anysphere.cursor' icons under hicolor theme
if [ -d "$HOME/.local/share/icons/hicolor" ]; then
    find "$HOME/.local/share/icons/hicolor" -type f \
        \( -name 'cursor.*' -o -name 'co.anysphere.cursor.*' \) \
        -path '*/apps/*' -delete 2>/dev/null || true
    # Clean up now-empty directories
    find "$HOME/.local/share/icons/hicolor" -type d -empty -delete 2>/dev/null || true
fi

# Remove desktop file
log_step "Removing Cursor desktop file..."
safe_remove "$HOME/.local/share/applications/cursor.desktop" "Cursor desktop file"

# Refresh desktop database for menu visibility cleanup
if command -v update-desktop-database &>/dev/null; then
    update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
fi

log_ok "Cursor has been uninstalled."

# Optionally, ask the user if they want to remove configuration files
read -r -p "Do you want to remove Cursor configuration files? (y/N) " remove_config
if [[ $remove_config =~ ^[Yy]$ ]]; then
    log_step "Removing Cursor configuration files..."
    safe_remove "$HOME/.config/Cursor" "Cursor configuration directory" true
    log_ok "Configuration files removed."
fi

# Also remove extracted installations (FUSE-free mode) and related metadata
read -r -p "Do you want to remove extracted installation directories? (y/N) " remove_extracted
if [[ $remove_extracted =~ ^[Yy]$ ]]; then
    log_step "Removing extracted installation directories..."
    safe_remove "$HOME/.local/share/cursor" "extracted installation directory" true
    safe_remove "$HOME/.cursor" "legacy extracted installation directory" true
    log_ok "Extracted installation directories removed (if present)."
fi

log_ok "Uninstallation complete."
