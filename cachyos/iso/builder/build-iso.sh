#!/usr/bin/env bash
# Runs INSIDE the archlinux container started by bin/slievr-iso-make.
#   /src      read-only clone of the repo at HEAD (origin = DOTFILES_REPO)
#   /release  output dir (the host's release/)
#   HOST_UID / HOST_GID  owner for the outputs
set -euo pipefail

ISO=/src/cachyos/iso
PROFILE=/tmp/profile
OUT=/tmp/out
# UNVERIFIED: CachyOS packaging key, from CachyOS's "add the repo manually"
# instructions. Confirm against https://wiki.cachyos.org before relying on it.
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
  -e 's/^iso_name=.*/iso_name="made-by-moonlight"/' \
  -e 's/^iso_label=.*/iso_label="MBM_$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y%m)"/' \
  -e 's/^iso_publisher=.*/iso_publisher="made by moonlight"/' \
  -e 's/^iso_application=.*/iso_application="made by moonlight installer"/' \
  "$PROFILE/profiledef.sh"
cat >> "$PROFILE/profiledef.sh" <<'EOF'
file_permissions+=(
  ["/root/.automated_script.sh"]="0:0:755"
  ["/usr/local/bin/mbm-configurator"]="0:0:755"
  ["/usr/local/bin/mbm-install"]="0:0:755"
)
EOF

step "boot menu"
# UNVERIFIED: releng's title string and UEFI entry file names. Check with
#   grep -rn title "$PROFILE"/efiboot "$PROFILE"/grub "$PROFILE"/syslinux
# and adjust the patterns if releng renamed them.
grep -rlZ 'Arch Linux install medium' "$PROFILE"/efiboot "$PROFILE"/grub "$PROFILE"/syslinux 2>/dev/null \
  | xargs -0r sed -i 's/Arch Linux install medium/made by moonlight installer/g'
for f in "$PROFILE"/efiboot/loader/entries/*linux*.conf; do
  [[ -e "$f" && "$f" != *speech* ]] || continue
  sed -e 's/^title .*/& (safe graphics)/' -e 's/^options .*/& nomodeset/' "$f" > "${f%.conf}-nomodeset.conf"
  break
done
grep -rq 'made by moonlight installer' "$PROFILE"/efiboot || die "boot entries were not retitled"
compgen -G "$PROFILE/efiboot/loader/entries/*nomodeset.conf" >/dev/null || die "no safe-graphics boot entry"

step "bake repo + branding"
cp -a /src "$PROFILE/airootfs/usr/share/slievr-cachy"
mkdir -p "$PROFILE/airootfs/usr/share/mbm"
python3 /src/cachyos/branding/render-console.py /src/cachyos/branding/owl.svg --cols 48 --ansi \
  > "$PROFILE/airootfs/usr/share/mbm/owl.ansi"

step "sanity checks"
for f in usr/share/slievr-cachy/cachyos/install/install-cachyos.sh usr/share/slievr-cachy/.git/HEAD \
         usr/share/mbm/owl.ansi usr/local/bin/mbm-configurator usr/local/bin/mbm-install \
         root/.automated_script.sh etc/pacman.conf; do
  [[ -s "$PROFILE/airootfs/$f" ]] || die "missing or empty airootfs/$f"
done
grep -q '^\[cachyos\]' "$PROFILE/airootfs/etc/pacman.conf" || die "live pacman.conf lacks [cachyos]"
[[ "$(git -C "$PROFILE/airootfs/usr/share/slievr-cachy" remote get-url origin)" == https://* ]] \
  || die "baked repo's origin is not the GitHub URL"

step "mkarchiso"
mkarchiso -v -w /tmp/work -o "$OUT" "$PROFILE"
iso="$(ls "$OUT"/*.iso)"
cp "$iso" /release/
( cd /release && sha256sum "${iso##*/}" > "${iso##*/}.sha256" )
chown "${HOST_UID:-0}:${HOST_GID:-0}" "/release/${iso##*/}" "/release/${iso##*/}.sha256"
step "done: release/${iso##*/}"
