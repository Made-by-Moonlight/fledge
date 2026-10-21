# cachyos/vm/ — disposable CachyOS test VM

Proves out `cachyos/install/` + `cachyos/bootstrap.sh` in a throwaway
QEMU/KVM VM before touching real hardware.

| Script | Purpose |
| --- | --- |
| `host-deps.sh` | one-time: install libvirt/qemu/etc., join the `libvirt` group, grant the ISO-dir ACLs |
| `download-iso.sh` | fetch + verify the latest stock CachyOS desktop ISO (cached) |
| `provision-vm.sh` | create the VM: 40G system disk, 8G data disk, 4G disk to wipe, boot the ISO |
| `dev-up.sh` | bring an already-installed VM up for a test iteration (SSH + viewer) |
| `destroy-vm.sh` | delete the VM and all its disks |
| `vm.sh` | dev loop: `sync` the working tree in, `run`/`sudo` commands in the logged-in session, `restow`, restart the dev `shell`, `shot` screenshots into `.superpowers/shots/`, `type` into the console, `relogin` |

Only `host-deps.sh` needs `sudo`. Everything else talks to the system
libvirt over `qemu:///system` via `libvirt`-group membership.

VM name: `cachyos-test`. Three disks:

- **disk 1** (`vda`, 40G) — install target
- **disk 2** (`vdb`, 8G) — stands in for the real machine's data disks;
  exercises multi-disk selection and the wrong-disk guard, and carries the
  staged repo (mirrors the real "copy the repo onto an untouched
  partition" delivery)
- **disk 3** (`vdc`, 4G, blank) — the drive the graphical installer's
  Data disks › Wipe erases into storage

## First-time setup

1. `./host-deps.sh` (once per host; log out/in after if it added you to
   the `libvirt` group)
2. `./provision-vm.sh` — creates the VM and boots the ISO
3. `virt-viewer --connect qemu:///system cachyos-test` — the CachyOS live
   desktop comes up. **One manual step** (the live ISO has no serial
   shell): switch to a text VT with **Ctrl+Alt+F2**, log in as `root`
   (no password on the live ISO), then authorize your host key so the
   rest can be driven over SSH:
   ```sh
   systemctl start sshd
   mkdir -p /root/.ssh
   # paste your ~/.ssh/id_ed25519.pub:
   echo 'ssh-ed25519 AAAA... you@host' > /root/.ssh/authorized_keys
   chmod 600 /root/.ssh/authorized_keys
   ip -4 -o addr show scope global
   ```
   (Password SSH is blocked — archiso sshd is `PermitRootLogin
   prohibit-password`.)
4. From the host, stage the repo onto the data disk and run the installer:
   ```sh
   VM_IP=<from step 3>
   ssh root@$VM_IP '
     sgdisk -Zog /dev/vdb && sgdisk -n1:0:0 -t1:8300 /dev/vdb &&
     partprobe /dev/vdb && sleep 1 && mkfs.ext4 -F /dev/vdb1 &&
     mkdir -p /mnt-repo && mount /dev/vdb1 /mnt-repo'
   scp -r ~/proj/fledge root@$VM_IP:/mnt-repo/
   ssh -t root@$VM_IP '/mnt-repo/fledge/cachyos/install/install-cachyos.sh'
   ```
   Pick `vda` at the disk prompt (virtio disks report an empty MODEL — just
   press Enter to confirm). It partitions/encrypts, pacstraps, chroot-
   configures, stages the repo into the target home, enables
   `fledge-firstboot.service`, and reboots.
5. Unlock the disk in `virt-viewer`. `fledge-firstboot.service` then runs
   `bootstrap.sh` automatically on TTY1 (log:
   `/var/log/fledge-firstboot.log`) and starts SDDM when it finishes — no
   manual bootstrap step. If bootstrap fails you land at a TTY with the
   repo at `~slievr/proj/fledge` and on-screen instructions.

## After it's installed

`./dev-up.sh` is the whole iteration loop — starts the VM, waits for SSH,
sets up key auth (via `expect`, using `slievr` / `$VM_PASSWORD`, default
`TestPass1`), opens the viewer, prints the IP. Then `./vm.sh` drives it
(`sync`, `restow`, `run`, `relogin`, `shot`; see its header and AGENTS.md).

## Notes

- `provision-vm.sh` uses `--boot uefi` — the installer requires UEFI.
- `destroy-vm.sh` removes **all three** qcow2 disks (`--remove-all-storage`)
  and the NVRAM.
- Hibernate works in the VM up to the picture: `systemctl hibernate`, unlock
  the disk, and the session resumes (a file in `/tmp` and `uptime -s` survive),
  lock screen and all. The first frame Hyprland draws after unlocking then
  hangs the virtio-gpu driver (`virtio_gpu_queue_ctrl_sgs` blocked in the
  kernel log, black screen, `grim` stuck); `virsh reset` recovers. That's
  QEMU's virtual GPU, not fledge: check resume over ssh, not on screen.
- Wi-Fi without hardware: `mac80211_hwsim` gives two simulated radios, one
  of them an access point through NetworkManager's hotspot (hostapd can't
  take a radio wpa_supplicant holds; dnsmasq hands out the addresses):

      sudo pacman -S --needed dnsmasq
      sudo modprobe mac80211_hwsim radios=2
      sudo nmcli dev wifi hotspot ifname wlan1 con-name test-ap ssid fledge-test password hunter2pass

  `fledge-test` then shows in the Wi-Fi picker on `wlan0`.
- Extra monitors for Settings › Displays: in the session, `hyprctl output
  create headless` adds one and `hyprctl output remove <name>` removes it
  (`hyprctl monitors` shows the name). They report no physical size, so the
  canvas draws them at 96 dpi tagged "size unknown". `verify-displays.sh`
  does this itself: `vm.sh run 'bash ~/proj/fledge/cachyos/iso/test/verify-displays.sh'`
  (the other `iso/test/verify-*.sh` checks run the same way; `verify-shell.sh`
  also needs `wtype`, see `cachyos/iso/README.md`).
- `--events on_reboot=restart` is set but doesn't always take on this
  virt-install version — the VM may power off after the install reboot;
  just `virsh -c qemu:///system start cachyos-test`.
