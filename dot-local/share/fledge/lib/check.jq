# Input: merged settings (and --slurpfile dsp dsp-names.json). Output: one string
# per problem; nothing = valid.
# Kept in step with the schema in docs/superpowers/specs/2026-10-10-mbm-shell-design.md.

def isint: type == "number" and . == floor;
def str_matches($re): type == "string" and test($re);
def unknown($allowed; $where): (keys - $allowed)[] | "\($where): unknown field \(.)";
def mods_list: split(" ") | map(select(. != ""));
def mods_ok: type == "string" and (mods_list | all(IN("SUPER", "SHIFT", "CTRL", "ALT", "MOD2", "MOD3", "MOD5")));
def scalar: type | IN("string", "number", "boolean");
# hyprctl keyword, --batch/-b and `dispatch <legacy string>` are refused by
# Hyprland's Lua config, mostly with exit status 0, so a bind running them
# would do nothing without a word. A dispatch of a Lua expression is fine.
# Same pattern and message as the keybind editor (settings/DspShort.js).
def legacy_ipc: test("\\bhyprctl\\s+(?:-\\S+\\s+)*?(?:keyword(?:\\s|$)|--batch(?:\\s|$)|-b(?:\\s|$)|dispatch\\s+(?!hl\\.)[a-z])");
def legacy_ipc_problem: "runs Hyprland's legacy IPC (hyprctl keyword, --batch or a dispatch string), which the Lua config refuses: use fledge hypr set|dispatch|eval";
# One action: {exec}, {shell} or {dsp[, args]}. Problems as text, nothing = valid.
# args is a positional value (layout("togglesplit")) or a one-level table of
# scalars, the shapes the generator can render as a Lua argument.
def action_problems($id):
  if type == "object" and keys == ["dispatch"] then
    "binds.\($id): can't convert dispatcher \(.dispatch | tojson); rewrite it as {dsp, args}"
  elif type != "object" or ((keys - ["exec", "shell", "dsp", "args"]) | length) > 0
       or ([has("exec"), has("shell"), has("dsp")] | map(select(.)) | length) != 1
       or (has("args") and (has("dsp") | not)) then
    "binds.\($id): action must be one of {exec}, {shell}, {dsp[, args]} (or a list of them)"
  elif has("dsp") then
    if (.dsp | type == "string" and IN($dsp[0].names[])) | not then "binds.\($id): unknown dispatcher \(.dsp | tojson)"
    elif has("args") and (.args | scalar or (type == "object" and all(.[]; scalar)) | not) then
      "binds.\($id): args for \(.dsp) must be text, a number, true/false or an object of those"
    else empty end
  elif (.exec // .shell | type == "string" and length > 0) then
    if (.exec // .shell | legacy_ipc) then "binds.\($id): \(legacy_ipc_problem)" else empty end
  else "binds.\($id): action must be one of {exec}, {shell}, {dsp[, args]} (or a list of them)" end;
# What Hyprland treats as "the same keys": modifiers in any order, key case-insensitively, same flags.
def combo: (.mods | mods_list | sort | join("+")) + "+" + (.key | ascii_downcase)
           + "/" + ((.flags // "") | gsub("d"; "") | split("") | sort | join(""));

def check_bind($id):
  . as $b
  | if type != "object" then "binds.\($id): must be an object"
    else
      unknown(["mods", "key", "flags", "label", "group", "action"]; "binds.\($id)"),
      (if ($b.mods | mods_ok) then empty else "binds.\($id): bad modifiers \($b.mods | tojson)" end),
      (if ($b.key | type == "string" and length > 0) then empty else "binds.\($id): key is required" end),
      # 's' (separate keysyms) is a .conf bind flag with no hl.bind option: refused
      # rather than dropped, so the bind can't quietly behave differently.
      (if ($b.flags // "" | str_matches("^[elrnmtip]*$")) then empty
       elif ($b.flags | str_matches("^[elrnmtisp]*$")) then "binds.\($id): flag s (separate keysyms) has no Lua equivalent; remove it"
       else "binds.\($id): bad flags \($b.flags | tojson)" end),
      (if ($b.label | type == "string" and (test(",") | not)) then empty else "binds.\($id): label must be a string without commas" end),
      (if ($b.group | type == "string") then empty else "binds.\($id): group is required" end),
      ($b.action | if type == "array" and length > 0 then .[] | action_problems($id)
                   elif type == "array" then "binds.\($id): action must be one of {exec}, {shell}, {dsp[, args]} (or a list of them)"
                   else action_problems($id) end)
    end;

def check_display($name):
  . as $d
  | unknown(["mode", "position", "scale", "transform", "enabled"]; "displays.\($name)"),
    (if ($d.mode // "preferred" | str_matches("^(preferred|highres|highrr|[0-9]+x[0-9]+(@[0-9]+(\\.[0-9]+)?)?)$")) then empty
     else "displays.\($name): bad mode \($d.mode | tojson)" end),
    (if ($d.position // "auto" | str_matches("^(auto|-?[0-9]+x-?[0-9]+)$")) then empty
     else "displays.\($name): bad position \($d.position | tojson)" end),
    (if ($d.scale // "auto" | . == "auto" or (type == "number" and . > 0)) then empty
     else "displays.\($name): bad scale \($d.scale | tojson)" end),
    (if ($d.transform // 0 | isint and . >= 0 and . <= 7) then empty
     else "displays.\($name): bad transform \($d.transform | tojson)" end),
    (if ($d.enabled // true | type == "boolean") then empty else "displays.\($name): enabled must be true or false" end);

# Keys are `desc:<description>` or a connector name; a rule is one comma-
# separated Hyprland line, so a comma in a key would corrupt it.
def check_display_key:
  if . == "" then "displays: monitor name can't be empty"
  elif test(",") then "displays: monitor name can't contain a comma"
  else empty end;

def check_workspace($k):
  . as $w
  | if type != "object" then "workspaces.\($k): must be an object"
    else
      unknown(["monitor", "persistent"]; "workspaces.\($k)"),
      (if ($w.monitor | type == "string" and length > 0) then empty else "workspaces.\($k): monitor is required" end),
      (if ($w.monitor | type == "string" and contains(",")) then "workspaces.\($k): monitor can't contain a comma" else empty end),
      (if ($w | has("persistent") | not) or ($w.persistent | type == "boolean") then empty
       else "workspaces.\($k): persistent must be true or false" end)
    end;

def modules($side):
  (.[$side] // [])
  | if type != "array" then "bar.\($side) must be a list"
    else .[] | select(IN("workspaces", "title", "clock", "tray", "glyphs", "cog", "media", "updates") | not) | "bar.\($side): unknown module \(tojson)"
    end;

def secs($k): if (.[$k] // 0 | isint and . >= 0) then empty else "idle.\($k) must be a whole number of seconds >= 0" end;

((keys - ["version", "binds", "displays", "workspaces", "wallpaper", "bar", "launcher", "notifications", "idle", "input"])[] | "unknown setting: \(.)"),

(if .version != 2 then "version must be 2 (got \(.version | tojson))" else empty end),

(.binds // {} | to_entries[] | .key as $id | .value | check_bind($id)),

([.binds // {} | to_entries[]
  | select(.value | type == "object" and (.mods | type) == "string" and (.key | type) == "string")
  | {id: .key, c: (.value | combo)}]
 | group_by(.c)[] | select(length > 1)
 | "binds: \(map(.id) | join(" and ")) use the same keys (\(.[0].c | sub("/.*$"; "")))"),

(.displays // {} | keys[] | check_display_key),
(.displays // {} | to_entries[] | .key as $n | .value | check_display($n)),

(.workspaces // {} | to_entries[] | .key as $k
 | if ($k | test("^[1-9][0-9]*$")) then (.value | check_workspace($k))
   else "workspaces: \($k) is not a workspace number" end),

(.wallpaper // {}
 | unknown(["image", "monitors"]; "wallpaper"),
   (if (.image // "" | type == "string") then empty else "wallpaper.image must be text (a file path, or empty for Moonrise)" end),
   (if (.monitors // {} | type == "object") then
      (.monitors // {} | keys[] | select(test("[\"\\\\]")) | "wallpaper.monitors: monitor name can't contain a quote or backslash: \(tojson)"),
      (.monitors // {} | to_entries[]
       | select(.value | type != "string" or length == 0)
       | "wallpaper.monitors.\(.key): must be a non-empty path (or moonrise)")
    else "wallpaper.monitors must be an object" end)),

(.bar // {}
 | unknown(["position", "left", "centre", "right", "glyphs", "clockFormat", "height", "main", "hidden"]; "bar"),
   (if (.height // 32 | isint and . >= 20 and . <= 48) then empty else "bar.height must be a whole number from 20 to 48" end),
   (if (.clockFormat // 0 | isint and . >= 0 and . <= 3) then empty else "bar.clockFormat must be a whole number from 0 to 3" end),
   (if (.position // "top" | IN("top", "bottom")) then empty else "bar.position must be top or bottom" end),
   modules("left"), modules("centre"), modules("right"),
   # Monitor keys as Displays writes them (desc:<description> or a connector), stored as values.
   (.main // "" | if type != "string" then "bar.main must be text (a monitor name)"
     elif test("[\"\\\\]") then "bar.main: monitor name can't contain a quote or backslash: \(tojson)" else empty end),
   ((.hidden // []) | if type != "array" then "bar.hidden must be a list"
     elif any(.[]; type != "string") then "bar.hidden must be a list of monitor names"
     else .[] | select(test("[\"\\\\]")) | "bar.hidden: monitor name can't contain a quote or backslash: \(tojson)" end),
   ((.glyphs // []) | if type != "array" then "bar.glyphs must be a list"
     else .[] | select(IN("network", "bluetooth", "battery", "volume") | not) | "bar.glyphs: unknown glyph \(tojson)" end)),

(.launcher // {}
 | unknown(["position"]; "launcher"),
   (if (.position // "centre" | IN("centre", "anchored")) then empty else "launcher.position must be centre or anchored" end)),

(.notifications // {}
 | unknown(["corner", "timeoutMs"]; "notifications"),
   (if (.corner // "top-right" | IN("top-right", "top-left", "bottom-right", "bottom-left")) then empty
    else "notifications.corner must be top-right, top-left, bottom-right or bottom-left" end),
   (if (.timeoutMs // 5000 | isint and . >= 0) then empty else "notifications.timeoutMs must be a whole number >= 0" end)),

(.idle // {}
 | unknown(["dimSec", "lockSec", "screenOffSec", "suspendSec", "lockOnSleep"]; "idle"),
   secs("dimSec"), secs("lockSec"), secs("screenOffSec"), secs("suspendSec"),
   (if (.lockOnSleep // true | type == "boolean") then empty else "idle.lockOnSleep must be true or false" end),
   (if ((.dimSec // 0) > 0 and (.lockSec // 0) > 0 and (.lockSec // 0) < (.dimSec // 0)) then "idle.lockSec must be >= dimSec" else empty end)),

(.input // {}
 | unknown(["kbLayout", "kbVariant", "kbOptions", "repeatRate", "repeatDelay", "numlock", "sensitivity", "touchpad"]; "input"),
   (if (.kbLayout // "us" | type == "string" and length > 0) then empty else "input.kbLayout is required" end),
   (if (.kbVariant // "" | type == "string") then empty else "input.kbVariant must be text" end),
   (if (.kbOptions // "" | type == "string") then empty else "input.kbOptions must be text" end),
   (if (.repeatRate // 25 | isint and . >= 1 and . <= 200) then empty else "input.repeatRate must be 1-200" end),
   (if (.repeatDelay // 600 | isint and . >= 100 and . <= 2000) then empty else "input.repeatDelay must be 100-2000" end),
   (if (.numlock // false | type == "boolean") then empty else "input.numlock must be true or false" end),
   (if (.sensitivity // 0 | type == "number" and . >= -1 and . <= 1) then empty else "input.sensitivity must be between -1 and 1" end),
   (.touchpad // {}
    | unknown(["naturalScroll", "tapToClick", "scrollFactor"]; "input.touchpad"),
      (if (.naturalScroll // false | type == "boolean") then empty else "input.touchpad.naturalScroll must be true or false" end),
      (if (.tapToClick // true | type == "boolean") then empty else "input.touchpad.tapToClick must be true or false" end),
      (if (.scrollFactor // 1 | type == "number" and . > 0) then empty else "input.touchpad.scrollFactor must be > 0" end)))
