# cachyos/plymouth-theme/

`fledge/` — Plymouth boot splash: dark (Tokyo Night `#1a1b26`), a
centered logo, and the LUKS passphrase prompt rendered graphically instead
of the bare `Enter passphrase for /dev/...` text line.

Vendored from Omarchy's `default/plymouth` (`script` module theme),
renamed `omarchy.{plymouth,script}` → `fledge.{plymouth,script}`
with the `ImageDir` / `ScriptFile` paths updated to
`/usr/share/plymouth/themes/fledge`. `logo.png` is the made by moonlight owl, generated from
`cachyos/branding/owl.svg` by `cachyos/branding/build-assets.sh`; the
background is the brand `#171e28`. (`logos/oma.png` is unused by the script.)

## How it's installed

`cachyos/install/install-cachyos.sh` copies this dir to
`/usr/share/plymouth/themes/fledge` in the target, adds the
`plymouth` package to pacstrap, and `cachyos/install/lib/chroot-setup.sh`
runs `plymouth-set-default-theme fledge` and inserts the `plymouth`
hook into `mkinitcpio.conf` (after `kms`, before `encrypt`). `splash` is
already in the kernel cmdline via `profile.sh` `EXTRA_CMDLINE`.

Not stow-managed — Plymouth only reads themes from the system path.
