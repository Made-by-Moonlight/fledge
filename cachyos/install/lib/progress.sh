# shellcheck shell=bash
# Progress markers for the graphical installer. With MBM_PROGRESS=1 the
# installer prints, on stdout, lines of exactly:
#   @@mbm stage <id> <title>   a stage starts (prepare disk base config boot desktop finish)
#   @@mbm count <n> <m>        package n of m in the current pacman transaction
#   @@mbm fail <id>            the stage failed (just before a non-zero exit)
#   @@mbm done                 everything succeeded
# Without it, output is exactly as before. The UI (Run.qml) parses these.

MBM_STAGE="${MBM_STAGE:-prepare}"

progress_on() { [[ "${MBM_PROGRESS:-}" == 1 ]]; }

progress_stage() { # <id> <title>
  MBM_STAGE="$1"
  if progress_on; then printf '@@mbm stage %s %s\n' "$1" "$2"; fi
}

progress_fail() { # [id]  (default: the stage that was running)
  if progress_on; then printf '@@mbm fail %s\n' "${1:-$MBM_STAGE}"; fi
}

progress_done() {
  if progress_on; then printf '@@mbm done\n'; fi
}

# progress_filter: stdin -> stdout, plus "@@mbm count n m" after each
# package pacman/pacstrap/paru installs, so the UI can show package counts
# without pacman knowing about it. Piped (as here) pacman prints no "( n/m)"
# bar: the transaction's "Packages (m)" line (or "Package (m)" with
# VerbosePkgLists) gives the total and each "installing x..." line counts one.
# The tty form is matched too. Colour codes (warn/die, tools that colour
# anyway) and private-mode ones (cursor hide/show, "\e[?25l") are stripped:
# the UI's log box and the log file show plain text.
# Flushes per line: the UI reads live.
progress_filter() {
  awk '{
    gsub(/\033\[[?0-9;]*[A-Za-z]/, "")
    print
    if (match($0, /^\( *[0-9]+\/[0-9]+\) (installing|upgrading|reinstalling|downgrading) /)) {
      s = substr($0, RSTART, RLENGTH); gsub(/[^0-9\/]/, "", s); split(s, a, "/")
      printf "@@mbm count %d %d\n", a[1], a[2]
    } else if (match($0, /^Packages? \([0-9]+\)/)) {
      s = substr($0, RSTART, RLENGTH); gsub(/[^0-9]/, "", s); m = s + 0; n = 0
    } else if (m > 0 && n < m && $0 ~ /^(installing|upgrading|reinstalling|downgrading) [^ ]+\.\.\.$/) {
      printf "@@mbm count %d %d\n", ++n, m
    }
    fflush()
  }'
}
