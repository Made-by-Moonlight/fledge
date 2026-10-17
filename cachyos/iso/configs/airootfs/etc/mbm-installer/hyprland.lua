-- fledge live installer session. Hand-written on purpose: one client, no
-- binds, nothing a user configures. Started by ~moonlight/.bash_profile with
-- --config; keep it free of errors (an error here is Hyprland's emergency mode).

-- The session ends when the installer does. Registered first, so a setting
-- below that this Hyprland refuses (a key renamed in a point release an ISO
-- rebuild pulled in) can't stop the installer starting, or the session ending
-- (back to .bash_profile's message on tty1).
hl.on("hyprland.start", function()
  hl.exec_cmd("qs -c mbm-installer; hyprctl dispatch 'hl.dsp.exit()'")
end)

-- Hyprland reports most refused settings itself (the error bar) and keeps the
-- rest. Anything that raises instead costs only its own call: say so (stderr
-- is /tmp/hyprland-installer.log) and carry on.
local function try(what, fn, arg)
  local ok, err = pcall(fn, arg)
  if ok then return end
  local text = "mbm-installer: " .. what .. ": " .. tostring(err)
  io.stderr:write(text, "\n")
  pcall(function() hl.notification.create({ text = text, timeout = 15000, icon = "error" }) end)
end

try("monitor", hl.monitor, { output = "", mode = "preferred", position = "auto", scale = "auto" })

try("settings", hl.config, {
  input = { kb_layout = "us" },
  general = { gaps_in = 0, gaps_out = 0, border_size = 0 },
  decoration = { rounding = 0 },
  animations = { enabled = false },
  misc = {
    disable_hyprland_logo = true,
    disable_splash_rendering = true,
    force_default_wallpaper = 0,
    background_color = "0x171e28",
    -- Run straight from .bash_profile; a crashed session is restarted from tty1.
    disable_watchdog_warning = true,
    -- Nothing here changes at runtime; don't watch the file.
    disable_autoreload = true,
  },
  ecosystem = { no_update_news = true, no_donation_nag = true },
})
