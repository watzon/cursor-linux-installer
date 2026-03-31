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

# Validation function to check if a path is safe to remove
function validate_path() {
    local path="$1"
    local description="$2"
    
    # Check if path is empty
    if [ -z "$path" ]; then
        log_error "Invalid path: empty path for $description"
        return 1
    fi
    
    # Check if path is a critical system directory
    local critical_dirs=("/" "/home" "/usr" "/bin" "/sbin" "/etc" "/var" "/opt" "/root")
    for critical in "${critical_dirs[@]}"; do
        if [ "$path" = "$critical" ]; then
            log_error "Refusing to remove critical system directory: $path"
            return 1
        fi
    done
    
    # Check if path is user's home directory
    if [ "$path" = "$HOME" ]; then
        log_error "Refusing to remove home directory: $path"
        return 1
    fi
    
    # Check if path exists
    if [ ! -e "$path" ]; then
        log_warn "$description not found: $path"
        return 2  # Non-fatal: path doesn't exist
    fi
    
    # Verify path is within expected locations for Cursor files
    case "$path" in
        "$HOME/.local/bin/"*|"$HOME/.local/share/"*|"$HOME/.config/"*|"$HOME/AppImages/"*|"$HOME/Applications/"*|"$HOME/.cursor"*)
            return 0  # Valid path
            ;;
        *)
            log_warn "Path outside expected locations: $path"
            read -r -p "Are you sure you want to remove this? (y/N) " confirm
            if [[ ! $confirm =~ ^[Yy]$ ]]; then
                log_info "Skipping removal of $path"
                return 1
            fi
            return 0
            ;;
    esac
}

# Safe removal function
function safe_remove() {
    local path="$1"
    local description="$2"
    local recursive="${3:-false}"
    
    local ret=0
    validate_path "$path" "$description" || ret=$?
    if [ $ret -eq 2 ]; then
        return 0  # Path doesn't exist, continue
    elif [ $ret -ne 0 ]; then
        return 1  # Validation failed
    fi
    
    if [ "$recursive" = "true" ]; then
        log_info "Removing $description: $path"
        rm -rf "$path"
    else
        log_info "Removing $description: $path"
        rm -f "$path"
    fi
    
    return 0
}

# Find the installed Cursor AppImage path (if any)
function find_cursor_appimage() {
    local search_dirs=("$HOME/.local/bin" "$HOME/AppImages" "$HOME/Applications")
    for dir in "${search_dirs[@]}"; do
        # Skip non-existent directories to avoid 'find' non-zero status with set -e
        [ -d "$dir" ] || continue
        local appimage
        appimage=$(find "$dir" -name "cursor.appimage" -print -quit 2>/dev/null || true)
        if [ -n "$appimage" ]; then
            echo "$appimage"
            return 0
        fi
    done
    return 1
}

# --- Installer source metadata ---
INSTALLER_SOURCE_STATE="${LIB_DIR}/source.env"

function load_installer_source_state() {
    if [ ! -f "$INSTALLER_SOURCE_STATE" ]; then
        return 0
    fi

    # shellcheck disable=SC1090
    source "$INSTALLER_SOURCE_STATE"
}

function persist_installer_source_state() {
    mkdir -p "$LIB_DIR"

    local source_root="${1:-${INSTALLER_SOURCE_ROOT:-}}"
    local tmp_file
    tmp_file=$(mktemp)

    {
        printf 'INSTALLER_REPO_OWNER=%q\n' "${REPO_OWNER:-watzon}"
        printf 'INSTALLER_REPO_BRANCH=%q\n' "${REPO_BRANCH:-main}"
        printf 'INSTALLER_REPO_NAME=%q\n' "${REPO_NAME:-cursor-linux-installer}"

        if [ -n "$source_root" ] && [ -d "$source_root" ]; then
            printf 'INSTALLER_SOURCE_ROOT=%q\n' "$source_root"
        fi
    } > "$tmp_file"

    mv "$tmp_file" "$INSTALLER_SOURCE_STATE"
}

function apply_local_installer_source_overrides() {
    local source_root="${INSTALLER_SOURCE_ROOT:-}"

    if [ -z "$source_root" ] || [ ! -d "$source_root" ]; then
        return 0
    fi

    if [ -z "${LOCAL_CURSOR_SH:-}" ] && [ -f "$source_root/cursor.sh" ]; then
        LOCAL_CURSOR_SH="$source_root/cursor.sh"
    fi
    if [ -z "${LOCAL_SHIM_PATH:-}" ] && [ -f "$source_root/shim.sh" ]; then
        LOCAL_SHIM_PATH="$source_root/shim.sh"
    fi
    if [ -z "${LOCAL_SHIM_HELPER_PATH:-}" ] && [ -f "$source_root/scripts/ensure-shim.sh" ]; then
        LOCAL_SHIM_HELPER_PATH="$source_root/scripts/ensure-shim.sh"
    fi
    if [ -z "${LOCAL_SHELL_PATH_SCRIPT:-}" ] && [ -f "$source_root/shell-path.sh" ]; then
        LOCAL_SHELL_PATH_SCRIPT="$source_root/shell-path.sh"
    fi
    if [ -z "${LOCAL_SHELL_PATH_HELPER_PATH:-}" ] && [ -f "$source_root/scripts/ensure-shell-path.sh" ]; then
        LOCAL_SHELL_PATH_HELPER_PATH="$source_root/scripts/ensure-shell-path.sh"
    fi
}

function get_managed_shell_files() {
    local candidate
    local files=()

    for candidate in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
        if [ -e "$candidate" ] || [ -L "$candidate" ]; then
            files+=("$candidate")
        fi
    done

    if [ ${#files[@]} -eq 0 ]; then
        case "$(basename "${SHELL:-}")" in
            bash)
                files+=("$HOME/.bashrc")
                ;;
            zsh)
                files+=("$HOME/.zshrc")
                ;;
            sh|dash|ksh)
                files+=("$HOME/.profile")
                ;;
        esac
    fi

    if [ ${#files[@]} -eq 0 ]; then
        return 1
    fi

    local old_ifs="$IFS"
    IFS=:
    printf '%s' "${files[*]}"
    IFS="$old_ifs"
}

function download_asset_atomically() {
    local url="$1"
    local destination="$2"
    local description="$3"
    local tmp_file

    tmp_file=$(mktemp)
    if curl -fsSL "$url" -o "$tmp_file"; then
        mv "$tmp_file" "$destination"
        return 0
    fi

    rm -f "$tmp_file"
    log_warn "Failed to download $description"
    return 1
}

# --- Shim (cursor in PATH): canonical paths and helpers ---
# Requires LIB_DIR to be set by caller before sourcing lib.
load_installer_source_state
REPO_OWNER="${REPO_OWNER:-${INSTALLER_REPO_OWNER:-watzon}}"
REPO_BRANCH="${REPO_BRANCH:-${INSTALLER_REPO_BRANCH:-main}}"
REPO_NAME="${REPO_NAME:-${INSTALLER_REPO_NAME:-cursor-linux-installer}}"
BASE_RAW_URL="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${REPO_BRANCH}"
SHIM_TARGET="${SHIM_TARGET:-$HOME/.local/bin/cursor}"
SHARED_SHIM="${LIB_DIR}/shim.sh"
SHIM_HELPER="${LIB_DIR}/ensure-shim.sh"
SHELL_PATH_SCRIPT="${LIB_DIR}/shell-path.sh"
SHELL_PATH_HELPER="${LIB_DIR}/ensure-shell-path.sh"
SHIM_URL="${BASE_RAW_URL}/shim.sh"
SHIM_HELPER_URL="${BASE_RAW_URL}/scripts/ensure-shim.sh"
SHELL_PATH_SCRIPT_URL="${BASE_RAW_URL}/shell-path.sh"
SHELL_PATH_HELPER_URL="${BASE_RAW_URL}/scripts/ensure-shell-path.sh"
LIB_URL="${BASE_RAW_URL}/lib.sh"
CURSOR_SCRIPT_URL="${BASE_RAW_URL}/cursor.sh"
apply_local_installer_source_overrides

# Sync shim.sh and ensure-shim.sh into LIB_DIR (local copy or download).
# Set LOCAL_SHIM_PATH and/or LOCAL_SHIM_HELPER_PATH to prefer repo files.
function sync_shim_assets() {
    mkdir -p "$LIB_DIR"
    if [ -n "${LOCAL_SHIM_PATH:-}" ] && [ -f "$LOCAL_SHIM_PATH" ]; then
        cp "$LOCAL_SHIM_PATH" "$SHARED_SHIM"
    elif [ ! -f "$SHARED_SHIM" ]; then
        download_asset_atomically "$SHIM_URL" "$SHARED_SHIM" "shim.sh" || return 1
    fi
    if [ -n "${LOCAL_SHIM_HELPER_PATH:-}" ] && [ -f "$LOCAL_SHIM_HELPER_PATH" ]; then
        cp "$LOCAL_SHIM_HELPER_PATH" "$SHIM_HELPER"
    elif [ ! -f "$SHIM_HELPER" ]; then
        download_asset_atomically "$SHIM_HELPER_URL" "$SHIM_HELPER" "ensure-shim.sh" || return 1
    fi
    chmod +x "$SHIM_HELPER" "$SHARED_SHIM" 2>/dev/null || true
    return 0
}

function sync_shell_path_assets() {
    mkdir -p "$LIB_DIR"
    if [ -n "${LOCAL_SHELL_PATH_SCRIPT:-}" ] && [ -f "$LOCAL_SHELL_PATH_SCRIPT" ]; then
        cp "$LOCAL_SHELL_PATH_SCRIPT" "$SHELL_PATH_SCRIPT"
    elif [ ! -f "$SHELL_PATH_SCRIPT" ]; then
        download_asset_atomically "$SHELL_PATH_SCRIPT_URL" "$SHELL_PATH_SCRIPT" "shell-path.sh" || return 1
    fi
    if [ -n "${LOCAL_SHELL_PATH_HELPER_PATH:-}" ] && [ -f "$LOCAL_SHELL_PATH_HELPER_PATH" ]; then
        cp "$LOCAL_SHELL_PATH_HELPER_PATH" "$SHELL_PATH_HELPER"
    elif [ ! -f "$SHELL_PATH_HELPER" ]; then
        download_asset_atomically "$SHELL_PATH_HELPER_URL" "$SHELL_PATH_HELPER" "ensure-shell-path.sh" || return 1
    fi
    chmod +x "$SHELL_PATH_HELPER" "$SHELL_PATH_SCRIPT" 2>/dev/null || true
    return 0
}

# Refresh shim assets from GitHub (used on cursor-installer --update).
function refresh_shim_assets() {
    log_step "Refreshing cursor shim assets..."
    mkdir -p "$LIB_DIR"
    if [ -n "${LOCAL_SHIM_PATH:-}" ] && [ -f "$LOCAL_SHIM_PATH" ]; then
        cp "$LOCAL_SHIM_PATH" "$SHARED_SHIM"
    elif ! download_asset_atomically "$SHIM_URL" "$SHARED_SHIM" "shim.sh"; then
        return 0
    fi
    if [ -n "${LOCAL_SHIM_HELPER_PATH:-}" ] && [ -f "$LOCAL_SHIM_HELPER_PATH" ]; then
        cp "$LOCAL_SHIM_HELPER_PATH" "$SHIM_HELPER"
    elif ! download_asset_atomically "$SHIM_HELPER_URL" "$SHIM_HELPER" "ensure-shim.sh"; then
        return 0
    fi
    chmod +x "$SHIM_HELPER" "$SHARED_SHIM" 2>/dev/null || true
}

function refresh_shell_path_assets() {
    log_step "Refreshing shell PATH assets..."
    mkdir -p "$LIB_DIR"
    if [ -n "${LOCAL_SHELL_PATH_SCRIPT:-}" ] && [ -f "$LOCAL_SHELL_PATH_SCRIPT" ]; then
        cp "$LOCAL_SHELL_PATH_SCRIPT" "$SHELL_PATH_SCRIPT"
    elif ! download_asset_atomically "$SHELL_PATH_SCRIPT_URL" "$SHELL_PATH_SCRIPT" "shell-path.sh"; then
        return 0
    fi
    if [ -n "${LOCAL_SHELL_PATH_HELPER_PATH:-}" ] && [ -f "$LOCAL_SHELL_PATH_HELPER_PATH" ]; then
        cp "$LOCAL_SHELL_PATH_HELPER_PATH" "$SHELL_PATH_HELPER"
    elif ! download_asset_atomically "$SHELL_PATH_HELPER_URL" "$SHELL_PATH_HELPER" "ensure-shell-path.sh"; then
        return 0
    fi
    chmod +x "$SHELL_PATH_HELPER" "$SHELL_PATH_SCRIPT" 2>/dev/null || true
}

# Run ensure-shim.sh with canonical SOURCE_SHIM and TARGET_SHIM.
function run_ensure_shim() {
    if [ ! -f "$SHIM_HELPER" ]; then
        log_info "Shim helper not found; skipping shim update."
        return 0
    fi
    SOURCE_SHIM="$SHARED_SHIM" TARGET_SHIM="$SHIM_TARGET" sh "$SHIM_HELPER" || { log_warn "Shim update failed; continuing."; return 0; }
}

function run_ensure_shell_path() {
    if [ ! -f "$SHELL_PATH_HELPER" ] || [ ! -f "$SHELL_PATH_SCRIPT" ]; then
        log_info "Shell PATH helper not found; skipping shell PATH setup."
        return 0
    fi
    local target_shell_files
    target_shell_files="${TARGET_SHELL_FILES:-${MANAGED_SHELL_FILES:-$(get_managed_shell_files || true)}}"
    if [ -z "$target_shell_files" ]; then
        log_info "No managed shell rc files detected; skipping shell PATH setup."
        return 0
    fi
    TARGET_SHELL_FILES="$target_shell_files" SHELL_PATH_SCRIPT="$SHELL_PATH_SCRIPT" sh "$SHELL_PATH_HELPER" || { log_warn "Shell PATH setup failed; continuing."; return 0; }
}

function run_remove_shell_path() {
    if [ ! -f "$SHELL_PATH_HELPER" ]; then
        return 0
    fi
    local target_shell_files
    target_shell_files="${TARGET_SHELL_FILES:-${MANAGED_SHELL_FILES:-$(get_managed_shell_files || true)}}"
    if [ -z "$target_shell_files" ]; then
        return 0
    fi
    TARGET_SHELL_FILES="$target_shell_files" SHELL_PATH_SCRIPT="$SHELL_PATH_SCRIPT" sh "$SHELL_PATH_HELPER" --remove || { log_warn "Shell PATH cleanup failed; continuing."; return 0; }
}

function warn_if_cursor_shadowed_by_appimage_runtime() {
    local resolved_cursor
    resolved_cursor=$(command -v cursor 2>/dev/null || true)

    case "$resolved_cursor" in
        /tmp/.mount_*)
            log_warn "The current shell resolves 'cursor' to Cursor's AppImage runtime path."
            log_info "Open a new terminal or source your shell startup file so ~/.local/bin takes precedence."
            ;;
    esac
}
