# CachyOS migration — resume prompt

Paste this whole file as your first message in a fresh session to pick up
where we left off. Delete this file once you've resumed (it's a handoff
note, not permanent project doc).

---

# ⟶ RESUME HERE (2026-10-01): made by moonlight ISO — all code committed

**Branch `custom-iso`** (worktree `/home/slievr/proj/slievr-cachy-iso`, off `main`,
NOT pushed, NOT merged).
Design: `docs/superpowers/specs/2026-10-01-custom-iso-design.md`
Plan:   `docs/superpowers/plans/2026-10-01-custom-iso.md`

ISO built: `release/made-by-moonlight-2026.10.01-x86_64.iso`
SHA256: `9d38515e3bc44de8be04eac2ceaaa8769ee56f9f792a8c96102b4611402c15c2`
Live kernel: 7.2.7
Desktop theme made-by-moonlight (login, lock, Moonrise wallpaper, themed apps) — **VM-verified 2026-10-02**:
  install → firstboot → SDDM login → Hyprland, screenshots of installer, login, desktop, lock, walker, btop
  all match the mockups; `verify-install.sh` 16/16 PASS (after fixes 9aeee3f, bc9bacf, 8c5a8a6, applied to
  the VM by re-running bootstrap.sh; the ISO above includes them but has not had a fresh end-to-end run).
  LUKS unlock now graphical (owl, brand field) — the text prompt was Plymouth forcing "details" because
  systemd's UKI stub appends console=uart,… when the firmware console has a serial port; fixed with
  plymouth.ignore-serial-consoles in profile.sh EXTRA_CMDLINE (3855d49). The owl is centred on the
  midpoint between its eyes on unlock, login, lock and wallpaper (9021778) — all VM-verified 2026-10-02.
  ISO above is built from bare-metal-install @ 9021778; not yet re-run end to end from a fresh install.
  Heads-up: Hyprland warns the .conf config format is removed in 0.57 — plan a migration before then.

**Pending checks** (by the user):
1. Answers-mode install from the stock ISO (plan Task 2 Step 10)
2. Brand palette on a real console (Task 5 Step 3)
3. Full ISO run in the VM + `verify-install.sh` + Hyprland login (Task 7 Steps 5–7)
4. Interactive configurator dry run (Task 4 Step 5)

---

# ARCHIVE: RESUME HERE (2026-08-31): bare-metal install — firstboot validated

**Branch `bare-metal-install`** (off `main`, NOT pushed, NOT merged).
Design: `docs/superpowers/specs/2026-08-28-bare-metal-install-design.md`
Plan:   `docs/superpowers/plans/2026-08-28-bare-metal-install.md`

## 2026-08-31 session progress

Fresh `destroy + provision + install-cachyos.sh` VM run done from scratch
(the prior VM's passwords were unknown). Uncommitted changes on the branch:

- **`cachyos/vm/{provision,destroy,dev-up}.sh` + `host-deps.sh`** — dropped
  all `sudo`: they now talk to `virsh -c qemu:///system` / `virt-install
  --connect qemu:///system` via libvirt-group membership. The one-time
  privileged bits (ISO-dir ACLs for `libvirt-qemu`) moved into
  `host-deps.sh`; `dev-up.sh` sets up key auth with `expect` instead of
  `sudo pacman -S sshpass`. `provision-vm.sh` verifies the ACL rather
  than re-applying it.
- **`cachyos/bootstrap.sh` line ~214** — **bug #5 fixed**: was
  `sudo systemctl enable --now power-profiles-daemon.service`; the `--now`
  start deadlocks when bootstrap runs from `slievr-firstboot.service`
  (firstboot waits on the p-p-d job → p-p-d is `After=multi-user.target`
  → multi-user.target waits on firstboot). Now plain `enable`; p-p-d
  starts with `graphical.target`. Confirmed `enabled` + `active` after
  reboot with no hang.

### Validation state — firstboot now works end to end

`slievr-firstboot.service` ran `bootstrap.sh` to `Bootstrap complete.`,
self-disabled, wrote the done-guard, enabled + started SDDM. **Bug #4
(elephant `systemctl --user` hang) and bug #5 (p-p-d deadlock) both
validated fixed.** The stow-managed
`~/.config/systemd/user/graphical-session.target.wants/elephant.service`
symlink is in place. Plymouth graphical "SLIEVR" LUKS prompt **works**
(the plain-text prompt seen first is the pre-splash initramfs stage).

**Clean end-to-end run DONE** (2nd VM build, driven entirely from the
host — `virsh send-key` for the LUKS unlock, `expect` for the installer):
`journalctl --list-boots` shows exactly **1 boot**, firstboot log has
`Created symlink .../graphical.target.wants/power-profiles-daemon.service`
immediately followed by `Bootstrap complete.` (no deadlock), 0
FAILED/error lines, 449 pkgs, p-p-d active+enabled, sddm active, firstboot
disabled + done-guard written, elephant symlink correct, shell = zsh.
Bug #5 fix confirmed in a genuine single uninterrupted pass.

**NOT yet checked:** an actual SDDM login → Hyprland/waybar/walker render
on the fresh install. The greeter came up and showed Hyprland's
".conf format deprecation" notification (so the session config loads),
but a real login over `virsh send-key`/screenshots was too fiddly —
verify in virt-viewer (`slievr` / `TestPass1`).

Note: the graphical "SLIEVR" Plymouth prompt DOES render (the plain-text
one is the pre-splash initramfs stage); it can linger on screen with an
empty box after unlock until SDDM takes the tty — cosmetic.
`virsh send-key` LUKS unlock: use `KEY_LEFTCTRL KEY_U` first to clear any
stray char, then type the passphrase (`scratchpad/typ.py` maps a string
to send-key calls). SSH password auth into the installed VM is slow while
bootstrap runs — `expect` needs `timeout ~200`, a `sleep 0.5` before
`send`, and `PubkeyAuthentication=no`.

### VM access this session

`cachyos-test`, user `slievr` / **`TestPass1`** (LUKS passphrase and root
password also `TestPass1` — set via the installer). Host SSH key is NOT
authorized on the installed system; use password auth. `expect` snag:
`ssh`/`scp` with `-tt` hangs on the password prompt under `expect`;
plain `ssh -o NumberOfPasswordPrompts=1` (no `-tt`) works. `sudo` on the
VM needs a password now (the firstboot NOPASSWD drop-in was removed on
success) — use `ssh -t` ... except that hangs, so read root files via
`journalctl`/world-readable paths, or unlock via `virsh console`.

### Then: finish the branch (unchanged from below)

## What was built

`cachyos/install/` — a hardware-adaptive installer run as root in the stock
CachyOS live ISO. Replaces `cachyos/vm/install-cachyos.sh`.

- `install-cachyos.sh` — orchestrator: preflight → detect → disk guard
  (type the model string + `YES`) → partition/LUKS2/btrfs → pacstrap →
  arch-chroot → stage repo into target home + install first-boot service.
- `profile.sh` — fixed choices: LUKS2, btrfs `@ @home @log @pkg @swap`
  (+`@/.snapshots`), Limine UKI, zram, `SWAP=hibernate` (encrypted btrfs
  swapfile), the 4 desktop data-disk fstab lines.
- `lib/detect.sh` (+ `test-detect.sh`, 18 assertions passing) — microcode /
  GPU pkgs+cmdline+modules / disk list / part-suffix / zram+swap sizing.
- `lib/disk.sh`, `lib/bootloader.sh` (Limine UKI via `/etc/default/limine`
  + `limine-update`/`limine-install`), `lib/chroot-setup.sh`.
- `cachyos/install/firstboot/` — `slievr-firstboot.service` (oneshot,
  guard `/var/lib/slievr-firstboot-done`) runs `bootstrap.sh` as the user
  on TTY1 on first real boot, logs to `/var/log/slievr-firstboot.log`,
  then enables+starts SDDM. Removes the blind post-install TTY phase.
- `cachyos/plymouth-theme/slievr-cachy/` — vendored+renamed from Omarchy;
  graphical boot splash + LUKS prompt. Installer adds `plymouth` pkg +
  hook (after `kms`, before `encrypt`) and selects the theme.
- `cachyos/vm/provision-vm.sh` — 2nd blank disk (`vdb`) for multi-disk
  test + `--events on_reboot=restart`. `cachyos/vm/README.md` — new.
- `cachyos/vm/destroy-vm.sh` — `--nvram` fix (UEFI varstore).

## Validation state

A full VM install **succeeded once** end-to-end BEFORE the last two
commits: LUKS + btrfs subvols + Limine UKI + zram + 10G swapfile + resume
cmdline → boots → SDDM → Hyprland/waybar/walker/kitty all work. Data disk
`vdb` untouched. 4 bugs found + fixed along the way:

1. `disk.sh` pre-`mkdir` broke `.snapshots` subvol — FIXED, validated
2. CachyOS repos don't survive pacstrap (stock-Arch pacman.conf written) —
   `chroot-setup.sh` runs `cachyos-repo.sh` — FIXED, validated
3. SDDM theme: empty `userModel.lastUser` on fresh install → login
   rejected "user unknown" — first-user fallback added — FIXED, validated
4. `systemctl --user enable elephant.service` in `bootstrap.sh` HANGS under
   `runuser` (no user D-Bus) during firstboot — replaced with stow-managed
   `dot-config/systemd/user/graphical-session.target.wants/elephant.service`
   symlink — **FIXED, NOT YET VALIDATED** (this is where we stopped)

## VM state right now

`cachyos-test` is **installed** (base system good, boots, plymouth+LUKS
works) but **powered off** — user hard-restarted it mid-`bootstrap.sh`
(hung on bug #4). `/var/lib/slievr-firstboot-done` was never written, so
`slievr-firstboot.service` **will retry automatically on next boot**. The
staged repo at `~slievr/proj/slievr-cachy` on the VM is STALE (pre-bug-#4
fix) — must be patched before firstboot retries or it hangs again.

## Next step: validate bug #4 fix (surgical, no reinstall)

```sh
sudo virsh start cachyos-test
# unlock at the plymouth LUKS prompt in virt-viewer, then from host:
VM_IP=$(sudo virsh domifaddr cachyos-test | awk '/ipv4/{print $4}' | cut -d/ -f1); echo "$VM_IP"
ssh-keygen -R "$VM_IP" 2>/dev/null

# stop firstboot before it wedges; kill any wedged bootstrap
ssh slievr@$VM_IP 'sudo systemctl stop slievr-firstboot.service; sudo pkill -9 -f bootstrap.sh; sudo pkill -9 -f "systemctl --user"' || true

# patch the two changed files onto the VM's staged repo
scp ~/proj/slievr-cachy/cachyos/bootstrap.sh slievr@$VM_IP:proj/slievr-cachy/cachyos/bootstrap.sh
ssh slievr@$VM_IP 'cd proj/slievr-cachy/dot-config/systemd/user && mkdir -p graphical-session.target.wants && ln -sf ../elephant.service graphical-session.target.wants/elephant.service'

# resume, watch live
ssh -t slievr@$VM_IP 'sudo rm -f /var/lib/slievr-firstboot-done; sudo systemctl start slievr-firstboot.service & journalctl -fu slievr-firstboot.service'
```

`bootstrap.sh` is re-run-safe (`pacman -Qi`/`paru -Qi` guards, stow
idempotent). Expect: bootstrap finishes → `Bootstrap complete.` →
firstboot enables+starts SDDM → greeter → log in → verify elephant/walker.

Then optionally one clean `./destroy-vm.sh && ./provision-vm.sh` run to
confirm the committed scripts work start-to-finish unpatched.

## Then: finish the branch

1. Cutover: `git rm cachyos/vm/install-cachyos.sh` (replaced by
   `cachyos/install/`); grep for other refs to it.
2. Update this file / `cachyos/vm/README.md` if needed.
3. `superpowers:finishing-a-development-branch` → merge `bare-metal-install`.

## Known loose ends (not blockers)

- **Auto-reboot after install still didn't happen** in the last VM run
  despite `--events on_reboot=restart` in `provision-vm.sh` — check
  `sudo virsh dumpxml cachyos-test | grep on_reboot`; if `destroy`, the
  flag didn't take on this virt-install version → set `<on_reboot>restart`
  via `virsh edit` or a post-provision `virt-xml` call. On real hardware
  firmware boots the disk, so this is VM-only.
- **Plymouth logo art is still Omarchy's** (`logo.png` 800×188,
  `logos/oma.png`) — an anime "silent." image showed on the LUKS screen,
  which is a *customized* `~/.local/share/omarchy/default/plymouth/logo.png`
  on the host, not stock Omarchy. Replace with a real slievr logo, or pull
  the upstream Omarchy theme art for a cleaner look.
- **stow links `~/cachyos` and `~/docs`** into $HOME (repo dirs with no
  `dot-` prefix) — pre-existing `bootstrap.sh` quirk (`stow -d repo -t $HOME .`
  stows every top-level entry). Harmless; clean up by stowing only the
  `dot-*` entries, or add a `.stow-local-ignore`.
- `console=uart,io,0x3f8 console=tty0` appeared in `/proc/cmdline` on the
  installed VM — not set by us; a CachyOS ISO / mkinitcpio default. Harmless
  in the VM; check on real hardware.
- `limine-mkinitcpio-hook` — turned out to BE in the CachyOS repos (the
  anticipated AUR roadblock never hit); `limine-update` regenerated the
  UKI cleanly on a kernel bump. No action.

## Bare-metal target (the real machine = this dev host)

AMD Ryzen 9 7900X, RTX 3080 + Raphael iGPU, 61 GiB RAM, UEFI. Root disk:
`nvme1n1` (WD Blue SN570 1TB). Four data disks (`sda1 sdb1 nvme2n1p1
nvme0n1p3` → `~/storage1..4`) MUST survive — their UUIDs are already in
`profile.sh` `EXTRA_FSTAB_ENTRIES`. Delivery: copy the repo onto a data
disk before booting the ISO; installer stages it into the target itself.

---

## What this project is

Migrating the user's Arch/Omarchy Hyprland desktop (waybar, walker, mako,
swayosd, starship, kitty, Zen browser) to CachyOS, proven out in a
disposable QEMU/KVM test VM first, then to real hardware later. Full
design/plan history: `docs/superpowers/specs/2026-08-26-cachyos-migration-design.md`
and `docs/superpowers/plans/2026-08-26-cachyos-migration.md` in
`~/proj/dotfiles` (that worktree — see "Repo layout" below).

**The actual distribution mechanism** (confirmed, not aspirational): boot
the *stock* official CachyOS ISO on real hardware, run `install-cachyos.sh`
then `bootstrap.sh`. No custom ISO — the live installer's own desktop
never carries into the installed system, so a different ISO variant
wouldn't help with anything; all the actual desktop setup comes from
these two scripts.

## Repo layout — READ THIS FIRST, it's not obvious

- **`~/proj/slievr-cachy`** (GitHub: `slievr/slievr-cachy`, private) — this
  is where ALL real work now lives: `cachyos/` (VM scripts, bootstrap.sh),
  `dot-config/`, `dot-local/` (stow-managed dotfiles). **Work here.**
- **`~/proj/dotfiles`** (this session's worktree at
  `.claude/worktrees/cachyos-migration`) — the ORIGINAL personal dotfiles
  repo. Early work happened here before a mid-session pivot (see below)
  to a separate repo so this work never touches the host's real, live
  dotfiles. Has a few **stale uncommitted changes** left over from before
  the pivot (`.gitignore`, `dot-config/zen/`, `docs/`) — safe to ignore or
  just discard; nothing there is current.

## Why the separate repo

The VM's Hyprland setup turned out to be built on the
[Omarchy](https://github.com/basecamp/omarchy) framework (not just
hand-picked Hyprland packages) — `bindings.conf` and other configs call
dozens of `omarchy-*` commands and source files from
`~/.local/share/omarchy/default/`. Decision made: vendor what's needed
(not install the full Omarchy framework — its installer overrides the
pacman mirrorlist and would fight with CachyOS's own repos), then rename
every `omarchy-*` command to `slievr-*` since it's a permanent fork, not
synced from upstream. All of `dot-local/share/slievr-cachy/bin/` (282
scripts) is that vendored, renamed tree.

## VM access

VM name: `cachyos-test` (libvirt/QEMU). Login: `slievr` / `TestPass1`
(also root). Passwordless sudo already set up for `slievr` on the VM.
SSH key auth already set up from host → VM (no password needed for
`ssh`/`scp`).

**`cachyos/vm/dev-up.sh`** brings an already-installed VM up for testing:
starts it if stopped, waits for SSH, sets up key auth automatically if
missing, opens `virt-viewer`. It does NOT provision from scratch — that
needs one manual GUI step (see script header) because this CachyOS
desktop-edition live ISO doesn't attach a shell to the serial console, so
`unlock-console.exp`'s automated approach doesn't apply to it.

To get the VM's current IP if `dev-up.sh` isn't used:
`sudo virsh domifaddr cachyos-test`

## Deploy workflow used throughout this session

```bash
# From host, after editing files in ~/proj/slievr-cachy:
ssh slievr@<vm-ip> 'rm -rf ~/proj/slievr-cachy'
scp -r ~/proj/slievr-cachy slievr@<vm-ip>:~/proj/slievr-cachy
scp ~/proj/slievr-cachy/cachyos/bootstrap.sh slievr@<vm-ip>:~/bootstrap.sh
ssh slievr@<vm-ip> '~/bootstrap.sh'
```

(A partial `scp` of just the changed file(s) also works and is faster —
just don't forget `bootstrap.sh` itself needs a separate `scp` to
`~/bootstrap.sh`, it's not read from `~/proj/slievr-cachy` when invoked as
`~/bootstrap.sh`.)

To test changes: **must fully restart Hyprland**, not just `hyprctl
reload` — env var changes (`~/.config/uwsm/env`) only take effect on a
fresh session start:

```bash
ssh slievr@<vm-ip> 'systemctl --user stop wayland-wm@hyprland.service'
# then in the VM's console: uwsm start -e -D Hyprland hyprland.desktop
```

(`uwsm start hyprland` also works but triggers a "started without
start-hyprland" warning — the `hyprland-uwsm.desktop` invocation above is
the correct one, resolves that warning.)

## Current state: working

SDDM login (custom "SLIEVR" DodgerBlue-on-`#131315` themed greeter,
`cachyos/sddm-theme/slievr-cachy/`) → Hyprland session → waybar (icons
render now, needed 3 separate nerd font packages that were never
installed) → walker launcher, background/theme picker (via `elephant` +
its specific provider packages, not the bloated `elephant-all-bin`) →
zsh default shell → kitty terminal → Thunar file manager → Discord →
ProtonVPN GTK app → ffmpeg/wifi/bluetooth/audio TUIs (`nmtui`, `bluetui`,
`wiremix` — not `impala`, which needs `iwd` not NetworkManager).

`cachyos-hyprland-settings` (CachyOS's opinionated Hyprland metapackage,
pulls in kvantum/wofi/bemenu/grimblast/etc.) was removed — this repo has
its own equivalents for everything it provided that's actually used.

## Known open items (not fixed, in priority-ish order)

1. **Zen webapp windows show full browser chrome** (URL bar, tabs,
   sidebar) instead of a seamless standalone app window. Zen (Firefox-
   based) has no CLI-scriptable equivalent to Chromium's `--app=` mode —
   its real "Web App" feature is GUI-only. `--kiosk` was tried and
   rejected: forced fullscreen, still showed full chrome, then crashed
   after ~6s (confirmed via `journalctl`). Current state: plain
   `--new-window` (`dot-local/share/slievr-cachy/bin/slievr-launch-webapp`)
   — stable but not seamless. **Next idea to try**: a dedicated Firefox
   profile with a `userChrome.css` that hides `#nav-bar`/`#TabsToolbar` —
   standard technique for this on Firefox-family browsers, more setup
   than a flag, not attempted yet.
2. **"gazelle" wifi TUI** — the *original* waybar config's network-icon
   click handler and the user's memory both referenced a tool called
   "gazelle" as an nmtui/impala alternative. Confirmed: not in official
   repos or AUR. User says it came from a GitHub repo they can't
   currently pin down. Currently substituted with `nmtui` everywhere
   (works, just not the exact originally-intended tool). Revisit if the
   repo gets found.
3. **Multi-monitor app-placement bindings** (`dot-config/hypr/monitors.conf`,
   `workspaces.conf` — 3 real monitors by EDID description, workspace 9/10
   pinned to side monitors, Discord/Spotify/YouTube Music pinned to
   workspace 9) were reviewed for correctness but **cannot be tested** in
   this single-virtual-monitor VM. Only verifiable on real hardware.
4. **Bare-metal deployment not yet done.** `install-cachyos.sh` has
   `DISK=/dev/vda` hardcoded — needs to change to the real target disk
   (e.g. `/dev/nvme0n1`) before running on actual hardware. This is
   otherwise the literal distribution mechanism (see top).
5. `.conf` config format deprecation warning in Hyprland's startup
   overlay — cosmetic only, not actionable: Hyprland 0.57 (where it's
   actually removed) hasn't shipped, and there's no published
   replacement spec or migration tool yet to move to.
6. A handful of vendored `slievr-*` self-management commands
   (`slievr-update*`, `slievr-reinstall*`, `slievr-migrate`, theme-catalog
   browsing, some `slievr-refresh-*`) still reference `$OMARCHY_PATH`,
   which assumed a live upstream git checkout that isn't vendored.
   Intentionally left inert — documented in
   `dot-local/share/slievr-cachy/README.md` — nothing in the active
   desktop config calls them.

## Useful context for the next session

- User prefers being told the reasoning/tradeoff, not just the fix — several
  turns this session involved presenting 2-3 options with a recommendation
  before acting on anything architecturally significant (e.g. Omarchy
  vendoring scope, the metapackage removal).
- User caught at least one case where I stated something as fact without
  verifying first (the "cold-start timing quirk" claim about a glob error
  that was actually a real path bug) — be correspondingly careful about
  confidence framing; verify against the actual on-screen error/log rather
  than inferring from indirect signals when the two might disagree.
- A recurring failure mode this session: editing a file locally and
  believing it's deployed, when actually a stale copy was still on the
  VM (either `~/bootstrap.sh` not re-synced after editing
  `cachyos/bootstrap.sh`, or an `scp -r` nesting into an already-existing
  destination directory instead of overwriting it cleanly). When
  something "isn't picking up a fix," verify the actual bytes on the VM
  match the local file before looking elsewhere.
