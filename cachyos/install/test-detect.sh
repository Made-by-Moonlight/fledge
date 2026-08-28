#!/usr/bin/env bash
# Unit tests for lib/detect.sh pure functions, run against fixtures. No VM.
#   bash cachyos/install/test-detect.sh
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/detect.sh
source "$DIR/lib/detect.sh"
FIX="$DIR/test/fixtures"

fail=0
check() { # <description> <expected> <actual>
  if [[ "$2" == "$3" ]]; then
    printf 'PASS  %s\n' "$1"
  else
    printf 'FAIL  %s\n        expected: [%s]\n        actual:   [%s]\n' "$1" "$2" "$3"
    fail=1
  fi
}
contains() { # <description> <needle> <haystack>
  if [[ "$3" == *"$2"* ]]; then
    printf 'PASS  %s\n' "$1"
  else
    printf 'FAIL  %s\n        [%s] not in [%s]\n' "$1" "$2" "$3"
    fail=1
  fi
}

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

exit $fail
