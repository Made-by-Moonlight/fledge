#!/usr/bin/env bash
set -euo pipefail

DOTFILES_REPO="https://github.com/slievr/slievr-cachy.git"
DOTFILES_DIR="$HOME/proj/slievr-cachy"

PACMAN_PACKAGES=(
  hyprland waybar xorg-xwayland
  kitty
  mako swayosd starship
  git stow fzf mise base-devel
  zsh
  # waybar/style.css and kitty.conf font_family both name specific nerd
  # fonts that were never actually installed — every icon glyph in
  # waybar (not just the menu one, which had its own separate missing-
  # font issue already fixed) rendered as a missing-glyph box.
  # JetBrainsMono Nerd Font: used by walker (config.toml/CSS) and the
  # vendored sddm greeter theme's password field.
  ttf-cascadia-mono-nerd ttf-firacode-nerd ttf-jetbrains-mono-nerd
  # swaybg (autostart.conf wallpaper), pamixer (waybar pulseaudio
  # right-click mute), brightnessctl (slievr-brightness-display/-keyboard)
  # were all previously only pulled in transitively via
  # cachyos-hyprland-settings (see the removal step below) — its removal
  # cascaded them away too since nothing had them explicit yet.
  swaybg pamixer brightnessctl
  # Deps for the vendored dot-local/share/slievr-cachy/bin/ scripts that
  # dot-config/hypr/bindings.conf calls (see that dir's README.md).
  uwsm xdg-desktop-portal-hyprland
  grim slurp satty hyprpicker wl-clipboard jq
  # autostart.conf's exec-once entries — all missing on a fresh install:
  # idle daemon, input method framework, power-profile D-Bus service
  # (slievr-powerprofiles-init needs powerprofilesctl), polkit agent.
  hypridle fcitx5 power-profiles-daemon polkit-gnome
  # Activity monitor (Super+Ctrl+T, waybar cpu click); calculator key.
  btop gnome-calculator
  # TUI controls the Setup menu (slievr-menu setup) and its keybinds
  # (Super+Ctrl+W/B/A) launch: nmtui (wifi — ships with networkmanager
  # already, not impala, which hard-depends on iwd instead of
  # NetworkManager), bluetui (bluetooth), wiremix (audio).
  bluetui wiremix
  # Official ProtonVPN GTK client.
  proton-vpn-gtk-app
  # Login manager. uwsm ships hyprland-uwsm.desktop specifically for this
  # (see /usr/share/wayland-sessions/hyprland-uwsm.desktop) — sddm is
  # what Omarchy itself defaults to (dot-local/share/slievr-cachy/bin/
  # slievr-refresh-sddm and the vendored apps/system.conf both reference
  # it), so matching that rather than picking a different DM.
  # sddm lists this as merely "optional" (for using Qt5 themes), but it's
  # actually required for the vendored QML theme below — without it
  # sddm-greeter fails at the dynamic-link stage ("error while loading
  # shared libraries: libQt5Quick.so.5"), which surfaces as a blank
  # screen with just a cursor, no error dialog.
  sddm qt5-declarative
  # Explicit vulkan-driver/lib32-vulkan-driver provider, matching the
  # NVIDIA env vars already in dot-config/hypr/hyprland.conf — installed
  # in the same transaction as steam-jupiter-stable below so pacman
  # doesn't need to prompt for (and non-interactively default to a
  # conflicting) provider choice for that virtual dependency.
  nvidia-utils lib32-nvidia-utils
  # CachyOS's Jupiter-bootstrapped Steam build.
  steam-jupiter-stable
  # Discord (windows.conf already pins it to workspace 9).
  discord
  # GUI file manager — lighter than the GNOME stack, no dependency on the
  # yazi TUI keybind it replaces.
  thunar
)

# steam-jupiter-stable needs lib32-* packages, which need the multilib
# repo — commented out by default on a fresh install.
if grep -q '^#\[multilib\]' /etc/pacman.conf; then
  sudo sed -i '/^#\[multilib\]/,/^#Include = \/etc\/pacman.d\/mirrorlist$/ s/^#//' /etc/pacman.conf
  sudo pacman -Sy
fi

missing=()
for pkg in "${PACMAN_PACKAGES[@]}"; do
  if ! pacman -Qi "$pkg" &>/dev/null; then
    missing+=("$pkg")
  fi
done
if [ "${#missing[@]}" -gt 0 ]; then
  sudo pacman -S --needed --noconfirm "${missing[@]}"
fi

# cachyos-hyprland-settings (an earlier version of this script installed
# it) pulls in a lot we don't want or already have our own equivalent
# for: kvantum/qt5ct/cachyos-nord-gtk-theme-git (GTK/QT theming we don't
# use), wofi/bemenu (walker replaces these), grimblast-git (our own
# grim+slurp+satty), polkit-kde-agent (polkit-gnome above instead),
# swaylock-effects-git/swaylock-fancy-git/wlogout/wob, cachyos-wallpapers
# (the theme's own vendored backgrounds are used instead),
# cachyos-alacritty-config (kitty only, no alacritty). Removing it here
# rather than leaving it installed; -Rns cascades to its now-orphaned
# deps, but not to anything this script's own PACMAN_PACKAGES loop above
# already made explicit (hyprland, waybar, mako, swaybg, etc.).
if pacman -Qi cachyos-hyprland-settings &>/dev/null; then
  sudo pacman -Rns --noconfirm cachyos-hyprland-settings
fi

# Use CachyOS's own cachyos/paru package, not AUR paru-bin: paru-bin is
# linked against stock Arch's libalpm ABI, which mismatches CachyOS's
# custom pacman/libalpm build and fails at runtime
# ("error while loading shared libraries: libalpm.so.15").
if ! command -v paru &>/dev/null; then
  sudo pacman -S --needed --noconfirm paru
fi

# elephant (official repo) ships only the daemon, no providers — providers
# are separate AUR packages. elephant-all-bin bundles every official one
# (~450MB: apt/dnf5/dpkg package-manager providers, a Rust toolchain,
# niri, password managers — none of which this setup uses), so install
# only the specific providers config.toml's [providers] list and
# dot-config/elephant/menus/*.lua actually need instead.
ELEPHANT_PROVIDER_PKGS=(
  elephant-desktopapplications-bin elephant-calc-bin elephant-symbols-bin
  elephant-files-bin elephant-clipboard-bin elephant-websearch-bin
  elephant-providerlist-bin elephant-menus-bin elephant-1password-bin
)

# Each provider package pulls in elephant (the daemon) as its own
# dependency, in place of the providers-less official-repo one — remove
# that first, along with walker-bin, which depends on it (reinstalled
# right after, against elephant-*-bin's provides=elephant instead), since
# it isn't declared as replacing the base elephant package and installing
# both would collide on /usr/bin/elephant.
if pacman -Qi elephant &>/dev/null && ! pacman -Qi elephant-desktopapplications-bin &>/dev/null; then
  sudo pacman -Rdd --noconfirm elephant walker-bin
fi

for aur_pkg in "${ELEPHANT_PROVIDER_PKGS[@]}" walker-bin zen-browser-bin xdg-terminal-exec 1password 1password-cli; do
  if ! pacman -Qi "$aur_pkg" &>/dev/null; then
    paru -S --noconfirm "$aur_pkg"
  fi
done

if [ ! -d "$DOTFILES_DIR" ]; then
  git clone "$DOTFILES_REPO" "$DOTFILES_DIR"
fi

# Ensure these exist as real directories before stowing, so stow links
# only their specific dot-local/* subdirs/files into them instead of
# tree-folding the whole directory into one symlink into the repo (which
# would send every other app's real data — or, for ~/.local/bin, the
# mise symlink added below — into git-tracked territory on a fresh
# account with no prior ~/.local/share or ~/.local/bin).
mkdir -p "$HOME/.local/share" "$HOME/.local/bin"

stow --dotfiles -v -d "$DOTFILES_DIR" -t "$HOME" .

# The vendored dot-local/share/slievr-cachy/bin/ scripts (stowed above) need
# to be on PATH inside the Hyprland/uwsm session for bindings.conf's
# slievr-* keybindings to resolve. uwsm reads this file for session env
# vars; it isn't stow-managed since it's created fresh on any machine
# (matches how the current host's ~/.config/uwsm/env was set up).
mkdir -p "$HOME/.config/uwsm"
UWSM_ENV="$HOME/.config/uwsm/env"
touch "$UWSM_ENV"
if ! grep -q '^export SLIEVR_BIN_PATH=' "$UWSM_ENV"; then
  # shellcheck disable=SC2016 # literal $HOME/$SLIEVR_BIN_PATH, expanded when uwsm sources this file later
  {
    echo 'export SLIEVR_BIN_PATH=$HOME/.local/share/slievr-cachy'
    echo 'export PATH=$SLIEVR_BIN_PATH/bin/:$PATH'
  } >>"$UWSM_ENV"
fi

# bindings.conf's terminal keybind ($terminal = uwsm app -- $TERMINAL) and
# $EDITOR need these too. Previously written to ~/.config/uwsm/default,
# which — despite a plausible-looking pre-existing comment on the host
# implying otherwise — uwsm's prepare-env.sh does NOT read: it only
# sources env and env-<compositor> (confirmed against
# /usr/lib/uwsm/prepare-env.sh). That file was silently never taking
# effect; these belong in env instead, same as SLIEVR_BIN_PATH above.
if ! grep -q '^export TERMINAL=' "$UWSM_ENV"; then
  {
    echo 'export TERMINAL=xdg-terminal-exec'
    echo 'export EDITOR=nvim'
  } >>"$UWSM_ENV"
fi

# xdg-terminal-exec (what $TERMINAL delegates to, and what
# slievr-launch-tui/omarchy-launch-tui use) picks the first entry here;
# an empty/missing list falls back to its own probing order, so pin it
# to kitty explicitly to match this setup's one installed terminal.
mkdir -p "$HOME/.config"
if [ ! -f "$HOME/.config/xdg-terminals.list" ]; then
  echo "kitty.desktop" >"$HOME/.config/xdg-terminals.list"
fi

# hyprland.conf sources ~/.local/state/hypr-toggles/*.conf for dynamic
# feature toggles (waybar-off, etc.) — needs to exist (even empty) so the
# glob source doesn't warn, and enabled/disabled state persists across
# rebuilds since it's outside the stowed repo.
mkdir -p "$HOME/.local/state/hypr-toggles"
rm -f "$HOME/.local/state/hypr-toggles/.keep"
# Needs to be *.conf (not just present) — hyprland's glob source errors
# ("globbing error: found no match") if nothing matches the pattern.
# Checking for *.conf specifically (not just "dir non-empty") matters:
# an earlier version of this script left a .keep placeholder here, which
# satisfied an "is dir empty" check without ever fixing the actual error.
if ! compgen -G "$HOME/.local/state/hypr-toggles/*.conf" >/dev/null; then
  printf '# Permanent config toggle flags. Do not remove (dir needs >=1 *.conf file).\n' \
    >"$HOME/.local/state/hypr-toggles/flags.conf"
fi

# power-profiles-daemon provides the D-Bus service powerprofilesctl (and
# slievr-powerprofiles-init, run at Hyprland startup) needs.
sudo systemctl enable --now power-profiles-daemon.service

# Enable sddm as the login manager, pre-selecting the uwsm-managed
# Hyprland session (hyprland-uwsm.desktop — resolves the "Hyprland was
# started without start-hyprland" warning that a plain `Hyprland` binary
# launch, or `uwsm start hyprland`, both trigger) without enabling
# autologin: setting Session= under [Autologin] without User= just
# pre-selects it in the greeter's session picker, real hardware/VM
# testing should still see a real password prompt.
sudo mkdir -p /etc/sddm.conf.d
printf '[Autologin]\nSession=hyprland-uwsm.desktop\n' \
  | sudo tee /etc/sddm.conf.d/default-session.conf >/dev/null

# Vendored SDDM theme (cachyos/sddm-theme/slievr-cachy/, adapted from
# Omarchy's default one — same style, relabeled logo, see that dir).
# Not stow-managed: SDDM reads themes from a system path, not $HOME.
sudo rm -rf /usr/share/sddm/themes/slievr-cachy
sudo cp -r "$DOTFILES_DIR/cachyos/sddm-theme/slievr-cachy" /usr/share/sddm/themes/slievr-cachy
printf '[Theme]\nCurrent=slievr-cachy\n' \
  | sudo tee /etc/sddm.conf.d/theme.conf >/dev/null

sudo systemctl enable sddm.service

# Enable elephant (walker's search-provider backend) as a user service.
# restart, not enable --now: if it was already running against the old
# providers-less elephant package, --now alone wouldn't pick up the
# replacement binary/providers from the elephant-*-bin packages above.
systemctl --user enable elephant.service
systemctl --user restart elephant.service

# dot-zshrc expects mise at ~/.local/bin/mise (the host's curl-installer
# location); the pacman package above installs to /usr/bin/mise instead.
mkdir -p "$HOME/.local/bin"
if [ ! -e "$HOME/.local/bin/mise" ]; then
  ln -s "$(command -v mise)" "$HOME/.local/bin/mise"
fi

# dot-zshrc's zinit bootstrap clones over SSH (git@github.com:...) on
# first shell start; without GitHub's host key already trusted (as it
# would be on a machine with prior git history) that clone fails
# non-interactively instead of prompting.
mkdir -p "$HOME/.ssh"
touch "$HOME/.ssh/known_hosts"
if ! ssh-keygen -F github.com &>/dev/null; then
  ssh-keyscan -t ed25519 github.com >>"$HOME/.ssh/known_hosts" 2>/dev/null
fi

# Default shell: zsh (dot-zshrc), not bash.
zsh_path=$(command -v zsh)
if [ "$(getent passwd "$USER" | cut -d: -f7)" != "$zsh_path" ]; then
  sudo usermod --shell "$zsh_path" "$USER"
fi

echo "Bootstrap complete."
