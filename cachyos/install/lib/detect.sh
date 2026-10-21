# shellcheck shell=bash
# Hardware detection. Pure functions where possible: they take their input
# source as an argument so test-detect.sh can feed fixtures. The live-only
# helpers (list_disks) are exercised in the VM and with stubs.

# detect_ucode <cpuinfo_path>  ->  amd-ucode | intel-ucode
detect_ucode() {
  local f="${1:-/proc/cpuinfo}"
  if grep -qm1 'AuthenticAMD' "$f"; then
    echo "amd-ucode"
  elif grep -qm1 'GenuineIntel' "$f"; then
    echo "intel-ucode"
  else
    echo "amd-ucode"  # sane default; warn upstream
    return 1
  fi
}

# _gpu_vendors <lspci_text>  ->  newline list of nvidia|amd|intel seen on a
# display-class device (VGA / 3D / Display controller)
_gpu_vendors() {
  local line
  while IFS= read -r line; do
    case "$line" in
      *"VGA compatible controller"*|*"3D controller"*|*"Display controller"*) ;;
      *) continue ;;
    esac
    case "$line" in
      *NVIDIA*|*"nVidia"*)                          echo nvidia ;;
    esac
    case "$line" in
      *"Advanced Micro Devices"*|*"[AMD/ATI]"*|*" ATI "*) echo amd ;;
    esac
    case "$line" in
      *"Intel Corporation"*)                        echo intel ;;
    esac
  done <<<"$1"
}

# detect_gpu_pkgs <lspci_text>  ->  space-separated pacman package list
detect_gpu_pkgs() {
  local v pkgs=() seen
  seen="$(_gpu_vendors "$1" | sort -u)"
  for v in $seen; do
    case "$v" in
      nvidia) pkgs+=(linux-cachyos-nvidia nvidia-utils lib32-nvidia-utils) ;;
      amd)    pkgs+=(vulkan-radeon lib32-vulkan-radeon) ;;
      intel)  pkgs+=(vulkan-intel) ;;
    esac
  done
  echo "${pkgs[*]-}"
}

# detect_gpu_cmdline <lspci_text>  ->  nvidia_drm.modeset=1 | (empty)
detect_gpu_cmdline() {
  if _gpu_vendors "$1" | grep -qx nvidia; then
    echo "nvidia_drm.modeset=1"
  fi
}

# detect_gpu_modules <lspci_text>  ->  mkinitcpio MODULES for the GPU | (empty)
detect_gpu_modules() {
  if _gpu_vendors "$1" | grep -qx nvidia; then
    echo "nvidia nvidia_modeset nvidia_uvm nvidia_drm"
  fi
}

# part_suffix <disk_basename>  ->  p (nvme/mmcblk/loop) | (empty)
part_suffix() {
  case "$1" in
    nvme*|mmcblk*|loop*) echo p ;;
    *) echo "" ;;
  esac
}

# zram_size <memtotal_kB>  ->  MiB, min(RAM/2, 8192)
zram_size() {
  local mib=$(( $1 / 1024 / 2 ))
  (( mib > 8192 )) && mib=8192
  echo "$mib"
}

# hibernate_swap_size <memtotal_kB>  ->  MiB, ceil(RAM to GiB)*1024 + 2048
hibernate_swap_size() {
  local gib=$(( ($1 + 1048576 - 1) / 1048576 ))
  echo "$(( gib * 1024 + 2048 ))"
}

# data_disk_defaults <present_uuids> <uuid:path>...  ->  "uuid<TAB>path" for
# the profile.sh DATA_DISKS entries whose UUID is on this machine
# (present_uuids is newline-separated, as `blkid -s UUID -o value` prints).
# Paths stay as written (may start with ~); callers expand them.
data_disk_defaults() {
  local present="$1" e; shift
  for e in "$@"; do
    grep -qxF -- "${e%%:*}" <<<"$present" || continue
    printf '%s\t%s\n' "${e%%:*}" "${e#*:}"
  done
}

# fstab_line <uuid> <fstype> <path> <uid> <gid>  ->  a permanent data mount:
# by UUID, automounted on first access, and nofail with a short timeout so a
# missing disk never holds up boot. Filesystems without Unix owners (ntfs,
# vfat, exfat) are mounted as the user so they're writable.
fstab_line() {
  local uuid="$1" fs="$2" path="$3" uid="$4" gid="$5"
  local opts="defaults,nofail,x-systemd.automount,x-systemd.device-timeout=10"
  case "$fs" in
    ntfs|ntfs3) fs=ntfs3; opts+=",uid=$uid,gid=$gid" ;;
    vfat|exfat) opts+=",uid=$uid,gid=$gid,umask=022" ;;
  esac
  printf 'UUID=%s %s %s %s 0 0\n' "$uuid" "$path" "$fs" "$opts"
}

# console_keymap <xkb layout> <xkb variant> [kbd-model-map]  ->  the console
# keymap localectl would pick (first layout only): exact variant match, else
# the layout's plain entry, else us. The LUKS prompt uses this keymap.
console_keymap() {
  local layout="${1%%,*}" variant="${2%%,*}" map="${3:-/usr/share/systemd/kbd-model-map}" km=""
  km="$(awk -v l="$layout" -v v="${variant:--}" '!/^#/ && $2 == l && $4 == v {print $1; exit}' "$map" 2>/dev/null)" || km=""
  if [[ -z "$km" && -n "$variant" ]]; then
    km="$(awk -v l="$layout" '!/^#/ && $2 == l && $4 == "-" {print $1; exit}' "$map" 2>/dev/null)" || km=""
  fi
  echo "${km:-us}"
}

# live_disk  ->  /dev/<disk> backing the live medium, or nothing when it can't
# be identified (e.g. Ventoy's device-mapper node, which lsblk can't resolve).
live_disk() {
  local src pk
  src="$(findmnt -no SOURCE /run/archiso/bootmnt 2>/dev/null \
    || findmnt -no SOURCE /run/archiso/cowspace 2>/dev/null || true)"
  [[ -n "$src" ]] || return 0
  pk="$({ lsblk -no PKNAME "$src" 2>/dev/null || true; } | head -n1)"
  if [[ -n "$pk" ]]; then echo "/dev/$pk"; fi
}

# list_disks  ->  lines: NAME<TAB>SIZE<TAB>MODEL<TAB>TRAN
# Whole disks only, excluding the live-media disk (when it can be identified)
# and zram/ramdisks. Tested with stubbed findmnt/lsblk in test-detect.sh.
list_disks() {
  local live; live="$(live_disk)"
  lsblk -dpno NAME,SIZE,MODEL,TRAN,TYPE | awk -v live="$live" '
    $NF == "disk" {
      name=$1; $NF=""; sub(/[ \t]+$/, "")
      if (name == live) next
      # zram / ramdisks report TYPE=disk but are not install targets
      if (name ~ /\/(zram|ram)[0-9]+$/) next
      # rebuild: NAME SIZE MODEL... TRAN
      printf "%s\n", $0
    }'
}

# disk_by_id <kname> [byid_dir]  ->  stable by-id path for a whole disk, or
# kname when there is none (e.g. virtio). Skips -partN, wwn-* and eui links,
# which are either partitions or opaque.
disk_by_id() {
  local kname="$1" dir="${2:-/dev/disk/by-id}" link want
  want="$(realpath "$kname")"
  for link in "$dir"/*; do
    [[ -e "$link" ]] || continue
    [[ "$link" == *-part* ]] && continue
    case "${link##*/}" in wwn-*|*eui.*) continue ;; esac
    if [[ "$(realpath "$link")" == "$want" ]]; then
      echo "$link"; return 0
    fi
  done
  echo "$kname"
}

# busy_reason <"TYPE MOUNTPOINT" lines of a disk's descendants>  ->  lvm|raid|
# crypt|swap|mounted, or nothing when the disk is free. Mirrors `def busy` in
# iso/lib/probe.jq (same order), so the installer refuses what the UI hid.
busy_reason() {
  local type mp swap=0 mounted=0
  while read -r type mp; do
    case "$type" in
      lvm)     echo lvm;   return 0 ;;
      raid*)   echo raid;  return 0 ;;
      crypt)   echo crypt; return 0 ;;
    esac
    if [[ "$mp" == "[SWAP]" ]]; then swap=1
    elif [[ -n "$mp" ]]; then mounted=1; fi
  done <<<"$1"
  if (( swap )); then echo swap; elif (( mounted )); then echo mounted; fi
  return 0
}

# stale_boot_entries <efibootmgr -v text> <partuuid>...  ->  the 4-hex number
# of every entry whose HD(n,GPT,<guid>,...) path names one of the GUIDs, one
# per line. GUIDs compare case-insensitively (firmware upper-cases them,
# blkid lower-cases). Entries without a disk path never match.
stale_boot_entries() {
  local text="$1"; shift
  awk -v guids="$*" '
    BEGIN { n = split(tolower(guids), g, " "); for (i = 1; i <= n; i++) want[g[i]] = 1 }
    /^Boot[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]/ {
      if (match(tolower($0), /hd\([0-9]+,gpt,[0-9a-f-]+,/)) {
        s = substr(tolower($0), RSTART, RLENGTH); split(s, f, ",")
        if (f[3] in want) print substr($1, 5, 4)
      }
    }' <<<"$text"
}

# boot_entry_for <efibootmgr -v text> <partuuid>  ->  the first matching entry number.
boot_entry_for() {
  stale_boot_entries "$1" "$2" | head -n1
}

# order_first <BootOrder csv> <num>  ->  csv with num first, without duplicate.
order_first() {
  local order="$1" num="$2" out="$2" e
  local IFS=,
  for e in $order; do [[ "$e" == "$num" || -z "$e" ]] || out+=",$e"; done
  echo "$out"
}
