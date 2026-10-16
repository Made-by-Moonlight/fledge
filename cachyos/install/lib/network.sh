# shellcheck shell=bash
# Carry the live ISO's networks into the installed system. Both run
# NetworkManager, so the keyfiles the live session saved (Wi-Fi joined in the
# installer) copy straight across and the first boot is online.

# copy_nm_profiles <src dir> <dst dir>  ->  every *.nmconnection into dst
# (dir 700, files 600: they hold Wi-Fi passwords). Prints what it carried.
copy_nm_profiles() {
  local src="$1" dst="$2" f
  local LC_COLLATE=C   # glob order must not depend on the live locale
  compgen -G "$src/*.nmconnection" >/dev/null || return 0
  install -d -m 700 "$dst"
  for f in "$src"/*.nmconnection; do
    install -m 600 "$f" "$dst/"
    printf 'network: %s\n' "$(basename "$f" .nmconnection)"
  done
}
