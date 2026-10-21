# lsblk -J -b -o PATH,SIZE,MODEL,TRAN,TYPE,FSTYPE,UUID,LABEL,PARTTYPE,ROTA,MOUNTPOINTS  ->  {disks, drives, datafs}
#   $live      the disk holding the live medium ("" when unknown): never listed
#   $defaults  {uuid: mountpoint} from profile.sh DATA_DISKS
# disks:  install targets (whole disks, not USB, not zram/ram/loop)
# drives: every whole disk but the live one, USB included, with its kind and
#         whether the running system holds it (the wipe-into-storage list)
# datafs: filesystems that can be mounted as data disks, on any disk but the
#         live one (USB included); ESPs, swap and LUKS never qualify. The UI
#         drops the ones on the disk chosen as the target.
def esp: (.parttype // "" | ascii_downcase) == "c12a7328-f81f-11d2-ba4b-00a0c93ec93b";
# lsblk prints rota as a boolean (2.40), "1"/"0" or 1/0 depending on version.
def rotational: . == true or . == "1" or . == 1;
def kind: if .tran == "usb" then "usb" elif .tran == "nvme" then "nvme" elif (.rota | rotational) then "hdd" else "ssd" end;
# What keeps a disk in use right now, from its descendants (partitions, then
# whatever is stacked on them: an active LV, md array or open LUKS mapping).
# A closed LUKS partition has no child, so it stays free.
def busy:
  [.children[]? | recurse(.children[]?)
   | if .type == "lvm" then "lvm"
     elif (.type // "" | startswith("raid")) then "raid"
     elif .type == "crypt" then "crypt"
     elif (.mountpoints // [] | index("[SWAP]")) then "swap"
     elif (.mountpoints // [] | map(select(. != null)) | length) > 0 then "mounted"
     else empty end][0] // "";
def drive: {
  path, size,
  model: ((.model // "") | sub("\\s+$"; "")),
  tran: (.tran // ""),
  kind: kind,
  # A filesystem made on the whole disk (no partition table) counts too,
  # or the card would call a disk full of data "Empty".
  parts: [((select(.fstype != null)), (.children // [])[]) | {path, size, fstype: (.fstype // ""), label: (.label // "")}]
};
[.blockdevices[]
 | select(.type == "disk" and .path != $live and (.path | test("/(zram|ram|loop)[0-9]+$") | not))] as $all
| {
    disks: [$all[] | select(.tran != "usb") | drive],
    drives: [$all[] | drive + {busy: busy}],
    datafs: [$all[] | .path as $disk | (., (.children // [])[])
      | select((.fstype // "") | IN("ext4", "btrfs", "xfs", "ntfs", "exfat", "vfat"))
      | select(esp | not)
      | select(.uuid != null)       # DATA_MOUNTS is keyed by UUID; no UUID, no mount
      | {uuid, fstype, label: (.label // ""), size, disk: $disk, mount: ($defaults[.uuid] // null)}]
  }
