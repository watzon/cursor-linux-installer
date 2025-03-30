#!/usr/bin/env bash

set -e

# URL of the cursor.sh script in the GitHub repository
CURSOR_SCRIPT_URL="https://raw.githubusercontent.com/watzon/cursor-linux-installer/main/cursor.sh"

# Local bin directory
LOCAL_BIN="$HOME/.local/bin"

# Create ~/.local/bin if it doesn't exist
mkdir -p "$LOCAL_BIN"

# Download cursor.sh and save it as 'cursor' in ~/.local/bin
echo "Downloading Cursor installer script..."
curl -fsSL "$CURSOR_SCRIPT_URL" -o "$LOCAL_BIN/cursor"

# Make the script executable
chmod +x "$LOCAL_BIN/cursor"

echo "Cursor installer script has been placed in $LOCAL_BIN/cursor"

# Check if ~/.local/bin is in PATH
if [[ ":$PATH:" != *":$LOCAL_BIN:"* ]]; then
    echo "Warning: $LOCAL_BIN is not in your PATH."
    echo "To add it, run this command or add it to your shell profile:"
    echo "export PATH=\"\$HOME/.local/bin:\$PATH\""
fi

# Run cursor --update to download and install Cursor
echo "Downloading and installing Cursor..."
"$LOCAL_BIN/cursor" --update "$@"

echo "Installation complete. You can now run 'cursor' to start Cursor."

