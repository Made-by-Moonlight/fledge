-- Window and layer rules: https://wiki.hypr.land/Configuring/Basics/Window-Rules/
-- Regexes match the whole string, as before. Rules apply in this order, so
-- the tag rules come before the rules that match on those tags, and the
-- default opacity comes after every app has had the chance to opt out.

-- Each rule runs on its own: one Hyprland refuses (a field renamed in a new
-- release, say) is listed in one notification at the end, instead of every
-- rule after it being lost.
local failed = {}
local function try(add, spec)
  local ok, err = pcall(add, spec)
  if not ok then
    local what = {} -- the rule's match, to say which one
    for k, v in pairs(spec.match or {}) do what[#what + 1] = k .. "=" .. tostring(v) end
    table.sort(what)
    failed[#failed + 1] = table.concat(what, " ") .. " (" .. tostring(err) .. ")"
  end
end
local function rule(spec) try(hl.window_rule, spec) end
local function layer_rule(spec) try(hl.layer_rule, spec) end

rule({ match = { class = ".*" }, suppress_event = "maximize" })

-- Tag all windows for default opacity (apps can override with -default-opacity tag)
rule({ match = { class = ".*" }, tag = "+default-opacity" })

-- Fix some dragging issues with XWayland
rule({
  match = { class = "^$", title = "^$", xwayland = true, float = true, fullscreen = false, pin = false },
  no_focus = true,
})

---- App-specific tweaks (may remove the default-opacity tag) ----

-- 1Password
rule({ match = { class = "^(1[p|P]assword)$" }, no_screen_share = true })
rule({ match = { class = "^(1[p|P]assword)$" }, tag = "+floating-window" })

-- Bitwarden, and its Chrome extension
rule({ match = { class = "^(Bitwarden)$" }, no_screen_share = true })
rule({ match = { class = "^(Bitwarden)$" }, tag = "+floating-window" })
rule({ match = { class = "chrome-nngceckbapebfimnlniiiahkandclblb-Default" }, no_screen_share = true })
rule({ match = { class = "chrome-nngceckbapebfimnlniiiahkandclblb-Default" }, tag = "+floating-window" })

-- Browser types
rule({
  match = { class = "((google-)?[cC]hrom(e|ium)|[bB]rave-browser|[mM]icrosoft-edge|Vivaldi-stable|helium)" },
  tag = "+chromium-based-browser",
})
rule({ match = { class = "([fF]irefox|zen|librewolf)" }, tag = "+firefox-based-browser" })
rule({ match = { tag = "chromium-based-browser" }, tag = "-default-opacity" })
rule({ match = { tag = "firefox-based-browser" }, tag = "-default-opacity" })
-- Video apps: remove chromium browser tag so they don't get opacity applied
rule({ match = { class = "(chrome-youtube.com__-Default|chrome-app.zoom.us__wc_home-Default)" }, tag = "-chromium-based-browser" })
rule({ match = { class = "(chrome-youtube.com__-Default|chrome-app.zoom.us__wc_home-Default)" }, tag = "-default-opacity" })
-- Force chromium-based browsers into a tile to deal with --app bug
rule({ match = { tag = "chromium-based-browser" }, tile = true })
-- Only a subtle opacity change, but not for video sites
rule({ match = { tag = "chromium-based-browser" }, opacity = "1.0 0.97" })
rule({ match = { tag = "firefox-based-browser" }, opacity = "1.0 0.97" })
-- Hide the screen-sharing notification bar (the "Hide" button on it is broken on Wayland)
rule({ match = { title = ".*is sharing.*" }, workspace = "special silent" })

-- Hyprshot: remove the 1px border around screenshots
layer_rule({ match = { namespace = "selection" }, no_anim = true })

-- JetBrains: disable mouse focus (see https://github.com/basecamp/omarchy/pull/5183#issuecomment-4189299971)
rule({ name = "jetbrains-focus", match = { class = "^(jetbrains-.*)$" }, no_follow_mouse = true })

-- Float LocalSend and fzf file picker
rule({ match = { class = "(Share|localsend)" }, float = true })
rule({ match = { class = "(Share|localsend)" }, center = true })
rule({ match = { class = "localsend" }, size = "1100 700" })

-- Picture-in-picture overlays
rule({ match = { title = "(Picture.?in.?[Pp]icture)" }, tag = "+pip" })
rule({ match = { tag = "pip" }, tag = "-default-opacity" })
rule({ match = { tag = "pip" }, float = true })
rule({ match = { tag = "pip" }, pin = true })
rule({ match = { tag = "pip" }, size = "600 338" })
rule({ match = { tag = "pip" }, keep_aspect_ratio = true })
rule({ match = { tag = "pip" }, border_size = 0 })
rule({ match = { tag = "pip" }, opacity = "1 1" })
rule({ match = { tag = "pip" }, move = "(monitor_w-window_w-40) (monitor_h*0.04)" })

-- QEMU
rule({ match = { class = "qemu" }, tag = "-default-opacity" })
rule({ match = { class = "qemu" }, opacity = "1 1" })

-- RetroArch
rule({ match = { class = "com.libretro.RetroArch" }, fullscreen = true })
rule({ match = { class = "com.libretro.RetroArch" }, tag = "-default-opacity" })
rule({ match = { class = "com.libretro.RetroArch" }, opacity = "1 1" })
rule({ match = { class = "com.libretro.RetroArch" }, idle_inhibit = "fullscreen" })

-- Float Steam
rule({ match = { class = "steam" }, float = true })
rule({ match = { class = "steam", title = "Steam" }, center = true })
rule({ match = { class = "steam.*" }, tag = "-default-opacity" })
rule({ match = { class = "steam.*" }, opacity = "1 1" })
rule({ match = { class = "steam", title = "Steam" }, size = "1100 700" })
rule({ match = { class = "steam", title = "Friends List" }, size = "460 800" })
rule({ match = { class = "steam" }, idle_inhibit = "fullscreen" })

-- GeForce NOW
rule({ name = "geforce", match = { class = "GeForceNOW" }, idle_inhibit = "fullscreen" })

-- Moonlight
rule({ name = "moonlight", match = { class = "com.moonlight_stream.Moonlight" }, fullscreen = true, idle_inhibit = "fullscreen" })

-- Floating windows
rule({ match = { tag = "floating-window" }, float = true })
rule({ match = { tag = "floating-window" }, center = true })
rule({ match = { tag = "floating-window" }, size = "875 600" })
rule({
  match = {
    class = "(org.omarchy.bluetui|org.omarchy.impala|org.omarchy.wiremix|org.omarchy.btop|org.omarchy.terminal|org.omarchy.bash|org.codeberg.dnkl.foot|org.gnome.NautilusPreviewer|org.gnome.Evince|com.gabm.satty|Omarchy|About|TUI.float|imv|mpv)",
  },
  tag = "+floating-window",
})
rule({
  match = {
    class = "(xdg-desktop-portal-gtk|sublime_text|DesktopEditors|org.gnome.Nautilus)",
    title = "^(Open.*Files?|Open [F|f]older.*|Save.*Files?|Save.*As|Save|All Files|.*wants to [open|save].*|[C|c]hoose.*)",
  },
  tag = "+floating-window",
})
rule({ match = { class = "org.gnome.Calculator" }, float = true })

-- Fullscreen screensaver
rule({ match = { class = "org.omarchy.screensaver" }, fullscreen = true })
rule({ match = { class = "org.omarchy.screensaver" }, float = true })
rule({ match = { class = "org.omarchy.screensaver" }, animation = "slide" })

-- No transparency on media windows
local media = "^(zoom|vlc|mpv|org.kde.kdenlive|com.obsproject.Studio|com.github.PintaProject.Pinta|imv|org.gnome.NautilusPreviewer)$"
rule({ match = { class = media }, tag = "-default-opacity" })
rule({ match = { class = media }, opacity = "1 1" })

-- Popped window rounding
rule({ match = { tag = "pop" }, rounding = 8 })

-- Prevent idle while open
rule({ match = { tag = "noidle" }, idle_inhibit = "always" })

-- Prevent Telegram from stealing focus on new messages
rule({ match = { class = "org.telegram.desktop" }, focus_on_activate = false })

-- Float Typora print dialog
rule({ match = { class = "^Typora$", title = "^Print$" }, float = true, center = true })

-- Define terminal tag to style them uniformly
rule({ match = { class = "(Alacritty|kitty|com.mitchellh.ghostty|foot)" }, tag = "+terminal" })
rule({ match = { tag = "terminal" }, tag = "-default-opacity" })
rule({ match = { tag = "terminal" }, opacity = "0.97 0.9" })

-- Webcam overlay for screen recording
rule({ match = { title = "WebcamOverlay" }, float = true })
rule({ match = { title = "WebcamOverlay" }, pin = true })
rule({ match = { title = "WebcamOverlay" }, no_initial_focus = true })
rule({ match = { title = "WebcamOverlay" }, no_dim = true })
rule({ match = { title = "WebcamOverlay" }, move = "(monitor_w-window_w-40) (monitor_h-window_h-40)" })

---- Apply default opacity after apps have had a chance to opt out ----
rule({ match = { tag = "default-opacity" }, opacity = "0.97 0.9" })

---- fledge's own rules ----

-- Discord, Spotify and YouTube Music live on workspace 9
rule({ match = { class = "discord" }, workspace = "9" })
rule({ match = { class = "discord" }, opacity = "1.0 override 1.0 override 1.0 override" })
rule({ match = { class = "spotify" }, workspace = "9" })
-- YouTube Music opens via Zen's --new-window: no Chromium-style --app= class
-- to match, so match the title (its own existing-window check keys off it too)
rule({ match = { title = "^YouTube Music" }, workspace = "9" })
rule({ match = { title = "^YouTube Music" }, opacity = "1.0 override 1.0 override 1.0 override" })

-- Zen
rule({ match = { class = "zen" }, no_blur = true })
rule({ match = { class = "zen" }, opacity = "1.0 override 1.0 override 1.0 override" })

-- Force all Steam windows to tile and stay tiled
rule({ match = { class = "steam" }, tile = true })
rule({ match = { class = "steam" }, suppress_event = "float maximize activate" })
-- Steam context menus have an empty title - exempt them so they float
rule({ match = { class = "steam", title = "^$" }, float = true })
rule({ match = { class = "^steam_app_\\d+$" }, opacity = "1.0 override" })

-- Scroll nicely in the terminal
rule({ match = { class = "(Alacritty|kitty|foot)" }, scroll_touchpad = 1.5 })
rule({ match = { class = "com.mitchellh.ghostty" }, scroll_touchpad = 0.2 })

-- The settings window (Super+K): a dialog, not a tiled app. Quickshell windows
-- all share the class org.quickshell, so match the title too
-- (dot-config/quickshell/mbm/settings/SettingsWindow.qml).
local settings = { class = "^org\\.quickshell$", title = "^fledge . settings$" }
rule({ match = settings, float = true })
rule({ match = settings, size = "960 680" })
rule({ match = settings, center = true })

if #failed > 0 then
  local text = "fledge: rules.lua: these rules didn't load: " .. table.concat(failed, "; ")
  io.stderr:write(text, "\n")
  pcall(function()
    hl.notification.create({ text = text, timeout = 15000, icon = "error", color = "rgb(ff5555)" })
  end)
end
