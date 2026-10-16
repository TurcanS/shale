#!/usr/bin/env bash
# Shale installer. Works from a minimal Arch install: it installs what the shell needs
# (asking first), then the shell itself. Pass --help to see the options, including --update and
# --uninstall.
set -euo pipefail
shopt -s inherit_errexit

die() {
  printf '%s\n' "$*" >&2
  exit 1
}

# The first way to become root that is installed, in the order scripts/install.py tries them too: sudo, what
# people install instead of it, then pkexec (it asks in the terminal when there is no desktop yet).
root_tool() {
  local tool
  for tool in /usr/bin/sudo /usr/bin/sudo-rs /usr/bin/doas /usr/bin/pkexec; do
    if [[ -x $tool ]]; then
      printf '%s\n' "$tool"
      return 0
    fi
  done
  return 1
}

cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")"

(( EUID != 0 )) || die "Run ./install.sh as your normal user, not root. It asks for your password when it needs it."
command -v pacman >/dev/null || die "Shale's installer supports Arch Linux (pacman was not found)."
[[ -f scripts/install.py && -f shell.qml ]] || die "This copy of Shale is incomplete (scripts/install.py or shell.qml is missing). Clone it again with git."

# A minimal Arch has no Python yet, and the rest of the installer is Python.
if ! command -v python3 >/dev/null; then
  echo "Installing Python first; the installer needs it."
  root=$(root_tool) || die "No sudo, doas or pkexec is installed. As root: pacman -S sudo, then add yourself to the wheel group."
  [[ $root == /usr/bin/sudo ]] || echo "sudo is not installed, so this step uses ${root##*/}."
  "$root" /usr/bin/pacman -S --needed python \
    || die "pacman did not install Python. If it could not download it, your package lists are out of date: run sudo pacman -Syu, then ./install.sh again."
fi

# Updating and uninstalling leave packages alone; everything else sets up this machine's packages first.
args=(--apply "$@")
setup=true
for arg; do
  case $arg in
    --update | --uninstall) setup=false ;;
  esac
done
if $setup; then
  args=(--setup "${args[@]}")
fi
SHALE_INSTALLER=install.sh exec python3 scripts/install.py "${args[@]}"
