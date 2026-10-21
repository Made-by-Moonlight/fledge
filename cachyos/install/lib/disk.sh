# shellcheck shell=bash
# Partition + LUKS2 + btrfs + swapfile. Every function writes ONLY to the
# device passed in. Progress goes to stderr; the caller must have already
# run the disk-selection guard in install-cachyos.sh.
#
# Consumes from profile.sh: ESP_SIZE LUKS_NAME BTRFS_SUBVOLS BTRFS_OPTS
#                           CREATE_SNAPSHOTS_SUBVOL SWAP HIBERNATE_SWAP_SIZE
# Consumes from detect.sh:  hibernate_swap_size
# Consumes (optional):      LUKS_PASSPHRASE (unattended install)
# Globals: WIPED_UUIDS USERNAME (own_wiped_roots)
# Sets globals: ESP_PART LUKS_PART LUKS_PARTUUID RESUME_OFFSET

_log() { printf '>>> %s\n' "$*" >&2; }

# format_data_disk <disk> <label>  ->  prints the new ext4's UUID on stdout.
# One GPT partition spanning the drive; the label names both the partition
# and the filesystem.
format_data_disk() {
  local disk="$1" label="$2" part
  [[ -b "$disk" ]] || { echo "not a block device: $disk" >&2; return 1; }
  if findmnt -rno SOURCE | grep -q "^$(realpath "$disk")"; then
    echo "refusing: $disk (or a partition of it) is mounted" >&2
    return 1
  fi

  _log "wiping $disk into storage '$label'"
  wipefs -a "$disk" >&2
  sgdisk --zap-all "$disk" >&2
  sgdisk -n1:0:0 -t1:8300 -c1:"$label" "$disk" >&2
  partprobe "$disk"; udevadm settle

  part="$(lsblk -rpno NAME,TYPE "$disk" | awk '$2=="part"{print $1; exit}')"
  [[ -n "$part" ]] || { echo "no partition on $disk after partitioning" >&2; return 1; }
  mkfs.ext4 -F -L "$label" "$part" >&2
  blkid -s UUID -o value "$part"
}

# partition_disk <disk>  (by-id path or /dev/xxx)
partition_disk() {
  local disk="$1" size
  [[ -b "$disk" ]] || { echo "not a block device: $disk" >&2; return 1; }
  if findmnt -rno SOURCE | grep -q "^$(realpath "$disk")"; then
    echo "refusing: $disk (or a partition of it) is mounted" >&2
    return 1
  fi

  _log "wiping $disk"
  wipefs -a "$disk"
  sgdisk --zap-all "$disk"

  size="${ESP_SIZE/iB/}"          # sgdisk wants +2G, not +2GiB
  _log "partitioning $disk (ESP ${size}, LUKS rest)"
  sgdisk -n1:0:+"${size}" -t1:ef00 -c1:ESP "$disk"
  sgdisk -n2:0:0          -t2:8309 -c2:LUKS "$disk"

  partprobe "$disk"; udevadm settle

  mapfile -t _parts < <(lsblk -rpno NAME,TYPE "$disk" | awk '$2=="part"{print $1}')
  ESP_PART="${_parts[0]:?failed to find ESP partition}"
  LUKS_PART="${_parts[1]:?failed to find LUKS partition}"
  _log "ESP=$ESP_PART  LUKS=$LUKS_PART"
}

# luks_format_open <luks_part>   (LUKS_PASSPHRASE if set, else prompts twice)
luks_format_open() {
  local part="$1" p1 p2
  if [[ -n "${LUKS_PASSPHRASE:-}" ]]; then
    p1="$LUKS_PASSPHRASE"
  else
    read -rsp "LUKS passphrase: " p1; echo >&2
    read -rsp "Confirm passphrase: " p2; echo >&2
    [[ "$p1" == "$p2" && -n "$p1" ]] || { echo "passphrases differ or empty" >&2; return 1; }
  fi

  LUKS_PASSPHRASE="$p1"   # read by write_autologin (install-cachyos.sh)

  _log "luksFormat $part"
  printf '%s' "$p1" | cryptsetup luksFormat --type luks2 --batch-mode "$part" -
  _log "opening as /dev/mapper/$LUKS_NAME"
  printf '%s' "$p1" | cryptsetup open "$part" "$LUKS_NAME" -

  LUKS_PARTUUID="$(blkid -s PARTUUID -o value "$part")"
  _log "LUKS PARTUUID=$LUKS_PARTUUID"
}

# make_filesystems   (uses ESP_PART + /dev/mapper/$LUKS_NAME)
make_filesystems() {
  local dev="/dev/mapper/$LUKS_NAME" entry subvol mnt

  _log "mkfs ESP + btrfs"
  mkfs.fat -F32 "$ESP_PART"
  mkfs.btrfs -f "$dev"

  mount "$dev" /mnt
  for entry in "${BTRFS_SUBVOLS[@]}"; do
    subvol="${entry%%:*}"
    _log "btrfs subvol $subvol"
    btrfs subvolume create "/mnt/$subvol"
  done
  if [[ "${CREATE_SNAPSHOTS_SUBVOL:-false}" == true ]]; then
    _log "btrfs subvol @/.snapshots"
    btrfs subvolume create "/mnt/@/.snapshots"
  fi
  umount /mnt

  for entry in "${BTRFS_SUBVOLS[@]}"; do
    subvol="${entry%%:*}"; mnt="${entry#*:}"
    mkdir -p "/mnt${mnt}"
    if [[ "$subvol" == "@swap" ]]; then
      mount -o "subvol=${subvol},nodatacow" "$dev" "/mnt${mnt}"
    else
      mount -o "subvol=${subvol},${BTRFS_OPTS}" "$dev" "/mnt${mnt}"
    fi
  done

  mkdir -p /mnt/boot
  mount "$ESP_PART" /mnt/boot
  _log "mounted: $(findmnt -nRo TARGET /mnt | tr '\n' ' ')"
}

# make_swapfile   (only meaningful when SWAP=hibernate)
make_swapfile() {
  [[ "${SWAP:-zram}" == hibernate ]] || { RESUME_OFFSET=""; return 0; }
  local size="${HIBERNATE_SWAP_SIZE:-}"
  if [[ -z "$size" ]]; then
    size="$(hibernate_swap_size "$(awk '/^MemTotal:/{print $2}' /proc/meminfo)")"
  fi
  local sf=/mnt/swap/swapfile
  _log "creating ${size}MiB btrfs swapfile at ${sf#/mnt}"
  if btrfs filesystem mkswapfile --help >/dev/null 2>&1; then
    btrfs filesystem mkswapfile --size "${size}M" "$sf"
  else
    truncate -s 0 "$sf"
    chattr +C "$sf"
    fallocate -l "${size}M" "$sf"
    chmod 600 "$sf"
    mkswap "$sf"
  fi
  RESUME_OFFSET="$(btrfs inspect-internal map-swapfile -r "$sf")"
  _log "resume_offset=$RESUME_OFFSET"
}

# add_data_mounts  ->  fstab entries + mountpoints for DATA_MOUNTS_TSV
# ("uuid<TAB>/path" lines) in the target at /mnt. Runs after the user exists
# (chroot-setup.sh) so ntfs/vfat mounts and folders in the home get their ids.
# Folders inside the user's home are created owned by the user, parents too.
add_data_mounts() {
  local uid gid uuid path dev fs d
  [[ -n "${DATA_MOUNTS_TSV:-}" ]] || return 0
  uid="$(arch-chroot /mnt id -u "$USERNAME")"; gid="$(arch-chroot /mnt id -g "$USERNAME")"
  printf '\n# Data disks (fledge installer): mounted by UUID on every boot;\n# nofail, so a missing disk never holds up boot.\n' >> /mnt/etc/fstab
  while IFS=$'\t' read -r uuid path; do
    [[ -n "$uuid" ]] || continue
    dev="$(blkid -U "$uuid")"
    fs="$(blkid -s TYPE -o value "$dev")"
    fstab_line "$uuid" "$fs" "$path" "$uid" "$gid" >> /mnt/etc/fstab
    mkdir -p "/mnt$path"
    if [[ "$path" == "/home/$USERNAME/"* ]]; then
      d="$path"
      while [[ "$d" != "/home/$USERNAME" ]]; do chown "$uid:$gid" "/mnt$d"; d="${d%/*}"; done
    fi
    _log "data disk $uuid ($fs) -> $path"
  done <<<"$DATA_MOUNTS_TSV"
}

# own_wiped_roots  ->  a fresh ext4 root belongs to root; give each wiped
# filesystem's (WIPED_UUIDS) to the user. Existing filesystems keep theirs.
own_wiped_roots() {
  local uuid dev tmp uid gid
  (( ${#WIPED_UUIDS[@]} )) || return 0
  uid="$(arch-chroot /mnt id -u "$USERNAME")"; gid="$(arch-chroot /mnt id -g "$USERNAME")"
  for uuid in "${WIPED_UUIDS[@]}"; do
    dev="$(blkid -U "$uuid")"
    tmp="$(mktemp -d)"
    mount "$dev" "$tmp"
    chown "$uid:$gid" "$tmp"
    umount "$tmp"; rmdir "$tmp"
    _log "storage $uuid is owned by $USERNAME"
  done
}
