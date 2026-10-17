# Settings v1 -> v2: legacy Hyprland dispatch strings -> structured actions.
# A library (jq -L lib 'include "migrate-dispatch"; ...'):
#   migrate_dispatch  legacy string -> {dsp, args?} (or {exec}), or null when unknown
#   needs_migration   user settings -> true when the file is version 1 or holds {dispatch}
#   migrate_user      user settings -> {settings: <version 2>, count: <binds converted>,
#                                       unconverted: <binds still holding {dispatch}, or the s flag>}
# Hyprland 0.57 drops the .conf format, and under a Lua config the legacy strings
# stop working. Only forms in this table are converted; anything else (other
# dispatchers, or arguments we can't map exactly) is left as {dispatch} for the
# user to rewrite, and `mbm settings check` names it. Never guess.

def _dir: {"l": "left", "r": "right", "u": "up", "d": "down"}[.];
# Plain workspace numbers become numbers; e+1, previous, name:x, special:x stay text.
def _ws: if test("^[0-9]+$") then tonumber else . end;
def _int: test("^-?[0-9]+$");
# One workspace token only: a target that names a window too ("3,address:0x…")
# or carries more words has no exact mapping here.
def _ws_ok: length > 0 and (test("[,\\s]") | not);

def migrate_dispatch:
  (capture("^\\s*(?<d>\\S+)\\s*(?<r>.*?)\\s*$") // {d: "", r: ""}) as {d: $d, r: $r}
  # `exec [rules] cmd`: {exec} has no place for the rules (hl.dsp.exec_cmd's
  # second argument), and running "[float] cmd" as a command would fail, so
  # it is left for the user, like anything else without an exact mapping.
  | if $d == "exec" and $r != "" and ($r | startswith("[") | not) then {exec: $r}
    elif $d == "workspace" and ($r | _ws_ok) then {dsp: "focus", args: {workspace: ($r | _ws)}}
    elif $d == "movetoworkspace" and ($r | _ws_ok) then {dsp: "window.move", args: {workspace: ($r | _ws)}}
    elif $d == "movetoworkspacesilent" and ($r | _ws_ok) then {dsp: "window.move", args: {workspace: ($r | _ws), follow: false}}
    elif $d == "togglespecialworkspace" and $r != "" then {dsp: "workspace.toggle_special", args: $r}
    elif $d == "movefocus" and ($r | _dir) then {dsp: "focus", args: {direction: ($r | _dir)}}
    elif $d == "focusmonitor" and $r != "" then {dsp: "focus", args: {monitor: $r}}
    elif $d == "swapwindow" and ($r | _dir) then {dsp: "window.swap", args: {direction: ($r | _dir)}}
    elif $d == "resizeactive" and ($r | split(" ") | map(select(. != "")) | length == 2 and all(_int)) then
      ($r | split(" ") | map(select(. != "") | tonumber)) as [$x, $y]
      | {dsp: "window.resize", args: {x: $x, y: $y, relative: true}}
    elif $d == "movecurrentworkspacetomonitor" and $r != "" then {dsp: "workspace.move", args: {monitor: $r}}
    elif $d == "togglefloating" and $r == "" then {dsp: "window.float", args: {action: "toggle"}}
    elif $d == "fullscreen" and ($r == "" or $r == "0") then {dsp: "window.fullscreen"}
    elif $d == "fullscreen" and $r == "1" then {dsp: "window.fullscreen", args: {mode: "maximized"}}
    elif $d == "fullscreenstate" and ($r | split(" ") | map(select(. != "")) | length == 2 and all(_int)) then
      ($r | split(" ") | map(select(. != "") | tonumber)) as [$i, $c]
      | {dsp: "window.fullscreen_state", args: {internal: $i, client: $c}}
    elif $d == "killactive" and $r == "" then {dsp: "window.close"}
    elif $d == "pseudo" and $r == "" then {dsp: "window.pseudo"}
    elif $d == "bringactivetotop" and $r == "" then {dsp: "window.bring_to_top"}
    elif $d == "cyclenext" and $r == "" then {dsp: "window.cycle_next"}
    elif $d == "cyclenext" and $r == "prev" then {dsp: "window.cycle_next", args: false}
    elif $d == "togglegroup" and $r == "" then {dsp: "group.toggle"}
    elif $d == "moveintogroup" and ($r | _dir) then {dsp: "window.move", args: {into_group: $r}}
    elif $d == "moveoutofgroup" and $r == "" then {dsp: "window.move", args: {out_of_group: true}}
    elif $d == "changegroupactive" and $r == "f" then {dsp: "group.next"}
    elif $d == "changegroupactive" and $r == "b" then {dsp: "group.prev"}
    elif $d == "changegroupactive" and ($r | test("^[0-9]+$")) then {dsp: "group.active", args: {index: ($r | tonumber)}}
    elif $d == "layoutmsg" and $r != "" then {dsp: "layout", args: $r}
    elif $d == "sendshortcut" and ($r | split(",") | length | IN(2, 3)) then
      ($r | split(",") | map(sub("^\\s+"; "") | sub("\\s+$"; ""))) as $p
      | if $p[1] == "" or $p[2] == "" then null
        else {dsp: "send_shortcut", args: ({mods: $p[0], key: $p[1]} + if ($p | length) == 3 then {window: $p[2]} else {} end)}
        end
    elif $d == "submap" and $r != "" then {dsp: "submap", args: $r}
    elif $d == "dpms" and ($r | IN("on", "off")) then {dsp: "dpms", args: {action: $r}}
    # Mouse binds (bindm): Hyprland's Lua API drags and resizes with these.
    elif $d == "movewindow" and $r == "" then {dsp: "window.drag"}
    elif $d == "resizewindow" and $r == "" then {dsp: "window.resize"}
    elif $d == "exit" and $r == "" then {dsp: "exit"}
    elif $d == "forcerendererreload" and $r == "" then {dsp: "force_renderer_reload"}
    else null end;

def _is_legacy: type == "object" and keys == ["dispatch"] and (.dispatch | type == "string");
# The v1 defaults' zoom binds ran `hyprctl keyword`, which the Lua config refuses
# (exit 0, nothing happens). A user file that copied them gets fledge's forms;
# only these exact strings: any other legacy IPC in a command is left for
# `mbm settings check` to name.
def _legacy_exec: {
  "hyprctl keyword cursor:zoom_factor $(hyprctl getoption cursor:zoom_factor -j | jq '.float + 1')":
    "fledge hypr eval 'hl.config({ cursor = { zoom_factor = hl.get_config(\"cursor.zoom_factor\") + 1 } })'",
  "hyprctl keyword cursor:zoom_factor 1": "fledge hypr set 'cursor = { zoom_factor = 1 }'"
};
def _is_legacy_exec: type == "object" and keys == ["exec"] and (.exec | type == "string") and _legacy_exec[.exec] != null;
def _migrate_action:
  (if _is_legacy then ((.dispatch | migrate_dispatch) // .) else . end)
  | if _is_legacy_exec then .exec = _legacy_exec[.exec] else . end;
def _actions: .action | if type == "array" then .[] else . end;

# A file `settings set` wrote has no version; it is v1 only if it holds legacy actions
# (a {dispatch}, or one of the v1 zoom commands).
def needs_migration:
  .version == 1
  or ((has("version") | not)
      and any(.binds | objects | .[] | objects | select(has("action")) | _actions; _is_legacy or _is_legacy_exec));

def migrate_user:
  . as $u
  | (if .binds | type == "object" then
       .binds |= map_values(if type == "object" and has("action") then
                              .action |= (if type == "array" then map(_migrate_action) else _migrate_action end)
                            else . end)
     else . end) as $new
  | {settings: ($new | if has("version") then .version = 2 else {version: 2} + . end),
     count: [($u.binds | objects | keys[]) as $k | select($u.binds[$k] != $new.binds[$k])] | length,
     # A bind with the 's' flag can't be converted either (check refuses it).
     unconverted: [$new.binds | objects | .[] | objects
                   | select((has("action") and any(_actions; _is_legacy)) or (.flags | type == "string" and test("s")))] | length};
