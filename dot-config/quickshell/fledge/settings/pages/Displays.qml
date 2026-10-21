import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../services"
import "../../components"
import ".."
// Not "as Layout": that would hide QtQuick.Layouts' attached Layout.
import "../Layout.js" as Geom

// Monitors: an arrangement canvas (Arrange) over a card per monitor; everything only stages, and one
// Apply writes the whole page through DisplayConfirm (confirm-or-revert). Workspaces and Wallpaper
// apply at once.
Flickable {
    id: page
    contentHeight: col.implicitHeight; clip: true
    property var staged: ({})         // key -> {mode, scale, transform, enabled}
    property var rects: []            // the canvas, mm (Layout.js); rects[0] is the anchor, which Apply leaves where it is
    property bool moved: false        // dragged or rotated on the canvas
    property string selected: ""
    readonly property bool dirty: moved || Object.keys(staged).length > 0

    // The settings key for a monitor: Layout.js keyFor() (desc:<description>, else the connector),
    // and the connector too when the description has a quote or backslash (it would break the
    // settings path).
    function keyOf(m) { const v = page.monitorValue(m); return /["\\]/.test(v) ? m.name : v; }

    // Switched-off monitors that are still connected. Hyprland's monitor list (and Quickshell's)
    // drops a disabled one; `hyprctl monitors all -j` keeps it, with its real modes and size.
    property var all: []
    readonly property var offline: {
        const live = new Set(Hyprland.monitors.values.map(m => m.name));
        return page.all.filter(o => o.disabled && !live.has(o.name));
    }
    readonly property var connected: [...Hyprland.monitors.values, ...page.offline]
    function queryAll() { allQuery.running = false; allQuery.running = true; }
    Process {
        id: allQuery
        command: ["hyprctl", "monitors", "all", "-j"]
        stdout: StdioCollector {
            onStreamFinished: { try { page.all = JSON.parse(text); } catch (e) { console.warn("Displays: hyprctl monitors all:", e); } }
        }
    }
    Connections {
        target: Hyprland
        function onRawEvent(event) { if (event.name.startsWith("monitor")) page.queryAll(); }
    }

    // Connected monitors (switched off ones too), plus saved ones switched off that aren't connected
    // (unplugged: listed so they can be seen, but they can't be switched on). A saved desc: key
    // matches a monitor by description, a connector key by name. o is Hyprland's view of the
    // monitor (null when unplugged); mon the live Quickshell monitor (null when off).
    readonly property var displays: {
        const out = [], all = Settings.merged?.displays ?? {}, claimed = new Set();
        const add = (m, o, mon) => {
            const key = page.keyOf(m);
            claimed.add(key); claimed.add(m.name);
            if (m.description) claimed.add("desc:" + m.description);
            out.push({ key: key, name: m.name, title: o.model || m.description, mon: mon, o: o,
                       saved: all[key] ?? all[m.name] ?? (m.description ? all["desc:" + m.description] : null) ?? null });
        };
        for (const m of Hyprland.monitors.values) add(m, m.lastIpcObject ?? {}, m);
        for (const o of page.offline) add(o, o, null);
        for (const k of Object.keys(all))
            if (!claimed.has(k) && all[k]?.enabled === false) out.push({ key: k, name: Geom.label(k), title: "", mon: null, o: null, saved: all[k] });
        return out;
    }
    function on(d) { const s = page.staged[d.key]?.enabled; return s !== undefined && d.o !== null ? s : d.mon !== null; }
    readonly property int liveOn: displays.filter(d => d.mon && page.on(d)).length

    // "2560x1440@144.00Hz", "2560x1440@144" and "2560x1440" compare equal on the rate's value.
    function modeKey(s) {
        const m = /^(\d+x\d+)(?:@([\d.]+))?/.exec(s ?? "");
        return m ? m[1] + (m[2] ? "@" + (+m[2]).toFixed(2) : "") : String(s);
    }
    function liveMode(d) { const o = d.mon?.lastIpcObject ?? {}; return `${o.width}x${o.height}@${(o.refreshRate ?? 60).toFixed(2)}`; }
    // What the card shows: staged, else what Hyprland runs now (a switched-off monitor: its saved entry).
    function cur(d) {
        const s = page.staged[d.key] ?? {}, o = d.o ?? {}, v = d.saved ?? {};
        return {
            mode: s.mode ?? (d.mon ? page.liveMode(d) : v.mode ?? "preferred"),
            scale: s.scale ?? (d.mon ? d.mon.scale : typeof v.scale === "number" ? v.scale : o.scale ?? 1),
            transform: s.transform ?? (d.mon ? o.transform ?? 0 : v.transform ?? o.transform ?? 0),
            enabled: page.on(d)
        };
    }
    // The panel's preferred mode, [w, h]: the kernel lists it first.
    function native(d) {
        const wh = /^(\d+)x(\d+)/.exec(d.o?.availableModes?.[0] ?? "");
        return wh ? [+wh[1], +wh[2]] : d.o?.width ? [d.o.width, d.o.height] : null;
    }
    // The monitor as Layout.js sees it. A mode that isn't a size ("preferred", or "highres" from
    // the settings file) is drawn at the preferred one.
    function geo(d) {
        const c = page.cur(d), o = d.o ?? {}, wh = /^(\d+)x(\d+)/.exec(c.mode), n = page.native(d);
        return { key: d.key, name: d.name, title: d.title,
                 px: wh ? [+wh[1], +wh[2]] : n ?? [1920, 1080], native: n,
                 mm: [o.physicalWidth ?? 0, o.physicalHeight ?? 0], scale: c.scale, transform: c.transform };
    }
    // The scales the card offers for its mode: only those Hyprland keeps as they are.
    function scalesFor(d) { return Geom.scales(page.geo(d).px, 0.5, 3); }
    readonly property var onMons: displays.filter(d => page.on(d)).map(d => page.geo(d))
    function savedPos(d) {
        if (d.mon) return [d.mon.x, d.mon.y];
        const p = /^(-?\d+)x(-?\d+)$/.exec(d.saved?.position ?? "");
        return p ? [+p[1], +p[2]] : undefined;
    }

    // The canvas from where the monitors are now (a hand-set gap or overlap draws as it is, and
    // Apply names it).
    function rebuild() {
        const pos = {};
        for (const d of page.displays) if (page.on(d)) pos[d.key] = page.savedPos(d);
        page.rects = Geom.fromLogical(page.onMons, pos);
        page.moved = false;
        if (!page.rects.some(r => r.key === page.selected)) page.selected = page.rects[0]?.key ?? "";
    }
    // Back on the canvas at its saved position (worked out with the others where they are now,
    // then moved by however far the canvas has shifted from that), pushed out and slid to touch.
    function placeBack(key, rects) {
        const pos = {};
        for (const d of page.displays) if (page.on(d)) pos[d.key] = page.savedPos(d);
        // Last, so a saved 0,0 doesn't take the anchor from a monitor that is there now.
        const ms = page.onMons.filter(m => m.key !== key).concat(page.onMons.filter(m => m.key === key));
        const fresh = Geom.fromLogical(ms, pos), mine = fresh.find(r => r.key === key);
        if (!mine) return rects;
        const ref = rects.find(r => fresh.some(f => f.key === r.key)), f = ref ? fresh.find(q => q.key === ref.key) : null;
        const dx = ref ? ref.x - f.x : 0, dy = ref ? ref.y - f.y : 0;
        return Geom.settle(rects.concat([{ key: key, x: mine.x + dx, y: mine.y + dy, w: mine.w, h: mine.h }]), key);
    }
    // Rects to match what is on: switched off leaves, switched on comes back, a new mode, scale or
    // rotation resizes about the centre (then settles).
    function reconcile() {
        const want = new Map(page.onMons.map(m => [m.key, Geom.physical(m)]));
        let rs = page.rects.filter(r => want.has(r.key));
        for (const r of rs.slice()) {
            const wh = want.get(r.key);
            if (Math.abs(r.w - wh[0]) > 0.01 || Math.abs(r.h - wh[1]) > 0.01) rs = Geom.rotate(rs, r.key, wh[0], wh[1]);
        }
        for (const k of want.keys()) if (!rs.some(r => r.key === k)) rs = page.placeBack(k, rs);
        page.rects = rs;
        if (!rs.some(r => r.key === page.selected)) page.selected = rs[0]?.key ?? "";
    }
    // Monitors plugged, unplugged or moved (an Apply, its revert): staged edits for monitors that
    // went away are dropped; with nothing else staged the canvas is redrawn from Hyprland.
    readonly property string liveSig: JSON.stringify(displays.map(d => {
        const o = d.mon?.lastIpcObject ?? {};
        return [d.key, d.mon ? [d.mon.x, d.mon.y, d.mon.scale, o.width, o.height, o.transform, o.physicalWidth, o.physicalHeight] : [d.o !== null, d.saved]];
    }))
    onLiveSigChanged: page.sync()
    function sync() {
        const known = new Set(page.displays.map(d => d.key)), s = {};
        let pruned = false;
        for (const k of Object.keys(page.staged)) if (known.has(k)) s[k] = page.staged[k]; else pruned = true;
        if (pruned) page.staged = s;
        if (page.dirty) page.reconcile(); else page.rebuild();
    }
    // A reload moves monitors without an event Quickshell refreshes on: ask after every settings write.
    // And redraw from Hyprland then, unless something is staged: Apply clears the staging, and a
    // refused change (reverted, monitors never moved) changes nothing liveSig sees, so the canvas
    // would keep the layout that was never applied.
    Connections { target: Settings; function onWriteFinished() { refresh.restart(); } }
    Timer { id: refresh; interval: 300; onTriggered: { Hyprland.refreshMonitors(); page.queryAll(); if (!page.dirty) page.rebuild(); } }

    function stage(d, k, v) {
        if (k === "enabled" && !v && d.mon && page.on(d) && page.liveOn <= 1) { Settings.lastError = "Can't switch off the only connected display."; return; }
        if (k === "enabled" && v && d.o === null) { Settings.lastError = d.name + " isn't connected."; return; }
        const x = Object.assign({}, page.staged);
        x[d.key] = Object.assign({}, x[d.key] ?? {}, { [k]: v });
        // A new mode the scale doesn't divide: the nearest scale that does (see scalesFor).
        const wh = k === "mode" ? /^(\d+)x(\d+)/.exec(v) : null;
        if (wh) {
            const sc = page.cur(d).scale, n = Geom.nearestScale([+wh[1], +wh[2]], sc, Math.min(0.5, sc), Math.max(3, sc));
            if (Math.abs(n - sc) > 1e-9) x[d.key].scale = n;
        }
        page.staged = x;
        page.reconcile();
    }
    // Keeps the flip bit; dir +1 is a quarter-turn anticlockwise (Wayland's 90).
    function rotate(key, dir) {
        const d = page.displays.find(q => q.key === key);
        if (!d) return;
        const t = page.cur(d).transform;
        page.stage(d, "transform", (t & 4) | ((t + dir + 4) & 3));
    }
    // Error strings name monitors by key; the connector reads better.
    function named(msg) {
        for (const d of page.displays) if (d.key !== d.name) msg = msg.split(Geom.label(d.key)).join(d.name);
        return msg;
    }
    // {ok, pos, error}: the layout Apply would write, or why it can't.
    readonly property var verdict: {
        if (page.onMons.some(m => !page.rects.some(r => r.key === m.key))) return { ok: false, pos: {}, error: "The canvas is missing a monitor: Discard and try again" };
        const p = Geom.problems(page.rects);
        if (p.length) return { ok: false, pos: {}, error: page.named(p[0]) };
        const t = Geom.toLogical(page.onMons, page.rects, page.anchorAt);
        return t.ok ? t : { ok: false, pos: t.pos, error: page.named(t.error) };
    }
    // Where the anchor is now: Apply places the rest from it and leaves it there. Always 0,0
    // would move it on every Apply (an undocked laptop saved at 2560x0, re-docked, under the
    // external at 0x0).
    readonly property var anchorAt: {
        const d = page.rects.length ? page.displays.find(q => q.key === page.rects[0].key) : null;
        return (d && page.savedPos(d)) || [0, 0];
    }
    // A layout's problem shows even with nothing staged (a gap set by hand): Apply is off then anyway.
    readonly property string blocked: page.dirty && DisplayConfirm.active ? "Keep or revert the last change first." : page.verdict.error
    // Every monitor that is on gets its whole entry (the walk can shift any position); one
    // switched off in this edit keeps its saved entry, off. A connector-keyed user entry of a
    // monitor written under its desc: key goes, so one monitor never has two rules; so does a
    // desc: entry of twins now keyed by connector (desc: rules are written last and would win),
    // and a twin left off gets its own entry, off, in its place.
    function apply() {
        if (page.blocked !== "" || !page.dirty) return;
        const set = {}, remove = [], user = Settings.user?.displays ?? {};
        for (const d of page.displays) {
            const s = page.staged[d.key] ?? {}, c = page.cur(d), v = d.saved ?? {};
            if (page.on(d)) {
                const p = page.verdict.pos[d.key];
                if (!p) continue;
                set[d.key] = { mode: s.mode ?? v.mode ?? c.mode, scale: s.scale ?? v.scale ?? c.scale, transform: c.transform,
                               position: p[0] + "x" + p[1], enabled: true };
            } else if (d.mon && s.enabled === false) {
                set[d.key] = Object.assign({ mode: c.mode, scale: c.scale, transform: c.transform, position: d.mon.x + "x" + d.mon.y }, v, { enabled: false });
            }
            if (d.o && d.key !== d.name && set[d.key] && user[d.name] !== undefined) remove.push(d.name);
            const dk = d.o?.description ? "desc:" + d.o.description : "";
            if (dk && d.key !== dk && set[d.key] && user[dk] !== undefined && !remove.includes(dk)) remove.push(dk);
        }
        for (const d of page.displays) {
            const dk = d.o?.description ? "desc:" + d.o.description : "";
            if (dk && remove.includes(dk) && !set[d.key])
                set[d.key] = Object.assign({}, d.saved ?? {}, { enabled: false });
        }
        if (DisplayConfirm.begin({ set: set, remove: remove })) { page.staged = ({}); page.moved = false; }
    }
    function discard() { page.staged = ({}); page.rebuild(); }

    // Workspaces 1–10, plus any other pinned number.
    readonly property var workspaceNumbers: {
        const pinned = Object.keys(Settings.merged?.workspaces ?? {}).map(Number);
        return [...new Set([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, ...pinned])].sort((a, b) => a - b);
    }
    // [value, label] for the monitor Choice: Any, each connected monitor (stored as desc:… so the pin
    // survives a port change), and the current value when that monitor isn't connected.
    // A comma would split the generated `workspace =` line, so such a monitor is pinned by connector.
    // Twins (same description) are pinned by connector too: see Layout.js keyFor().
    function monitorValue(m) { return Geom.keyFor(m, page.connected); }
    function monitorOptions(current) {
        const opts = [["", "Any"]], seen = new Set([""]);
        for (const m of Hyprland.monitors.values) {
            const v = page.monitorValue(m);
            opts.push([v, m.name]); seen.add(v); seen.add(m.name);
        }
        // A desc: pin of connected twins (written before the second one came) is on both of them.
        const here = page.connected.some(m => m.description && "desc:" + m.description === current);
        if (current && !seen.has(current)) opts.push([current, current.replace(/^desc:/, "").slice(0, 24) + (here ? "" : " (unplugged)")]);
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
        const o = target === "" ? Settings.wallpaperImage : Settings.wallpaperMonitors?.[target];
        if (typeof o !== "string") return null;
        return o === "" || o === "moonrise" ? page.moonrise : o;
    }
    function wallPick(path) {
        // Moonrise is a setting, not the asset's path: "" for All (the shipped default stays the default),
        // "moonrise" for one monitor, so the shell picks the asset that fits that screen.
        const v = path !== page.moonrise ? path : page.wallTarget === "" ? "" : "moonrise";
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
        command: ["find", "-L", page.wallDir, "-maxdepth", "1", "-type", "f", "(", "-iname", "*.jpg", "-o", "-iname", "*.jpeg",
                  "-o", "-iname", "*.png", "-o", "-iname", "*.webp", ")", "-print0"]
        stdout: StdioCollector {
            onStreamFinished: page.wallFiles = text.split("\0").filter(f => f !== "").sort()
        }
    }
    Component.onCompleted: { maker.running = true; Hyprland.refreshMonitors(); page.queryAll(); page.rebuild(); }

    ColumnLayout {
        id: col
        width: page.width; spacing: 14

        Glyph { Layout.fillWidth: true; wrapMode: Text.WordWrap; color: Theme.muted; font.pixelSize: Theme.fontSmall
                text: "Drag the monitors to match your desk, drawn at their real size. Changes here wait for Apply, then you have 15 seconds to keep them." }
        Arrange {
            Layout.fillWidth: true
            mons: page.onMons; rects: page.rects; selected: page.selected
            onMoved: r => { page.rects = r; page.moved = true; }
            onPicked: k => page.selected = k
            onRotated: (k, dir) => page.rotate(k, dir)
        }
        // Switched off: off the canvas, a click puts it back. Unplugged: shown, but there is nothing to switch on.
        Flow {
            Layout.fillWidth: true; spacing: 6
            visible: page.displays.some(d => !page.on(d))
            Glyph { height: 26; text: "Off:"; color: Theme.muted; font.pixelSize: Theme.fontSmall }
            Repeater {
                model: page.displays.filter(d => !page.on(d))
                delegate: Rectangle {
                    id: chip
                    required property var modelData
                    readonly property bool plugged: modelData.o !== null
                    height: 26; width: chipText.implicitWidth + 18; radius: 6; color: Theme.surface; opacity: plugged ? 0.6 : 0.4
                    Glyph { id: chipText; anchors.centerIn: parent; font.pixelSize: Theme.fontSmall; color: Theme.fgDim
                            text: chip.modelData.name.slice(0, 32) + (chip.plugged ? "  · switch on" : "  · unplugged") }
                    MouseArea { anchors.fill: parent; enabled: chip.plugged; cursorShape: Qt.PointingHandCursor
                                onClicked: page.stage(chip.modelData, "enabled", true) }
                }
            }
        }
        RowLayout {
            Layout.fillWidth: true; spacing: 8
            Button { text: "Apply"; primary: true; enabled: page.dirty && page.blocked === ""; onClicked: page.apply() }
            Button { text: "Discard"; enabled: page.dirty; onClicked: page.discard() }
            Glyph { Layout.fillWidth: true; elide: Text.ElideRight; color: Theme.muted; font.pixelSize: Theme.fontSmall; text: page.blocked }
        }

        // The selected monitor's card (one at a time: a card each made the page long, the canvas
        // already says which monitor is which); its controls only stage. Switching it off
        // selects another monitor, and its chip above switches it back on.
        Repeater {
            model: page.displays.filter(d => (d.mon || page.on(d)) && d.key === page.selected)
            delegate: Pill {
                id: card
                required property var modelData
                readonly property var c: page.cur(modelData)
                readonly property var modes: {
                    const seen = new Set(), out = [];
                    for (const s of (modelData.o?.availableModes ?? [])) {
                        const k = page.modeKey(s);
                        if (!seen.has(k)) { seen.add(k); out.push(k); }
                    }
                    return out;
                }
                Layout.fillWidth: true; color: Theme.bgRaised; implicitHeight: inner.implicitHeight + 24
                border.color: page.selected === modelData.key ? Theme.accent : Theme.surface
                opacity: c.enabled ? 1 : 0.6
                ColumnLayout {
                    id: inner
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                    spacing: 10
                    RowLayout {
                        Layout.fillWidth: true
                        Glyph { text: card.modelData.name; font.bold: true; Layout.maximumWidth: 260; elide: Text.ElideRight
                                MouseArea { anchors.fill: parent; onClicked: page.selected = card.modelData.key } }
                        Glyph { Layout.fillWidth: true; color: Theme.muted; elide: Text.ElideRight
                                text: card.modelData.o?.description ?? "" }
                        Toggle { visible: page.displays.length > 1; label: "Enabled"; checked: card.c.enabled; onToggled: v => page.stage(card.modelData, "enabled", v) }
                    }
                    Flow {
                        visible: card.modelData.o !== null
                        Layout.fillWidth: true; spacing: 6
                        Repeater { model: card.modes.slice(0, 16)
                            delegate: Rectangle { required property string modelData
                                readonly property bool on: page.modeKey(card.c.mode) === modelData
                                height: 26; width: t.implicitWidth + 14; radius: 6
                                color: on ? Theme.accent : Theme.surface
                                Glyph { id: t; anchors.centerIn: parent; text: parent.modelData; font.pixelSize: 10; color: parent.on ? Theme.bg : Theme.fgDim }
                                MouseArea { anchors.fill: parent; onClicked: page.stage(card.modelData, "mode", parent.modelData) } } }
                    }
                    RowLayout {
                        visible: card.modelData.o !== null
                        spacing: 16
                        Stepper { label: "Scale"; value: typeof card.c.scale === "number" ? card.c.scale : 1; values: page.scalesFor(card.modelData); decimals: 2
                                  onChanged: v => page.stage(card.modelData, "scale", v) }
                        Choice { label: "Rotation"; value: card.c.transform; options: [[0, "0°"], [1, "90°"], [2, "180°"], [3, "270°"]]
                                 onPicked: v => page.stage(card.modelData, "transform", v) }
                    }
                }
            }
        }

        Glyph { text: "Wallpaper"; font.bold: true; Layout.topMargin: 10 }
        Glyph { Layout.fillWidth: true; wrapMode: Text.WordWrap; color: Theme.muted; font.pixelSize: Theme.fontSmall
                text: "Put images in ~/Pictures/Wallpapers (jpg, png, webp). A monitor's own pick overrides the one for all monitors." }
        RowLayout {
            Layout.fillWidth: true; spacing: 12
            Choice { label: "Monitor"; value: page.wallTarget
                     options: { const o = [["", "All"]]; for (const m of Hyprland.monitors.values) o.push([page.keyOf(m), m.name]); return o; }
                     onPicked: v => page.wallTarget = v }
            Item { Layout.fillWidth: true }
            Button { text: page.wallTarget === "" ? "Moonrise on all monitors" : "Same as all"; Layout.alignment: Qt.AlignBottom
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
