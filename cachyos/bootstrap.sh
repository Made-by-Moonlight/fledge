#!/usr/bin/env bash
set -euo pipefail

DOTFILES_REPO="https://github.com/slievr/dotfiles.git"
DOTFILES_DIR="$HOME/proj/dotfiles"

PACMAN_PACKAGES=(
  cachyos-hyprland-settings hyprland waybar
  kitty
  mako swayosd starship
  git stow fzf mise base-devel
  # Deps for the vendored dot-local/share/omarchy/bin/ scripts that
  # dot-config/hypr/bindings.conf calls (see that dir's README.md).
  uwsm xdg-desktop-portal-hyprland
  grim slurp satty hyprpicker wl-clipboard jq
)

missing=()
for pkg in "${PACMAN_PACKAGES[@]}"; do
  if ! pacman -Qi "$pkg" &>/dev/null; then
    missing+=("$pkg")
  fi
done
if [ "${#missing[@]}" -gt 0 ]; then
  sudo pacman -S --needed --noconfirm "${missing[@]}"
fi

# Use CachyOS's own cachyos/paru package, not AUR paru-bin: paru-bin is
# linked against stock Arch's libalpm ABI, which mismatches CachyOS's
# custom pacman/libalpm build and fails at runtime
# ("error while loading shared libraries: libalpm.so.15").
if ! command -v paru &>/dev/null; then
  sudo pacman -S --needed --noconfirm paru
fi

for aur_pkg in walker-bin zen-browser-bin xdg-terminal-exec; do
  if ! pacman -Qi "$aur_pkg" &>/dev/null; then
    paru -S --noconfirm "$aur_pkg"
  fi
done

if [ ! -d "$DOTFILES_DIR" ]; then
  git clone "$DOTFILES_REPO" "$DOTFILES_DIR"
fi

# Ensure ~/.local/share exists as a real directory before stowing, so stow
# links only dot-local/share/omarchy into it instead of tree-folding the
# whole ~/.local/share into one symlink into the repo (which would send
# every other app's real data under ~/.local/share into git-tracked
# territory on a fresh account with no prior ~/.local/share).
mkdir -p "$HOME/.local/share"

stow --dotfiles -v -d "$DOTFILES_DIR" -t "$HOME" .

# The vendored dot-local/share/omarchy/bin/ scripts (stowed above) need to
# be on PATH inside the Hyprland/uwsm session for bindings.conf's
# omarchy-* keybindings to resolve. uwsm reads this file for session env
# vars; it isn't stow-managed since it's created fresh on any machine
# (matches how the current host's ~/.config/uwsm/env was set up).
mkdir -p "$HOME/.config/uwsm"
UWSM_ENV="$HOME/.config/uwsm/env"
touch "$UWSM_ENV"
if ! grep -q '^export OMARCHY_PATH=' "$UWSM_ENV"; then
  # shellcheck disable=SC2016 # literal $HOME/$OMARCHY_PATH, expanded when uwsm sources this file later
  {
    echo 'export OMARCHY_PATH=$HOME/.local/share/omarchy'
    echo 'export PATH=$OMARCHY_PATH/bin/:$PATH'
  } >>"$UWSM_ENV"
fi

echo "Bootstrap complete."
