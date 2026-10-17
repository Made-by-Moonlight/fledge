-- Started once per session ("hyprland.start"), not on every config reload.
-- Each command runs through a shell, as exec-once did.
hl.on("hyprland.start", function()
  hl.exec_cmd("uwsm-app -- fcitx5 --disable notificationitem")
  hl.exec_cmd("slievr-powerprofiles-init")
  hl.exec_cmd("uwsm-app -- slievr-hyprland-monitor-watch")

  -- Slow app launch fix -- set systemd vars
  hl.exec_cmd("systemctl --user import-environment $(env | cut -d'=' -f 1)")
  hl.exec_cmd("dbus-update-activation-environment --systemd --all")

  -- Run post-boot hooks after startup config has loaded
  hl.exec_cmd("sleep 2 && slievr-hook post-boot")

  hl.exec_cmd("~/.config/omarchy/scripts/nvidia-power.sh")

  -- Upgrading from the .conf config inside a .conf session: that session sees
  -- hyprland.conf deleted and writes Hyprland's stub in its place, through the
  -- stow link into the repo, until it ends. hyprland.lua wins, so the stub is
  -- unused; remove it now that no .conf session is left to write it again.
  -- Only the stub (it says so): a hyprland.conf of the user's own stays.
  local stub = os.getenv("HOME") .. "/.config/hypr/hyprland.conf"
  local f = io.open(stub, "r")
  if f then
    local head = f:read(200) or ""
    f:close()
    if head:find("This config is a STUB!", 1, true) then os.remove(stub) end
  end
end)
