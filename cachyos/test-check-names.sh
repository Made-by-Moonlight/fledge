#!/usr/bin/env bash
# Tests for check-names.sh against temporary git trees: one holding every
# allowed form passes, and adding any one forbidden form to it fails.
#   bash cachyos/test-check-names.sh
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=SCRIPTDIR/install/test/lib.sh
source "$DIR/install/test/lib.sh"
GUARD="$DIR/check-names.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

put() { # <tree> <path> <line>...
  local tree=$1 path=$2; shift 2
  mkdir -p "$(dirname "$tree/$path")"
  printf '%s\n' "$@" >>"$tree/$path"
}

# The allowed tree: every exception the guard knows, plus unrelated words.
ok="$T/ok"
mkdir -p "$ok" && git -C "$ok" init -q
put "$ok" README.md '# fledge' 'by made by moonlight, Made By Moonlight' \
  'https://github.com/Made-by-Moonlight/fledge/releases/latest'
put "$ok" cachyos/bootstrap.sh 'DOTFILES_REPO="https://github.com/made-by-moonlight/fledge.git"'
put "$ok" cachyos/install/profile.sh 'USERNAME="slievr"          # default'
put "$ok" cachyos/vm/vm.sh 'VM_USER="${VM_USER:-slievr}"'
put "$ok" cachyos/vm/dev-up.sh 'VM_USER="slievr"'
put "$ok" cachyos/vm/README.md 'repo at `~slievr/proj/fledge` and' 'sets up key auth (via `expect`, using `slievr` / `$VM_PASSWORD`'
put "$ok" cachyos/iso/README.md '    scp verify-install.sh "slievr@$ip:/tmp/"'
put "$ok" cachyos/iso/test/verify-install.sh '# Run as slievr on the installed system' '#   ssh -t "slievr@$ip" bash'
put "$ok" AGENTS.md '`slievr` is the user'"'"'s handle (and the default username), not the brand' \
  '   The old names (`slievr`, `mbm`, `made-by-moonlight`) are gone, and'
put "$ok" dot-local/share/fledge/test/test-migrate.sh '# b970944:dot-local/share/mbm/defaults/settings.json' \
  '| gsub("^slievr "; "fledge ")'
put "$ok" dot-local/share/fledge/test/fixtures/defaults-v1.json '{"exec": "slievr-menu", "mbm": 1}'
put "$ok" docs/superpowers/specs/2026-10-10-mbm-shell-design.md 'mbm shell, mbm-shell.service, MBM_X, slievr-cachy, made-by-moonlight'
put "$ok" docs/superpowers/notes/2026-10-17-spike.md 'slievr'
put "$ok" docs/superpowers/notes/2026-10-18-script-inventory.md 'slievr-menu'
put "$ok" dot-local/share/fledge/lib/check.jq '# Kept in step with docs/superpowers/specs/2026-10-10-mbm-shell-design.md.'
put "$ok" dot-config/hypr/rules.lua '-- Moonlight game streaming' 'mbmx ambm submbm'
put "$ok" dot-config/starship.toml 'palette = "moonlight"'

out="$(bash "$GUARD" "$ok" 2>&1)"; rc=$?
check "allowed forms pass" 0 "$rc"
contains "allowed forms report clean" "check-names: clean" "$out"

n=0
bad() { # <description> <path> <line>
  local tree="$T/bad$((++n))" out rc
  cp -a "$ok" "$tree"
  put "$tree" "$2" "$3"
  out="$(bash "$GUARD" "$tree" 2>&1)"; rc=$?
  check "fails: $1" 1 "$rc"
  contains "names the file: $1" "$2" "$out"
}
bad "slievr" cachyos/x.sh 'slievr'
bad "Slievr, any case" cachyos/x.sh 'Slievr desktop'
bad "slievr- script" dot-local/share/fledge/libexec/x 'exec slievr-menu'
bad "slievr-cachy path" cachyos/x.sh 'cd ~/proj/slievr-cachy'
bad "mbm word" cachyos/x.sh 'run mbm settings apply'
bad "@@mbm marker" cachyos/x.sh 'echo "@@mbm stage"'
bad "mbm- prefix" cachyos/x.sh 'systemctl --user restart mbm-shell'
bad "mbm_ prefix" cachyos/x.sh 'mbm_online'
bad "MBM_ env var" cachyos/x.sh 'export MBM_PROGRESS=1'
bad "made-by-moonlight" dot-config/x.toml 'theme = "made-by-moonlight"'
bad "Made_By_Moonlight" dot-config/x.toml 'Made_By_Moonlight'
bad "madebymoonlight" dot-config/x.toml 'madebymoonlight'
bad "a name in a path" cachyos/mbm-thing.sh 'clean'
bad "slievr outside its allowed text" cachyos/install/profile.sh 'HOME=/home/slievr'
bad "an allowed URL and a bare name on one line" README.md 'https://github.com/made-by-moonlight/fledge made-by-moonlight'
bad "an old name in AGENTS.md beyond its two sentences" AGENTS.md '| A | **mbm shell** |'
bad "an allowed rule from another file" cachyos/x.sh 'VM_USER="slievr"'
bad "the org name outside the URL" README.md 'org: made-by-moonlight'
bad "another repo of the org" README.md 'https://github.com/made-by-moonlight-x/y'
bad "a doc dated on the rename day" docs/superpowers/specs/2026-10-18-other-design.md 'mbm'
bad "a doc dated after the rename" docs/superpowers/plans/2026-10-19-x.md 'slievr'
bad "a history name outside docs/superpowers" docs/2026-10-01-x.md 'slievr'
bad "a home path in test-theme.sh (its link is relative now)" cachyos/branding/test-theme.sh '/home/slievr/x.png'
bad "an untracked file" cachyos/new.sh 'mbm-x'

# Ignored files are not the repo's.
ign="$T/ignored"; cp -a "$ok" "$ign"
put "$ign" .gitignore 'release/'
put "$ign" release/notes.md 'mbm'
bash "$GUARD" "$ign" >/dev/null 2>&1
check "ignored files are skipped" 0 "$?"

exit $fail
