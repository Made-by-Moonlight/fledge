# fledge

The desktop's command line, one tree stowed to `~/.local/share/fledge/`:

| path | what |
|---|---|
| `bin/fledge` | the one command on PATH (the session's uwsm env adds `bin/`) |
| `libexec/` | the actions: `fledge <group> <action> [args]` runs `libexec/<group>-<action>` |
| `lib/` | `fledge settings` (`settings.sh`, the Hyprland generators `gen-*.jq`), `fledge dmenu` (`dmenu.sh`) |
| `defaults/settings.json` | the shipped settings (binds, bar, idle, …); user overrides go in `~/.config/mbm/settings.json` |
| `default/themed/` | app theme templates (`fledge theme set templates`) |
| `assets/` | the shell's wallpapers and owl |
| `test/` | unit suites (run them in the test VM, never on the host) |

## Commands

- `fledge help [group]` lists the groups, or a group's actions with each
  script's first comment line.
- `fledge settings get|set|reset|check|apply …` reads and writes settings and
  generates the Hyprland binds, monitors, workspaces and input.
- `fledge hypr dispatch|set|eval|quote …` is the one place that talks Lua to
  Hyprland.
- `fledge dmenu [--prompt P] [--select N] [--input-only]` asks the shell's
  launcher to pick from stdin.
- Anything else resolves by the longest run of leading words that names a
  script: `fledge capture screenshot region copy` runs
  `libexec/capture-screenshot region copy`. Only those command words must be
  lowercase `[a-z0-9_.]` words; the arguments after them pass through as
  given. Unknown commands exit 2 with the nearest matches.

Scripts call each other through `fledge <group> <action>`, never by path, so
the command surface is the only interface. A new action is a new executable
in `libexec/` named `<group>-<action>`, with a `#` comment after the shebang
that `fledge help` shows. Don't name one so that it is a prefix plus a word
of another script's argument: `libexec/menu-share` would have swallowed
`fledge menu share` (so that script is `libexec/share`).

## Where `libexec/` came from

The scripts started as a vendored copy of `bin/` from
[basecamp/omarchy](https://github.com/basecamp/omarchy) (at the version in
`VENDORED_VERSION`), MIT-licensed (see `LICENSE`, kept with Omarchy's
copyright). They are a permanent, independent fork: renamed, no longer
synced with upstream, and pruned to what the desktop reaches (a bind, the
shell, Hyprland autostart, the menu, or another kept script). Omarchy's
self-management commands, its install/remove menus, theme switching and
every web app script went; the inventory is in
`docs/superpowers/notes/2026-10-18-script-inventory.md`. Vendoring only these
self-contained bash scripts gives the binds their commands without
installing Omarchy, which would override the pacman mirrorlist and change
the system more broadly.
