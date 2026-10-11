# Deliberate changes from the Omarchy-era binds (spec: Cutover -> Bind remaps).
# Errors on an unknown id, so a converter change can't silently skip one.
def shell($s): {shell: $s};
def remap($id; $a): if .binds[$id] then .binds[$id].action = $a else error("remap: no bind \($id)") end;
def relabel($id; $l): if .binds[$id] then .binds[$id].label = $l else error("relabel: no bind \($id)") end;
def id_for($mods; $key): [.binds | to_entries[] | select(.value.mods == $mods and .value.key == $key) | .key][0];

remap("utilities.launch-apps"; shell("launcher.toggle"))
| remap("utilities.emoji-picker"; shell("launcher.open emoji"))
| remap("clipboard.clipboard-manager"; shell("launcher.open clipboard"))
| remap("utilities.slievr-menu"; shell("launcher.open system")) | relabel("utilities.slievr-menu"; "System menu")
| remap("utilities.slievr-menu-2"; shell("launcher.open system")) | relabel("utilities.slievr-menu-2"; "System menu")
| remap("utilities.system-menu"; shell("launcher.open system"))
| remap("utilities.power-menu"; shell("launcher.open system"))
| remap("utilities.show-key-bindings"; shell("settings.open keybinds")) | relabel("utilities.show-key-bindings"; "Keybinds")
| remap("utilities.toggle-top-bar"; shell("bar.toggle"))
| remap("utilities.dismiss-last-notification"; shell("notifications.dismiss"))
| remap("utilities.dismiss-all-notifications"; shell("notifications.dismissAll"))
| remap("utilities.toggle-silencing-notifications"; shell("notifications.dndToggle"))
| remap("utilities.invoke-last-notification"; shell("notifications.invokeLast"))
| remap("utilities.restore-last-notification"; shell("notifications.restoreLast"))
| remap("utilities.toggle-locking-on-idle"; shell("idle.toggle"))
| remap("utilities.lock-system"; shell("lock.lock"))
| remap("utilities.audio-controls"; shell("quicksettings.open audio"))
| remap("utilities.bluetooth-controls"; shell("quicksettings.open bluetooth"))
| remap("utilities.wifi-controls"; shell("quicksettings.open wifi"))
| remap("media.volume-up"; shell("osd.volume +5"))
| remap("media.volume-down"; shell("osd.volume -5"))
| remap("media.mute"; shell("osd.volume mute"))
| remap("media.mute-microphone"; shell("osd.mic mute"))
| remap("media.brightness-up"; shell("osd.brightness +5"))
| remap("media.brightness-down"; shell("osd.brightness -5"))
| remap("media.brightness-maximum"; shell("osd.brightness 100"))
| remap("media.brightness-minimum"; shell("osd.brightness 1"))
| remap("media.volume-up-precise"; shell("osd.volume +1"))
| remap("media.volume-down-precise"; shell("osd.volume -1"))
| remap("media.brightness-up-precise"; shell("osd.brightness +1"))
| remap("media.brightness-down-precise"; shell("osd.brightness -1"))
| remap("media.next-track"; shell("media.next"))
| remap("media.pause"; shell("media.playPause"))
| remap("media.play"; shell("media.playPause"))
| remap("media.previous-track"; shell("media.previous"))
| .binds["shell.quick-settings"] = {mods: "SUPER", key: "A", label: "Quick settings", group: "Utilities",
                                    action: shell("quicksettings.toggle")}
| relabel(id_for(""; "switch:on:Lid Switch"); "Lid closed")
| relabel(id_for(""; "switch:off:Lid Switch"); "Lid opened")
| relabel(id_for("SUPER SHIFT"; "G"); "Game workspace")
