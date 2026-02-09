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
