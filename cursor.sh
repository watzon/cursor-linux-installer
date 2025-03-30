#!/usr/bin/env bash

set -e

ROOT=$(dirname "$(dirname "$(readlink -f $0)")")

function check_fuse() {
    # Set command prefix based on whether we're root
    local cmd_prefix=""
    if [ "$EUID" -ne 0 ]; then
        cmd_prefix="sudo"
    fi

    # Check and install FUSE using the appropriate package manager
    if command -v apt-get &> /dev/null; then
        if ! dpkg -l | grep -q "^ii.*fuse "; then
            echo "Installing FUSE..."
            $cmd_prefix apt-get update
            $cmd_prefix apt-get install -y fuse
        else
            echo "FUSE is already installed."
        fi
    elif command -v dnf &> /dev/null; then
        if ! rpm -q fuse >/dev/null 2>&1; then
            echo "Installing FUSE..."
            $cmd_prefix dnf install -y fuse
        else
            echo "FUSE is already installed."
        fi
    elif command -v pacman &> /dev/null; then
        if ! pacman -Qi fuse2 >/dev/null 2>&1; then
            echo "Installing FUSE..."
            $cmd_prefix pacman -S fuse2
        else
            echo "FUSE is already installed."
        fi
    else
        echo "Unsupported package manager. Please install FUSE manually."
        echo "You can install FUSE using your system's package manager:"
        echo "  - Debian/Ubuntu: ${cmd_prefix}apt-get install fuse"
        echo "  - Fedora: ${cmd_prefix}dnf install fuse"
        echo "  - Arch Linux: ${cmd_prefix}pacman -S fuse2"
        exit 1
    fi
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

    # this AppImage is potentially older than expected, see
    # https://github.com/watzon/cursor-linux-installer/issues/5
    echo "MESSAGE=$1"
    echo "URL=https://downloader.cursor.sh/linux/appImage/$arch"
    echo "VERSION=fallback"
    return 1
}

function get_download_info() {
    if ! which jq >/dev/null 2>&1; then
        get_fallback_download_info "jq not available"
        return 1
    fi

    local temp_file=$(mktemp)
    local api_url="https://www.cursor.com/api/download?platform=linux-$(get_arch)&releaseTrack=stable"
    if ! curl -s "$api_url" -o "$temp_file"; then
        rm -f "$temp_file"
        get_fallback_download_info "curl failed on $api_url"
        return 1
    fi

    if ! download_url=$(jq -er '.downloadUrl' "$temp_file"); then
        rm -f "$temp_file"
        get_fallback_download_info "jq failed: downloadUrl not found in JSON response"
        return 1
    fi

    if ! version=$(jq -er '.version' "$temp_file"); then
        rm -f "$temp_file"
        get_fallback_download_info "jq failed: version not found in JSON response"
        return 1
    fi

    rm -f "$temp_file"

    echo "URL=$download_url"
    echo "VERSION=$version"
    return 0
}

function install_cursor() {
    local install_dir="$1"
    local temp_file=$(mktemp)
    local current_dir=$(pwd)
    local download_info=$(get_download_info)
    local message=$(echo "$download_info" | grep "MESSAGE=" | sed 's/^MESSAGE=//')

    if [ -n "$message" ]; then
        echo "$message"
        return 1
    fi

    # Check for FUSE before proceeding with installation
    check_fuse

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

    echo "Extracting icons and desktop file..."
    local temp_extract_dir=$(mktemp -d)
    cd "$temp_extract_dir"

    # Extract icons
    "$install_dir/cursor.appimage" --appimage-extract "usr/share/icons" >/dev/null 2>&1
    # Extract desktop file
    "$install_dir/cursor.appimage" --appimage-extract "cursor.desktop" >/dev/null 2>&1

    # Copy icons
    local icon_dir="$HOME/.local/share/icons/hicolor"
    mkdir -p "$icon_dir"
    cp -r squashfs-root/usr/share/icons/hicolor/* "$icon_dir/"

    # Copy desktop file
    local apps_dir="$HOME/.local/share/applications"
    mkdir -p "$apps_dir"
    cp squashfs-root/cursor.desktop "$apps_dir/"

    # Update desktop file to point to the correct AppImage location
    sed -i "s|Exec=.*|Exec=$install_dir/cursor.appimage --no-sandbox|g" "$apps_dir/cursor.desktop"

    # Clean up
    cd "$current_dir"
    rm -rf "$temp_extract_dir"

    echo "Cursor has been installed to $install_dir/cursor.appimage"
    echo "Icons and desktop file have been extracted and placed in the appropriate directories"
}

function update_cursor() {
    echo "Updating Cursor..."
    local arch=$(get_arch)
    local current_appimage=$(find_cursor_appimage)
    local install_dir

    if [ -n "$current_appimage" ]; then
        install_dir=$(dirname "$current_appimage")
    else
        install_dir=$(get_install_dir)
    fi

    install_cursor "$install_dir"
}

function launch_cursor() {
    local cursor_appimage=$(find_cursor_appimage)
    
    if [ -z "$cursor_appimage" ]; then
        echo "Error: Cursor AppImage not found. Running update to install it."
        update_cursor
        cursor_appimage=$(find_cursor_appimage)
    fi

    # Launch Cursor in the background with no logs
    nohup "$cursor_appimage" "$@" >/dev/null 2>&1 &
}

# Parse command-line arguments
if [ "$1" == "--update" ]; then
    update_cursor
else
    launch_cursor "$@"
fi

exit $?
