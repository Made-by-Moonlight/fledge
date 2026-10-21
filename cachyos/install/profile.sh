# shellcheck shell=bash
# shellcheck disable=SC2034  # every variable here is consumed by the scripts that source this file
# Fixed, hardware-INDEPENDENT install choices. Sourced by install-cachyos.sh.
# Everything hardware-specific (microcode, GPU driver, kernel params for the
# GPU, target disk, partition-name suffix, swap sizing) is DETECTED at install
# time by lib/detect.sh and must never be added here.
#
# Reviewed by eye before every run. Two vars are per-machine:
#   HOSTNAME     - leave "" to be prompted
#   DATA_DISKS   - set to () on machines with no extra data disks

TIMEZONE="UTC"
LOCALE="en_US.UTF-8"
USERNAME="slievr"          # default; the ISO configurator asks and overrides it
HOSTNAME=""                       # empty -> prompt at install time

ESP_SIZE="2GiB"
LUKS_NAME="root"                  # cryptsetup mapper name -> /dev/mapper/root

# subvol:mountpoint. @swap is mounted nodatacow + no compression (btrfs swapfile
# requirement); the rest get $BTRFS_OPTS.
BTRFS_SUBVOLS=( "@:/" "@home:/home" "@log:/var/log" "@pkg:/var/cache/pacman/pkg" "@swap:/swap" )
BTRFS_OPTS="compress=zstd:3,ssd,space_cache=v2,relatime"
CREATE_SNAPSHOTS_SUBVOL=true      # create @/.snapshots now so snapper can be
                                  # added later with no reformat (v1 does NOT
                                  # configure snapper / limine-snapper-sync)

KERNEL="linux-cachyos"
MIN_KERNEL="7.2"                  # refuse to install an older $KERNEL (hardware needs 7.2+)

# "hibernate" = zram-generator + an encrypted btrfs swapfile (+ resume= cmdline).
# "zram"      = zram-generator only, no hibernate.
SWAP="hibernate"
HIBERNATE_SWAP_SIZE=""            # empty -> auto: round(RAM up to GiB) + 2 GiB

# plymouth.ignore-serial-consoles: when the firmware console includes a serial
# port (VMs, some servers), systemd's UKI stub appends console=uart,... and
# Plymouth then forces its plain text "details" screen at the LUKS prompt.
EXTRA_CMDLINE="quiet splash plymouth.ignore-serial-consoles zswap.enabled=0"

# Per-machine, optional: data filesystems the installer pre-selects for a
# permanent mount, "uuid:mountpoint" (~ = the new user's home). Entries whose
# UUID isn't on the machine are ignored, so one list serves every machine.
# The installer writes them to fstab by UUID with nofail, mounted at boot. A drive
# listed here defaults to Mount, never to Wipe: erasing is always chosen by hand.
# Folders are named by kind (nvme/ssd/hdd/usb + n); nvme1 is left free for the
# old system drive, wiped into storage at install time.
DATA_DISKS=(
  "77d7988e-2e64-4654-bda2-481d321eecdd:~/nvme2"   # Sabrent Rocket 4.0 1TB
  "5e62f799-8df9-4ee3-b4d7-4da62c8c65ff:~/ssd1"    # Crucial MX500 2TB
  "ceb2ac52-2fea-40e5-b2b6-e6f6fe1c8bc7:~/ssd2"    # PNY CS900 480GB
  # The VM's test data disk (cachyos/vm, formatted with this UUID by the
  # end-to-end test); absent on every real machine.
  "00000000-0000-4000-8000-00000000da7a:~/testdata"
)
