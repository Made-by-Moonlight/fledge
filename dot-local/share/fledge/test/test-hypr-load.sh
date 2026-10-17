#!/usr/bin/env bash
# Tests for the guarded loader in dot-config/hypr/fledge/load.lua, run with
# plain `lua` and a stand-in `hl` that records notifications.
set -uo pipefail
HERE="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)"
REPO="$(cd "$HERE/../../../.." && pwd)"
# shellcheck source=../../../../cachyos/install/test/lib.sh
source "$REPO/cachyos/install/test/lib.sh"
LOAD="$REPO/dot-config/hypr/fledge/load.lua"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

# Each fixture appends to the global `trace`, so the driver can see what ran.
printf 'trace[#trace + 1] = "good"\nreturn { colour = "rgb(f4af03)" }\n' > "$T/good.lua"
printf 'trace[#trace + 1] = "syntax"\nlocal x = = 1\n' > "$T/syntax.lua"
printf 'trace[#trace + 1] = "runtime"\nerror("boom")\n' > "$T/runtime.lua"
mkdir -p "$T/dir" "$T/empty" "$T/odd dir"
printf 'trace[#trace + 1] = "b"\n' > "$T/dir/b.lua"
printf 'trace[#trace + 1] = "a"\n' > "$T/dir/a.lua"
printf 'trace[#trace + 1] = "c"\nerror("c broke")\n' > "$T/dir/c.lua"
printf 'trace[#trace + 1] = "d"\n' > "$T/dir/d.lua"
printf 'trace[#trace + 1] = "not lua"\n' > "$T/dir/e.conf"
printf 'trace[#trace + 1] = "odd"\n' > "$T/odd dir/x.lua"

# driver: runs one scenario (arg 2) and prints `key=value` lines
cat > "$T/driver.lua" <<'EOL'
local load_path, scenario, dir = arg[1], arg[2], arg[3]
trace, notes = {}, {}
hl = { notification = { create = function(opts) notes[#notes + 1] = opts end } }
local load = dofile(load_path)
local function show(...) local t = { ... } for i = 1, select("#", ...) do t[i] = tostring(t[i]) end return table.concat(t, ",") end
local r
if scenario == "missing" then r = show(load.file(dir .. "/nope.lua"))
elseif scenario == "good" then
  local ok, v = load.file(dir .. "/good.lua"); r = show(ok, type(v) == "table" and v.colour)
elseif scenario == "syntax" then r = show(load.file(dir .. "/syntax.lua"))
elseif scenario == "runtime" then r = show(load.file(dir .. "/runtime.lua"))
elseif scenario == "dir" then r = show(load.dir(dir .. "/dir"))
elseif scenario == "nodir" then r = show(load.dir(dir .. "/nodir"))
elseif scenario == "empty" then r = show(load.dir(dir .. "/empty"))
elseif scenario == "odd" then r = show(load.dir(dir .. "/odd dir"))
elseif scenario == "notify" then r = show(load.notify("theme colours", "bad colour"))
end
trace[#trace + 1] = "after"
print("ret=" .. r)
print("trace=" .. table.concat(trace, " "))
print("notes=" .. #notes)
for i, n in ipairs(notes) do print("note" .. i .. "=" .. tostring(n.text) .. "|timeout=" .. tostring(n.timeout)) end
for i, n in ipairs(notes) do print("style" .. i .. "=" .. tostring(n.icon) .. "," .. tostring(n.color)) end
EOL

run() { out="$(lua "$T/driver.lua" "$LOAD" "$1" "$T" 2>&1)"; rc=$?; }
field() { sed -n "s/^$1=//p" <<<"$out"; }

run missing
check "missing file: no error" 0 "$rc"
check "missing file: returns nil (skipped)" "nil" "$(field ret)"
check "missing file: no notification" 0 "$(field notes)"

run good
check "good file: returns true and its value" "true,rgb(f4af03)" "$(field ret)"
check "good file: ran, caller continued" "good after" "$(field trace)"
check "good file: no notification" 0 "$(field notes)"

run syntax
check "syntax error: no error escapes" 0 "$rc"
contains "syntax error: returns false" "false," "$(field ret)"
check "syntax error: caller continues" "after" "$(field trace)"
check "syntax error: one notification" 1 "$(field notes)"
contains "syntax error: notification names the file" "fledge: $T/syntax.lua: " "$(field note1)"
contains "syntax error: notification has Lua's message" "syntax.lua:2:" "$(field note1)"
contains "syntax error: notification has a timeout" "|timeout=" "$(field note1)"
check "syntax error: timeout is a number" "" "$(field note1 | grep -o 'timeout=nil')"
check "syntax error: shown as an error, not info" "error,rgb(ff5555)" "$(field style1)"

run runtime
check "runtime error: no error escapes" 0 "$rc"
contains "runtime error: returns false" "false," "$(field ret)"
check "runtime error: file ran up to the error, caller continues" "runtime after" "$(field trace)"
check "runtime error: one notification" 1 "$(field notes)"
contains "runtime error: notification has the message" "boom" "$(field note1)"

run dir
check "dir: *.lua only, sorted, an error doesn't stop the rest" "a b c d after" "$(field trace)"
check "dir: the broken file notifies" 1 "$(field notes)"
contains "dir: notification names the broken file" "fledge: $T/dir/c.lua: " "$(field note1)"
check "dir: returns false when a file failed" "false" "$(field ret)"

run nodir
check "missing dir: no error" 0 "$rc"
check "missing dir: nothing ran, no notification" "after|0" "$(field trace)|$(field notes)"
check "missing dir: returns true" "true" "$(field ret)"

run empty
check "empty dir: returns true, nothing ran" "true|after" "$(field ret)|$(field trace)"

run odd
check "dir with a space in its path" "odd after" "$(field trace)"

run notify
check "notify: one notification, what and error" "1|fledge: theme colours: bad colour" "$(field notes)|$(field note1 | sed 's/|timeout=.*//')"

# the notification itself failing must not break the caller
cat > "$T/driver2.lua" <<'EOL'
hl = { notification = { create = function() error("no notifications yet") end } }
trace = {}
local load = dofile(arg[1])
print(tostring(load.file(arg[2])) .. " continued")
EOL
out="$(lua "$T/driver2.lua" "$LOAD" "$T/runtime.lua" 2>/dev/null)"; rc=$?
check "notification failure: caller still continues" "0|false continued" "$rc|$out"

# hyprland.lua itself, run against a stand-in home: every file it loads appends
# its name to `trace`. fledge/load.lua missing or broken (a git pull or restow
# mid-way) must not stop the rest: a stand-in loader takes over and says so.
HYPR_LUA="$REPO/dot-config/hypr/hyprland.lua"
mkhome() { # mkhome <dir>: the config tree hyprland.lua expects, with tracing stubs
  local h="$1" f
  mkdir -p "$h/.config/hypr/fledge" "$h/.local/state/mbm/hypr" "$h/.local/state/hypr-toggles"
  cp "$HYPR_LUA" "$h/.config/hypr/hyprland.lua"
  for f in envs looknfeel misc rules autostart; do
    printf 'trace[#trace + 1] = "%s"\n' "$f" >"$h/.config/hypr/fledge/$f.lua"
  done
  printf 'trace[#trace + 1] = "binds"\n' >"$h/.local/state/mbm/hypr/binds.lua"
  printf 'trace[#trace + 1] = "toggle"\n' >"$h/.local/state/hypr-toggles/t.lua"
}
cat > "$T/driver3.lua" <<'EOL'
trace, notes = {}, {}
hl = { notification = { create = function(opts) notes[#notes + 1] = opts end },
       config = function() end }
if os.getenv("NO_NOTIFY") then hl.notification = nil end
package.path = os.getenv("HOME") .. "/.config/hypr/?.lua;" .. package.path
dofile(os.getenv("HOME") .. "/.config/hypr/hyprland.lua")
print("trace=" .. table.concat(trace, " "))
print("notes=" .. #notes)
for i, n in ipairs(notes) do print("icon" .. i .. "=" .. tostring(n.icon)) end
for i, n in ipairs(notes) do print("note" .. i .. "=" .. tostring(n.text)) end
EOL
run_hypr() { out="$(HOME="$1" lua "$T/driver3.lua" 2>/dev/null)"; rc=$?; }

mkhome "$T/h1"; cp "$LOAD" "$T/h1/.config/hypr/fledge/load.lua"
run_hypr "$T/h1"
check "hyprland.lua: everything loads, in order" "envs looknfeel misc rules binds toggle autostart" "$(field trace)"
check "hyprland.lua: no notification" "0" "$(field notes)"

mkhome "$T/h2"
run_hypr "$T/h2"
check "load.lua missing: no error escapes" 0 "$rc"
check "load.lua missing: the rest still loads (no toggles)" "envs looknfeel misc rules binds autostart" "$(field trace)"
check "load.lua missing: one notification" "1" "$(field notes)"
contains "load.lua missing: notification names it" "fledge: fledge/load.lua: " "$(field note1)"
check "load.lua missing: shown as an error" "error" "$(field icon1)"

# Without hl.notification (an API change, say) the stand-in still only reports.
out="$(NO_NOTIFY=1 HOME="$T/h2" lua "$T/driver3.lua" 2>&1)"; rc=$?
check "load.lua missing, no hl.notification: no error escapes" 0 "$rc"
check "load.lua missing, no hl.notification: the rest still loads" "envs looknfeel misc rules binds autostart" "$(field trace)"
contains "load.lua missing, no hl.notification: said on stderr" "fledge: fledge/load.lua: " "$out"

mkhome "$T/h3"; printf 'local M = = {}\n' >"$T/h3/.config/hypr/fledge/load.lua"
printf 'trace[#trace + 1] = "rules"\nerror("rules broke")\n' >"$T/h3/.config/hypr/fledge/rules.lua"
run_hypr "$T/h3"
check "load.lua broken: no error escapes" 0 "$rc"
check "load.lua broken: the rest still loads" "envs looknfeel misc rules binds autostart" "$(field trace)"
check "load.lua broken: it and the broken file notify" "2" "$(field notes)"
contains "load.lua broken: names load.lua" "fledge: fledge/load.lua: " "$(field note1)"
contains "load.lua broken: names the broken file" "rules.lua: " "$(field note2)"

# envs.lua reads the theme's gum.env.conf with hyprlang's rules: `#` starts a
# comment, `##` is a literal `#`.
mkdir -p "$T/eh/.config/omarchy/current/theme"
cat >"$T/eh/.config/omarchy/current/theme/gum.env.conf" <<'EOC'
# a comment line
env = PLAIN,##ffffff
env = TRAILING,##171e28   # the background
env = THREE,###
env = MIDDLE,a ## b#c
  env = SPACED , value with spaces  
#env = COMMENTED,x
env = EMPTY,# nothing
EOC
cat > "$T/driver4.lua" <<'EOL'
local envs = {}
hl = { env = function(k, v) envs[#envs + 1] = k .. "=[" .. v .. "]" end }
dofile(arg[1])
for _, e in ipairs(envs) do print(e) end
EOL
out="$(HOME="$T/eh" lua "$T/driver4.lua" "$REPO/dot-config/hypr/fledge/envs.lua" 2>&1)"; rc=$?
check "envs.lua: runs" 0 "$rc"
contains "gum env: ## is a literal #" "PLAIN=[#ffffff]" "$out"
contains "gum env: inline comment dropped" "TRAILING=[#171e28]" "$out"
contains "gum env: ### is # then a comment" "THREE=[#]" "$out"
contains "gum env: comment after text" "MIDDLE=[a # b]" "$out"
contains "gum env: spaces trimmed" "SPACED=[value with spaces]" "$out"
contains "gum env: all comment -> empty" "EMPTY=[]" "$out"
check "gum env: commented-out line skipped" "" "$(grep COMMENTED <<<"$out")"

# shellcheck disable=SC2154 # $fail comes from lib.sh
exit $fail
