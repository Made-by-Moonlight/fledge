# cachyos/vm/ — disposable CachyOS test VM

Proves out `cachyos/install/` + `cachyos/bootstrap.sh` in a throwaway
QEMU/KVM VM before touching real hardware.

| Script | Purpose |
| --- | --- |
| `host-deps.sh` | one-time: install libvirt/qemu/etc. on the host |
| `download-iso.sh` | fetch + verify the latest stock CachyOS desktop ISO (cached) |
| `provision-vm.sh` | create the VM: 40G system disk + 8G blank data disk, boot the ISO |
| `dev-up.sh` | bring an already-installed VM up for a test iteration (SSH + viewer) |
| `destroy-vm.sh` | delete the VM and all its disks |

VM name: `cachyos-test`. Two disks:

- **disk 1** (`vda`, 40G) — install target
- **disk 2** (`vdb`, 8G) — stands in for the real machine's data disks;
  exercises multi-disk selection and the wrong-disk guard, and carries the
  staged repo (mirrors the real "copy the repo onto an untouched
  partition" delivery)

## First-time setup

1. `./host-deps.sh` (once per host)
2. `./provision-vm.sh` — creates the VM and boots the ISO
3. `virt-viewer --connect qemu:///system cachyos-test` — the CachyOS live
   desktop comes up. **This one GUI step is manual**: the CachyOS desktop
   live ISO doesn't attach a shell to the serial console, so
   `unlock-console.exp` can't drive it. In the live desktop's terminal:
   ```sh
   sudo systemctl start sshd
   passwd            # set a known root password, or:
   sudo passwd cachyos
   ip a              # note the VM's IP
   ```
4. From the host, stage the repo onto the data disk and run the installer:
   ```sh
   VM_IP=<from step 3>
   # partition + format the blank data disk, mount it, copy the repo in
   ssh root@$VM_IP '
     sgdisk -Zog /dev/vdb && sgdisk -n1:0:0 -t1:8300 /dev/vdb &&
     mkfs.ext4 -F /dev/vdb1 && mkdir -p /mnt-repo && mount /dev/vdb1 /mnt-repo'
   scp -r ~/proj/slievr-cachy root@$VM_IP:/mnt-repo/
   ssh -t root@$VM_IP '/mnt-repo/slievr-cachy/cachyos/install/install-cachyos.sh'
   ```
   Pick disk `[0]` (`vda`) at the prompt. When it reboots, unlock the
   disk in `virt-viewer`, log in as `slievr`, then:
   ```sh
   mount /dev/vdb1 /mnt-repo
   /mnt-repo/slievr-cachy/cachyos/bootstrap.sh
   ```

## After it's installed

`./dev-up.sh` is the whole iteration loop — starts the VM, waits for SSH,
sets up key auth, opens the viewer, prints the IP. See the deploy
workflow in `../NEXT-SESSION.md`.

## Notes

- `provision-vm.sh` uses `--boot uefi` — the installer requires UEFI.
- `destroy-vm.sh` removes **both** qcow2 disks (`--remove-all-storage`).
- The VM has 8 GiB RAM, so hibernate can't be meaningfully tested, but the
  btrfs swapfile and `resume=` cmdline are still created and verifiable.
