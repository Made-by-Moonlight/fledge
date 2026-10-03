# shellcheck shell=bash
# Carry the live ISO's Wi-Fi into the installed system: the installer connects
# with iwd, the installed system runs NetworkManager. Convert iwd's known
# networks (/var/lib/iwd) into NetworkManager keyfiles so first boot is online.
# Enterprise (802.1X) networks are skipped: their settings don't map cleanly.

# iwd_ssid <iwd file>  ->  the SSID. iwd names files <SSID>.<ext>, or
# =<hex>.<ext> when the SSID has characters outside [A-Za-z0-9 _-].
iwd_ssid() {
  local base
  base="$(basename "$1")"; base="${base%.*}"
  if [[ "$base" == =* ]]; then
    printf '%b' "$(sed 's/../\\x&/g' <<<"${base#=}")"
  else
    printf '%s' "$base"
  fi
}

# ssid_bytes <ssid>  ->  "79;119;108;". The keyfile byte-list form, so SSIDs
# with ';', '=' or leading spaces survive.
ssid_bytes() {
  local i out=""
  for (( i = 0; i < ${#1}; i++ )); do
    out+="$(printf '%d' "'${1:i:1}");"
  done
  printf '%s' "$out"
}

# iwd_get <file> <key>  ->  value of the first Key= line, or nothing.
iwd_get() { sed -n "s/^$2=//p" "$1" | head -n1; }

# iwd_to_nm <iwd file> <uuid>  ->  NetworkManager keyfile on stdout.
# Returns 1 for networks it can't convert (802.1X, or a .psk with no key).
iwd_to_nm() {
  local f="$1" ssid key=""
  ssid="$(iwd_ssid "$f")"
  case "$f" in
    *.psk)
      key="$(iwd_get "$f" Passphrase)"
      [[ -n "$key" ]] || key="$(iwd_get "$f" PreSharedKey)"
      [[ -n "$key" ]] || return 1 ;;
    *.open) ;;
    *) return 1 ;;
  esac
  printf '[connection]\nid=%s\nuuid=%s\ntype=wifi\nautoconnect=true\n\n' "$ssid" "$2"
  printf '[wifi]\nmode=infrastructure\nssid=%s\n' "$(ssid_bytes "$ssid")"
  [[ "$(iwd_get "$f" Hidden)" == true ]] && printf 'hidden=true\n'
  [[ -n "$key" ]] && printf '\n[wifi-security]\nkey-mgmt=wpa-psk\npsk=%s\n' "$key"
  printf '\n[ipv4]\nmethod=auto\n\n[ipv6]\nmethod=auto\n'
}

# install_wifi_profiles <iwd dir> <NetworkManager system-connections dir>
# Writes one root-only keyfile per convertible network. Prints what it carried.
install_wifi_profiles() {
  local src="$1" dst="$2" f ssid name
  [[ -d "$src" ]] || return 0
  for f in "$src"/*.psk "$src"/*.open; do
    [[ -f "$f" ]] || continue
    ssid="$(iwd_ssid "$f")"
    name="${ssid//\//_}"
    mkdir -p "$dst"
    ( umask 077
      iwd_to_nm "$f" "$(cat /proc/sys/kernel/random/uuid)" > "$dst/$name.nmconnection" ) \
      || { rm -f "$dst/$name.nmconnection"; continue; }
    chmod 600 "$dst/$name.nmconnection"
    printf 'Wi-Fi: %s\n' "$ssid"
  done
}
