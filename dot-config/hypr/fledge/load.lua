-- The guarded loader: hyprland.lua runs every other file through it, so one
-- bad file (a hand-edited toggle, a broken generated fragment, a theme) loses
-- only its own settings and says so, instead of taking every bind with it.
--   load.file(path) -> nil if there's no such file; true, <its return value>;
--                      or false, <error> after notifying the user
--   load.dir(dir)   -> runs every *.lua in dir through file(), sorted by name;
--                      false if any of them failed, true otherwise (also when
--                      the dir is missing or empty)
--   load.notify(what, err) -> tells the user something failed
local M = {}

function M.notify(path, err)
  local text = "fledge: " .. path .. ": " .. tostring(err)
  io.stderr:write(text, "\n")
  -- Not being able to tell the user must not stop the rest of the config.
  pcall(function() hl.notification.create({ text = text, timeout = 15000 }) end)
end

function M.file(path)
  local f = io.open(path, "r")
  if not f then return nil end
  f:close()
  local ok, res = pcall(dofile, path)
  if not ok then
    M.notify(path, res)
    return false, res
  end
  return true, res
end

function M.dir(dir)
  -- Plain Lua has no directory listing; ls is always there. Single-quoted,
  -- with any ' in the path closed, escaped and reopened.
  local quoted = "'" .. dir:gsub("'", "'\\''") .. "'"
  local ls = io.popen("ls -1 -- " .. quoted .. " 2>/dev/null")
  if not ls then return true end
  local names = {}
  for name in ls:lines() do
    if name:match("%.lua$") then names[#names + 1] = name end
  end
  ls:close()
  table.sort(names)
  local all = true
  for _, name in ipairs(names) do
    if M.file(dir .. "/" .. name) == false then all = false end
  end
  return all
end

return M
