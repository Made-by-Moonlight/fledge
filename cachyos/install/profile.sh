# shellcheck shell=bash
# Fixed, hardware-INDEPENDENT install choices. Sourced by install-cachyos.sh.
# Everything hardware-specific (microcode, GPU driver, kernel params for the
# GPU, target disk, partition-name suffix, swap sizing) is DETECTED at install
# time by lib/detect.sh and must never be added here.
#
# Reviewed by eye before every run. Two vars are per-machine:
#   HOSTNAME              - leave "" to be prompted
#   EXTRA_FSTAB_ENTRIES   - set to () on machines with no extra data disks

TIMEZONE="UTC"
LOCALE="en_US.UTF-8"
KEYMAP="us"
USERNAME="slievr"
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

# Per-machine, optional. Full fstab lines, appended verbatim after genfstab.
# Empty on the laptop. On the desktop: the 4 data disks, copied from the
# current host /etc/fstab (UUIDs are stable across the reinstall).
EXTRA_FSTAB_ENTRIES=(
  "UUID=ceb2ac52-2fea-40e5-b2b6-e6f6fe1c8bc7 /home/slievr/storage1 ext4 defaults,nofail,x-systemd.automount,x-systemd.device-timeout=10 0 0"
  "UUID=5e62f799-8df9-4ee3-b4d7-4da62c8c65ff /home/slievr/storage2 ext4 defaults,nofail,x-systemd.automount,x-systemd.device-timeout=10 0 0"
  "UUID=77d7988e-2e64-4654-bda2-481d321eecdd /home/slievr/storage3 ext4 defaults,nofail,x-systemd.automount,x-systemd.device-timeout=10 0 0"
  "UUID=55cefb4f-6b27-4dbc-bbf8-5e9120defa26 /home/slievr/storage4 ext4 defaults,nofail,x-systemd.automount,x-systemd.device-timeout=10 0 0"
)
