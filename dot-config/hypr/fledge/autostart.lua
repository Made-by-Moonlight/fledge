-- Started once per session ("hyprland.start"), not on every config reload.
-- Each command runs through a shell, as exec-once did.
hl.on("hyprland.start", function()
  hl.exec_cmd("uwsm-app -- fcitx5 --disable notificationitem")
  hl.exec_cmd("slievr-first-run")
  hl.exec_cmd("slievr-powerprofiles-init")
  hl.exec_cmd("uwsm-app -- slievr-hyprland-monitor-watch")

  -- Slow app launch fix -- set systemd vars
  hl.exec_cmd("systemctl --user import-environment $(env | cut -d'=' -f 1)")
  hl.exec_cmd("dbus-update-activation-environment --systemd --all")

  -- Run post-boot hooks after startup config has loaded
  hl.exec_cmd("sleep 2 && slievr-hook post-boot")

  hl.exec_cmd("~/.config/omarchy/scripts/nvidia-power.sh")
end)
