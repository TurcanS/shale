#!/bin/bash
# Shale installer. Works from a minimal Arch install: it installs what the shell needs
# (asking first), then the shell itself. Pass --help to see the options, including --update and
# --uninstall.
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"

if [ "$(id -u)" -eq 0 ]; then
  echo "Run ./install.sh as your normal user, not root. It asks for your password when it needs it." >&2
  exit 1
fi
if ! command -v pacman >/dev/null; then
  echo "Shale's installer supports Arch Linux (pacman was not found)." >&2
  exit 1
fi
# A minimal Arch has no Python yet, and the rest of the installer is Python.
if ! command -v python3 >/dev/null; then
  echo "Installing Python first; the installer needs it."
  if [ -x /usr/bin/sudo ]; then
    /usr/bin/sudo /usr/bin/pacman -S --needed python
  elif [ -x /usr/bin/pkexec ]; then
    echo "sudo is not installed, so this step uses pkexec."
    /usr/bin/pkexec /usr/bin/pacman -S --needed python
  else
    echo "Neither sudo nor pkexec is installed. As root: pacman -S sudo, then add yourself to the wheel group." >&2
    exit 1
  fi
fi
# Updating and uninstalling leave packages alone.
setup=--setup
for arg in "$@"; do
  case "$arg" in --update|--uninstall) setup= ;; esac
done
SHALE_INSTALLER=install.sh exec python3 scripts/install.py $setup --apply "$@"
