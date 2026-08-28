# cachyos/plymouth-theme/

`slievr-cachy/` — Plymouth boot splash: dark (Tokyo Night `#1a1b26`), a
centered logo, and the LUKS passphrase prompt rendered graphically instead
of the bare `Enter passphrase for /dev/...` text line.

Vendored from Omarchy's `default/plymouth` (`script` module theme),
renamed `omarchy.{plymouth,script}` → `slievr-cachy.{plymouth,script}`
with the `ImageDir` / `ScriptFile` paths updated to
`/usr/share/plymouth/themes/slievr-cachy`. `logo.png` (and
`logos/oma.png`) are still Omarchy's mark — replace them with a slievr
logo when there is one; sizes are 800×188 and 800×378 RGBA.

## How it's installed

`cachyos/install/install-cachyos.sh` copies this dir to
`/usr/share/plymouth/themes/slievr-cachy` in the target, adds the
`plymouth` package to pacstrap, and `cachyos/install/lib/chroot-setup.sh`
runs `plymouth-set-default-theme slievr-cachy` and inserts the `plymouth`
hook into `mkinitcpio.conf` (after `kms`, before `encrypt`). `splash` is
already in the kernel cmdline via `profile.sh` `EXTRA_CMDLINE`.

Not stow-managed — Plymouth only reads themes from the system path.
