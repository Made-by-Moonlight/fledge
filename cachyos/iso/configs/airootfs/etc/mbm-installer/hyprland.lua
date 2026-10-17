-- fledge live installer session. Hand-written on purpose: one client, no
-- binds, nothing a user configures. Started by ~moonlight/.bash_profile with
-- --config; keep it free of errors (an error here is Hyprland's emergency mode).
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto" })

hl.config({
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

-- The session ends when the installer does.
hl.on("hyprland.start", function()
  hl.exec_cmd("qs -c mbm-installer; hyprctl dispatch 'hl.dsp.exit()'")
end)
