#!/usr/bin/env bash

set -e

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
LIB_DIR="$HOME/.local/share/cursor-installer"
LIB_PATH="$SCRIPT_DIR/lib.sh"
SHARED_LIB="$LIB_DIR/lib.sh"

# Source shared helpers (local repo or installed lib)
if [ -f "$LIB_PATH" ]; then
    # shellcheck disable=SC1090
    source "$LIB_PATH"
elif [ -f "$SHARED_LIB" ]; then
    # shellcheck disable=SC1090
    source "$SHARED_LIB"
else
    echo "Error: lib.sh not found. Reinstall using install.sh." >&2
    exit 1
fi

CLI_NAME="cursor-installer"
CLI_BIN="$HOME/.local/bin/$CLI_NAME"

# Installation mode: 'appimage' (default) or 'extracted'
# Can be set via CURSOR_INSTALL_MODE environment variable or --extract flag
INSTALL_MODE="${CURSOR_INSTALL_MODE:-appimage}"

function is_extracted_install() {
    local install_dir="$1"
    [ -f "$install_dir/.cursor_extracted" ] && [ -d "$install_dir/cursor" ]
}

function get_extracted_root() {
    local search_dirs=("$HOME/.local/share/cursor" "$HOME/.cursor")
    for dir in "${search_dirs[@]}"; do
        if is_extracted_install "$dir"; then
            echo "$dir"
            return 0
        fi
    done
    return 1
} 

function get_extraction_dir() {
    # Prefer ~/.local/share/cursor for extracted installations
    echo "$HOME/.local/share/cursor"
}

function check_fuse() {
    # First, check if FUSE is already available
    if fusermount -V >/dev/null 2>&1; then
        log_ok "FUSE2 is already available."
        return 0
    fi

    # Check if we're in an interactive terminal
    local is_interactive=false
    if [ -t 0 ] && [ -t 1 ]; then
        is_interactive=true
    fi

    # Set command prefix based on whether we're root
    local cmd_prefix=""
    if [ "$EUID" -ne 0 ]; then
        cmd_prefix="sudo"
    fi

    # Try to install FUSE2 using the appropriate package manager
    if command -v apt-get &>/dev/null; then
        if ! dpkg -l | grep -q "^ii.*libfuse2 "; then
            if [ "$is_interactive" = true ]; then
                log_step "Installing libfuse2..."
                $cmd_prefix apt-get update && $cmd_prefix apt-get install -y libfuse2
            else
                log_warn "libfuse2 is not installed. AppImage requires FUSE2."
                log_info "Install: sudo apt-get install -y libfuse2"
                log_info "Continuing installation anyway..."
                return 0
            fi
        else
            log_ok "libfuse2 is already installed."
        fi
    elif command -v dnf &>/dev/null; then
        if ! rpm -q fuse >/dev/null 2>&1; then
            if [ "$is_interactive" = true ]; then
                log_step "Installing fuse..."
                $cmd_prefix dnf install -y fuse
            else
                log_warn "fuse is not installed. AppImage requires FUSE2."
                log_info "Install: sudo dnf install -y fuse"
                log_info "Continuing installation anyway..."
                return 0
            fi
        else
            log_ok "fuse is already installed."
        fi
    elif command -v pacman &>/dev/null; then
        if ! pacman -Qi fuse2 >/dev/null 2>&1; then
            if [ "$is_interactive" = true ]; then
                log_step "Installing fuse2..."
                $cmd_prefix pacman -S --noconfirm fuse2
            else
                log_warn "fuse2 is not installed. AppImage requires FUSE2."
                log_info "Install: sudo pacman -S fuse2"
                log_info "Continuing installation anyway..."
                return 0
            fi
        else
            log_ok "fuse2 is already installed."
        fi
    else
        log_warn "Unsupported package manager. Install libfuse2 manually or use --extract."
        log_info "  - Debian/Ubuntu: sudo apt-get install libfuse2"
        log_info "  - Fedora: sudo dnf install fuse"
        log_info "  - Arch Linux: sudo pacman -S fuse2"
        log_info "Continuing installation anyway..."
        return 0
    fi

    # Verify FUSE2 is functional
    if ! fusermount -V >/dev/null 2>&1; then
        log_warn "FUSE2 verification failed. AppImage may not run."
        log_info "You may need to install FUSE2 manually or use --extract mode."
        return 0  # Don't fail, just warn
    fi
    log_ok "FUSE2 is ready."
    return 0
}

function get_arch() {
    local arch
    arch=$(uname -m)
    if [ "$arch" == "x86_64" ]; then
        echo "x64"
    elif [ "$arch" == "aarch64" ]; then
        echo "arm64"
    else
        echo "Unsupported architecture: $arch" >&2
        exit 1
    fi
}

function get_install_dir() {
    local search_dirs=("$HOME/.local/bin" "$HOME/AppImages" "$HOME/Applications")
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
    local arch
    arch=$(get_arch)
    local path_arch="$arch"  # x64/arm64 for path
    local file_arch="x86_64"  # Map for filename
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
    local temp_html
    temp_html=$(mktemp || true)
    local release_track=${1:-stable} # Default to stable if not specified
    local arch
    arch=$(get_arch)  # x64 or arm64
    local path_arch="$arch"  # For platform param (x64/arm64)
    local file_arch="x86_64"  # For filename filter (x86_64/aarch64)
    if [ "$arch" = "arm64" ]; then
        file_arch="aarch64"
    fi
    local platform="linux-${path_arch}"
    local api_url="https://cursor.com/api/download?platform=$platform&releaseTrack=$release_track"

    log_step "Fetching download info for $release_track track ($file_arch)..."
    if ! curl -sL "$api_url" -o "$temp_html"; then
        rm -f "$temp_html"
        get_fallback_download_info
        return 1
    fi

    # FIXED: Arch-specific scrape (filters to correct binary)
    local download_url
    download_url=$(grep -o "https://downloads\.cursor\.com/[^[:space:]]*${file_arch}\.AppImage" "$temp_html" | head -1 | sed 's/["'\'']\?$//' || true)

    rm -f "$temp_html" || true

    if [ -z "$download_url" ]; then
        get_fallback_download_info
        return 1
    fi

    # Extract version from filename (e.g., Cursor-1.6.35-x86_64.AppImage → 1.6.35)
    local version
    version=$(basename "$download_url" | sed -E 's/.*Cursor-([0-9]+\.[0-9]+\.[0-9]+).*/\1/')

    if [ -z "$version" ]; then
        version="unknown"  # Rare fallback
    fi

    echo "URL=$download_url"
    echo "VERSION=$version"
    return 0
}

function clean_broken_cursor_symlinks() {
    local relative_path="$1"
    local target_root="$2"
    local destination="$target_root/$relative_path"
    local destination_dir
    destination_dir=$(dirname "$destination")

    mkdir -p "$destination_dir"

    if [ -L "$destination" ] && [ ! -e "$destination" ]; then
        rm -f "$destination"
    fi
}

function install_icons_from_source() {
    local source_root="$1"
    local target_root="$HOME/.local/share/icons/hicolor"

    mkdir -p "$target_root"

    if [ ! -d "$source_root" ]; then
        return 1
    fi

    if command -v find >/dev/null 2>&1; then
        while IFS= read -r relative_file; do
            [ -z "$relative_file" ] && continue
            clean_broken_cursor_symlinks "$relative_file" "$target_root"
        done < <(cd "$source_root" && find . -type f -name 'cursor.*' -printf '%P\n')
    fi

    if command cp -r "$source_root/"* "$target_root/" 2>/dev/null; then
        log_ok "Icons installed to $target_root"
        return 0
    fi

    log_warn "Icon copy failed."
    return 1
}

function create_launcher_script() {
    local extracted_root="$1"
    local launcher_script="$CLI_BIN"
    
    mkdir -p "$HOME/.local/bin"
    
    cat > "$launcher_script" << 'EOF'
#!/usr/bin/env bash
# Cursor launcher script for extracted installation

CURSOR_ROOT="__CURSOR_ROOT__"
CURSOR_EXECUTABLE="$CURSOR_ROOT/cursor/cursor"

if [ ! -x "$CURSOR_EXECUTABLE" ]; then
    echo "Error: Cursor executable not found at $CURSOR_EXECUTABLE" >&2
    exit 1
fi

# Set up environment for extracted AppImage
export APPDIR="$CURSOR_ROOT/cursor"
export PATH="$APPDIR/usr/bin:$PATH"
export LD_LIBRARY_PATH="$APPDIR/usr/lib:$LD_LIBRARY_PATH"

# Run Cursor with all arguments
cd "$APPDIR" || exit 1
exec "$CURSOR_EXECUTABLE" "$@"
EOF

    # Replace placeholder with actual path
    sed -i "s|__CURSOR_ROOT__|$extracted_root|g" "$launcher_script"
    chmod +x "$launcher_script"
    
    echo "Launcher script created at $launcher_script"
}

function install_cursor_extracted() {
    local install_dir="$1"
    local release_track=${2:-stable}
    local temp_file
    temp_file=$(mktemp)
    local arch
    arch=$(get_arch)
    local download_info
    download_info=$(get_download_info "$release_track" || true)
    local message
    message=$(echo "$download_info" | grep "MESSAGE=" | sed 's/^MESSAGE=//')

    if [ -n "$message" ]; then
        echo "$message"
        rm -f "$temp_file"
        return 1
    fi

    local download_url
    download_url=$(echo "$download_info" | grep "URL=" | sed 's/^URL=//')
    local version
    version=$(echo "$download_info" | grep "VERSION=" | sed 's/^VERSION=//')

    log_step "Downloading $version Cursor AppImage for extraction..."
    if ! curl -L "$download_url" -o "$temp_file"; then
        log_error "Failed to download Cursor AppImage"
        rm -f "$temp_file"
        return 1
    fi

    chmod +x "$temp_file"

    # Verify binary architecture
    local binary_info
    binary_info=$(file "$temp_file" 2>/dev/null || echo "unreadable")
    local expected_grep="x86-64"
    if [ "$arch" = "arm64" ]; then
        expected_grep="ARM aarch64"
    fi
    if ! echo "$binary_info" | grep -q "$expected_grep"; then
        echo "Error: Arch mismatch detected ($binary_info). Expected $expected_grep." >&2
        rm -f "$temp_file"
        return 1
    fi

    log_step "Extracting Cursor AppImage (this may take a moment)..."
    local temp_extract_dir
    temp_extract_dir=$(mktemp -d)
    local current_dir
    current_dir=$(pwd)
    cd "$temp_extract_dir"

    # Extract the full AppImage
    if ! "$temp_file" --appimage-extract >/dev/null 2>&1; then
        log_error "Failed to extract AppImage. Install 'file' and 'squashfs-tools' if needed."
        cd "$current_dir"
        rm -rf "$temp_extract_dir" "$temp_file"
        return 1
    fi

    if [ ! -d "squashfs-root" ]; then
        log_error "Extraction failed (squashfs-root missing)."
        cd "$current_dir"
        rm -rf "$temp_extract_dir" "$temp_file"
        return 1
    fi

    # Create installation directory and move extracted content
    mkdir -p "$install_dir"
    safe_remove "$install_dir/cursor" "existing extracted installation" true
    mv squashfs-root "$install_dir/cursor"

    # Mark as extracted installation
    echo "$version" > "$install_dir/.cursor_extracted"
    echo "$version" > "$install_dir/.cursor_version"

    # Find the main Cursor executable
    local main_exe=""
    for possible_exe in "$install_dir/cursor/cursor" "$install_dir/cursor/usr/bin/cursor" "$install_dir/cursor/AppRun"; do
        if [ -x "$possible_exe" ]; then
            main_exe="$possible_exe"
            break
        fi
    done

    if [ -z "$main_exe" ]; then
        log_warn "Could not find Cursor executable in extracted files."
    else
        log_ok "Cursor executable found at: $main_exe"
    fi

    # Create launcher script
    create_launcher_script "$install_dir"

    # Install icons
    local icons_installed=false
    local icon_source="$install_dir/cursor/usr/share/icons/hicolor"
    if [ -d "$icon_source" ]; then
        if install_icons_from_source "$icon_source"; then
            icons_installed=true
        fi
    fi

    # Install desktop file
    local apps_dir="$HOME/.local/share/applications"
    local desktop_installed=false
    mkdir -p "$apps_dir"
    if [ -f "$install_dir/cursor/cursor.desktop" ]; then
        if cp "$install_dir/cursor/cursor.desktop" "$apps_dir/"; then
            sed -i "s|^Exec=.*|Exec=$CLI_BIN --no-sandbox --open-url %U|" "$apps_dir/cursor.desktop"
            sed -i 's/^Icon=co.anysphere.cursor/Icon=cursor/' "$apps_dir/cursor.desktop"
            
            # Fix MimeType
            if grep -q '^MimeType=' "$apps_dir/cursor.desktop"; then
                sed -i '/^MimeType=/{
                    /x-scheme-handler\/cursor;/!s/$/x-scheme-handler\/cursor;/
                }' "$apps_dir/cursor.desktop"
            else
                echo 'MimeType=x-scheme-handler/cursor;' >> "$apps_dir/cursor.desktop"
            fi

            update-desktop-database "$apps_dir" 2>/dev/null || true
            log_ok ".desktop file installed and updated."
            desktop_installed=true
        else
            log_warn "Failed to install .desktop file."
        fi
    fi

    # Cleanup
    cd "$current_dir"
    rm -rf "$temp_extract_dir" "$temp_file"

    echo ""
    log_ok "Cursor $version has been extracted and installed to $install_dir/cursor"
    log_ok "No FUSE required - running as native application"
    log_ok "Launcher script created at $CLI_BIN"
    if [ "$icons_installed" = true ] && [ "$desktop_installed" = true ]; then
        log_ok "Icons and desktop file installed"
    elif [ "$icons_installed" = true ]; then
        log_warn "Icons installed, but desktop file installation skipped or failed."
    elif [ "$desktop_installed" = true ]; then
        log_warn "Desktop file installed, but icons installation skipped or failed."
    else
        log_warn "Icons and desktop file were not installed."
    fi
    return 0
}

function install_cursor() {
    local install_dir="$1"
    local release_track=${2:-stable} # Default to stable if not specified
    
    # Check if we should do extracted installation
    if [ "$INSTALL_MODE" = "extracted" ]; then
        local extract_dir
        extract_dir=$(get_extraction_dir)
        install_cursor_extracted "$extract_dir" "$release_track"
        return $?
    fi
    
    # Otherwise, proceed with AppImage installation
    local temp_file
    temp_file=$(mktemp)
    local current_dir
    current_dir=$(pwd)
    local arch
    arch=$(get_arch)
    local download_info
    download_info=$(get_download_info "$release_track" || true)
    local message
    message=$(echo "$download_info" | grep "MESSAGE=" | sed 's/^MESSAGE=//')

    if [ -n "$message" ]; then
        echo "$message"
        return 1
    fi

    # Check for FUSE before proceeding with AppImage installation
    # Note: check_fuse only warns in non-interactive mode, doesn't fail
    check_fuse

    local download_url
    download_url=$(echo "$download_info" | grep "URL=" | sed 's/^URL=//')
    local version
    version=$(echo "$download_info" | grep "VERSION=" | sed 's/^VERSION=//')

    log_step "Downloading $version Cursor AppImage..."
    if ! curl -L "$download_url" -o "$temp_file"; then
        log_error "Failed to download Cursor AppImage"
        rm -f "$temp_file"
        return 1
    fi

    chmod +x "$temp_file"
    mv "$temp_file" "$install_dir/cursor.appimage"

    # Ensure execution permissions persist post-move (robust against FS quirks)
    chmod +x "$install_dir/cursor.appimage"
    if [ -x "$install_dir/cursor.appimage" ]; then
        log_ok "Execution permissions confirmed for $install_dir/cursor.appimage"
    else
        log_warn "Failed to set execution permissions—check filesystem."
        return 1
    fi

    # Verify binary architecture matches host
    local binary_info
    binary_info=$(file "$install_dir/cursor.appimage" 2>/dev/null || echo "unreadable")
    local expected_grep="x86-64"
    if [ "$arch" = "arm64" ]; then
        expected_grep="ARM aarch64"
    fi
    if ! echo "$binary_info" | grep -q "$expected_grep"; then
        echo "Error: Arch mismatch detected ($binary_info). Expected $expected_grep. Aborting install." >&2
        safe_remove "$install_dir/cursor.appimage" "Cursor AppImage"
        return 1
    fi
    log_ok "Binary verified: $binary_info"

    # Store version information in a simple file
    echo "$version" >"$install_dir/.cursor_version"

    log_step "Extracting icons and desktop file..."
    local temp_extract_dir
    temp_extract_dir=$(mktemp -d)
    cd "$temp_extract_dir"

    # Extract icons
    if ! "$install_dir/cursor.appimage" --appimage-extract "usr/share/icons" >/dev/null 2>&1; then
        log_warn "Icon extraction failed—skipping."
    fi
    # Extract desktop file
    if ! "$install_dir/cursor.appimage" --appimage-extract "cursor.desktop" >/dev/null 2>&1; then
        log_warn "Desktop extraction failed—skipping."
    fi

    # Verify extraction succeeded before copying
    if [ ! -d "squashfs-root" ]; then
        log_error "Extraction failed (squashfs-root missing). Check arch/FUSE."
        cd "$current_dir"
        rm -rf "$temp_extract_dir"
        return 1
    fi

    # Copy icons
    local icons_installed=false
    local icon_source="squashfs-root/usr/share/icons/hicolor"
    if [ -d "$icon_source" ]; then
        if install_icons_from_source "$icon_source"; then
            icons_installed=true
        fi
    fi

    # Copy desktop file
    local apps_dir="$HOME/.local/share/applications"
    local desktop_installed=false
    mkdir -p "$apps_dir"
    if [ -f "squashfs-root/cursor.desktop" ]; then
        if cp squashfs-root/cursor.desktop "$apps_dir/"; then
            # Update desktop file to point to the correct AppImage location
            sed -i "s|^Exec=.*|Exec=$install_dir/cursor.appimage --no-sandbox --open-url %U|" "$apps_dir/cursor.desktop"

            # Fix potential icon name mismatch in the extracted desktop file
            sed -i 's/^Icon=co.anysphere.cursor/Icon=cursor/' "$apps_dir/cursor.desktop"

            # Fix MimeType to support xdg-open and backlinks
            # If MimeType line exists, append x-scheme-handler/cursor; if not already present; else add the line
            if grep -q '^MimeType=' "$apps_dir/cursor.desktop"; then
                sed -i '/^MimeType=/{
                    /x-scheme-handler\/cursor;/!s/$/x-scheme-handler\/cursor;/
                }' "$apps_dir/cursor.desktop"
            else
                echo 'MimeType=x-scheme-handler/cursor;' >> "$apps_dir/cursor.desktop"
            fi

            # Refresh desktop database for menu visibility
            update-desktop-database "$apps_dir" 2>/dev/null || true
            log_ok ".desktop file installed and updated."
            desktop_installed=true
        else
            log_warn "Failed to install .desktop file."
        fi
    else
        log_warn "cursor.desktop not found in extraction—manual setup needed."
    fi

    # Clean up
    cd "$current_dir"
    rm -rf "$temp_extract_dir"

    log_ok "Cursor has been installed to $install_dir/cursor.appimage"
    if [ "$icons_installed" = true ] && [ "$desktop_installed" = true ]; then
        log_ok "Icons and desktop file installed"
    elif [ "$icons_installed" = true ]; then
        log_warn "Icons installed, but desktop file installation skipped or failed."
    elif [ "$desktop_installed" = true ]; then
        log_warn "Desktop file installed, but icons installation skipped or failed."
    else
        log_warn "Icons and desktop file were not installed."
    fi
}

function reinstall_desktop_file() {
    log_step "Reinstalling Cursor desktop file..."

    local apps_dir="$HOME/.local/share/applications"
    mkdir -p "$apps_dir"

    # Prefer extracted installation if present
    local extracted_root
    if extracted_root=$(get_extracted_root); then
        local src_desktop="$extracted_root/cursor/cursor.desktop"
        if [ ! -f "$src_desktop" ]; then
            log_error "cursor.desktop not found in extracted installation at $src_desktop"
            return 1
        fi
        cp "$src_desktop" "$apps_dir/"
        # Set Exec to launcher script
        sed -i "s|^Exec=.*|Exec=$CLI_BIN --no-sandbox --open-url %U|" "$apps_dir/cursor.desktop"
    else
        # Fall back to AppImage installation
        local cursor_appimage
        cursor_appimage=$(find_cursor_appimage || true)
        if [ -z "$cursor_appimage" ]; then
            log_error "Cursor installation not found. Install or update before reinstalling desktop file."
            return 1
        fi
        local install_dir
        install_dir=$(dirname "$cursor_appimage")
        local temp_extract_dir
        temp_extract_dir=$(mktemp -d)
        local current_dir
        current_dir=$(pwd)
        cd "$temp_extract_dir"
        if ! "$cursor_appimage" --appimage-extract "cursor.desktop" >/dev/null 2>&1; then
            log_warn "Failed to extract cursor.desktop from AppImage."
        fi
        if [ -f "squashfs-root/cursor.desktop" ]; then
            cp "squashfs-root/cursor.desktop" "$apps_dir/"
        else
            log_warn "cursor.desktop not found in extraction; creating minimal desktop entry."
            cat > "$apps_dir/cursor.desktop" <<EOF
[Desktop Entry]
Name=Cursor
Exec=$install_dir/cursor.appimage --no-sandbox --open-url %U
Terminal=false
Type=Application
Icon=cursor
Categories=Development;IDE;TextEditor;
MimeType=x-scheme-handler/cursor;
EOF
        fi
        cd "$current_dir"
        rm -rf "$temp_extract_dir"
        # Ensure Exec points to AppImage
        sed -i "s|^Exec=.*|Exec=$install_dir/cursor.appimage --no-sandbox --open-url %U|" "$apps_dir/cursor.desktop"
    fi

    # Normalize icon name and ensure custom scheme support
    sed -i 's/^Icon=co.anysphere.cursor/Icon=cursor/' "$apps_dir/cursor.desktop"
    if grep -q '^MimeType=' "$apps_dir/cursor.desktop"; then
        sed -i '/^MimeType=/{
                /x-scheme-handler\/cursor;/!s/$/x-scheme-handler\/cursor;/
            }' "$apps_dir/cursor.desktop"
    else
        echo 'MimeType=x-scheme-handler/cursor;' >> "$apps_dir/cursor.desktop"
    fi

    update-desktop-database "$apps_dir" 2>/dev/null || true
    log_ok "Desktop file reinstalled at $apps_dir/cursor.desktop"
}

function update_cursor() {
    log_step "Updating Cursor..."
    local current_appimage
    current_appimage=$(find_cursor_appimage || true)
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
    # Check for extracted installation first
    local extracted_root
    if extracted_root=$(get_extracted_root); then
        local cursor_exe="$extracted_root/cursor/cursor"
        if [ ! -x "$cursor_exe" ]; then
            # Try alternate locations
            for alt in "$extracted_root/cursor/usr/bin/cursor" "$extracted_root/cursor/AppRun"; do
                if [ -x "$alt" ]; then
                    cursor_exe="$alt"
                    break
                fi
            done
        fi
        
        if [ -x "$cursor_exe" ]; then
            echo "Launching extracted Cursor installation..."
            local log_file="/tmp/cursor_extracted.log"
            
            # Set up environment
            export APPDIR="$extracted_root/cursor"
            export PATH="$APPDIR/usr/bin:$PATH"
            export LD_LIBRARY_PATH="$APPDIR/usr/lib:${LD_LIBRARY_PATH:-}"
            
            cd "$APPDIR" || return 1
            nohup "$cursor_exe" --no-sandbox "$@" >"$log_file" 2>&1 &
            
            local pid=$!
            sleep 1
            
            if ! kill -0 "$pid" 2>/dev/null; then
                echo "Error: Cursor failed to start. Check the log for details."
                cat "$log_file"
                return 1
            else
                echo "Cursor is running (extracted mode)."
                return 0
            fi
        fi
    fi
    
    # Fall back to AppImage mode
    local cursor_appimage
    cursor_appimage=$(find_cursor_appimage || true)

    if [ -z "$cursor_appimage" ]; then
        log_warn "Cursor not found. Running update to install it."
        update_cursor
        cursor_appimage=$(find_cursor_appimage)
    fi

    # Pre-launch safeguard (re-chmod + arch check)
    if [ ! -x "$cursor_appimage" ]; then
        log_info "Fixing execution permissions..."
        chmod +x "$cursor_appimage"
    fi
    local binary_info
    binary_info=$(file "$cursor_appimage" 2>/dev/null || echo "unreadable")
    if ! echo "$binary_info" | grep -q "$(get_arch | sed 's/x64/x86-64/;s/arm64/ARM aarch64/')"; then  # Simplified arch map
        log_error "Arch mismatch in binary ($binary_info). Re-update."
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
        log_error "Cursor AppImage failed to start. Check the log for details."
        cat "$log_file"
    else
        log_ok "Cursor AppImage is running."
    fi
}

function get_version() {
    # Check extracted installation first
    local extracted_root
    if extracted_root=$(get_extracted_root || true); then
        local version_file="$extracted_root/.cursor_version"
        if [ -f "$version_file" ]; then
            local version
            version=$(cat "$version_file")
            echo "Cursor version: $version (extracted installation)"
            return 0
        fi
    fi
    
    # Check AppImage installation
    local cursor_appimage
    cursor_appimage=$(find_cursor_appimage)
    if [ -z "$cursor_appimage" ]; then
        echo "Cursor is not installed"
        return 1
    fi

    local install_dir
    install_dir=$(dirname "$cursor_appimage")
    local version_file="$install_dir/.cursor_version"

    if [ -f "$version_file" ]; then
        local version
        version=$(cat "$version_file")
        if [ -n "$version" ]; then
            echo "Cursor version: $version (AppImage)"
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
case "$1" in
    --version|-v)
        get_version
        exit $?
        ;;
    --check|-c)
        check_cursor_versions
        exit $?
        ;;
    --update|-u)
        update_cursor "$2"
        exit $?
        ;;
    --extract|--no-fuse)
        # Enable extracted installation mode
        INSTALL_MODE="extracted"
        shift
        if [ "$1" == "--update" ] || [ "$1" == "-u" ]; then
            update_cursor "$2"
        else
            # Install in extracted mode
            extract_dir=$(get_extraction_dir)
            install_cursor_extracted "$extract_dir" "${1:-stable}"
        fi
        exit $?
        ;;
    --reinstall-desktop)
        reinstall_desktop_file
        exit $?
        ;;
    --help|-h)
        cat << 'HELP'
Usage: cursor-installer [OPTIONS] [ARGUMENTS]

Options:
  --version, -v           Show the installed version of Cursor
  --check, -c             Show stable and latest available versions
  --update, -u [stable|latest] Update Cursor to the specified release track
  --extract, --no-fuse    Install/update Cursor in extracted mode (no FUSE required)
  --reinstall-desktop     Reinstall only the desktop entry for debugging
  --help, -h              Show this help message

Installation Modes:
  AppImage (default)      Uses FUSE to run Cursor as an AppImage
  Extracted (--extract)   Fully extracts and installs Cursor without FUSE dependency
                          Useful for systems without FUSE support or restricted environments

Examples:
  cursor-installer                        Launch Cursor
  cursor-installer --check               Show latest and stable versions
  cursor-installer --update stable        Update to stable release
  cursor-installer --extract --update     Install/update in extracted mode (no FUSE)
  cursor-installer --version              Show installed version

Environment Variables:
  CURSOR_INSTALL_MODE     Set to 'extracted' to use extracted mode by default
HELP
        exit 0
        ;;
    *)
        launch_cursor "$@"
        exit $?
        ;;
esac
