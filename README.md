# Cursor Linux Installer

Cursor is an excellent AI-powered code editor, but it doesn't treat Linux as a first-class citizen. Unlike macOS and Windows, which have distribution-specific installers, Linux users are left with an AppImage that doesn't integrate well with the system. This means no `cursor` or `code` commands in your terminal, making it less convenient to use.

This repository aims to solve that problem by providing a set of shell scripts that will:

1. Download and install Cursor for you
2. Provide a `cursor` command that you can run from your shell
3. Allow you to easily update Cursor when new versions are released

## Installation

There are two ways to install, depending on whether you want to run from the GitHub one-liner or from a locally cloned repository.

### Method 1: One‑liner (curl)

```bash
# Install stable version (default, AppImage mode)
curl -fsSL https://raw.githubusercontent.com/watzon/cursor-linux-installer/main/install.sh | bash

# Install latest version
curl -fsSL https://raw.githubusercontent.com/watzon/cursor-linux-installer/main/install.sh | bash -s -- latest

# Install in extracted mode (no FUSE required)
curl -fsSL https://raw.githubusercontent.com/watzon/cursor-linux-installer/main/install.sh | bash -s -- stable --extract
```

### Method 1: One‑liner (wget)

```bash
# Install stable version (default, AppImage mode)
wget -qO- https://raw.githubusercontent.com/watzon/cursor-linux-installer/main/install.sh | bash

# Install latest version
wget -qO- https://raw.githubusercontent.com/watzon/cursor-linux-installer/main/install.sh | bash -s -- latest

# Install in extracted mode (no FUSE required)
wget -qO- https://raw.githubusercontent.com/watzon/cursor-linux-installer/main/install.sh | bash -s -- stable --extract
```

The one‑liner script will:

1. Download the `cursor.sh` script and save it as `cursor` in `~/.local/bin/`
2. Make the script executable
3. Download and install the latest version of Cursor

**Note:** If you're installing via the piped bash method and don't have FUSE2 installed, the script will warn you but continue. You'll need to either:

- Install FUSE2 manually: `sudo apt-get install libfuse2` (Debian/Ubuntu), `sudo dnf install fuse` (Fedora), or `sudo pacman -S fuse2` (Arch)
- Use extracted mode: `curl -fsSL https://raw.githubusercontent.com/watzon/cursor-linux-installer/main/install.sh | bash -s -- stable --extract`

### Method 2: Local clone

```bash
git clone https://github.com/watzon/cursor-linux-installer.git
cd cursor-linux-installer

# AppImage mode (default)
./install.sh stable

# Latest release
./install.sh latest

# Extracted, no-FUSE mode
./install.sh latest --extract
```

When you run `./install.sh` from the repo, it uses the local `cursor.sh` instead of downloading from GitHub.

### Maintainers: Switching between personal and canonical repos

This fork uses a personal branch for development and the upstream repo for canonical links. The installer supports environment overrides so you can test personal builds without modifying repo defaults:

```bash
# (Optional) Personal testing without editing repo defaults
export REPO_OWNER="ZanzyTHEbar"
export REPO_BRANCH="personal"
./install.sh latest
```

CI or release scripts can set these env vars to ensure links point to the canonical repo in artifacts and docs.

#### Branch protection and automation

This repository enforces that `main` always points to the canonical upstream (`watzon/cursor-linux-installer`).

- A GitHub Action (`.github/workflows/enforce-canonical.yml`) runs on pushes and PRs to `main` and fails if:
  - Any personal links like `ZanzyTHEbar/cursor-linux-installer/personal` are present in tracked files.
  - `install.sh` defaults are not `REPO_OWNER=watzon` and `REPO_BRANCH=main`.

Maintainer workflow:

1. Develop on personal branch.
2. Merge to `main` in your fork.
3. Canonical defaults are used automatically (`watzon/main`). For personal testing, use the env overrides shown above.

4. Enable local git hook to prevent pushing non-canonical links to main:

   ```bash
   git config core.hooksPath .githooks
   chmod +x .githooks/pre-push
   ```

5. Open PR to upstream. CI will verify canonical links.

## Uninstalling

To uninstall the Cursor Linux Installer, you can run the uninstall script:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/watzon/cursor-linux-installer/main/uninstall.sh)"
```

or

```bash
bash -c "$(wget -qO- https://raw.githubusercontent.com/watzon/cursor-linux-installer/main/uninstall.sh)"

```

The uninstall script will:

1. Remove the `cursor` script from `~/.local/bin/`
2. Remove the Cursor AppImage
3. Ask if you want to remove the Cursor configuration files

## Usage

After installation, you can use the `cursor` command to launch Cursor or update it:

- To launch Cursor: `cursor`
- To update Cursor: `cursor --update [options]`
  - Update to stable version: `cursor --update` or `cursor --update stable`
  - Update to latest version: `cursor --update latest`
  - Additional arguments can be passed after `--update` to control the update behavior
- To check Cursor version: `cursor --version` or `cursor -v`
  - Shows the installed version of Cursor if available
  - Returns an error if Cursor is not installed or version cannot be determined

## Installation Modes

The installer supports two installation modes:

### AppImage Mode (Default)

The default mode installs Cursor as an AppImage. This requires FUSE2 to be installed on your system.

**Requirements:**

- FUSE2 (automatically installed by the script on Debian/Ubuntu, Fedora, and Arch)

**Advantages:**

- Smaller disk footprint
- Standard AppImage format

**Usage:**

```bash
cursor --update stable
```

### Extracted Mode (FUSE-Free)

This mode fully extracts the AppImage and installs Cursor as a native application, **eliminating the need for FUSE**. This is ideal for:

- Systems without FUSE support
- Restricted environments (containers, some cloud instances)
- Users who prefer traditional installations

**Advantages:**

- No FUSE dependency
- Works in restricted environments
- Native application structure
- Potentially better compatibility

**Usage:**

```bash
# Install in extracted mode
cursor --extract

# Update in extracted mode
cursor --extract --update stable

# Set as default via environment variable
export CURSOR_INSTALL_MODE=extracted
cursor --update stable
```

**Note:** The extracted installation is stored in `~/.local/share/cursor/`.

## Note

If you encounter a warning that `~/.local/bin` is not in your PATH, you can add it by running:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

or add it to your shell profile (e.g., `.bashrc`, `.zshrc`, etc.):

```bash
echo "export PATH=\"\$HOME/.local/bin:\$PATH\"" >> ~/.bashrc
source ~/.bashrc
```

## License

This software is released under the MIT License.

## Contributing

If you find a bug or have a feature request, please open an issue on GitHub.

If you want to contribute to the project, please fork the repository and submit a pull request.
