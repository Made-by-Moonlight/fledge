import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../services"
import "../../components"

// Monitors (confirm-or-revert, see DisplayConfirm), Workspaces and Wallpaper (both applied at once).
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

    // Wallpaper: thumbnails of the shipped Moonrise art and ~/Pictures/Wallpapers. The setting is read
    // live by the shell, so these writes don't apply. target "" is every monitor, else one monitor's key.
    readonly property string wallDir: Settings.home + "/Pictures/Wallpapers"
    readonly property string moonrise: Theme.assets + "/moonrise-2560x1440.png"
    property string wallTarget: ""
    property var wallFiles: []
    function wallPath(target) { return target === "" ? ".wallpaper.image" : ".wallpaper.monitors[" + JSON.stringify(target) + "]"; }
    // What this target shows now: the chosen file, "" for Moonrise (All), null when a monitor follows All.
    function wallCurrent(target) {
        if (target === "") return Settings.wallpaperImage === "" ? page.moonrise : Settings.wallpaperImage;
        const o = Settings.wallpaperMonitors?.[target];
        return typeof o === "string" ? o : null;
    }
    function wallPick(path) {
        // Moonrise for All is the empty setting, so the shipped default stays the default.
        const v = path === page.moonrise && page.wallTarget === "" ? "" : path;
        Settings.set([[page.wallPath(page.wallTarget), v]], false);
    }
    function wallReset() {
        if (page.wallTarget === "") Settings.reset([".wallpaper"], false);
        else Settings.reset([page.wallPath(page.wallTarget)], false);
    }
    function wallScan() { lister.running = false; lister.running = true; }
    Process {
        id: maker
        command: ["mkdir", "-p", page.wallDir]
        onExited: page.wallScan()
    }
    Process {
        id: lister
        command: ["find", page.wallDir, "-maxdepth", "1", "-type", "f", "(", "-iname", "*.jpg", "-o", "-iname", "*.jpeg",
                  "-o", "-iname", "*.png", "-o", "-iname", "*.webp", ")", "-print0"]
        stdout: StdioCollector {
            onStreamFinished: page.wallFiles = text.split("\0").filter(f => f !== "").sort()
        }
    }
    Component.onCompleted: maker.running = true

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

        Glyph { text: "Wallpaper"; font.bold: true; Layout.topMargin: 10 }
        Glyph { Layout.fillWidth: true; wrapMode: Text.WordWrap; color: Theme.muted; font.pixelSize: Theme.fontSmall
                text: "Put images in ~/Pictures/Wallpapers (jpg, png, webp). A monitor's own pick overrides the one for all monitors." }
        RowLayout {
            Layout.fillWidth: true; spacing: 12
            Choice { label: "Monitor"; value: page.wallTarget
                     options: { const o = [["", "All"]]; for (const m of Hyprland.monitors.values) o.push([page.monitorValue(m), m.name]); return o; }
                     onPicked: v => page.wallTarget = v }
            Item { Layout.fillWidth: true }
            Button { text: page.wallTarget === "" ? "Use Moonrise" : "Same as all"; Layout.alignment: Qt.AlignBottom
                     enabled: page.wallTarget === "" ? (Settings.wallpaperImage !== "" || Object.keys(Settings.wallpaperMonitors ?? {}).length > 0) : page.wallCurrent(page.wallTarget) !== null
                     onClicked: page.wallReset() }
            Button { text: "Rescan"; Layout.alignment: Qt.AlignBottom; onClicked: page.wallScan() }
        }
        Glyph { visible: page.wallFiles.length === 0; Layout.fillWidth: true; color: Theme.muted; font.pixelSize: Theme.fontSmall
                text: "Put images in ~/Pictures/Wallpapers" }
        Flow {
            Layout.fillWidth: true; spacing: 10
            Repeater {
                model: [page.moonrise, ...page.wallFiles]
                delegate: Rectangle {
                    id: thumb
                    required property string modelData
                    readonly property bool on: page.wallCurrent(page.wallTarget) === modelData
                    width: 150; height: 104; radius: Theme.radius
                    color: Theme.surface; border.width: 2; border.color: on ? Theme.accent : "transparent"
                    Image {
                        x: 4; y: 4; width: parent.width - 8; height: 76
                        source: "file://" + encodeURI(thumb.modelData).replace(/#/g, "%23").replace(/\?/g, "%3F")
                        fillMode: Image.PreserveAspectCrop; asynchronous: true
                        sourceSize: Qt.size(300, 152)   // small decode: a 8K picture costs no more than a 300px one
                    }
                    Glyph { anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 6 }
                            elide: Text.ElideRight; font.pixelSize: Theme.fontSmall; color: thumb.on ? Theme.accent : Theme.fgDim
                            text: thumb.modelData === page.moonrise ? "Moonrise" : thumb.modelData.slice(thumb.modelData.lastIndexOf("/") + 1) }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: page.wallPick(thumb.modelData) }
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
