#!/usr/bin/env bash

set -e

# Color and logging helpers
if [ -t 1 ]; then
    BOLD="\033[1m"; RESET="\033[0m"; RED="\033[31m"; GREEN="\033[32m"; YELLOW="\033[33m"; BLUE="\033[34m"
else
    BOLD=""; RESET=""; RED=""; GREEN=""; YELLOW=""; BLUE=""
fi

log_info()  { echo -e "${BLUE}[*]${RESET} $*"; }
log_ok()    { echo -e "${GREEN}[✓]${RESET} $*"; }
log_warn()  { echo -e "${YELLOW}[!]${RESET} $*"; }
log_error() { echo -e "${RED}[x]${RESET} $*"; }
log_step()  { echo -e "${BOLD}$*${RESET}"; }

# Parse arguments
RELEASE_TRACK="stable"
INSTALL_MODE="appimage"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --extract|--no-fuse)
            INSTALL_MODE="extracted"
            shift
            ;;
        --stable|--latest)
            RELEASE_TRACK="${1#--}"
            shift
            ;;
        stable|latest)
            RELEASE_TRACK="$1"
            shift
            ;;
        *)
    echo "Unknown option: $1"
    echo "Usage: bash install.sh [stable|latest] [--extract|--no-fuse]"
    echo "Environment overrides: REPO_OWNER, REPO_NAME, REPO_BRANCH"
            exit 1
            ;;
    esac
done

# Determine whether to use local cursor.sh or download from GitHub
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
LOCAL_CURSOR_SH="$SCRIPT_DIR/cursor.sh"

# Repo URL parameters (override via env for release workflows)
REPO_OWNER=${REPO_OWNER:-watzon}
REPO_BRANCH=${REPO_BRANCH:-main}
REPO_NAME=${REPO_NAME:-cursor-linux-installer}
BASE_RAW_URL="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${REPO_BRANCH}"
CURSOR_SCRIPT_URL="$BASE_RAW_URL/cursor.sh"

# Local bin directory
LOCAL_BIN="$HOME/.local/bin"

# Create ~/.local/bin if it doesn't exist
mkdir -p "$LOCAL_BIN"

# Place cursor launcher into ~/.local/bin from local file or GitHub
log_step "Preparing cursor launcher script..."
if [ -f "$LOCAL_CURSOR_SH" ]; then
    log_info "Using local cursor.sh from repository"
    cp "$LOCAL_CURSOR_SH" "$LOCAL_BIN/cursor"
else
    log_info "Downloading cursor.sh from GitHub..."
curl -fsSL "$CURSOR_SCRIPT_URL" -o "$LOCAL_BIN/cursor" || {
    echo "Failed to download cursor.sh from GitHub" >&2
    exit 1
}
fi

# Make the script executable
chmod +x "$LOCAL_BIN/cursor"

log_ok "Cursor installer script has been placed in $LOCAL_BIN/cursor"

# Check if ~/.local/bin is in PATH
if [[ ":$PATH:" != *":$LOCAL_BIN:"* ]]; then
    log_warn "$LOCAL_BIN is not in your PATH."
    log_info "To add it, run this or add it to your shell profile:"
    log_info "export PATH=\"\$HOME/.local/bin:\$PATH\""
fi

# Run cursor --update to download and install Cursor
log_step "Downloading and installing Cursor ($INSTALL_MODE mode) from ${REPO_OWNER}/${REPO_NAME}@${REPO_BRANCH}..."
if [ "$INSTALL_MODE" = "extracted" ]; then
    "$LOCAL_BIN/cursor" --extract --update "$RELEASE_TRACK"
else
    "$LOCAL_BIN/cursor" --update "$RELEASE_TRACK"
fi

log_ok "Installation complete. You can now run 'cursor' to start Cursor."

