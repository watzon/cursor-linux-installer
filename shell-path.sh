#!/bin/sh
# cursor-linux-installer-path

cursor_installer_local_bin="$HOME/.local/bin"

if [ -d "$cursor_installer_local_bin" ]; then
  cursor_installer_filtered_path=$(
    printf '%s' "${PATH:-}" |
      awk -v RS=: -v ORS=: -v skip="$cursor_installer_local_bin" '$0 != skip { print }' |
      sed 's/:$//'
  )

  if [ -n "$cursor_installer_filtered_path" ]; then
    PATH="$cursor_installer_local_bin:$cursor_installer_filtered_path"
  else
    PATH="$cursor_installer_local_bin"
  fi

  export PATH
fi

unset cursor_installer_local_bin
unset cursor_installer_filtered_path
