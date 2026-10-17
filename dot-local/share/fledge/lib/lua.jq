# Lua literals for the Hyprland generators. A jq library (defs only; jq won't
# include a file with a main expression): `jq -L lib -f gen-x.jq`, which starts
# with `include "lua";`.

# Names Lua reserves: as table keys they must be bracketed (["end"] = 1).
def lua_reserved: ["and", "break", "do", "else", "elseif", "end", "false", "for", "function",
  "goto", "global", "if", "in", "local", "nil", "not", "or", "repeat", "return", "then", "true",
  "until", "while"];

# A double-quoted Lua string. Control characters become \ddd (always three
# digits, so a following digit can't join the escape); a raw newline or CR
# inside quotes is a Lua syntax error.
def lua_str:
  "\"" + (explode | map(
    if . == 92 then "\\\\"
    elif . == 34 then "\\\""
    elif . == 10 then "\\n"
    elif . < 32 or . == 127 then "\\" + ("00" + tostring)[-3:]
    else [.] | implode end) | join("")) + "\"";

def lua_key: if test("^[A-Za-z_][A-Za-z0-9_]*$") and (IN(lua_reserved[]) | not) then . else "[" + lua_str + "]" end;

# Any JSON value as a Lua expression; objects with sorted keys, so the output
# doesn't depend on the order the user wrote them in.
def lua_value:
  if type == "string" then lua_str
  elif type == "number" or type == "boolean" then tostring
  elif type == "object" then
    if length == 0 then "{}"
    else "{ " + (to_entries | sort_by(.key) | map((.key | lua_key) + " = " + (.value | lua_value)) | join(", ")) + " }" end
  elif type == "array" then
    if length == 0 then "{}" else "{ " + (map(lua_value) | join(", ")) + " }" end
  else "nil" end;
