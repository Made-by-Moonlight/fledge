-- A stand-in for Hyprland's `hl` table, so the tests can run generated files
-- with plain `lua` (no Hyprland). Only the calls the generators may make exist:
-- anything else is an error. Every hl.dsp.* call returns {name, args} instead
-- of a dispatcher, and every call is printed one per line, so a test can check
-- what the file really does (e.g. that an escaped command comes back intact).
-- HL_STUB_MISSING (comma-separated, e.g. "window.drag") makes those dispatchers
-- nil, as when a Hyprland release renames one.
-- Usage: lua hl-stub.lua <generated.lua>...
local out = {}
local function show(v)
  if type(v) ~= "table" then return tostring(v) end
  if v.name then
    local a = {}
    for i = 1, v.n do a[i] = show(v.args[i]) end
    return v.name .. "(" .. table.concat(a, ", ") .. ")"
  end
  local keys, parts = {}, {}
  for k in pairs(v) do keys[#keys + 1] = k end
  table.sort(keys)
  for _, k in ipairs(keys) do parts[#parts + 1] = k .. "=" .. show(v[k]) end
  return "{" .. table.concat(parts, " ") .. "}"
end
local missing = {}
for name in (os.getenv("HL_STUB_MISSING") or ""):gmatch("[^,]+") do missing["dsp." .. name] = true end
local function dsp(path)
  return setmetatable({}, {
    __index = function(_, k)
      if missing[path .. "." .. k] then return nil end
      return dsp(path .. "." .. k)
    end,
    __call = function(_, ...) return { name = path, args = { ... }, n = select("#", ...) } end,
  })
end
local submap = ""
hl = {
  dsp = dsp("dsp"),
  bind = function(keys, action, opts)
    if type(action) == "function" then
      local calls = {}
      local real = hl.dispatch
      hl.dispatch = function(d) calls[#calls + 1] = show(d) end
      action()
      hl.dispatch = real
      action = "fn[" .. table.concat(calls, "; ") .. "]"
    else
      action = show(action)
    end
    out[#out + 1] = "bind" .. submap .. "\t" .. keys .. "\t" .. action .. "\t" .. show(opts)
  end,
  define_submap = function(name, fn)
    submap = "@" .. name
    fn()
    submap = ""
  end,
  dispatch = function() error("hl.dispatch outside a bind") end,
  monitor = function(spec) out[#out + 1] = "monitor\t" .. show(spec) end,
  workspace_rule = function(spec) out[#out + 1] = "workspace_rule\t" .. show(spec) end,
  config = function(spec) out[#out + 1] = "config\t" .. show(spec) end,
  notification = { create = function(spec) out[#out + 1] = "notify\t" .. show(spec) end },
}
setmetatable(hl, { __index = function(_, k) error("unexpected hl." .. k) end })
for _, f in ipairs(arg) do dofile(f) end
io.write(table.concat(out, "\n"))
