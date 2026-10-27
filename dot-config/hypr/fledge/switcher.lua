-- The window switcher (quickshell switcher/Switcher.qml) picks a window when you let go of
-- its bind's modifier. A release bind can't do that: Hyprland fires one for a modifier
-- only when no other key came between press and release, and Tab did. So on entering
-- the fledge-switcher submap (the bind's last dispatch, gen-binds.jq) note the modifiers
-- held, and only while it is on, watch key releases until none of them is: then send
-- "commit" and leave, as the submap's Return does. Event-driven, nothing polls.
-- A bind with no modifier (a bare key) leaves nothing to let go of: Return picks.
local MODS = { "Alt_L", "Alt_R", "Super_L", "Super_R", "Control_L", "Control_R" }
local watch = nil

local function stop()
  if watch then watch:remove() end
  watch = nil
end

hl.on("keybinds.submap", function(name)
  stop()
  if name ~= "fledge-switcher" then return end
  local held = {}
  for _, k in ipairs(MODS) do
    if hl.is_key_down(k) then held[#held + 1] = k end
  end
  if #held == 0 then return end
  -- A modifier's release reaches here twice, the second time with is_key_down updated.
  watch = hl.on("input.keyboard.key", function(_, _, state)
    if state ~= 0 then return end
    for _, k in ipairs(held) do
      if hl.is_key_down(k) then return end
    end
    stop()
    hl.dispatch(hl.dsp.event("fledge-switcher commit"))
    hl.dispatch(hl.dsp.submap("reset"))
  end)
end)
