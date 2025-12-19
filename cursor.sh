#!/usr/bin/env bash

set -e

ROOT=$(dirname "$(dirname "$(readlink -f $0)")")

function check_fuse() {
    # Set command prefix based on whether we're root
    local cmd_prefix=""
    if [ "$EUID" -ne 0 ]; then
        cmd_prefix="sudo"
    fi

    # FIXED: Check and install FUSE2 using the appropriate package manager
    if command -v apt-get &>/dev/null; then
        if ! dpkg -l | grep -q "^ii.*libfuse2 "; then  # FIXED: libfuse2, not fuse
            echo "Installing libfuse2..."
            $cmd_prefix apt-get update
            $cmd_prefix apt-get install -y libfuse2  # FIXED: libfuse2 for AppImage compat
        else
            echo "libfuse2 is already installed."
        fi
    elif command -v dnf &>/dev/null; then
        if ! rpm -q fuse >/dev/null 2>&1; then
            echo "Installing fuse..."
            $cmd_prefix dnf install -y fuse
        else
            echo "fuse is already installed."
        fi
    elif command -v pacman &>/dev/null; then
        if ! pacman -Qi fuse2 >/dev/null 2>&1; then
            echo "Installing fuse2..."
            $cmd_prefix pacman -S fuse2
        else
            echo "fuse2 is already installed."
        fi
    else
        echo "Unsupported package manager. Please install libfuse2 manually."
        echo "You can install FUSE2 using your system's package manager:"
        echo "  - Debian/Ubuntu: ${cmd_prefix}apt-get install libfuse2"  # FIXED: libfuse2
        echo "  - Fedora: ${cmd_prefix}dnf install fuse"
        echo "  - Arch Linux: ${cmd_prefix}pacman -S fuse2"
        exit 1
    fi

    # Verify FUSE2 is functional
    if ! fusermount -V >/dev/null 2>&1; then
        echo "Warning: FUSE2 verification failed. AppImage may not run." >&2
        return 1
    fi
    echo "FUSE2 is ready."
}

function get_arch() {
    local arch=$(uname -m)
    if [ "$arch" == "x86_64" ]; then
        echo "x64"
    elif [ "$arch" == "aarch64" ]; then
        echo "arm64"
    else
        echo "Unsupported architecture: $arch" >&2
        exit 1
    fi
}

function find_cursor_appimage() {
    local search_dirs=("$HOME/AppImages" "$HOME/Applications" "$HOME/.local/bin")
    for dir in "${search_dirs[@]}"; do
        local appimage=$(find "$dir" -name "cursor.appimage" -print -quit 2>/dev/null)
        if [ -n "$appimage" ]; then
            echo "$appimage"
            return 0
        fi
    done
    return 1
}

function get_install_dir() {
    local search_dirs=("$HOME/AppImages" "$HOME/Applications" "$HOME/.local/bin")
    for dir in "${search_dirs[@]}"; do
        if [ -d "$dir" ]; then
            echo "$dir"
            return 0
        fi
    done
    echo "No suitable installation directory found" >&2
    exit 1
}

function get_fallback_download_info() {
    local arch=$(get_arch)
    local path_arch="$arch"  # NEW: x64/arm64 for path
    local file_arch="x86_64"  # NEW: Map for filename
    if [ "$arch" = "arm64" ]; then
        file_arch="aarch64"
    fi
    local fallback_hash="8ea935e79a50a02da912a034bbeda84a6d3d355d"  # FIXED: Recent from 0.50.4 (May 2025)
    local fallback_version="0.50.4"  # FIXED: Updated version
    echo "URL=https://downloads.cursor.com/production/$fallback_hash/linux/$path_arch/Cursor-$fallback_version-$file_arch.AppImage"
    echo "VERSION=$fallback_version"
    return 1  # Still error, but usable URL
}

function get_download_info() {
    local temp_html=$(mktemp)
    local release_track=${1:-stable} # Default to stable if not specified
    local arch=$(get_arch)  # x64 or arm64
    local path_arch="$arch"  # NEW: For platform param (x64/arm64)
    local file_arch="x86_64"  # NEW: For filename filter (x86_64/aarch64)
    if [ "$arch" = "arm64" ]; then
        file_arch="aarch64"
    fi
    local platform="linux-${path_arch}"
    local api_url="https://cursor.com/api/download?platform=$platform&releaseTrack=$release_track"

    echo "Fetching download info for $release_track track ($file_arch)..."
    if ! curl -sL "$api_url" -o "$temp_html"; then
        rm -f "$temp_html"
        get_fallback_download_info
        return 1
    fi

    # FIXED: Arch-specific scrape (filters to correct binary)
    local download_url=$(grep -o "https://downloads\.cursor\.com/[^[:space:]]*${file_arch}\.AppImage" "$temp_html" | head -1 | sed 's/["'\'']\?$//')

    rm -f "$temp_html"

    if [ -z "$download_url" ]; then
        get_fallback_download_info
        return 1
    fi

    # Extract version from filename (e.g., Cursor-1.6.35-x86_64.AppImage → 1.6.35)
    local version=$(basename "$download_url" | sed -E 's/.*Cursor-([0-9]+\.[0-9]+\.[0-9]+).*/\1/')

    if [ -z "$version" ]; then
        version="unknown"  # Rare fallback
    fi

    echo "URL=$download_url"
    echo "VERSION=$version"
    return 0
}

function install_cursor() {
    local install_dir="$1"
    local release_track=${2:-stable} # Default to stable if not specified
    local temp_file=$(mktemp)
    local current_dir=$(pwd)
    local arch=$(get_arch)  # NEW: For verification
    local download_info=$(get_download_info "$release_track")
    local message=$(echo "$download_info" | grep "MESSAGE=" | sed 's/^MESSAGE=//')

    if [ -n "$message" ]; then
        echo "$message"
        return 1
    fi

    # Check for FUSE before proceeding with installation
    check_fuse || return 1  # NEW: Propagate FUSE error

    local download_url=$(echo "$download_info" | grep "URL=" | sed 's/^URL=//')
    local version=$(echo "$download_info" | grep "VERSION=" | sed 's/^VERSION=//')

    echo "Downloading $version Cursor AppImage..."
    if ! curl -L "$download_url" -o "$temp_file"; then
        echo "Failed to download Cursor AppImage" >&2
        rm -f "$temp_file"
        return 1
    fi

    chmod +x "$temp_file"
    mv "$temp_file" "$install_dir/cursor.appimage"

    # Ensure execution permissions persist post-move (robust against FS quirks)
    chmod +x "$install_dir/cursor.appimage"
    if [ -x "$install_dir/cursor.appimage" ]; then
        echo "Execution permissions confirmed for $install_dir/cursor.appimage"
    else
        echo "Warning: Failed to set execution permissions—check filesystem." >&2
        return 1
    fi

    # NEW: Verify binary architecture matches host
    local binary_info=$(file "$install_dir/cursor.appimage" 2>/dev/null || echo "unreadable")
    local expected_grep="x86-64"
    if [ "$arch" = "arm64" ]; then
        expected_grep="ARM aarch64"
    fi
    if ! echo "$binary_info" | grep -q "$expected_grep"; then
        echo "Error: Arch mismatch detected ($binary_info). Expected $expected_grep. Aborting install." >&2
        rm -f "$install_dir/cursor.appimage"
        return 1
    fi
    echo "Binary verified: $binary_info"

    # Store version information in a simple file
    echo "$version" >"$install_dir/.cursor_version"

    echo "Extracting icons and desktop file..."
    local temp_extract_dir=$(mktemp -d)
    cd "$temp_extract_dir"

    # Extract icons
    if ! "$install_dir/cursor.appimage" --appimage-extract "usr/share/icons" >/dev/null 2>&1; then
        echo "Warning: Icon extraction failed—skipping." >&2
    fi
    # Extract desktop file
    if ! "$install_dir/cursor.appimage" --appimage-extract "cursor.desktop" >/dev/null 2>&1; then
        echo "Warning: Desktop extraction failed—skipping." >&2
    fi

    # NEW: Verify extraction succeeded before copying
    if [ ! -d "squashfs-root" ]; then
        echo "Error: Extraction failed (squashfs-root missing). Check arch/FUSE." >&2
        cd "$current_dir"
        rm -rf "$temp_extract_dir"
        return 1
    fi

    # Copy icons
    local icon_dir="$HOME/.local/share/icons/hicolor"
    mkdir -p "$icon_dir"
    if [ -d "squashfs-root/usr/share/icons/hicolor" ]; then
        cp -r squashfs-root/usr/share/icons/hicolor/* "$icon_dir/" 2>/dev/null || echo "Warning: Icon copy failed."
    fi

    # Copy desktop file
    local apps_dir="$HOME/.local/share/applications"
    mkdir -p "$apps_dir"
    if [ -f "squashfs-root/cursor.desktop" ]; then
        cp squashfs-root/cursor.desktop "$apps_dir/"
        # Update desktop file to point to the correct AppImage location
        sed -i "s|Exec=.*|Exec=$install_dir/cursor.appimage --no-sandbox|g" "$apps_dir/cursor.desktop"

        # Fix potential icon name mismatch in the extracted desktop file
        sed -i 's/^Icon=co.anysphere.cursor/Icon=cursor/' "$apps_dir/cursor.desktop"

        # NEW: Refresh desktop database for menu visibility
        update-desktop-database "$apps_dir" 2>/dev/null || true
        echo ".desktop file installed and updated."
    else
        echo "Warning: cursor.desktop not found in extraction—manual setup needed."
    fi

    # Clean up
    cd "$current_dir"
    rm -rf "$temp_extract_dir"

    echo "Cursor has been installed to $install_dir/cursor.appimage"
    echo "Icons and desktop file have been extracted and placed in the appropriate directories"
}

function update_cursor() {
    echo "Updating Cursor..."
    local current_appimage=$(find_cursor_appimage)
    local install_dir
    local release_track=${1:-stable} # Default to stable if not specified

    if [ -n "$current_appimage" ]; then
        install_dir=$(dirname "$current_appimage")
    else
        install_dir=$(get_install_dir)
    fi

    install_cursor "$install_dir" "$release_track"
}

function launch_cursor() {
    local cursor_appimage=$(find_cursor_appimage)

    if [ -z "$cursor_appimage" ]; then
        echo "Error: Cursor AppImage not found. Running update to install it."
        update_cursor
        cursor_appimage=$(find_cursor_appimage)
    fi

    # NEW: Pre-launch safeguard (re-chmod + arch check)
    if [ ! -x "$cursor_appimage" ]; then
        echo "Fixing execution permissions..."
        chmod +x "$cursor_appimage"
    fi
    local binary_info=$(file "$cursor_appimage" 2>/dev/null || echo "unreadable")
    if ! echo "$binary_info" | grep -q "$(get_arch | sed 's/x64/x86-64/;s/arm64/ARM aarch64/')"; then  # Simplified arch map
        echo "Error: Arch mismatch in binary ($binary_info). Re-update." >&2
        return 1
    fi

    # Create a log file to capture output and errors
    local log_file="/tmp/cursor_appimage.log"

    # Run the AppImage in the background using nohup, redirecting output and errors to a log file
    nohup "$cursor_appimage" --no-sandbox "$@" >"$log_file" 2>&1 &

    # Capture the process ID (PID) of the background process
    local pid=$!

    # Wait briefly (1 second) to allow the process to start
    sleep 1

    # Check if the process is still running
    if ! kill -0 "$pid" 2>/dev/null; then
        echo "Error: Cursor AppImage failed to start. Check the log for details."
        cat "$log_file"
    else
        echo "Cursor AppImage is running."
    fi
}

function get_version() {
    local cursor_appimage=$(find_cursor_appimage)
    if [ -z "$cursor_appimage" ]; then
        echo "Cursor is not installed"
        return 1
    fi

    local install_dir=$(dirname "$cursor_appimage")
    local version_file="$install_dir/.cursor_version"

    if [ -f "$version_file" ]; then
        local version=$(cat "$version_file")
        if [ -n "$version" ]; then
            echo "Cursor version: $version"
            return 0
        else
            echo "Version information is empty"
            return 1
        fi
    else
        echo "Version information not available"
        return 1
    fi
}

function check_cursor_versions() {
    local stable_info=$(get_download_info "stable")
    local stable_version=$(echo "$stable_info" | grep "VERSION=" | sed 's/^VERSION=//')
    local latest_info=$(get_download_info "latest")
    local latest_version=$(echo "$latest_info" | grep "VERSION=" | sed 's/^VERSION=//')
    echo "Stable Version: $stable_version"
    echo "Latest Version: $latest_version"
    echo "--------------------------------"
    get_version
    return 0
}

# Parse command-line arguments
if [ "$1" == "--version" ] || [ "$1" == "-v" ]; then
    get_version
    exit $?
elif [ "$1" == "--check" ] || [ "$1" == "-c" ]; then
    check_cursor_versions
elif [ "$1" == "--update" ] || [ "$1" == "-u" ]; then
    update_cursor "$2"
elif [ "$1" == "--help" ] || [ "$1" == "-h" ]; then
    echo "Usage: cursor [--check | --update <stable|latest> | --version]"
    echo "  --check, -c: Show the stable and latest version of Cursor available for download"
    echo "  --update, -u: Update Cursor to the specified version"
    echo "  --version, -v: Show the installed version of Cursor"
    exit 0
else
    launch_cursor "$@"
fi

exit $?
