# Input: merged settings. Output: one string per problem; nothing = valid.
# Kept in step with the schema in docs/superpowers/specs/2026-10-10-mbm-shell-design.md.

def isint: type == "number" and . == floor;
def str_matches($re): type == "string" and test($re);
def unknown($allowed; $where): (keys - $allowed)[] | "\($where): unknown field \(.)";
def mods_list: split(" ") | map(select(. != ""));
def mods_ok: type == "string" and (mods_list | all(IN("SUPER", "SHIFT", "CTRL", "ALT", "MOD2", "MOD3", "MOD5")));
def action_ok:
  type == "object"
  and ((keys - ["shell", "dispatch", "exec"]) | length) == 0
  and ([.shell, .dispatch, .exec] | map(select(. != null)) | length == 1 and (.[0] | type == "string" and length > 0));
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
      (if ($b.flags // "" | str_matches("^[elrnmtisp]*$")) then empty else "binds.\($id): bad flags \($b.flags | tojson)" end),
      (if ($b.label | type == "string" and (test(",") | not)) then empty else "binds.\($id): label must be a string without commas" end),
      (if ($b.group | type == "string") then empty else "binds.\($id): group is required" end),
      (if ($b.action | if type == "array" then length > 0 and all(action_ok) else action_ok end) then empty
       else "binds.\($id): action must be one of {shell}, {dispatch}, {exec} (or a list of them)" end)
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
    else .[] | select(IN("workspaces", "title", "clock", "tray", "glyphs", "cog", "media") | not) | "bar.\($side): unknown module \(tojson)"
    end;

def secs($k): if (.[$k] // 0 | isint and . >= 0) then empty else "idle.\($k) must be a whole number of seconds >= 0" end;

((keys - ["version", "binds", "displays", "workspaces", "wallpaper", "bar", "launcher", "notifications", "idle", "input"])[] | "unknown setting: \(.)"),

(if .version != 1 then "version must be 1 (got \(.version | tojson))" else empty end),

(.binds // {} | to_entries[] | .key as $id | .value | check_bind($id)),

([.binds // {} | to_entries[]
  | select(.value | type == "object" and (.mods | type) == "string" and (.key | type) == "string")
  | {id: .key, c: (.value | combo)}]
 | group_by(.c)[] | select(length > 1)
 | "binds: \(map(.id) | join(" and ")) use the same keys (\(.[0].c | sub("/.*$"; "")))"),

(.displays // {} | to_entries[] | .key as $n | .value | check_display($n)),

(.workspaces // {} | to_entries[] | .key as $k
 | if ($k | test("^[1-9][0-9]*$")) then (.value | check_workspace($k))
   else "workspaces: \($k) is not a workspace number" end),

(.wallpaper // {}
 | unknown(["image", "monitors"]; "wallpaper"),
   (if (.image // "" | type == "string") then empty else "wallpaper.image must be text (a file path, or empty for Moonrise)" end),
   (if (.monitors // {} | type == "object") then
      (.monitors // {} | to_entries[]
       | select(.value | type != "string" or length == 0)
       | "wallpaper.monitors.\(.key): must be a non-empty path")
    else "wallpaper.monitors must be an object" end)),

(.bar // {}
 | unknown(["position", "left", "centre", "right", "glyphs", "clockFormat"]; "bar"),
   (if (.clockFormat // 0 | isint and . >= 0 and . <= 3) then empty else "bar.clockFormat must be a whole number from 0 to 3" end),
   (if (.position // "top" | IN("top", "bottom")) then empty else "bar.position must be top or bottom" end),
   modules("left"), modules("centre"), modules("right"),
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
 | unknown(["kbLayout", "kbOptions", "repeatRate", "repeatDelay", "numlock", "sensitivity", "touchpad"]; "input"),
   (if (.kbLayout // "us" | type == "string" and length > 0) then empty else "input.kbLayout is required" end),
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
