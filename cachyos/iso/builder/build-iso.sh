#!/usr/bin/env bash
# Runs INSIDE the archlinux container started by bin/fledge-iso-make.
#   /src      read-only clone of the repo at HEAD (origin = DOTFILES_REPO)
#   /release  output dir (the host's release/)
#   HOST_UID / HOST_GID  owner for the outputs
set -euo pipefail

ISO=/src/cachyos/iso
PROFILE=/tmp/profile
OUT=/tmp/out
# CachyOS packaging key (from their "add the repo manually" instructions).
# Verified 2026-10-01: pacman-key --recv-keys fetched it in a real build.
# Re-check against https://wiki.cachyos.org if the fetch ever fails.
CACHYOS_KEY=F3B607488DB35A47

die() { echo "build-iso: $*" >&2; exit 1; }
step() { printf '\n>>> %s\n' "$*"; }

step "container packages"
pacman-key --init
# Full upgrade, not -Sy: a cached :latest image can be months old.
pacman --noconfirm -Syu archiso git python imagemagick librsvg
# /src and the baked repo are owned by the host uid, git runs as root here.
git config --global --add safe.directory '*'

step "CachyOS keyring + mirrorlist"
pacman-key --recv-keys "$CACHYOS_KEY" --keyserver keyserver.ubuntu.com \
  || die "couldn't fetch the CachyOS signing key $CACHYOS_KEY"
pacman-key --lsign-key "$CACHYOS_KEY"
# shellcheck disable=SC2016  # $arch/$repo are pacman variables
printf 'Server = https://mirror.cachyos.org/repo/$arch/$repo\n' > /etc/pacman.d/cachyos-mirrorlist
cat "$ISO/configs/pacman-cachyos.conf" >> /etc/pacman.conf
pacman --noconfirm -Sy --overwrite /etc/pacman.d/cachyos-mirrorlist cachyos-keyring cachyos-mirrorlist \
  || die "couldn't install cachyos-keyring / cachyos-mirrorlist"
pacman-key --populate cachyos

step "live kernel >= MIN_KERNEL"
# shellcheck source=/dev/null
MIN_KERNEL="$(. /src/cachyos/install/profile.sh; echo "$MIN_KERNEL")"
live_ver="$(pacman -Si linux | awk '/^Version/ {print $3; exit}')"
(( $(vercmp "$live_ver" "$MIN_KERNEL") >= 0 )) || die "live kernel linux $live_ver is older than $MIN_KERNEL"
echo "live kernel: linux $live_ver (minimum $MIN_KERNEL)"

step "profile: releng + our overlay"
cp -r /usr/share/archiso/configs/releng "$PROFILE"
rm -f "$PROFILE/airootfs/etc/motd"
rm -rf "$PROFILE/airootfs/etc/systemd/system/multi-user.target.wants/reflector.service" \
       "$PROFILE/airootfs/etc/systemd/system/reflector.service.d" \
       "$PROFILE/airootfs/etc/xdg/reflector"
cp -rT "$ISO/configs/airootfs" "$PROFILE/airootfs"

# NetworkManager instead of iwd + systemd-networkd: the installer's Wi-Fi
# picker talks to NM (Quickshell.Networking), and the profiles it saves copy
# straight into the installed system.
find "$PROFILE/airootfs/etc/systemd/system" \( -name 'iwd.service' -o -name 'systemd-networkd*' \
  -o -name 'dbus-org.freedesktop.network1.service' \) -prune -print -exec rm -rf {} +
mkdir -p "$PROFILE/airootfs/etc/systemd/system/multi-user.target.wants"
ln -sf /usr/lib/systemd/system/NetworkManager.service \
  "$PROFILE/airootfs/etc/systemd/system/multi-user.target.wants/NetworkManager.service"

# The installer UI, symlinks into dot-config/quickshell/fledge resolved (-L).
mkdir -p "$PROFILE/airootfs/etc/xdg/quickshell"
cp -rL "$ISO/installer" "$PROFILE/airootfs/etc/xdg/quickshell/fledge-installer"

# packages: releng's + ours, de-duplicated
grep -v '^#' "$ISO/configs/packages.extra" | sed '/^$/d' >> "$PROFILE/packages.x86_64"
sort -u -o "$PROFILE/packages.x86_64" "$PROFILE/packages.x86_64"

# pacman.conf: [cachyos] above [core], used for the build AND shipped in the live env
awk -v snip="$(cat "$ISO/configs/pacman-cachyos.conf")" \
  '/^\[core\]/ && !done { print snip; print ""; done = 1 } { print }' \
  "$PROFILE/pacman.conf" > "$PROFILE/pacman.conf.new"
mv "$PROFILE/pacman.conf.new" "$PROFILE/pacman.conf"
install -Dm644 "$PROFILE/pacman.conf" "$PROFILE/airootfs/etc/pacman.conf"

# profiledef: our name, label, publisher; permissions for our scripts
# shellcheck disable=SC2016  # $(date ...) is evaluated when mkarchiso sources profiledef.sh
sed -i \
  -e 's/^iso_name=.*/iso_name="fledge"/' \
  -e 's/^iso_label=.*/iso_label="FLEDGE_$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y%m)"/' \
  -e 's/^iso_publisher=.*/iso_publisher="made by moonlight"/' \
  -e 's/^iso_application=.*/iso_application="fledge installer"/' \
  "$PROFILE/profiledef.sh"
cat >> "$PROFILE/profiledef.sh" <<'EOF'
file_permissions+=(
  ["/usr/local/bin/fledge-install"]="0:0:755"
  ["/usr/local/bin/fledge-probe"]="0:0:755"
  ["/usr/local/bin/fledge-cleanup"]="0:0:755"
  ["/etc/sudoers.d/fledge-installer"]="0:0:440"
  ["/home/fledge"]="1000:1000:750"
  ["/home/fledge/.bash_profile"]="1000:1000:644"
)
EOF

step "boot menu"
# Verified 2026-10-01: releng's title string and UEFI entry names matched in a
# real build (the greps below die if they stop matching). Re-check with
#   grep -rn title "$PROFILE"/efiboot "$PROFILE"/grub "$PROFILE"/syslinux
# and adjust the patterns if releng renamed them.
grep -rlZ 'Arch Linux install medium' "$PROFILE"/efiboot "$PROFILE"/grub "$PROFILE"/syslinux 2>/dev/null \
  | xargs -0r sed -i 's/Arch Linux install medium/fledge installer/g'
for f in "$PROFILE"/efiboot/loader/entries/*linux*.conf; do
  [[ -e "$f" && "$f" != *speech* ]] || continue
  sed -e 's/^title .*/& (safe graphics)/' -e 's/^options .*/& nomodeset/' "$f" > "${f%.conf}-nomodeset.conf"
  break
done
grep -rq 'fledge installer' "$PROFILE"/efiboot || die "boot entries were not retitled"
compgen -G "$PROFILE/efiboot/loader/entries/*nomodeset.conf" >/dev/null || die "no safe-graphics boot entry"

step "bake repo + branding"
mkdir -p "$PROFILE/airootfs/usr/share"
cp -a /src "$PROFILE/airootfs/usr/share/fledge"
# mkarchiso copies airootfs with --no-preserve=mode: only file_permissions keep
# modes, so list every git-executable file explicitly.
{
  echo 'file_permissions+=('
  git -C /src ls-files -z -s | while IFS= read -r -d '' rec; do
    [[ "${rec%% *}" == 100755 ]] || continue
    printf '  [%q]="0:0:755"\n' "/usr/share/fledge/${rec#*$'\t'}"
  done
  echo ')'
} >> "$PROFILE/profiledef.sh"

step "sanity checks"
for f in usr/share/fledge/cachyos/install/install-cachyos.sh usr/share/fledge/.git/HEAD \
         usr/share/fledge/dot-local/share/fledge/assets/owl.png \
         usr/local/bin/fledge-install usr/local/bin/fledge-probe usr/local/bin/fledge-cleanup \
         etc/sudoers.d/fledge-installer etc/sysusers.d/fledge-installer.conf etc/fledge-installer/hyprland.lua home/fledge/.bash_profile \
         etc/systemd/system/getty@tty1.service.d/autologin.conf etc/polkit-1/rules.d/50-fledge-installer.rules \
         etc/xdg/quickshell/fledge-installer/shell.qml etc/xdg/quickshell/fledge-installer/theme/Theme.qml \
         etc/xdg/quickshell/fledge-installer/components/Button.qml etc/xdg/quickshell/fledge-installer/services/Net.qml \
         etc/xdg/quickshell/fledge-installer/services/Hypr.qml \
         etc/xdg/quickshell/fledge-installer/quicksettings/pickers/WifiPicker.qml etc/pacman.conf; do
  [[ -s "$PROFILE/airootfs/$f" ]] || die "missing or empty airootfs/$f"
done
if find "$PROFILE/airootfs/etc/xdg/quickshell/fledge-installer" -type l | grep -q .; then
  die "installer config still has symlinks (cp -rL should have resolved them)"
fi
grep -q '^u fledge 1000 ' "$PROFILE/airootfs/etc/sysusers.d/fledge-installer.conf" || die "no fledge user"
[[ -L "$PROFILE/airootfs/etc/systemd/system/multi-user.target.wants/NetworkManager.service" ]] || die "NetworkManager not enabled"
grep -q '^\[cachyos\]' "$PROFILE/airootfs/etc/pacman.conf" || die "live pacman.conf lacks [cachyos]"
[[ "$(git -C "$PROFILE/airootfs/usr/share/fledge" remote get-url origin)" == https://* ]] \
  || die "baked repo's origin is not the GitHub URL"

step "mkarchiso"
mkarchiso -v -w /tmp/work -o "$OUT" "$PROFILE"
du -h "$OUT"/*.iso   # the 2 GiB limit should stay visible

step "check modes inside the image"
command -v unsquashfs >/dev/null || pacman --noconfirm -S squashfs-tools
sfs="$(find /tmp/work -name airootfs.sfs | head -n1)"
[[ -n "$sfs" ]] || die "no airootfs.sfs found in the work dir"
for f in cachyos/install/install-cachyos.sh cachyos/bootstrap.sh; do
  line="$(unsquashfs -ll "$sfs" "usr/share/fledge/$f" | grep "fledge/$f\$" || true)"
  [[ "$line" == -rwxr-xr-x* ]] || die "$f is not mode 755 in the image: ${line:-not found}"
done
echo "modes ok"
iso="$(ls "$OUT"/*.iso)"
cp "$iso" /release/
( cd /release && sha256sum "${iso##*/}" > "${iso##*/}.sha256" )
chown "${HOST_UID:-0}:${HOST_GID:-0}" "/release/${iso##*/}" "/release/${iso##*/}.sha256"
step "done: release/${iso##*/}"
