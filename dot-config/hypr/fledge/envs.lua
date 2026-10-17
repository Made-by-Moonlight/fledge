-- Session environment. GPU-specific env (NVIDIA vars, AQ_DRM_DEVICES, the
-- Vulkan default device) is set per login from whichever GPU drives the
-- monitors, in ~/.config/uwsm/env-hyprland, not here.

-- Gum's colours come from the current theme's gum.env.conf (`env = K,V`
-- lines). It's the one theme file still in Hyprland's old syntax because the
-- theme scripts render it; read it here rather than making every theme ship a
-- Lua copy. A missing file is fine, as before. hyprlang's rules: a `#` starts a
-- comment, `##` is a literal `#` (so "##ff0000 # red" is "#ff0000").
local function hyprlang_value(v)
  -- \1 stands in for a literal # while the comment is cut off.
  v = v:gsub("##", "\1"):gsub("#.*$", ""):gsub("\1", "#")
  return (v:match("^(.-)%s*$"))
end
local gum = io.open(os.getenv("HOME") .. "/.config/omarchy/current/theme/gum.env.conf", "r")
if gum then
  for line in gum:lines() do
    local k, v = line:match("^%s*env%s*=%s*([%w_]+)%s*,%s*(.-)%s*$")
    if k then hl.env(k, hyprlang_value(v)) end
  end
  gum:close()
end

-- Cursor size
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")

-- Force all apps to use Wayland
hl.env("GDK_BACKEND", "wayland,x11,*")
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("QT_STYLE_OVERRIDE", "kvantum")
hl.env("MOZ_ENABLE_WAYLAND", "1")
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "wayland")
hl.env("OZONE_PLATFORM", "wayland")
hl.env("XDG_SESSION_TYPE", "wayland")

-- Allow better support for screen sharing (Google Meet, Discord, etc)
hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_DESKTOP", "Hyprland")

-- Use XCompose file
hl.env("XCOMPOSEFILE", "~/.XCompose")
