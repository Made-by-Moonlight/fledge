import Quickshell
import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../services"
import "../../components"

// Monitors (confirm-or-revert, see DisplayConfirm) and Workspaces (applied at once).
Flickable {
    id: page
    contentHeight: col.implicitHeight; clip: true
    property var edits: ({})          // name -> staged {mode, scale, position, transform, enabled}

    // Connected monitors, plus any the user switched off (Hyprland stops listing those, and
    // without a card there would be no way to switch them back on).
    readonly property var entries: {
        const out = [], live = new Set();
        for (const m of Hyprland.monitors.values) { out.push({ name: m.name, mon: m }); live.add(m.name); }
        const saved = Settings.merged?.displays ?? {};
        for (const n of Object.keys(saved)) if (!live.has(n) && saved[n]?.enabled === false) out.push({ name: n, mon: null });
        return out;
    }
    readonly property int liveCount: entries.filter(e => e.mon !== null).length

    // "2560x1440@144.00Hz", "2560x1440@144" and "2560x1440" compare equal on the rate's value.
    function modeKey(s) {
        const m = /^(\d+x\d+)(?:@([\d.]+))?/.exec(s ?? "");
        return m ? m[1] + (m[2] ? "@" + (+m[2]).toFixed(2) : "") : String(s);
    }
    function cur(e) {
        const m = e.mon, o = m?.lastIpcObject ?? {}, saved = Settings.merged?.displays?.[e.name] ?? null;
        return Object.assign(m ? {
            mode: saved?.mode ?? `${o.width}x${o.height}@${(o.refreshRate ?? 60).toFixed(2)}`,
            scale: saved?.scale ?? m.scale, position: saved?.position ?? `${m.x}x${m.y}`,
            transform: saved?.transform ?? (o.transform ?? 0), enabled: saved?.enabled ?? true
        } : {
            mode: saved?.mode ?? "preferred", scale: saved?.scale ?? 1, position: saved?.position ?? "auto",
            transform: saved?.transform ?? 0, enabled: saved?.enabled ?? false
        }, edits[e.name] ?? {});
    }
    function edit(name, k, v) { const e = Object.assign({}, edits); e[name] = Object.assign({}, e[name] ?? {}, { [k]: v }); edits = e; }
    function apply(e) {
        const c = cur(e);
        if (e.mon && !c.enabled && liveCount <= 1) { Settings.lastError = "Can't switch off the only connected display."; return; }
        if (DisplayConfirm.begin(e.name, { mode: c.mode, scale: c.scale, position: c.position, transform: c.transform, enabled: c.enabled })) {
            const x = Object.assign({}, edits); delete x[e.name]; edits = x;
        }
    }

    // Workspaces 1–10, plus any other pinned number.
    readonly property var workspaceNumbers: {
        const pinned = Object.keys(Settings.merged?.workspaces ?? {}).map(Number);
        return [...new Set([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, ...pinned])].sort((a, b) => a - b);
    }
    // [value, label] for the monitor Choice: Any, each connected monitor (stored as desc:… so the pin
    // survives a port change), and the current value when that monitor isn't connected.
    // A comma would split the generated `workspace =` line, so such a monitor is pinned by connector.
    function monitorValue(m) { return m.description && !m.description.includes(",") ? "desc:" + m.description : m.name; }
    function monitorOptions(current) {
        const opts = [["", "Any"]], seen = new Set([""]);
        for (const m of Hyprland.monitors.values) {
            const v = page.monitorValue(m);
            opts.push([v, m.name]); seen.add(v); seen.add(m.name);
        }
        if (current && !seen.has(current)) opts.push([current, current.replace(/^desc:/, "").slice(0, 24) + " (unplugged)"]);
        return opts;
    }
    // Workspace rules are harmless to change, so they apply at once (no confirm/revert).
    function pin(n, monitor, persistent) {
        const path = '.workspaces["' + n + '"]';
        if (monitor === "") {
            // A shipped default can't be deleted from the user file, only overridden with null.
            if (Settings.defaults?.workspaces?.[String(n)] !== undefined) Settings.set([[path, null]], true);
            else Settings.reset([path], true);
        } else Settings.set([[path, { monitor: monitor, persistent: persistent }]], true);
    }

    ColumnLayout {
        id: col
        width: page.width; spacing: 14

        Repeater {
            model: page.entries
            delegate: Pill {
                id: card
                required property var modelData
                readonly property var mon: modelData.mon
                readonly property string name: modelData.name
                readonly property var c: page.cur(modelData)
                readonly property var modes: {
                    const seen = new Set(), out = [];
                    for (const s of (mon?.lastIpcObject?.availableModes ?? [])) {
                        const k = page.modeKey(s);
                        if (!seen.has(k)) { seen.add(k); out.push(k); }
                    }
                    return out;
                }
                Layout.fillWidth: true; color: Theme.bgRaised; implicitHeight: inner.implicitHeight + 24
                ColumnLayout {
                    id: inner
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                    spacing: 10
                    RowLayout {
                        Layout.fillWidth: true
                        Glyph { text: card.name; font.bold: true }
                        Glyph { Layout.fillWidth: true; text: card.mon ? card.mon.description : "switched off"; color: Theme.muted; elide: Text.ElideRight }
                        Toggle { visible: !card.mon || page.liveCount > 1; label: "Enabled"; checked: card.c.enabled; onToggled: v => page.edit(card.name, "enabled", v) }
                    }
                    Flow {
                        visible: card.mon !== null
                        Layout.fillWidth: true; spacing: 6
                        Repeater { model: card.modes.slice(0, 16)
                            delegate: Rectangle { required property string modelData
                                readonly property bool on: page.modeKey(card.c.mode) === modelData
                                height: 26; width: t.implicitWidth + 14; radius: 6
                                color: on ? Theme.accent : Theme.surface
                                Glyph { id: t; anchors.centerIn: parent; text: parent.modelData; font.pixelSize: 10; color: parent.on ? Theme.bg : Theme.fgDim }
                                MouseArea { anchors.fill: parent; onClicked: page.edit(card.name, "mode", parent.modelData) } } }
                    }
                    RowLayout {
                        visible: card.mon !== null
                        spacing: 16
                        Stepper { label: "Scale"; value: typeof card.c.scale === "number" ? card.c.scale : 1; from: 0.5; to: 3; step: 0.25; decimals: 2
                                  onChanged: v => page.edit(card.name, "scale", v) }
                        Field { Layout.preferredWidth: 140; label: "Position (XxY)"; text: card.c.position; onEdited: t => page.edit(card.name, "position", t) }
                        Choice { label: "Rotation"; value: card.c.transform; options: [[0, "0°"], [1, "90°"], [2, "180°"], [3, "270°"]]
                                 onPicked: v => page.edit(card.name, "transform", v) }
                    }
                    Row { spacing: 8
                        Button { text: "Apply"; primary: true; enabled: page.edits[card.name] !== undefined && !DisplayConfirm.active; onClicked: page.apply(card.modelData) }
                        Button { text: "Reset"; enabled: !DisplayConfirm.active
                                 onClicked: { const x = Object.assign({}, page.edits); delete x[card.name]; page.edits = x; if (Settings.user?.displays?.[card.name] !== undefined) DisplayConfirm.begin(card.name, undefined); } } }
                }
            }
        }

        Glyph { text: "Workspaces"; font.bold: true; Layout.topMargin: 10 }
        Glyph { Layout.fillWidth: true; wrapMode: Text.WordWrap; color: Theme.muted; font.pixelSize: Theme.fontSmall
                text: "Pin workspaces to a monitor. The lowest-numbered workspace on each monitor opens there by default." }
        Repeater {
            model: page.workspaceNumbers
            delegate: RowLayout {
                id: ws
                required property int modelData
                readonly property var w: Settings.merged?.workspaces?.[String(modelData)] ?? null
                Layout.fillWidth: true; spacing: 12
                Glyph { text: String(ws.modelData); Layout.preferredWidth: 24; font.bold: true }
                Choice { Layout.fillWidth: true; value: ws.w?.monitor ?? ""; options: page.monitorOptions(ws.w?.monitor ?? "")
                         onPicked: v => page.pin(ws.modelData, v, ws.w?.persistent ?? true) }
                Toggle { label: "Persistent"; visible: ws.w !== null; checked: ws.w?.persistent ?? false
                         onToggled: v => page.pin(ws.modelData, ws.w.monitor, v) }
            }
        }
    }
}
