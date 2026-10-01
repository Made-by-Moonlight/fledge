# made by moonlight Desktop Theme Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The installed system boots into a made by moonlight desktop (login screen, lock screen, Moonrise wallpaper, themed Hyprland/waybar/walker/mako/terminals), and the five defects from the first ISO VM run are fixed.

**Architecture:** A real Omarchy theme at `dot-config/omarchy/themes/made-by-moonlight/` (`colors.toml` + generated images + pandora's non-templated files) is rendered by `cachyos/branding/render-theme.sh` through Omarchy 3.8.2's templates (vendored into the repo) into the committed `dot-config/omarchy/current/theme/`. Images come from `cachyos/branding/build-assets.sh` (extended). hyprlock and SDDM get hand-written layouts that use those images and colours.

**Tech Stack:** bash, ImageMagick (`magick`), `rsvg-convert`, Omarchy theme templates, Hyprland/hyprlock config, SDDM QML (Qt 5, `QtQuick 2.0`), libvirt for the VM.

**Spec:** `docs/superpowers/specs/2026-10-01-desktop-theme-design.md`

## Global Constraints

- Work in the worktree `/home/slievr/proj/slievr-cachy-iso` on branch `custom-iso`. Stage only explicit paths; never stage `.superpowers/` or `release/`.
- Brand name **"made by moonlight"** (lowercase). Internal directory names containing `slievr-cachy` stay as they are.
- `colors.toml` exactly as the spec's block (accent/cursor `#f4af03`, foreground `#ffffff`, background `#171e28`, selection `#171e28` on `#f4af03`, color0–15 as listed).
- Wallpaper **Moonrise**: background `#171e28`, radial glow `#222c39`→`#171e28` from the top, white owl 22% of the width at 90% opacity, centred, top edge at 38% of the height. Sizes 3440×1440, 2560×1440, 1920×1080. `glow.png` = same glow, 1920×1080, **no owl**.
- Focus = **amber** (`accent`). Login/lock: owl, wordmark "made by moonlight" in `JetBrainsMono Nerd Font` letter-spaced, field `#212a33` with `#2f3640` border (`#e5626a` on failure), amber dots.
- Templates: Omarchy **3.8.2**, from `~/.local/share/omarchy/default/themed/*.tpl` (17 files) on this host.
- Out of scope: apps without a template keep pandora's files; `slievr-theme-set` on fresh installs; SDDM/Plymouth directory renames.
- `set -euo pipefail` in new scripts (`set -uo pipefail` in test scripts). `shellcheck -x` clean except pre-existing SC1091 infos. No `sudo`. Docker usable without sudo. Do not touch libvirt/VMs except where a task says so (none do; the VM run is controller-driven).
- Existing tests must stay green: `cachyos/install/test-detect.sh` (26), `test-answers.sh` (8), `cachyos/iso/test-mbm.sh` (14), `cachyos/branding/test-branding.sh`.

## File Structure

| File | Responsibility |
| --- | --- |
| `cachyos/bootstrap.sh`, `cachyos/iso/test/verify-install.sh`, `cachyos/vm/provision-vm.sh`, `cachyos/iso/bin/slievr-iso-boot`, `.../usr/local/bin/mbm-configurator`, `cachyos/iso/builder/build-iso.sh` | Task 1 fixes |
| `dot-local/share/slievr-cachy/default/themed/*.tpl` + `README.md` + `LICENSE` | vendored Omarchy templates |
| `cachyos/branding/render-theme.sh` | theme dir + templates → rendered theme dir |
| `cachyos/branding/test-theme.sh` | render tests + drift check |
| `cachyos/branding/build-assets.sh`, `test-branding.sh` | + wallpapers, glow, owl, SDDM images |
| `dot-config/omarchy/themes/made-by-moonlight/` | the theme source |
| `dot-config/omarchy/current/{theme/,theme.name,background}` | rendered, committed |
| `dot-config/hypr/hyprlock.conf` | lock layout |
| `cachyos/sddm-theme/slievr-cachy/Main.qml` (+ images) | login layout |

---

### Task 1: Fixes from the first VM run

**Files:** Modify `cachyos/bootstrap.sh:144-147`, `cachyos/iso/test/verify-install.sh:13`, `cachyos/vm/provision-vm.sh:56`, `cachyos/iso/bin/slievr-iso-boot` (end), `cachyos/iso/configs/airootfs/usr/local/bin/mbm-configurator` (gum exports + `show_owl`), `cachyos/iso/builder/build-iso.sh` (owl render line).

**Interfaces:** none consumed; produces nothing later tasks use.

- [ ] **Step 1: `~/.config` must exist before stow**

In `cachyos/bootstrap.sh`, replace

```bash
mkdir -p "$HOME/.local/share" "$HOME/.local/bin"
```

with

```bash
mkdir -p "$HOME/.local/share" "$HOME/.local/bin" "$HOME/.local/state" "$HOME/.config"
```

and extend the comment block above it with one line: `# ~/.config too: without it stow folds the whole directory into one symlink to dot-config/, and every app then writes its settings into the repo.`

- [ ] **Step 2: verify-install.sh**

Replace the boot-count line with

```bash
is "exactly one boot (no hang/retry)"  1      "$(journalctl --list-boots --no-pager --no-legend | grep -c .)"
```

and add after the `bootstrap.sh is executable` check:

```bash
is "~/.config is a real directory"     yes    "$( [[ -d ~/.config && ! -L ~/.config ]] && echo yes || echo no )"
```

- [ ] **Step 3: emulated TPM in the test VM**

In `cachyos/vm/provision-vm.sh`, add `  --tpm emulator \` on the line after `  --boot uefi \`. (`swtpm` is already in `host-deps.sh`.)

- [ ] **Step 4: start the installed system after the install**

Append to `cachyos/iso/bin/slievr-iso-boot`, after its final `echo`:

```bash
# virt-install's first boot powers the VM off at the installer's reboot
# instead of restarting it. Wait for that, then boot the installed system.
V=(virsh -c qemu:///system)
echo "Waiting for the install to finish and the VM to power off (Ctrl-C stops waiting)..."
until [[ "$("${V[@]}" domstate cachyos-test 2>/dev/null)" == "shut off" ]]; do sleep 10; done
"${V[@]}" start cachyos-test
echo "Booting the installed system."
```

- [ ] **Step 5: installer cosmetics**

In `mbm-configurator`, add `export GUM_CONFIRM_PROMPT_FOREGROUND=7` next to the other `GUM_*` exports (slot 7 = text colour), and change `--cols 48` to `--cols 40` in `show_owl`. In `cachyos/iso/builder/build-iso.sh`, change the `render-console.py ... --cols 48 --ansi` line to `--cols 40`. (16 rows of owl plus the prompt overflowed the 25-row console; 40 cols ≈ 13 rows.)

- [ ] **Step 6: Verify and commit**

Run: `bash -n` on all six files; `shellcheck -x` on the five shell scripts; `bash cachyos/iso/test-mbm.sh`; `python3 cachyos/branding/render-console.py cachyos/branding/owl.svg --cols 40 | wc -l` (expect ≤ 14).

```bash
git add cachyos/bootstrap.sh cachyos/iso/test/verify-install.sh cachyos/vm/provision-vm.sh \
  cachyos/iso/bin/slievr-iso-boot cachyos/iso/configs/airootfs/usr/local/bin/mbm-configurator cachyos/iso/builder/build-iso.sh
git commit -m "fix: ~/.config before stow; boot-count check; VM TPM + restart after install; installer cosmetics"
```

---

### Task 2: Vendored templates + `render-theme.sh`

**Files:** Create `dot-local/share/slievr-cachy/default/themed/` (17 `.tpl`, `README.md`, `LICENSE`), `cachyos/branding/render-theme.sh`, `cachyos/branding/test-theme.sh`.

**Interfaces:**
- Produces: `render-theme.sh [THEME_DIR] [OUT_DIR]` (defaults `dot-config/omarchy/themes/made-by-moonlight` → `dot-config/omarchy/current/theme`). Deletes and recreates `OUT_DIR`, copies `THEME_DIR` in, then renders each vendored template whose output name doesn't already exist. Substitutions per `colors.toml` key: `{{ key }}` → value, `{{ key_strip }}` → value without `#`, `{{ key_rgb }}` → `r,g,b` for `#` values. Exits 1 with a message if `THEME_DIR/colors.toml` is missing or `OUT_DIR` is empty or `/`.
- Produces: `test-theme.sh` (later Task 4 appends to it).

- [ ] **Step 1: Vendor the templates**

```bash
mkdir -p dot-local/share/slievr-cachy/default/themed
cp ~/.local/share/omarchy/default/themed/*.tpl dot-local/share/slievr-cachy/default/themed/
cp ~/.local/share/omarchy/LICENSE dot-local/share/slievr-cachy/default/themed/LICENSE
ls dot-local/share/slievr-cachy/default/themed/*.tpl | wc -l      # expect 17
```

`dot-local/share/slievr-cachy/default/themed/README.md`:

```markdown
# Vendored Omarchy theme templates

From Omarchy 3.8.2 (`default/themed/`), MIT licensed (see `LICENSE`).
`cachyos/branding/render-theme.sh` fills them from a theme's `colors.toml`
the same way `slievr-theme-set-templates` does, so a theme can be rendered
without an Omarchy install. Update by copying a newer Omarchy's
`default/themed/*.tpl` over these and re-running render-theme.sh.
```

- [ ] **Step 2: Failing test**

`cachyos/branding/test-theme.sh`:

```bash
#!/usr/bin/env bash
# Tests for render-theme.sh (and, from Task 4, the committed theme render).
#   bash cachyos/branding/test-theme.sh
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$DIR/../.." && pwd)"
# shellcheck source=SCRIPTDIR/../install/test/lib.sh
source "$DIR/../install/test/lib.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
RENDER="$DIR/render-theme.sh"

# fixture theme: every key the templates use, distinctive values
mkdir -p "$T/theme"
cat > "$T/theme/colors.toml" <<'EOF'
accent = "#123456"
cursor = "#123457"
foreground = "#fedcba"
background = "#abcdef"
selection_foreground = "#111111"
selection_background = "#222222"
color0 = "#000000"
color1 = "#010101"
color2 = "#020202"
color3 = "#030303"
color4 = "#040404"
color5 = "#050505"
color6 = "#060606"
color7 = "#070707"
color8 = "#080808"
color9 = "#090909"
color10 = "#0a0a0a"
color11 = "#0b0b0b"
color12 = "#0c0c0c"
color13 = "#0d0d0d"
color14 = "#0e0e0e"
color15 = "#0f0f0f"
EOF
echo "theme-provided kitty" > "$T/theme/kitty.conf"

bash "$RENDER" "$T/theme" "$T/out" >/dev/null
check "render: every template rendered or provided" "17" \
  "$(cd "$REPO/dot-local/share/slievr-cachy/default/themed" && for f in *.tpl; do [[ -e "$T/out/${f%.tpl}" ]] && echo x; done | wc -l | tr -d ' ')"
check "render: no {{ placeholders left" "" "$(grep -rl '{{' "$T/out" || true)"
check "render: theme file wins over template" "theme-provided kitty" "$(cat "$T/out/kitty.conf")"
contains "render: _strip form (hyprland accent)" "rgb(123456)" "$(cat "$T/out/hyprland.conf")"
contains "render: _rgb form (hyprlock background)" "rgba(171,205,239" "$(tr -d ' ' < "$T/out/hyprlock.conf")"
contains "render: plain form (waybar background)" "#abcdef" "$(cat "$T/out/waybar.css")"
check "render: colors.toml copied" "yes" "$([[ -f "$T/out/colors.toml" ]] && echo yes || echo no)"

echo stale > "$T/out/stale.txt"
bash "$RENDER" "$T/theme" "$T/out" >/dev/null
check "render: output dir is rebuilt clean" "no" "$([[ -e "$T/out/stale.txt" ]] && echo yes || echo no)"
check "render: missing colors.toml is an error" "1" "$(bash "$RENDER" "$T/nope" "$T/out2" 2>/dev/null; echo $?)"

exit $fail
```

Run: `bash cachyos/branding/test-theme.sh` → FAIL (no render-theme.sh).

- [ ] **Step 3: Implement `render-theme.sh`**

```bash
#!/usr/bin/env bash
# Render an Omarchy-style theme (colors.toml + files) into a theme directory,
# filling the vendored Omarchy templates the way slievr-theme-set-templates
# does. Files the theme provides win over templates.
#   cachyos/branding/render-theme.sh [THEME_DIR] [OUT_DIR]
# Defaults: dot-config/omarchy/themes/made-by-moonlight -> dot-config/omarchy/current/theme
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
THEME="${1:-$REPO/dot-config/omarchy/themes/made-by-moonlight}"
OUT="${2:-$REPO/dot-config/omarchy/current/theme}"
TEMPLATES="$REPO/dot-local/share/slievr-cachy/default/themed"
COLORS="$THEME/colors.toml"
die() { echo "render-theme: $*" >&2; exit 1; }

[[ -f "$COLORS" ]] || die "no colors.toml in $THEME"
[[ -n "$OUT" && "$OUT" != / ]] || die "refusing to use '$OUT' as the output directory"

hex_to_rgb() { local hex="${1#\#}"; printf '%d,%d,%d' "0x${hex:0:2}" "0x${hex:2:2}" "0x${hex:4:2}"; }

sed_script="$(mktemp)"
trap 'rm -f "$sed_script"' EXIT
while IFS='=' read -r key value; do
  key="${key//[\"\' ]/}"
  [[ -n "$key" && "$key" != \#* ]] || continue
  value="${value#*[\"\']}"; value="${value%%[\"\']*}"
  printf 's|{{ %s }}|%s|g\n' "$key" "$value"
  printf 's|{{ %s_strip }}|%s|g\n' "$key" "${value#\#}"
  if [[ "$value" == \#* ]]; then
    printf 's|{{ %s_rgb }}|%s|g\n' "$key" "$(hex_to_rgb "$value")"
  fi
done < "$COLORS" > "$sed_script"

rm -rf "$OUT"
mkdir -p "$OUT"
cp -a "$THEME/." "$OUT/"
shopt -s nullglob
for tpl in "$TEMPLATES"/*.tpl; do
  name="$(basename "$tpl" .tpl)"
  [[ -e "$OUT/$name" ]] || sed -f "$sed_script" "$tpl" > "$OUT/$name"
done
echo "rendered ${THEME#"$REPO"/} -> ${OUT#"$REPO"/}"
```

Run: `chmod +x cachyos/branding/render-theme.sh && bash cachyos/branding/test-theme.sh` → 9 PASS. If a template uses a key the fixture lacks, the `{{` check names the file: add the key to the fixture (and tell the controller in the report).

- [ ] **Step 4: Lint and commit**

`shellcheck -x cachyos/branding/render-theme.sh cachyos/branding/test-theme.sh` → clean.

```bash
git add dot-local/share/slievr-cachy/default/themed cachyos/branding/render-theme.sh cachyos/branding/test-theme.sh
git commit -m "branding: vendor Omarchy 3.8.2 theme templates; render-theme.sh"
```

---

### Task 3: Theme images (wallpapers, glow, owl, SDDM)

**Files:** Modify `cachyos/branding/build-assets.sh`, `cachyos/branding/test-branding.sh`. Generated: `dot-config/omarchy/themes/made-by-moonlight/{backgrounds/1-moonrise-3440x1440.png,backgrounds/2-moonrise-2560x1440.png,backgrounds/3-moonrise-1920x1080.png,glow.png,owl.png,preview.png}`, `cachyos/sddm-theme/slievr-cachy/{logo.png,background.png}`.

**Interfaces:**
- Produces (theme dir): `owl.png` = white owl centred on a **transparent 520×520 square** (hyprlock's image widget is square); `glow.png` 1920×1080; `preview.png` 1280×720 (downscale of the 1920 wallpaper). SDDM: `logo.png` white owl 260 px wide (not square), `background.png` = copy of `glow.png`.

- [ ] **Step 1: Failing tests**

Append to `test-branding.sh`, before `exit $fail` (it already builds into `$T/assets` and has `$repo`):

```bash
# theme + SDDM images
theme_rel=dot-config/omarchy/themes/made-by-moonlight
sddm_rel=cachyos/sddm-theme/slievr-cachy
for spec in "backgrounds/1-moonrise-3440x1440.png 3440x1440" "backgrounds/2-moonrise-2560x1440.png 2560x1440" \
            "backgrounds/3-moonrise-1920x1080.png 1920x1080" "glow.png 1920x1080" "owl.png 520x520" "preview.png 1280x720"; do
  f="${spec% *}"; want="${spec#* }"
  check "theme $f is $want" "$want" "$(magick identify -format '%wx%h' "$T/assets/$theme_rel/$f" 2>/dev/null)"
  check "theme $f is current" "0" \
    "$(magick compare -metric AE "$repo/$theme_rel/$f" "$T/assets/$theme_rel/$f" null: 2>&1 | awk '{print $1}')"
done
check "sddm logo is 260px wide" "260" "$(magick identify -format '%w' "$T/assets/$sddm_rel/logo.png" 2>/dev/null)"
for f in logo.png background.png; do
  check "sddm $f is current" "0" \
    "$(magick compare -metric AE "$repo/$sddm_rel/$f" "$T/assets/$sddm_rel/$f" null: 2>&1 | awk '{print $1}')"
done
check "glow has no owl (centre pixel is background-ish)" "yes" \
  "$(magick "$T/assets/$theme_rel/glow.png" -format '%[fx:p{960,600}.r<0.2 ? "yes" : "no"]' info:)"
check "moonrise has the owl (white near the centre)" "yes" \
  "$(magick "$T/assets/$theme_rel/backgrounds/3-moonrise-1920x1080.png" -crop 422x200+749+411 -format '%[fx:maxima.r>0.8 ? "yes" : "no"]' info:)"
```

Run: `bash cachyos/branding/test-branding.sh` → the new checks FAIL.

- [ ] **Step 2: Extend `build-assets.sh`**

After the Plymouth logo block, add:

```bash
# Desktop theme + SDDM images (spec: Moonrise wallpaper, glow, owl).
THEME_DIR="$OUT/dot-config/omarchy/themes/made-by-moonlight"
SDDM_DIR="$OUT/cachyos/sddm-theme/slievr-cachy"
mkdir -p "$THEME_DIR/backgrounds" "$SDDM_DIR"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

white_owl() { # <width> <out.png>
  sed 's/currentColor/#ffffff/g' "$SVG" | rsvg-convert -w "$1" -o "$2"
}
glow() { # <w> <h> <out.png>: #171e28 with a faint radial glow from the top
  local w=$1 h=$2
  magick -size "${w}x${h}" xc:'#171e28' \
    \( -size "$((w * 7 / 5))x$((h * 6 / 5))" radial-gradient:'#222c39'-'#171e28' \) \
    -gravity north -geometry "+0-$((h * 3 / 10))" -composite "$3"
}
moonrise() { # <w> <h> <out.png>: glow + white owl, 22% wide, 90% opacity, top at 38%
  local w=$1 h=$2
  glow "$w" "$h" "$TMP/glow-$w.png"
  white_owl "$((w * 22 / 100))" "$TMP/owl-$w.png"
  magick "$TMP/glow-$w.png" \( "$TMP/owl-$w.png" -channel A -evaluate multiply 0.9 +channel \) \
    -gravity north -geometry "+0+$((h * 38 / 100))" -composite "$3"
}

moonrise 3440 1440 "$THEME_DIR/backgrounds/1-moonrise-3440x1440.png"
moonrise 2560 1440 "$THEME_DIR/backgrounds/2-moonrise-2560x1440.png"
moonrise 1920 1080 "$THEME_DIR/backgrounds/3-moonrise-1920x1080.png"
magick "$THEME_DIR/backgrounds/3-moonrise-1920x1080.png" -resize 1280x720 "$THEME_DIR/preview.png"
glow 1920 1080 "$THEME_DIR/glow.png"
white_owl 520 "$TMP/owl-520.png"
magick -size 520x520 xc:none "$TMP/owl-520.png" -gravity center -composite "$THEME_DIR/owl.png"
white_owl 260 "$SDDM_DIR/logo.png"
cp "$THEME_DIR/glow.png" "$SDDM_DIR/background.png"
```

and change the final `echo` to `echo "updated about.txt, the Plymouth logo, the theme images and the SDDM images under $OUT"`.

- [ ] **Step 3: Generate, check, look**

Run: `bash cachyos/branding/build-assets.sh` (writes into the repo), then `bash cachyos/branding/test-branding.sh` → all PASS. Look at `dot-config/omarchy/themes/made-by-moonlight/backgrounds/3-moonrise-1920x1080.png` (Read it as an image) and confirm: dark `#171e28`, faint lighter glow at the top, a white owl centred a little above the middle. Describe what you see in the report.

- [ ] **Step 4: Commit**

```bash
git add cachyos/branding/build-assets.sh cachyos/branding/test-branding.sh \
  dot-config/omarchy/themes/made-by-moonlight cachyos/sddm-theme/slievr-cachy/logo.png cachyos/sddm-theme/slievr-cachy/background.png
git commit -m "branding: Moonrise wallpapers, glow, owl and SDDM images"
```

---

### Task 4: The theme and its committed render

**Files:** Create `dot-config/omarchy/themes/made-by-moonlight/colors.toml` + pandora's non-templated files; regenerate `dot-config/omarchy/current/theme/`; modify `dot-config/omarchy/current/theme.name`, `dot-config/omarchy/current/background` (symlink); modify `cachyos/branding/test-theme.sh`.

**Interfaces:** Consumes `render-theme.sh` (Task 2) and the images (Task 3).

- [ ] **Step 1: `colors.toml`** — write exactly the spec's block to `dot-config/omarchy/themes/made-by-moonlight/colors.toml`.

- [ ] **Step 2: carry pandora's non-templated files**

These have no template, so the theme keeps pandora's versions unchanged (spec: out of scope):

```bash
cd dot-config/omarchy/current/theme
cp -a bypass-clock.css cava_theme colors.fish dock.css firefox.css fzf.fish gtk.css hyprbars.conf icons.theme \
  neovim.lua qt6ct.conf round-logo.svg spicetify_color.ini steam.css vencord.theme.css vicinae.toml \
  vscode_colors.json vscode.json zed.json zen.css ../../themes/made-by-moonlight/
cd -
```

If any listed file doesn't exist, skip it and say so in the report; don't copy templated outputs (alacritty.toml, chromium.theme, ghostty.conf, gum.env.conf, hyprland.conf, hyprlock.conf, kitty.conf, mako.ini, swayosd.css, walker.css, waybar.css) or pandora's images.

- [ ] **Step 3: Failing drift test**

Append to `test-theme.sh` before `exit $fail`:

```bash
# the committed render matches a fresh render of the real theme
bash "$RENDER" "$REPO/dot-config/omarchy/themes/made-by-moonlight" "$T/real" >/dev/null
check "committed current/theme matches a fresh render" "" \
  "$(diff -rq "$REPO/dot-config/omarchy/current/theme" "$T/real" 2>&1)"
check "theme.name" "made-by-moonlight" "$(cat "$REPO/dot-config/omarchy/current/theme.name")"
check "background link points at Moonrise 3440" \
  "/home/slievr/.config/omarchy/current/theme/backgrounds/1-moonrise-3440x1440.png" \
  "$(readlink "$REPO/dot-config/omarchy/current/background")"
contains "kitty uses the brand background" "171e28" "$(cat "$T/real/kitty.conf")"
contains "hyprland focus border is amber" "rgb(f4af03)" "$(cat "$T/real/hyprland.conf")"
```

Run → these FAIL (current/theme is still pandora).

- [ ] **Step 4: Render and repoint**

```bash
bash cachyos/branding/render-theme.sh
echo made-by-moonlight > dot-config/omarchy/current/theme.name
ln -sfn /home/slievr/.config/omarchy/current/theme/backgrounds/1-moonrise-3440x1440.png dot-config/omarchy/current/background
bash cachyos/branding/test-theme.sh     # all PASS
```

Spot-check: `grep -n 'background\|foreground' dot-config/omarchy/current/theme/kitty.conf | head` shows `#171e28` / `#ffffff`.

- [ ] **Step 5: Commit** (deletions of pandora's rendered files and images are expected)

```bash
git add -A dot-config/omarchy/themes/made-by-moonlight dot-config/omarchy/current cachyos/branding/test-theme.sh
git commit -m "theme: made by moonlight colours, rendered into current/theme"
```

(`git add -A` is restricted to those paths, which is allowed: it records the deleted pandora files.)

---

### Task 5: Lock screen and login screen layouts

**Files:** Modify `dot-config/hypr/hyprlock.conf` (rewrite), `cachyos/sddm-theme/slievr-cachy/Main.qml` (rewrite visuals), `cachyos/sddm-theme/slievr-cachy/metadata.desktop` (description only, if it says SLIEVR); delete now-unused `bullet.png entry.png entry-failed.png lock.png lock-failed.png` in that directory.

**Interfaces:** Consumes theme `glow.png`, `owl.png`, the rendered `hyprlock.conf` variables (`$color $font_color $check_color`), SDDM `logo.png` and `background.png`.

- [ ] **Step 1: `hyprlock.conf`**

Replace the whole file with:

```
source = ~/.config/omarchy/current/theme/hyprlock.conf

general {
    ignore_empty_input = true
}

background {
    monitor =
    color = $color
    path = ~/.config/omarchy/current/theme/glow.png
    blur_passes = 2
}

animations {
    enabled = false
}

label {
    monitor =
    text = cmd[update:1000] date +"%H:%M"
    color = $font_color
    font_size = 96
    font_family = JetBrainsMono Nerd Font
    position = 0, 300
    halign = center
    valign = center
}

image {
    monitor =
    path = ~/.config/omarchy/current/theme/owl.png
    size = 260
    rounding = 0
    border_size = 0
    position = 0, 70
    halign = center
    valign = center
}

input-field {
    monitor =
    size = 420, 64
    position = 0, -150
    halign = center
    valign = center

    inner_color = rgba(33, 42, 51, 1.0)
    outer_color = rgba(47, 54, 64, 1.0)
    outline_thickness = 2

    font_family = JetBrainsMono Nerd Font
    font_color = rgba(244, 175, 3, 1.0)
    placeholder_text =
    check_color = $check_color
    fail_color = rgba(229, 98, 106, 1.0)
    fail_text = <i>$FAIL ($ATTEMPTS)</i>
    dots_center = true

    rounding = 0
    shadow_passes = 0
    fade_on_empty = false
}

auth {
    fingerprint:enabled = false
}
```

- [ ] **Step 2: SDDM `Main.qml`**

Keep everything from `property string currentUser` through the `Connections { ... }` block and the `TextInput`'s behaviour (echoMode, transparent colours, `onTextChanged`, `Keys.onPressed` login call, `focus`) exactly as they are. Replace the root colour and the visual tree:

```qml
import QtQuick 2.0
import SddmComponents 2.0

Rectangle {
  id: root
  width: 640
  height: 480
  color: "#171e28"

  // ... currentUser, loginFailed, sessionIndex, Connections: unchanged ...

  Image {
    anchors.fill: parent
    source: "background.png"
    fillMode: Image.PreserveAspectCrop
  }

  Column {
    anchors.centerIn: parent
    spacing: 26

    Image {
      id: logo
      source: "logo.png"
      width: 260
      height: sourceSize.width > 0 ? Math.round(width * sourceSize.height / sourceSize.width) : 0
      fillMode: Image.PreserveAspectFit
      anchors.horizontalCenter: parent.horizontalCenter
    }

    Text {
      text: "made by moonlight"
      color: "#ffffff"
      font.family: "JetBrainsMono Nerd Font"
      font.pixelSize: 18
      font.letterSpacing: 9
      anchors.horizontalCenter: parent.horizontalCenter
    }

    Text {
      text: root.currentUser
      color: "#6c7787"
      font.family: "JetBrainsMono Nerd Font"
      font.pixelSize: 13
      anchors.horizontalCenter: parent.horizontalCenter
    }

    Rectangle {
      id: field
      width: 360
      height: 44
      color: "#212a33"
      border.width: 2
      border.color: root.loginFailed ? "#e5626a" : "#2f3640"
      anchors.horizontalCenter: parent.horizontalCenter

      Row {
        anchors.left: parent.left
        anchors.leftMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6

        Repeater {
          model: Math.min(password.text.length, 32)
          Rectangle { width: 7; height: 7; radius: 3.5; color: "#f4af03" }
        }
      }

      TextInput {
        id: password
        anchors.fill: parent
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        // ... verticalAlignment, echoMode, font, passwordCharacter, transparent
        //     colours, cursorDelegate, focus, onTextChanged, Keys.onPressed: unchanged ...
      }
    }
  }

  Component.onCompleted: password.forceActiveFocus()
}
```

Write the real file in full (no `...` comments): the elided parts are copied verbatim from the current `Main.qml`. Then `git rm` the five unused PNGs.

- [ ] **Step 3: Check**

`/usr/lib/qt6/bin/qmllint cachyos/sddm-theme/slievr-cachy/Main.qml` if it exists — syntax errors must be zero; warnings about the `SddmComponents` import or `sddm`/`userModel`/`sessionModel` being unknown are expected (they're provided by SDDM at runtime). If qmllint isn't available, report that. `grep -n 'png' Main.qml` must list only `background.png` and `logo.png`. `grep -c '^\s*\(label\|image\|input-field\|background\) {' dot-config/hypr/hyprlock.conf` → 4.

- [ ] **Step 4: Commit**

```bash
git add dot-config/hypr/hyprlock.conf cachyos/sddm-theme/slievr-cachy/Main.qml cachyos/sddm-theme/slievr-cachy/metadata.desktop
git rm -q cachyos/sddm-theme/slievr-cachy/{bullet,entry,entry-failed,lock,lock-failed}.png
git commit -m "theme: made by moonlight lock screen and login screen"
```

(Skip `metadata.desktop` in `git add` if unchanged.)

---

### Task 6: Docs + ISO rebuild

**Files:** Modify `cachyos/branding/README.md`, `cachyos/sddm-theme/README.md`, `cachyos/NEXT-SESSION.md`, `docs/superpowers/specs/2026-10-01-desktop-theme-design.md` (Status line). Build: `release/*.iso`.

- [ ] **Step 1: Docs**
  - `cachyos/branding/README.md`: add rows for `render-theme.sh` ("renders `dot-config/omarchy/themes/made-by-moonlight` into `dot-config/omarchy/current/theme` through the vendored templates") and `test-theme.sh`; extend `build-assets.sh`'s row with the wallpapers, glow, owl and SDDM images; add a "Changing the theme" note: edit `colors.toml` or the mark → `build-assets.sh` → `render-theme.sh` → commit.
  - `cachyos/sddm-theme/README.md`: replace any "SLIEVR"/Omarchy-logo description with the made by moonlight layout and note `logo.png`/`background.png` are generated by `build-assets.sh`.
  - Spec `**Status:**` → `implemented (see plan)`.
- [ ] **Step 2: Rebuild the ISO** — commit Step 1 first (the ISO ships HEAD), then `cachyos/iso/bin/slievr-iso-make` (long; log to a file outside the repo). Then `(cd release && sha256sum -c ./*.sha256)` → OK.
- [ ] **Step 3: NEXT-SESSION** — replace the ISO file/sha256 line(s) in the made-by-moonlight ISO section with the new ISO name and sha256 (fixes the stale `d8a530bf…`), and add a line: "Desktop theme made-by-moonlight (login, lock, Moonrise wallpaper, themed apps) — VM run pending." Commit.

```bash
git add cachyos/NEXT-SESSION.md
git commit -m "docs: NEXT-SESSION — rebuilt ISO with the desktop theme"
```
