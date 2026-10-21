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
check "data defaults keep present, in order" $'aaaa-1111\t~/s1\nbbbb-2222\t/data' \
  "$(data_disk_defaults "$present" "aaaa-1111:~/s1" "cccc-3333:~/s3" "bbbb-2222:/data")"
check "data defaults none present" "" "$(data_disk_defaults "" "aaaa-1111:~/s1")"
check "data defaults exact uuid only" "" "$(data_disk_defaults "aaaa-11112" "aaaa-1111:~/s1")"

O="defaults,nofail,x-systemd.automount,x-systemd.device-timeout=10"
check "fstab ext4"  "UUID=u1 /home/e/s1 ext4 $O 0 0"                         "$(fstab_line u1 ext4 /home/e/s1 1000 1000)"
check "fstab ntfs"  "UUID=u2 /data ntfs3 $O,uid=1000,gid=1000 0 0"          "$(fstab_line u2 ntfs /data 1000 1000)"
check "fstab vfat"  "UUID=u3 /data vfat $O,uid=1000,gid=1000,umask=022 0 0" "$(fstab_line u3 vfat /data 1000 1000)"
check "fstab exfat" "UUID=u4 /data exfat $O,uid=1000,gid=1000,umask=022 0 0" "$(fstab_line u4 exfat /data 1000 1000)"

KM="$FIX/kbd-model-map"
check "keymap us"            us                   "$(console_keymap us '' "$KM")"
check "keymap gb"            uk                   "$(console_keymap gb '' "$KM")"
check "keymap variant"       de-latin1-nodeadkeys "$(console_keymap de nodeadkeys "$KM")"
check "keymap us dvorak"     dvorak               "$(console_keymap us dvorak "$KM")"
check "keymap unknown variant falls back to layout" uk "$(console_keymap gb extd "$KM")"
check "keymap first of several layouts" de        "$(console_keymap de,us '' "$KM")"
check "keymap unknown layout" us                  "$(console_keymap zz '' "$KM")"
check "keymap missing map file" us                "$(console_keymap gb '' /nonexistent)"

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

EFI=$'BootCurrent: 0001\nBootOrder: 0003,0001,0002,0000\nBoot0000* UiApp\tFvVol(7cb8bdc9-f8eb-4f34-aaea-3ee4af6516a1)/FvFile(462caa21-7614-4503-836e-8ab6f4662331)\nBoot0001* Limine\tHD(1,GPT,6C2D0E1A-0000-4000-8000-000000000001,0x800,0x400000)/File(\\EFI\\limine\\BOOTX64.EFI)\nBoot0002* Windows Boot Manager\tHD(1,GPT,aaaa0000-0000-4000-8000-0000000000bb,0x800,0x32000)/File(\\EFI\\Microsoft\\Boot\\bootmgfw.efi)\nBoot0003* CachyOS\tHD(1,GPT,6c2d0e1a-0000-4000-8000-000000000009,0x800,0x400000)/File(\\EFI\\limine\\BOOTX64.EFI)'
check "boot: erased drives' entries" $'0001\n0003' "$(stale_boot_entries "$EFI" 6c2d0e1a-0000-4000-8000-000000000001 6C2D0E1A-0000-4000-8000-000000000009)"
check "boot: kept drive and firmware untouched" "" "$(stale_boot_entries "$EFI" 00000000-0000-4000-8000-000000000000)"
check "boot: entry for the new ESP" "0002" "$(boot_entry_for "$EFI" AAAA0000-0000-4000-8000-0000000000BB)"
check "boot: order first"   "0004,0003,0001" "$(order_first 0003,0004,0001 0004)"
check "boot: order new"     "0004,0003"      "$(order_first 0003 0004)"
check "busy: lvm"   lvm  "$(busy_reason $'part \nlvm /')"
check "busy: swap"  swap "$(busy_reason $'part [SWAP]')"
check "busy: mount" mounted "$(busy_reason $'part /run/media/x')"
check "busy: free"  ""   "$(busy_reason $'part \npart ')"

exit $fail
