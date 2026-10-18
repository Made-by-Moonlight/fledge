#!/usr/bin/env bash
set -euo pipefail

DOTFILES_REPO="https://github.com/made-by-moonlight/fledge.git"
DOTFILES_DIR="$HOME/proj/fledge"

# The lock screen's own PAM service, separate from the real login stack so a
# mistake here can't break logging in. Written first, before anything that can
# fail: without it the fledge lock falls back to PAM's `other` service, which
# denies everything, and a locked session could never be unlocked.
printf 'auth include login\n' | sudo tee /etc/pam.d/fledge-lock >/dev/null

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
  # gsettings' persistent backend: the GTK dark seeding below needs it.
  dconf
  # Login shell (dot-config/fish); pkgfile backs fish's command-not-found.
  fish pkgfile
  # The quick-settings night light tile (fledge toggle nightlight); it used to
  # arrive transitively and nothing pulls it in any more.
  hyprsunset
  # kitty.conf font_family names a specific nerd font, and the fledge shell's
  # glyphs come from nerd fonts too (missing ones render as boxes).
  # JetBrainsMono Nerd Font: the fledge shell's text and the vendored sddm
  # greeter theme's password field.
  ttf-cascadia-mono-nerd ttf-firacode-nerd ttf-jetbrains-mono-nerd
  # pamixer (fledge audio …), brightnessctl (fledge brightness keyboard,
  # the shell's brightness) were both previously only
  # pulled in transitively via cachyos-hyprland-settings (see the removal
  # step below) — its removal cascaded them away too since nothing had
  # them explicit yet.
  pamixer brightnessctl
  # Deps for the vendored scripts in dot-local/share/fledge/libexec/ that
  # the generated binds call (see dot-local/share/fledge/README.md). gum
  # draws the Setup tools' prompts and spinners (timezone and drive pickers,
  # the "Done!" after each one) and arrives with nothing else. socat feeds
  # `fledge hyprland monitor watch` the Hyprland event socket (the laptop
  # panel comes back after an external monitor is unplugged); nothing else
  # pulls it in either.
  uwsm xdg-desktop-portal-hyprland
  grim slurp satty hyprpicker wl-clipboard jq gum socat
  # menu › About (fledge launch about) runs fastfetch with
  # dot-config/fastfetch, whose logo is the About branding text.
  fastfetch
  # fledge/autostart.lua's startup commands — all missing on a fresh install:
  # input method framework, power-profile D-Bus service
  # (fledge powerprofiles init needs powerprofilesctl). No idle daemon or
  # polkit agent: the fledge shell does both.
  fcitx5 power-profiles-daemon
  # The fledge shell (dot-config/quickshell/fledge, run by fledge-shell.service): bar,
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
  # fledge transcode (Super+Ctrl+Period, pictures) and fledge transcode ascii
  # (Style -> About). It used to arrive only as an elephant
  # dependency, so retiring elephant would cascade it away.
  imagemagick
  # Activity monitor (Super+Ctrl+T); calculator key.
  btop gnome-calculator
  # Wi-Fi, Bluetooth and audio are the fledge quick settings now (Super+A,
  # Super+Ctrl+W/B/A); nmtui (ships with networkmanager) stays for the
  # Setup menu (fledge menu setup).
  # Official ProtonVPN GTK client.
  proton-vpn-gtk-app
  # Login manager. uwsm ships hyprland-uwsm.desktop specifically for this
  # (see /usr/share/wayland-sessions/hyprland-uwsm.desktop) — sddm is
  # what Omarchy itself defaults to (the vendored system app rules
  # reference it), so matching that rather than picking a different DM.
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
  # Discord (fledge/rules.lua already pins it to workspace 9).
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

# limusic-bin: YouTube Music client. It publishes MPRIS, so the bar's
# now-playing pill and the media keys control it with no shell code.
for aur_pkg in zen-browser-bin xdg-terminal-exec 1password 1password-cli limusic-bin; do
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
# a real directory (otherwise fledge-shell.service never starts: no desktop shell).
# ~/.config/uwsm too: the repo ships dot-config/uwsm/env-hyprland, but env
# (written below) must stay a real, untracked file rather than land in the repo.
# ~/.config/fish too: fish writes fish_variables beside the stowed config.
mkdir -p "$HOME/.local/share" "$HOME/.local/bin" "$HOME/.local/state" "$HOME/.config" \
  "$HOME/.config/systemd/user/graphical-session.target.wants" "$HOME/.config/uwsm" "$HOME/.config/fish"

stow --dotfiles -v -d "$DOTFILES_DIR" -t "$HOME" .

# Links stow made into the repo for files the repo has since dropped (the
# cutover removed waybar, walker, mako, swayosd, elephant's unit, ...; the Lua
# config removed ~/.config/hypr/*.conf and hypr-defaults/ where that directory
# was unfolded) are left dangling: restow only manages what is still there.
# Remove them.
find "$HOME" -maxdepth 1 -xtype l -name .zshrc -lname "*fledge/dot-zshrc" -delete 2>/dev/null || true
find "$HOME/.config" "$HOME/.local/share" -maxdepth 4 -xtype l -lname "*fledge/dot-*" -delete 2>/dev/null || true

# uwsm reads ~/.config/uwsm/env for session env vars; it isn't stow-managed
# since it's created fresh on any machine. The fledge command gets onto the
# session's PATH from the stowed env-hyprland instead, so it isn't here.
mkdir -p "$HOME/.config/uwsm"
UWSM_ENV="$HOME/.config/uwsm/env"
touch "$UWSM_ENV"

# The terminal keybind ($terminal = uwsm app -- $TERMINAL) and
# $EDITOR need these too. Previously written to ~/.config/uwsm/default,
# which — despite a plausible-looking pre-existing comment on the host
# implying otherwise — uwsm's prepare-env.sh does NOT read: it only
# sources env and env-<compositor> (confirmed against
# /usr/lib/uwsm/prepare-env.sh). That file was silently never taking
# effect; these belong in env instead.
if ! grep -q '^export TERMINAL=' "$UWSM_ENV"; then
  {
    echo 'export TERMINAL=xdg-terminal-exec'
    echo 'export EDITOR=nvim'
  } >>"$UWSM_ENV"
fi

# xdg-terminal-exec (what $TERMINAL delegates to, and what
# fledge launch tui uses) picks the first entry here;
# an empty/missing list falls back to its own probing order, so pin it
# to kitty explicitly to match this setup's one installed terminal.
mkdir -p "$HOME/.config"
if [ ! -f "$HOME/.config/xdg-terminals.list" ]; then
  echo "kitty.desktop" >"$HOME/.config/xdg-terminals.list"
fi

# GTK apps (Thunar...) follow the dark desktop. Nothing else sets this: the
# Omarchy theme switcher that did is gone. GTK4/libadwaita
# follow color-scheme. GTK3 ignores it and wants gtk-application-prefer-dark-theme
# in gtk-3.0/settings.ini (below) on the built-in Adwaita theme. Don't set
# gtk-theme to Adwaita-dark: gtk3 no longer ships that theme (gnome-themes-extra
# does), and a missing theme name makes GTK3 apps fall back to light.
# Seeded once, not on every run: bootstrap re-runs on every upgrade, and a user who
# later picks light must keep it. The marker is written only after a read-back through
# a fresh D-Bus session shows the values persisted: without the dconf backend,
# `gsettings set` succeeds in memory and stores nothing. gsettings needs a session
# bus: firstboot has none, so a private one is used (dconf writes
# ~/.config/dconf/user, which persists).
seed_gtk_dark() {
  local marker="$HOME/.local/state/fledge/gtk-dark-seeded" run=() out
  [[ -e $marker ]] && return 0
  command -v gsettings >/dev/null 2>&1 && command -v dconf >/dev/null 2>&1 || return 1
  [[ -S ${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/bus || -n ${DBUS_SESSION_BUS_ADDRESS:-} ]] || run=(dbus-run-session --)
  "${run[@]}" gsettings set org.gnome.desktop.interface color-scheme prefer-dark &&
    "${run[@]}" gsettings set org.gnome.desktop.interface gtk-theme Adwaita || return 1
  out="$("${run[@]}" gsettings get org.gnome.desktop.interface color-scheme)/$("${run[@]}" gsettings get org.gnome.desktop.interface gtk-theme)"
  [[ $out == "'prefer-dark'/'Adwaita'" ]] || return 1
  mkdir -p "${marker%/*}" && : >"$marker"
}
seed_gtk_dark || echo "WARN: could not set GTK dark mode via gsettings (needs gsettings and dconf); relying on gtk-3.0/settings.ini" >&2
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

# Hyprland toggles live in ~/.local/state/hypr-toggles (*.lua, loaded by
# hyprland.lua; a missing or empty dir is fine). The .conf config needed a
# placeholder flags.conf there for its glob; nothing reads it now.
rm -f "$HOME/.local/state/hypr-toggles/flags.conf"

# power-profiles-daemon provides the D-Bus service powerprofilesctl (and
# fledge powerprofiles init, run at Hyprland startup) needs. Enable only, no
# --now: p-p-d.service is `After=multi-user.target`, and when bootstrap.sh runs
# from fledge-firstboot.service (itself ordered before multi-user.target, which
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
# pre-selects it in the greeter's session picker, so the password prompt
# shows unless the installer set up autologin (autologin.conf, same disk
# and login password).
sudo mkdir -p /etc/sddm.conf.d
printf '[Autologin]\nSession=hyprland-uwsm.desktop\n' \
  | sudo tee /etc/sddm.conf.d/default-session.conf >/dev/null

# Vendored SDDM theme (cachyos/sddm-theme/fledge/, adapted from
# Omarchy's default one — same style, relabeled logo, see that dir).
# Not stow-managed: SDDM reads themes from a system path, not $HOME.
sudo rm -rf /usr/share/sddm/themes/fledge
sudo cp -r "$DOTFILES_DIR/cachyos/sddm-theme/fledge" /usr/share/sddm/themes/fledge
printf '[Theme]\nCurrent=fledge\n' \
  | sudo tee /etc/sddm.conf.d/theme.conf >/dev/null

sudo systemctl enable sddm.service

# fledge-shell.service (the desktop shell) is a user unit started with the
# graphical session: the stowed graphical-session.target.wants/ link enables it,
# so no `systemctl --user enable` here (it would hang from fledge-firstboot).
# Run from inside a session, the end of this script starts it (see there).

# Generate the Hyprland binds/monitors/input from fledge settings; hyprland.lua
# loads ~/.local/state/fledge/hypr/*.lua (a missing one just loses its settings).
# Invalid user settings must not stop the rest of bootstrap: warn, and the
# uwsm env hook (dot-config/uwsm/env-hyprland) falls back to the defaults.
# Run from inside a Hyprland session (an upgrade: git pull, then bootstrap),
# Hyprland may already have auto-reloaded the pulled config (a .conf session's
# config still auto-reloads), maybe while stow or the pull had files
# half-written, and before these existed: every bind is gone until it reloads
# again. So reload once everything is written (the reload is a
# query, the same on both config managers). From fledge-firstboot there is no
# Hyprland and nothing to reload.
fledge="$HOME/.local/share/fledge/bin/fledge"
# hypr_manager <fledge>: the running Hyprland's config manager, picked at session
# start: lua (it answers eval), conf (eval refused the way only the .conf manager
# refuses it), or "unknown: <why>" (any other failure, e.g. no fledge yet).
# cachyos/test-bootstrap.sh tests this function on its own.
hypr_manager() {
  local out
  if out="$("$1" hypr eval 'return 1' 2>&1)"; then
    echo lua
  elif [[ $out == *"only supported with the lua config manager"* ]]; then
    echo conf
  else
    echo "unknown: ${out%%$'\n'*}"
  fi
}
in_session="" lua_session="" manager=""
if [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]] && hyprctl version >/dev/null 2>&1; then
  in_session=1
  manager="$(hypr_manager "$fledge")"
  case $manager in
    lua) lua_session=1 ;;
    unknown*) echo "WARN: could not tell which config Hyprland is running (${manager#unknown: }); if your binds are gone, log out and back in" >&2 ;;
  esac
fi
if ! FLEDGE_NO_RELOAD=1 "$fledge" settings apply; then
  echo "WARN: fledge settings apply failed; fix ~/.config/fledge/settings.json (fledge settings check)" >&2
fi
if [[ -n $in_session ]]; then
  hyprctl reload >/dev/null 2>&1 || echo "WARN: hyprctl reload failed" >&2
fi
# A .conf session that saw hyprland.conf deleted (this upgrade) writes
# Hyprland's stub in its place, through the stow link into the repo, and again
# whenever it is removed while that session runs. fledge/autostart.lua removes
# it at the next Lua login; remove it here too, unless that session is running.
# Only an untracked stub (its first 200 bytes say so, the same test as
# autostart.lua's): never a file of the repo's or the user's.
# cachyos/test-bootstrap.sh tests this function on its own.
remove_hypr_stub() { # remove_hypr_stub <repo> <in_session> <lua_session>
  local repo="$1" in_session="$2" lua_session="$3"
  local stub="$repo/dot-config/hypr/hyprland.conf"
  if [[ -n $in_session && -z $lua_session ]]; then return 0; fi
  if [[ ! -f $stub ]]; then return 0; fi
  if git -C "$repo" ls-files --error-unmatch -- dot-config/hypr/hyprland.conf >/dev/null 2>&1; then return 0; fi
  if [[ $(head -c 200 -- "$stub") != *"This config is a STUB!"* ]]; then return 0; fi
  rm -f -- "$stub"
}
remove_hypr_stub "$DOTFILES_DIR" "$in_session" "$lua_session"

# dot-config/fish/conf.d/tools.fish expects mise at ~/.local/bin/mise (the host's curl-installer
# location); the pacman package above installs to /usr/bin/mise instead.
mkdir -p "$HOME/.local/bin"
if [ ! -e "$HOME/.local/bin/mise" ]; then
  ln -s "$(command -v mise)" "$HOME/.local/bin/mise"
fi

# Default shell: fish (dot-config/fish). Switched before zsh is retired below,
# so the login shell never points at a removed binary. bash and zsh (the
# stock and the previous default) are switched; anything else is the user's
# own choice and stays.
fish_path=$(command -v fish)
if ! grep -qx "$fish_path" /etc/shells; then
  echo "$fish_path" | sudo tee -a /etc/shells >/dev/null
fi
current_shell=$(getent passwd "$USER" | cut -d: -f7)
case "$current_shell" in
  "$fish_path") ;;
  */zsh | */bash) sudo usermod --shell "$fish_path" "$USER" ;;
  *) echo "NOTE: login shell is $current_shell; leaving it. Switch with: chsh -s $fish_path" >&2 ;;
esac

# The running session keeps the old SHELL: the user systemd manager outlives the
# switch (other sessions hold it open) and uwsm-launched apps inherit its
# environment, so kitty would still try a removed zsh after an in-session
# upgrade. Also on re-runs where the shell is already fish. Best effort.
login_shell=$(getent passwd "$USER" | cut -d: -f7)
export SHELL="$login_shell"
if [[ -n ${XDG_RUNTIME_DIR:-} ]] || systemctl --user show-environment >/dev/null 2>&1; then
  systemctl --user set-environment "SHELL=$login_shell" || echo "WARN: could not update the session's SHELL" >&2
  if command -v dbus-update-activation-environment >/dev/null; then
    dbus-update-activation-environment --systemd "SHELL=$login_shell" || echo "WARN: could not update the D-Bus activation SHELL" >&2
  fi
fi
# Keybind execs (Super+Return) run with Hyprland's own process environment,
# which still holds the login-time SHELL. After the one hyprctl reload above,
# so nothing re-reads config over it. A .conf session can't take it (no eval);
# it has to end now anyway (see the end). Unknown: try, it may still work.
if [[ $manager == conf ]]; then
  echo "NOTE: Hyprland's SHELL not updated in this .conf session; the next login has it"
elif [[ -n $in_session ]]; then
  "$fledge" hypr eval "hl.env(\"SHELL\", $("$fledge" hypr quote "$login_shell"))" >/dev/null 2>&1 ||
    echo "WARN: could not update Hyprland's SHELL; the next login has it" >&2
fi

# fish's command-not-found suggestions read pkgfile's database.
if command -v pkgfile >/dev/null; then
  sudo pkgfile -u || echo "WARN: could not update the pkgfile database" >&2
fi
# ...and the timer keeps it fresh afterwards.
if command -v pkgfile >/dev/null; then
  sudo systemctl enable --now pkgfile-update.timer || echo "WARN: could not enable pkgfile-update.timer" >&2
fi

# Removals come last, after everything that can fail (paru and the AUR loop,
# the clone, stow, the generated config): on an upgrade, a failure before this
# point leaves the old desktop's packages in place instead of a half-switched
# one with no bar and no binds. Keeping them installed until now is harmless:
# hyprland.lua and its autostart no longer launch any of them.
#
# cachyos-hyprland-settings (an earlier version of this script installed
# it) pulls in a lot we don't want or already have our own equivalent
# for: kvantum/qt5ct/cachyos-nord-gtk-theme-git (GTK/QT theming we don't
# use), wofi/bemenu (the fledge launcher replaces these), grimblast-git (our own
# grim+slurp+satty), polkit-kde-agent (the fledge shell is the agent),
# swaylock-effects-git/swaylock-fancy-git/wlogout/wob, cachyos-wallpapers
# (the theme's own vendored backgrounds are used instead),
# cachyos-alacritty-config (kitty only, no alacritty). Removing it here
# rather than leaving it installed; -Rns cascades to its now-orphaned
# deps, but never to a PACMAN_PACKAGES entry: those were all made explicit
# right after installing them, above.
if pacman -Qi cachyos-hyprland-settings &>/dev/null; then
  sudo pacman -Rns --noconfirm cachyos-hyprland-settings || echo "WARN: could not remove cachyos-hyprland-settings" >&2
fi

# Tools the fledge shell replaced (earlier versions of this script installed
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

# zsh goes in its own transaction: if something installed depends on it, pacman
# refuses the whole list, which must not strand the retirements above. After
# the login shell switch earlier, so no shell points at a removed binary.
load_installed
zsh_pkgs=()
for pkg in cachyos-zsh-config zsh-completions zsh; do
  if [[ -n ${installed[$pkg]:-} ]]; then zsh_pkgs+=("$pkg"); fi
done
if ((${#zsh_pkgs[@]})); then
  sudo pacman -Rns --noconfirm "${zsh_pkgs[@]}" || echo "WARN: could not remove zsh (${zsh_pkgs[*]}); fish is still the login shell" >&2
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
  if systemctl --user daemon-reload && systemctl --user start fledge-shell; then
    echo "The made by moonlight desktop is live: Super+Space opens the launcher."
  else
    echo "WARN: could not start fledge-shell; it starts at the next login" >&2
  fi
fi

# An upgrade from the .conf config, run inside that session: the stow fold
# means the pull already deleted ~/.config/hypr/hyprland.conf, and a .conf
# session that sees it go loads Hyprland's own stub within seconds: stock binds,
# rules and monitors. It can't load the Lua config; only a new login can. Last,
# so the notification goes to the shell started above.
if [[ $manager == conf ]]; then
  msg="This session is now on Hyprland's fallback config (stock binds). Log out and back in now to start fledge's Lua config."
  printf '\n%s\n\n' "$msg"
  notify-send -u critical -a fledge "Log out and back in now" "$msg" >/dev/null 2>&1 || true
fi

echo "Bootstrap complete."
