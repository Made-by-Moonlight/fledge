# lsblk -J -b -o PATH,SIZE,MODEL,TRAN,TYPE,FSTYPE,UUID,LABEL,PARTTYPE  ->  {disks, datafs}
#   $live      the disk holding the live medium ("" when unknown): never listed
#   $defaults  {uuid: mountpoint} from profile.sh DATA_DISKS
# disks:  install targets (whole disks, not USB, not zram/ram/loop)
# datafs: filesystems that can be mounted as data disks, on any disk but the
#         live one (USB included); ESPs, swap and LUKS never qualify. The UI
#         drops the ones on the disk chosen as the target.
def esp: (.parttype // "" | ascii_downcase) == "c12a7328-f81f-11d2-ba4b-00a0c93ec93b";
[.blockdevices[]
 | select(.type == "disk" and .path != $live and (.path | test("/(zram|ram|loop)[0-9]+$") | not))] as $all
| {
    disks: [$all[] | select(.tran != "usb") | {
      path, size,
      model: ((.model // "") | sub("\\s+$"; "")),
      tran: (.tran // ""),
      parts: [(.children // [])[] | {path, size, fstype: (.fstype // ""), label: (.label // "")}]
    }],
    datafs: [$all[] | .path as $disk | (., (.children // [])[])
      | select((.fstype // "") | IN("ext4", "btrfs", "xfs", "ntfs", "exfat", "vfat"))
      | select(esp | not)
      | {uuid, fstype, label: (.label // ""), size, disk: $disk, mount: ($defaults[.uuid] // null)}]
  }
