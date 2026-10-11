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
    // Requests not yet applied, in order: {abs, n}. A held key fires faster than brightnessctl
    // round-trips, so presses pile up here and are applied in one set call when the running
    // process finishes. An absolute request replaces everything pending before it.
    property var ops: []

    function refresh() { reader.running = true; }

    // Idle dim: brightnessctl -s saves the device's exact raw level, -r puts it back, so the
    // undim restores precisely what was there (not a rounded percent). Both go through the same
    // one-process-at-a-time pipeline as adjust(), so a key press that ends the dim steps from the
    // restored level, not the dimmed one. Already at or below the dim level: left alone, and no
    // restore follows. No backlight: both are no-ops.
    property bool dimmed: false
    property var effects: []
    function dim(percent) {
        if (!available || dimmed || Math.round(value * 100) <= percent) return;
        dimmed = true;
        effects = effects.concat([["brightnessctl", "-q", "-c", "backlight", "-s", "set", percent + "%"]]);
        kick();
    }
    function undim() {
        if (!dimmed) return;
        dimmed = false;
        effects = effects.concat([["brightnessctl", "-q", "-c", "backlight", "-r"]]);
        kick();
    }

    // arg: "+N" / "-N" relative, "N" absolute (percent).
    function adjust(arg) {
        const n = parseInt(arg);
        if (isNaN(n)) return;
        const op = { abs: !/^[+-]/.test(arg), n: n };
        ops = op.abs ? [op] : ops.concat([op]);
        kick();
    }
    // Start a fresh read (steps are computed from the live value) unless a process is already
    // running; its completion comes back here for whatever piled up meanwhile.
    function kick() {
        if (reader.running || writer.running || effect.running) return;
        if (effects.length > 0) {
            effect.command = effects[0];
            effects = effects.slice(1);
            effect.running = true;
        } else reader.running = true;
    }

    // Percent after applying the pending ops to cur, one press at a time so the small-step
    // rule (±5 steps by 1 at or below 5%, same feel as slievr-brightness-display) is not lost
    // when presses are combined. Floor 1%, ceiling 100%.
    function fold(cur) {
        let v = cur;
        for (const op of ops) {
            if (op.abs) v = op.n;
            else {
                const small = Math.abs(op.n) === 5 && (op.n > 0 ? v < 5 : v <= 5);
                v += small ? (op.n > 0 ? 1 : -1) : op.n;
            }
            v = Math.max(1, Math.min(100, v));
        }
        return v;
    }
    function set(percent) { if (!isNaN(percent)) adjust(String(Math.max(1, Math.round(percent)))); }
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

    Process {
        id: reader
        command: ["brightnessctl", "-m", "-c", "backlight"]
        running: true
        onExited: { if ((root.ops.length > 0 || root.effects.length > 0) && !writer.running) root.kick(); }
        stdout: StdioCollector {
            onStreamFinished: {
                const ok = root.parse(text);
                if (!ok) { root.ops = []; return; }
                if (root.ops.length === 0) return;
                const t = root.fold(Math.round(root.value * 100));
                root.ops = [];
                writer.command = ["brightnessctl", "-m", "-n1", "-c", "backlight", "set", t + "%"];
                writer.running = true;
            }
        }
    }
    Process {
        id: writer
        stdout: StdioCollector {
            onStreamFinished: { if (root.parse(text)) root.applied(); }
        }
        onExited: { if (root.ops.length > 0 || root.effects.length > 0) root.kick(); }
    }
    // A dim or undim; the read after it (kick) brings `value` back in line with the device.
    Process {
        id: effect
        onExited: root.kick()
        // A binary that can't start never emits exited.
        onRunningChanged: if (!running) Qt.callLater(() => { if (!effect.running && !reader.running && !writer.running) root.kick(); })
    }
}
