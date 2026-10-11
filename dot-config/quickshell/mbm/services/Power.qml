pragma Singleton
import Quickshell
import Quickshell.Services.UPower
import QtQuick

Singleton {
    id: root
    readonly property var dev: UPower.displayDevice
    readonly property bool battery: dev?.isLaptopBattery ?? false
    // The range of `percentage` (0-1 or 0-100) is undocumented in 0.3.2, so derive
    // it from energy / energyCapacity (spike notes) and only fall back to it.
    readonly property int percent: {
        const cap = dev?.energyCapacity ?? 0;
        if (cap > 0) return Math.round(Math.max(0, Math.min(100, (dev.energy / cap) * 100)));
        return Math.round(dev?.percentage ?? 0);
    }
    readonly property bool charging: dev ? (dev.state === UPowerDeviceState.Charging || dev.state === UPowerDeviceState.FullyCharged) : false
    readonly property string glyph: {
        if (!battery) return "";
        if (charging) return "󰂄";
        const g = ["󰂎", "󰁺", "󰁻", "󰁼", "󰁽", "󰁾", "󰁿", "󰂀", "󰂁", "󰂂", "󰁹"];
        return g[Math.min(10, Math.floor(percent / 10))];
    }
    readonly property int profile: PowerProfiles.profile
    readonly property bool hasPerformance: PowerProfiles.hasPerformanceProfile
    function setProfile(p) { PowerProfiles.profile = p; }
}
