#!/usr/bin/env bash
# Unit tests for lib/detect.sh pure functions, run against fixtures. No VM.
#   bash cachyos/install/test-detect.sh
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/detect.sh
source "$DIR/lib/detect.sh"
# shellcheck source=SCRIPTDIR/test/lib.sh
source "$DIR/test/lib.sh"
FIX="$DIR/test/fixtures"

check "ucode amd"   "amd-ucode"   "$(detect_ucode "$FIX/cpuinfo-amd")"
check "ucode intel" "intel-ucode" "$(detect_ucode "$FIX/cpuinfo-intel")"

desktop_gpu="$(detect_gpu_pkgs "$(cat "$FIX/lspci-desktop")")"
contains "gpu pkgs desktop has nvidia" "linux-cachyos-nvidia" "$desktop_gpu"
contains "gpu pkgs desktop has radeon" "vulkan-radeon"        "$desktop_gpu"
check "gpu pkgs laptop intel" "vulkan-intel" "$(detect_gpu_pkgs "$(cat "$FIX/lspci-laptop-intel")")"
check "gpu pkgs vm empty"     ""             "$(detect_gpu_pkgs "$(cat "$FIX/lspci-vm")")"

check "gpu cmdline desktop" "nvidia_drm.modeset=1" "$(detect_gpu_cmdline "$(cat "$FIX/lspci-desktop")")"
check "gpu cmdline vm empty" ""                    "$(detect_gpu_cmdline "$(cat "$FIX/lspci-vm")")"
check "gpu modules desktop" "nvidia nvidia_modeset nvidia_uvm nvidia_drm" \
  "$(detect_gpu_modules "$(cat "$FIX/lspci-desktop")")"
check "gpu modules vm empty" "" "$(detect_gpu_modules "$(cat "$FIX/lspci-vm")")"

check "part_suffix nvme"   "p" "$(part_suffix nvme1n1)"
check "part_suffix mmcblk" "p" "$(part_suffix mmcblk0)"
check "part_suffix sda"    ""  "$(part_suffix sda)"
check "part_suffix vda"    ""  "$(part_suffix vda)"

# 64000000 kB ~= 61.04 GiB RAM
check "zram_size capped at 8192" "8192" "$(zram_size 64000000)"
# 8000000 kB ~= 7.63 GiB -> 7812 MiB / 2 = 3906
check "zram_size small box"      "3906" "$(zram_size 8000000)"

# 64000000 kB -> ceil 62 GiB -> 62*1024 + 2048
check "hibernate_swap 61GiB box"  "65536" "$(hibernate_swap_size 64000000)"
# 16777216 kB = exactly 16 GiB -> 16*1024 + 2048
check "hibernate_swap 16GiB box"  "18432" "$(hibernate_swap_size 16777216)"

present=$'aaaa-1111\nbbbb-2222'
A="UUID=aaaa-1111 /a ext4 defaults,nofail 0 0"
B="UUID=bbbb-2222 /b ext4 defaults,nofail 0 0"
C="UUID=cccc-3333 /c ext4 defaults,nofail 0 0"
check "fstab filter keeps present"       "$A" "$(filter_fstab_entries "$present" "$A")"
check "fstab filter drops absent"        ""   "$(filter_fstab_entries "$present" "$C")"
check "fstab filter mixed keeps order"   "$A"$'\n'"$B" "$(filter_fstab_entries "$present" "$A" "$C" "$B")"
check "fstab filter no entries"          ""   "$(filter_fstab_entries "$present")"
check "fstab filter non-UUID passes"     "/dev/sdz1 /z ext4 defaults 0 0" \
  "$(filter_fstab_entries "" "/dev/sdz1 /z ext4 defaults 0 0")"
check "fstab filter exact match only"    ""   "$(filter_fstab_entries "aaaa-11112" "$A")"

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/dev" "$T/by-id"
: > "$T/dev/nvme0n1"; : > "$T/dev/nvme0n1p1"; : > "$T/dev/vda"
ln -s ../dev/nvme0n1   "$T/by-id/wwn-0x5000000000000001"
ln -s ../dev/nvme0n1   "$T/by-id/nvme-eui.0025385a01234567"
ln -s ../dev/nvme0n1p1 "$T/by-id/nvme-Samsung_SSD_990_PRO_2TB_S123-part1"
ln -s ../dev/nvme0n1   "$T/by-id/nvme-Samsung_SSD_990_PRO_2TB_S123"
check "disk_by_id picks the model link" "$T/by-id/nvme-Samsung_SSD_990_PRO_2TB_S123" \
  "$(disk_by_id "$T/dev/nvme0n1" "$T/by-id")"
check "disk_by_id falls back to kname"  "$T/dev/vda" "$(disk_by_id "$T/dev/vda" "$T/by-id")"

# list_disks under the configurator's strict mode, with the live medium on a
# device lsblk can't resolve (Ventoy): the lookup failing must not empty the list.
list_disks_strict() { # <live source findmnt reports>
  LIVESRC="$1" DETECT="$DIR/lib/detect.sh" bash -c '
    set -euo pipefail
    source "$DETECT"
    findmnt() { [[ -n "$LIVESRC" ]] && echo "$LIVESRC" || return 1; }
    lsblk() {
      case "$*" in
        *PKNAME*) [[ "${*: -1}" == /dev/sdc1 ]] && { echo sdc; return 0; }
                  echo "lsblk: ${*: -1}: not a block device" >&2; return 32 ;;
        *) printf "%s\n" "/dev/nvme0n1 476.9G SAMSUNG MZVL2512 nvme disk" \
                         "/dev/sdc 29.4G Ventoy usb disk" "/dev/zram0 4G  disk" ;;
      esac
    }
    list_disks'
}
check "list_disks: unresolvable live device keeps the disks" \
  $'/dev/nvme0n1 476.9G SAMSUNG MZVL2512 nvme\n/dev/sdc 29.4G Ventoy usb' "$(list_disks_strict /dev/mapper/ventoy)"
check "list_disks: no live mount keeps the disks" \
  $'/dev/nvme0n1 476.9G SAMSUNG MZVL2512 nvme\n/dev/sdc 29.4G Ventoy usb' "$(list_disks_strict '')"
check "list_disks: live disk is hidden" \
  "/dev/nvme0n1 476.9G SAMSUNG MZVL2512 nvme" "$(list_disks_strict /dev/sdc1)"

exit $fail
