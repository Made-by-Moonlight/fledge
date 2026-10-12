#!/usr/bin/env bash
set -euo pipefail

DOTFILES_REPO="https://github.com/slievr/slievr-cachy.git"
DOTFILES_DIR="$HOME/proj/slievr-cachy"

# The lock screen's own PAM service, separate from the real login stack so a
# mistake here can't break logging in. Written first, before anything that can
# fail: without it the mbm lock falls back to PAM's `other` service, which
# denies everything, and a locked session could never be unlocked.
printf 'auth include login\n' | sudo tee /etc/pam.d/mbm-lock >/dev/null

# Vulkan driver per GPU vendor present (PCI display class 0x03xxxx), read from
# sysfs so it needs no pciutils. Mixed vendors (e.g. RTX 3080 + RX 9070 XT) get
# both, plus Mesa's device-select layer, which dot-config/uwsm/env-hyprland
# uses to make the monitor-driving GPU the default Vulkan device. No GPU found
# (VM) -> lavapipe, a software provider that still satisfies Steam's deps.
GPU_VULKAN_PKGS=()
gpu_vendors=()
for dev in /sys/bus/pci/devices/*; do
  [[ "$(<"$dev/class")" == 0x03* ]] || continue
  case "$(<"$dev/vendor")" in
    0x10de) gpu_vendors+=(nvidia) GPU_VULKAN_PKGS+=(nvidia-utils lib32-nvidia-utils) ;;
    0x1002) gpu_vendors+=(amd) GPU_VULKAN_PKGS+=(vulkan-radeon lib32-vulkan-radeon) ;;
    0x8086) gpu_vendors+=(intel) GPU_VULKAN_PKGS+=(vulkan-intel lib32-vulkan-intel) ;;
  esac
done
if (( $(printf '%s\n' "${gpu_vendors[@]}" | sort -u | grep -c .) > 1 )); then
  GPU_VULKAN_PKGS+=(vulkan-mesa-layers lib32-vulkan-mesa-layers)
fi
if (( ${#GPU_VULKAN_PKGS[@]} == 0 )); then
  GPU_VULKAN_PKGS=(vulkan-swrast lib32-vulkan-swrast)
fi
mapfile -t GPU_VULKAN_PKGS < <(printf '%s\n' "${GPU_VULKAN_PKGS[@]}" | sort -u)

PACMAN_PACKAGES=(
  hyprland xorg-xwayland
  kitty
  starship
  git stow fzf mise base-devel
  zsh
  # The quick-settings night light tile (slievr-toggle-nightlight); it used to
  # arrive transitively and nothing pulls it in any more.
  hyprsunset
  # kitty.conf font_family names a specific nerd font, and the mbm shell's
  # glyphs come from nerd fonts too (missing ones render as boxes).
  # JetBrainsMono Nerd Font: the mbm shell's text and the vendored sddm
  # greeter theme's password field.
  ttf-cascadia-mono-nerd ttf-firacode-nerd ttf-jetbrains-mono-nerd
  # pamixer (slievr-audio-* scripts), brightnessctl (slievr-brightness-
  # display/-keyboard, the shell's brightness) were both previously only
  # pulled in transitively via cachyos-hyprland-settings (see the removal
  # step below) — its removal cascaded them away too since nothing had
  # them explicit yet.
  pamixer brightnessctl
  # Deps for the vendored dot-local/share/slievr-cachy/bin/ scripts that
  # the generated binds call (see that dir's README.md).
  uwsm xdg-desktop-portal-hyprland
  grim slurp satty hyprpicker wl-clipboard jq
  # autostart.conf's exec-once entries — all missing on a fresh install:
  # input method framework, power-profile D-Bus service
  # (slievr-powerprofiles-init needs powerprofilesctl). No idle daemon or
  # polkit agent: the mbm shell does both.
  fcitx5 power-profiles-daemon
  # The mbm shell (dot-config/quickshell/mbm, run by mbm-shell.service): bar,
  # launcher, notifications, OSD, lock, idle, polkit agent. cliphist backs its
  # clipboard history, unicode-emoji its emoji picker (noto-fonts-emoji draws them).
  # Needs Quickshell >= 0.3.2 (the version it was built and tested against;
  # the lock and idle code relies on 0.3.2 behaviour).
  quickshell cliphist unicode-emoji noto-fonts-emoji
  # Audio session: pipewire alone arrives only as a dependency; without a
  # session manager there are no sinks, so volume controls (and apps) have
  # nothing to drive. pipewire-pulse serves PulseAudio clients.
  wireplumber pipewire-pulse
  # Bluetooth stack for quick settings' Bluetooth picker. It used to arrive
  # only as bluetui's dependency, so retiring bluetui would cascade it away.
  bluez
  # slievr-transcode (Super+Ctrl+Period, pictures) and slievr-transcode-ascii
  # (Style -> About, the screensaver). It used to arrive only as an elephant
  # dependency, so retiring elephant would cascade it away.
  imagemagick
  # Activity monitor (Super+Ctrl+T); calculator key.
  btop gnome-calculator
  # Wi-Fi, Bluetooth and audio are the mbm quick settings now (Super+A,
  # Super+Ctrl+W/B/A); nmtui (ships with networkmanager) stays for the
  # Setup menu (slievr-menu setup).
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
  # Explicit vulkan-driver/lib32-vulkan-driver provider(s) for the GPUs
  # actually present (see GPU_VULKAN_PKGS above) — installed in the same
  # transaction as steam-jupiter-stable below so pacman doesn't need to
  # prompt for (and non-interactively default to a conflicting) provider
  # choice for that virtual dependency.
  "${GPU_VULKAN_PKGS[@]}"
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

# Exact installed names: `pacman -Qi walker` also matches walker-bin (it
# provides walker), so name lookups below go through this set instead.
declare -A installed=()
load_installed() {
  installed=()
  local p
  while read -r p; do installed[$p]=1; done < <(pacman -Qq)
}
load_installed

# Everything this script wants becomes explicitly installed. One that an
# earlier install got only as a dependency (bluez via bluetui, imagemagick via
# elephant) is skipped by the missing-package loop above, and the -Rns steps
# below would otherwise cascade it away with the retired package that pulled it in.
wanted=()
for pkg in "${PACMAN_PACKAGES[@]}"; do
  if [[ -n ${installed[$pkg]:-} ]]; then wanted+=("$pkg"); fi
done
if ((${#wanted[@]})); then
  sudo pacman -D --asexplicit "${wanted[@]}" >/dev/null
fi

# Use CachyOS's own cachyos/paru package, not AUR paru-bin: paru-bin is
# linked against stock Arch's libalpm ABI, which mismatches CachyOS's
# custom pacman/libalpm build and fails at runtime
# ("error while loading shared libraries: libalpm.so.15").
if ! command -v paru &>/dev/null; then
  sudo pacman -S --needed --noconfirm paru
fi

for aur_pkg in zen-browser-bin xdg-terminal-exec 1password 1password-cli; do
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
# ~/.config (and ~/.config/systemd/user) too: without it stow folds the whole directory into one symlink to dot-config/, and every app then writes its settings into the repo.
# graphical-session.target.wants too: systemd does not follow a .wants
# directory that is itself a symlink, so stow must link the unit files inside
# a real directory (otherwise mbm-shell.service never starts: no desktop shell).
# ~/.config/uwsm too: the repo ships dot-config/uwsm/env-hyprland, but env
# (written below) must stay a real, untracked file rather than land in the repo.
mkdir -p "$HOME/.local/share" "$HOME/.local/bin" "$HOME/.local/state" "$HOME/.config" \
  "$HOME/.config/systemd/user/graphical-session.target.wants" "$HOME/.config/uwsm"

stow --dotfiles -v -d "$DOTFILES_DIR" -t "$HOME" .

# Links stow made into the repo for files the repo has since dropped (the
# cutover removed waybar, walker, mako, swayosd, elephant's unit, ...) are left
# dangling: restow only manages what is still there. Remove them.
find "$HOME/.config" "$HOME/.local/share" -maxdepth 4 -xtype l -lname "*slievr-cachy/dot-*" -delete 2>/dev/null || true

# The vendored dot-local/share/slievr-cachy/bin/ scripts (stowed above) need
# to be on PATH inside the Hyprland/uwsm session for the generated binds'
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
if ! grep -q 'share/mbm/bin' "$UWSM_ENV"; then
  # shellcheck disable=SC2016 # expanded when uwsm sources the file
  echo 'export PATH=$HOME/.local/share/mbm/bin:$PATH' >>"$UWSM_ENV"
fi

# The terminal keybind ($terminal = uwsm app -- $TERMINAL) and
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

# GTK apps (Thunar...) follow the dark desktop. Nothing else sets this: the
# theme switcher that did (slievr-theme-set-gnome) is unused. GTK4/libadwaita
# follow color-scheme. GTK3 ignores it and wants gtk-application-prefer-dark-theme
# in gtk-3.0/settings.ini (below) on the built-in Adwaita theme. Don't set
# gtk-theme to Adwaita-dark: gtk3 no longer ships that theme (gnome-themes-extra
# does), and a missing theme name makes GTK3 apps fall back to light. Set
# once and idempotently. gsettings needs a D-Bus session: firstboot has none, so
# use a private one (dconf writes ~/.config/dconf/user, which persists).
set_gtk_dark() {
  local run=()
  [[ -S ${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/bus || -n ${DBUS_SESSION_BUS_ADDRESS:-} ]] || run=(dbus-run-session --)
  "${run[@]}" gsettings set org.gnome.desktop.interface color-scheme prefer-dark &&
    "${run[@]}" gsettings set org.gnome.desktop.interface gtk-theme Adwaita
}
if command -v gsettings >/dev/null 2>&1; then
  set_gtk_dark || echo "WARN: could not set GTK dark mode via gsettings" >&2
else
  echo "WARN: gsettings not found; relying on gtk-3.0/settings.ini for GTK dark mode" >&2
fi
# Not stow-managed (GTK tools rewrite it), so seed it only when the user hasn't made one.
mkdir -p "$HOME/.config/gtk-3.0"
if [ ! -e "$HOME/.config/gtk-3.0/settings.ini" ]; then
  printf '[Settings]\ngtk-application-prefer-dark-theme=1\n' >"$HOME/.config/gtk-3.0/settings.ini"
fi

# btop: use the Omarchy theme's btop.theme. btop rewrites btop.conf on exit,
# so it isn't stowed; seed it once and point themes/current.theme at the theme.
mkdir -p "$HOME/.config/btop/themes"
ln -sfn "$HOME/.config/omarchy/current/theme/btop.theme" "$HOME/.config/btop/themes/current.theme"
if [ ! -f "$HOME/.config/btop/btop.conf" ]; then
  printf 'color_theme = "current"\n' >"$HOME/.config/btop/btop.conf"
fi

# hyprland.conf sources ~/.local/state/hypr-toggles/*.conf for dynamic
# feature toggles (suspend-off, etc.) — needs to exist (even empty) so the
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
# slievr-powerprofiles-init, run at Hyprland startup) needs. Enable only, no
# --now: p-p-d.service is `After=multi-user.target`, and when bootstrap.sh runs
# from slievr-firstboot.service (itself ordered before multi-user.target, which
# waits on it), a synchronous `--now` start deadlocks — firstboot waits for the
# p-p-d job, which waits for multi-user.target, which waits for firstboot. It's
# only needed post-login at Hyprland startup, so plain enable is enough; it
# starts with graphical.target.
sudo systemctl enable power-profiles-daemon.service
# Same for bluetoothd (bluez): enable only, it starts with the system.
sudo systemctl enable bluetooth.service

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

# mbm-shell.service (the desktop shell) is a user unit started with the
# graphical session: the stowed graphical-session.target.wants/ link enables it,
# so no `systemctl --user enable` here (it would hang from slievr-firstboot).
# Run from inside a session, the end of this script starts it (see there).

# Generate the Hyprland binds/monitors/input from mbm settings; hyprland.conf
# sources ~/.local/state/mbm/hypr/*.conf and errors if nothing matches.
# Invalid user settings must not stop the rest of bootstrap: warn, and the
# uwsm env hook (dot-config/uwsm/env-hyprland) falls back to the defaults.
# Run from inside a Hyprland session (an upgrade: git pull, then bootstrap),
# Hyprland already auto-reloaded the pulled hyprland.conf, which sources these
# files: until they exist every bind is gone. So reload as soon as they're
# written. From slievr-firstboot there is no Hyprland and nothing to reload.
in_session=""
if [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]] && hyprctl version >/dev/null 2>&1; then
  in_session=1
fi
if ! MBM_NO_RELOAD=1 "$HOME/.local/share/mbm/bin/mbm" settings apply; then
  echo "WARN: mbm settings apply failed; fix ~/.config/mbm/settings.json (mbm settings check)" >&2
fi
if [[ -n $in_session ]]; then
  hyprctl reload >/dev/null 2>&1 || echo "WARN: hyprctl reload failed" >&2
fi

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

# Removals come last, after everything that can fail (paru and the AUR loop,
# the clone, stow, the generated config): on an upgrade, a failure before this
# point leaves the old desktop's packages in place instead of a half-switched
# one with no bar and no binds. Keeping them installed until now is harmless:
# hyprland.conf and autostart no longer launch any of them.
#
# cachyos-hyprland-settings (an earlier version of this script installed
# it) pulls in a lot we don't want or already have our own equivalent
# for: kvantum/qt5ct/cachyos-nord-gtk-theme-git (GTK/QT theming we don't
# use), wofi/bemenu (the mbm launcher replaces these), grimblast-git (our own
# grim+slurp+satty), polkit-kde-agent (the mbm shell is the agent),
# swaylock-effects-git/swaylock-fancy-git/wlogout/wob, cachyos-wallpapers
# (the theme's own vendored backgrounds are used instead),
# cachyos-alacritty-config (kitty only, no alacritty). Removing it here
# rather than leaving it installed; -Rns cascades to its now-orphaned
# deps, but never to a PACMAN_PACKAGES entry: those were all made explicit
# right after installing them, above.
if pacman -Qi cachyos-hyprland-settings &>/dev/null; then
  sudo pacman -Rns --noconfirm cachyos-hyprland-settings || echo "WARN: could not remove cachyos-hyprland-settings" >&2
fi

# Tools the mbm shell replaced (earlier versions of this script installed
# them). Their configs left the repo with the cutover, so nothing uses them.
RETIRED_PKGS=(waybar walker walker-bin elephant elephant-bin elephant-desktopapplications-bin elephant-calc-bin
  elephant-symbols-bin elephant-files-bin elephant-clipboard-bin elephant-websearch-bin
  elephant-providerlist-bin elephant-menus-bin elephant-1password-bin
  mako swayosd swaybg hyprlock hypridle polkit-gnome bluetui wiremix)
# Exact names (the set reloaded here, after the removal just before): `pacman
# -R walker`, or a name already gone, would fail the whole list.
load_installed
retired=()
for pkg in "${RETIRED_PKGS[@]}"; do
  if [[ -n ${installed[$pkg]:-} ]]; then retired+=("$pkg"); fi
done
if ((${#retired[@]})); then
  sudo pacman -Rns --noconfirm "${retired[@]}" || echo "WARN: could not remove some retired packages: ${retired[*]}" >&2
fi

# In a running session the switch happens now, not at the next login: the old
# daemons keep running until they're stopped, and hypridle's before_sleep_cmd
# would call the lock shim with no shell up, so the machine would suspend
# unlocked. Stop them (polkit-gnome first gives up the session's agent slot,
# which the shell's agent needs), then start the shell. After the package
# removals above, so D-Bus can't re-activate mako. Best effort: nothing here
# fails bootstrap.
if [[ -n $in_session ]]; then
  pkill -x 'waybar|mako|swayosd-server|hypridle|hyprlock|walker|elephant|swaybg' || true
  polkit_gnome="^/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1"
  pkill -f "$polkit_gnome" || true
  for _ in $(seq 20); do pgrep -f "$polkit_gnome" >/dev/null || break; sleep 0.25; done
  if systemctl --user daemon-reload && systemctl --user start mbm-shell; then
    echo "The made by moonlight desktop is live: Super+Space opens the launcher."
  else
    echo "WARN: could not start mbm-shell; it starts at the next login" >&2
  fi
fi

echo "Bootstrap complete."
