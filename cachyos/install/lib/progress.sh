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

# progress_filter: stdin -> stdout unchanged, plus "@@mbm count n m" after each
# pacman/pacstrap/paru "( n/m) installing ..." line, so the UI can show package
# counts without pacman knowing about it. Flushes per line: the UI reads live.
progress_filter() {
  awk '{
    print
    if (match($0, /^\( *[0-9]+\/[0-9]+\) (installing|upgrading|reinstalling) /)) {
      s = substr($0, RSTART, RLENGTH); gsub(/[^0-9\/]/, "", s); split(s, a, "/")
      printf "@@mbm count %d %d\n", a[1], a[2]
    }
    fflush()
  }'
}
