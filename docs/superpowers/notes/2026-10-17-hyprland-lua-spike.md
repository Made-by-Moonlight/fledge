# Hyprland 0.56.2 under a Lua config: spike findings (2026-10-17)

Committed copy of the spike notes the Lua config work was built on (the spike's
working copy lived in the gitignored `.superpowers/`). Evidence screenshots were
not kept. Referenced by the design spec `docs/superpowers/specs/2026-10-17-hyprland-lua-design.md`
and by `dot-local/share/fledge/bin/fledge`.

## Headline
- Legacy string dispatch does NOT work under Lua: `hyprctl dispatch X` is evaluated as `return hl.dispatch(X)`. `workspace 2`, `exec kitty`, `layoutmsg …`, `submap reset`, `forcerendererreload` all fail (rc 7); `--batch` fails but returns rc 0. Quickshell `Hyprland.dispatch("workspace 2")` fails too (WARN). Lua forms work: `hyprctl dispatch 'hl.dsp.focus({workspace=2})'`.
- `hyprctl keyword` is refused under Lua ("Use eval") with rc 0 (silent breakage). `hyprctl eval '<lua>'` works (e.g. `hl.config({input={kb_layout="gb"}})`, validated). `hyprctl repl` prints return values. Both share the config's Lua state (globals callable).
- Queries unchanged: activewindow/clients/monitors/workspaces/layers/binds -j, submap, getoption, configerrors, notify, dismissnotify, reload, switchxkblayout.
- `binds -j` for Lua binds: dispatcher "__lua", arg opaque; descriptions kept; mouse binds report mouse:false.
- Config manager is chosen at session start; `hyprctl reload` never switches .conf<->Lua. hyprland.lua wins over hyprland.conf when present (works via uwsm/SDDM login).
- Lua session: no ".conf format" notice.

## Structure
- package.path includes ~/.config/hypr/?.lua and ?/init.lua; require("sub.mod") works; dofile(abs path) works; prepend state dir to package.path works. Full stdlib. Each reload = fresh Lua state (no module cache issue). `config.reloaded` fires every load; `hyprland.start` once.
- Missing dofile → error (guard with pcall/io.open). Syntax error in a required file: main file continues, error bar + configerrors. pcall-guarded generated file with an error loses only its own content. Syntax error in hyprland.lua itself on cold start → EMERGENCY MODE (only SUPER+Q/R/M binds).

## API mapping
- bind: `hl.bind("MODS + key", dsp_or_fn, opts)`; bindd→{description=}; bindel→{locked=true, repeating=true}; bindl→{locked=true}; bindr→{release=true}; bindm→hl.dsp.window.drag()/resize() on mouse:272/273 (binds -j reports mouse:false but works). Unknown opts silently accepted. Action arrays → function bind.
- Submap: `hl.define_submap("mbm-record", function() hl.bind("SUPER + CTRL + ALT + Escape", hl.dsp.submap("reset")) end)`; binds -j shows submap:"mbm-record".
- Rules: `hl.window_rule({match={class=…}, tag="+x"})`, `{match={tag=…}, float=true, center=true, size="875 600"}`, `workspace="9 silent"`; `hl.layer_rule({match={namespace=…}, no_anim=true / blur=true})`. Fields validated. Regex full-match anchored (same as legacy).
- env → hl.env; exec-once → hl.on("hyprland.start", fn); monitor → hl.monitor({output, mode, position, scale, disabled, transform}); workspace rule → hl.workspace_rule({workspace, monitor, persistent, default, layout}); bezier → hl.curve(name,{type="bezier",points=…}); animation → hl.animation({leaf, enabled, speed, bezier, style}); theme colours: theme file returns a table (dofile); gradients {colors={…}, angle=}; devices hl.device({name, enabled}).
- No legacy-string dispatcher in hl.dsp (global() is the global-shortcut dispatcher). exec_cmd(cmd, rules) applies exec rules; exec_raw doesn't. Lua function binds work; runtime errors → configerrors.
- Gotcha: unknown keys in dispatcher tables are silently ignored (window.move({workspace=4, silent=true}) follows; correct key follow=false).

## Dispatcher table (legacy → Lua; ✓ = verified)
exec→exec_cmd ✓ · workspace N/e+1/previous→focus({workspace=…}) ✓ · movetoworkspace→window.move({workspace=N}) ✓ · movetoworkspacesilent→window.move({workspace=N, follow=false}) ✓ · togglespecialworkspace→workspace.toggle_special("x") ✓ · movefocus→focus({direction}) · focusmonitor→focus({monitor="+1"}) · focuswindow→focus({window="address:…"}) ✓ · swapwindow→window.swap({direction}) · resizeactive→window.resize({x,y,relative=true}) ✓ / exact={x,y,exact=true} ✓ · movecurrentworkspacetomonitor→workspace.move({monitor}) · togglefloating→window.float({action="toggle"}) ✓ · fullscreen 0→window.fullscreen() ✓, 1→({mode="maximized"}) ✓ · fullscreenstate→window.fullscreen_state({internal,client}) · killactive/closewindow→window.close({window?}) ✓ · pseudo→window.pseudo() · bringactivetotop→window.bring_to_top() · cyclenext→window.cycle_next() ✓, prev→cycle_next(false) (unconfirmed) · togglegroup→group.toggle() ✓ · moveintogroup→window.move({into_group="l"}) · moveoutofgroup→({out_of_group=true}) · changegroupactive→group.active({index})/next()/prev() · layoutmsg→layout("x") · sendshortcut→send_shortcut({mods,key,window}) · submap→submap("x") ✓ · dpms→dpms({action="on"}) ✓ · tagwindow→window.tag({tag}) ✓ · setprop→window.set_prop({prop,value}) · forcerendererreload→force_renderer_reload() · exit→exit() · mouse movewindow/resizewindow→window.drag() ✓/window.resize().

## Call sites that break (silently where rc 0)
- Shell QML: KeyRecorder.qml:34,47 (submap); shell.qml:26 (submap reset), :62; Lock.qml:94,116 and Idle.qml:51 (dpms). Installer shell.qml:67 (forcerendererreload), Xkb.qml:37-38 (keyword → eval, verified live).
- slievr-* scripts: 24 dispatch, 12 keyword, 2 --batch (keyword: cursor:invisible, device enable, monitor scale, workspace layout, debug:suppress_errors); settings.json zoom binds use `hyprctl keyword cursor:zoom_factor`.
- bootstrap.sh:391 `keyword env SHELL` → eval 'hl.env(...)'. hyprland.lua must be stowed before first login.
- verify-shell.sh:61, vm.sh:92, installer/dev/run.sh:16 (dispatch exec).
- Live ISO hyprland.conf → .lua (dismissnotify workaround goes; dispatch exit → hl.dsp.exit()).

## Side finding (bug from the fledge rename)
- The settings window title is now "fledge · settings", but the repo's window rule matches `^made by moonlight . settings$`, so it no longer floats/sizes. Fix in the migration (and it's wrong on main today).

## Recommended approach (spike)
One PR on a branch (managers can't mix): hand-port static config to a modular hyprland.lua; generated files loaded via a guarded loader; generators emit Lua from structured actions (with settings migration); every IPC caller through one helper per language (QML `Hypr` singleton; bash `mbm hypr dispatch|set` as the start of project B); verify by VM relogin; land before 0.57.
