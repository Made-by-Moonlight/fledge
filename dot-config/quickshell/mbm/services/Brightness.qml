pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Display backlight through brightnessctl (no Quickshell service for it).
// Writes go through `brightnessctl -m`, whose output is the device's state after the write,
// so `value` is always what the hardware reports and `applied` fires with it.
Singleton {
    id: root
    property bool available: false
    property real value: 0
    signal applied()

    property string pendingArg: ""     // adjust() waiting for a fresh read
    property var queued: null          // next write while one is running

    function refresh() { reader.running = true; }

    // arg: "+N" / "-N" relative, "N" absolute (percent). Reads the live value first so steps
    // start from what the backlight is now.
    function adjust(arg) {
        pendingArg = arg;
        reader.running = true;
    }

    // brightnessctl arguments for a set; null for bad input. -n1 keeps the backlight from reaching 0.
    function commandFor(arg, cur) {
        const n = parseInt(arg);
        if (isNaN(n)) return null;
        let spec;
        if (/^[+-]/.test(arg)) {
            // ±5 steps by 1 at or below 5% (same feel as slievr-brightness-display); other deltas are exact.
            const mag = (Math.abs(n) === 5 && (n > 0 ? cur < 5 : cur <= 5)) ? 1 : Math.abs(n);
            spec = mag + "%" + (n > 0 ? "+" : "-");
        } else {
            spec = Math.max(1, Math.min(100, n)) + "%";
        }
        return ["brightnessctl", "-m", "-n1", "-c", "backlight", "set", spec];
    }
    function set(percent) { if (!isNaN(percent)) adjust(String(Math.round(percent))); }
    function step(delta) { if (!isNaN(delta)) adjust((delta > 0 ? "+" : "-") + Math.abs(Math.round(delta))); }

    function parse(text) {
        // One line per device: device,class,current,percent,max. Use the first.
        const f = text.trim().split("\n")[0].split(",");
        const pct = parseInt(f[3]);
        const ok = f.length >= 5 && !isNaN(pct);
        root.available = ok;
        if (ok) root.value = pct / 100;
        return ok;
    }
    function write(cmd) {
        if (writer.running) { queued = cmd; return; }
        writer.command = cmd;
        writer.running = true;
    }

    Process {
        id: reader
        command: ["brightnessctl", "-m", "-c", "backlight"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                const ok = root.parse(text);
                const arg = root.pendingArg;
                root.pendingArg = "";
                if (ok && arg !== "") {
                    const cmd = root.commandFor(arg, Math.round(root.value * 100));
                    if (cmd) root.write(cmd);
                }
            }
        }
    }
    Process {
        id: writer
        stdout: StdioCollector {
            onStreamFinished: { if (root.parse(text)) root.applied(); }
        }
        onExited: {
            if (root.queued) { const c = root.queued; root.queued = null; root.write(c); }
        }
    }
}
