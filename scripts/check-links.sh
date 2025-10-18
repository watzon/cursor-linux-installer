#!/usr/bin/env bash

set -euo pipefail

# Verify no non-canonical links remain in tracked files.
# Canonical: watzon/cursor-linux-installer@main

root="$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)"

echo "Checking for non-canonical links..."

# Any raw.githubusercontent.com links not pointing to watzon/main
violations_raw=$(grep -RInE "raw\.githubusercontent\.com/.*/cursor-linux-installer/.+" "$root" \
  --include='*.sh' --include='README.md' | grep -v "watzon/cursor-linux-installer/main" || true)

# Any github.com clone links not pointing to watzon
violations_git=$(grep -RInE "github\.com/.*/cursor-linux-installer(\.git)?" "$root" \
  --include='*.sh' --include='README.md' | grep -v "github\.com/watzon/cursor-linux-installer" || true)

violations="${violations_raw}
${violations_git}"

if [[ -n "$(echo "$violations" | sed '/^$/d')" ]]; then
  echo "Found personal links in the following locations:" >&2
  echo "$violations" >&2
  exit 1
fi

# Enforce canonical defaults in install.sh
install_sh="$root/install.sh"
# shellcheck disable=SC2016
if ! grep -q '^REPO_OWNER=${REPO_OWNER:-watzon}' "$install_sh"; then
  echo "install.sh REPO_OWNER default must be 'watzon' on main" >&2
  exit 1
fi
# shellcheck disable=SC2016
if ! grep -q '^REPO_BRANCH=${REPO_BRANCH:-main}' "$install_sh"; then
  echo "install.sh REPO_BRANCH default must be 'main' on main" >&2
  exit 1
fi

echo "No non-canonical links found and canonical defaults are correct."


