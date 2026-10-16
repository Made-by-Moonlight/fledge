pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "../lib/Validate.js" as V
import "../lib/Answers.js" as A

// Every answer and the step machine. Steps only read and set these; nothing
// leaves the UI until Review's "Erase and install" hands answers() to mbm-install.
Singleton {
    id: root
    readonly property bool dev: Quickshell.env("MBM_INSTALLER_DEV") === "1"
    readonly property string repo: Quickshell.env("MBM_REPO") || "/usr/share/slievr-cachy"
    // The white render (build-assets.sh): owl.svg is fill="currentColor", which Qt draws black.
    readonly property string owl: "file://" + repo + "/dot-local/share/mbm/assets/owl.png"

    readonly property var steps: [
        { id: "welcome", title: "Welcome", page: "Welcome" },
        { id: "keyboard", title: "Keyboard", page: "Keyboard" },
        { id: "network", title: "Network", page: "Network" },
        { id: "region", title: "Region", page: "Region" },
        { id: "account", title: "Account", page: "Account" },
        { id: "disk", title: "Disk", page: "Disk" },
        { id: "data", title: "Data disks", page: "DataDisks" },
        { id: "review", title: "Review", page: "Review" },
        { id: "install", title: "Install", page: "Installing" }
    ]
    function indexOf(id) { return steps.findIndex(s => s.id === id); }
    property int step: 0
    property int returnTo: -1          // Review's Edit: Next/Back come back here
    readonly property string current: steps[step].id

    property string layout: "us"
    property string variant: ""
    property string timezone: ""
    property string username: ""
    property string hostname: ""
    property string password: ""
    property string password2: ""
    property bool sameLuks: true
    property string luks: ""
    property string luks2: ""
    property string disk: ""           // kernel path, e.g. /dev/nvme2n1
    property bool diskConfirmed: false  // "Erase this disk" pressed for the current disk
    property var mounts: ({})          // uuid -> { on, path }

    readonly property var facts: Probe.facts
    readonly property var diskInfo: facts ? (facts.disks.find(d => d.path === disk) ?? null) : null
    readonly property string confirmWord: A.confirmWord(diskInfo)
    readonly property var dataRows: facts ? facts.datafs.filter(f => f.disk !== disk) : []
    readonly property string home: "/home/" + (username || "you")

    onDiskChanged: diskConfirmed = false
    onLayoutChanged: Xkb.apply(layout, variant)
    onVariantChanged: Xkb.apply(layout, variant)
    onFactsChanged: {
        if (!facts) return;
        if (timezone === "") timezone = facts.timezone;
        // Keep choices across a refresh; new filesystems get the profile default
        // (ticked) or the next free ~/storageN (unticked).
        const used = new Set(facts.datafs.map(f => f.mount).filter(p => p));
        const m = {};
        let n = 1;
        for (const f of facts.datafs) {
            if (mounts[f.uuid]) { m[f.uuid] = mounts[f.uuid]; continue; }
            if (f.mount) { m[f.uuid] = { on: true, path: f.mount }; continue; }
            while (used.has("~/storage" + n)) n++;
            used.add("~/storage" + n);
            m[f.uuid] = { on: false, path: "~/storage" + n };
        }
        mounts = m;
    }
    function setMount(uuid, on, path) {
        // Unchanged: no new object, so DataDisks' bound field writing back its own
        // text doesn't re-trigger its binding (a binding loop).
        const r = mounts[uuid];
        if (r && r.on === on && r.path === path) return;
        const m = Object.assign({}, mounts);
        m[uuid] = { on: on, path: path };
        mounts = m;
    }
    function mountError(uuid) {
        const r = mounts[uuid];
        if (!r || !r.on) return "";
        const e = V.mountPath(r.path, home);
        if (e) return e;
        const abs = V.expand(r.path, home);
        const clash = dataRows.some(o => o.uuid !== uuid && mounts[o.uuid]?.on && V.expand(mounts[o.uuid].path, home) === abs);
        return clash ? "Two disks can't share a folder" : "";
    }

    // step id -> { field: message }. Empty object: the step is complete.
    function errors(id) {
        const e = {};
        switch (id) {
        case "welcome":
            if (!facts) e.facts = "Looking at this machine…";
            else if (facts.leftover) e.leftover = "Clean up the previous attempt first";
            break;
        case "keyboard": if (layout === "") e.layout = "Pick a layout"; break;
        case "network": if (!Probe.online) e.net = "Not connected yet"; break;
        case "region": if (timezone === "") e.timezone = "Pick a timezone"; break;
        case "account":
            if (!V.username(username)) e.username = "Start with a lowercase letter; then lowercase letters, digits, _ or -, up to 32";
            if (!V.hostname(hostname)) e.hostname = "Lowercase letters, digits and -, up to 63";
            if (password === "") e.password = "Choose a password";
            else if (password !== password2) e.password2 = "Doesn't match";
            if (!sameLuks) {
                if (luks === "") e.luks = "Choose a passphrase";
                else if (luks !== luks2) e.luks2 = "Doesn't match";
            }
            break;
        case "disk":
            if (!diskInfo) e.disk = "Pick the disk to install to";
            else if (!diskConfirmed) e.confirm = "Confirm the erase to continue";
            break;
        case "data":
            for (const r of dataRows) { const m = mountError(r.uuid); if (m) e[r.uuid] = m; }
            break;
        }
        return e;
    }
    function valid(id) { return Object.keys(errors(id)).length === 0; }
    // Errors show once Next has been tried on a step, not while typing the first time.
    property var shown: ({})
    function show(id) { const s = Object.assign({}, shown); s[id] = true; shown = s; }
    function err(id, field) { return shown[id] ? (errors(id)[field] ?? "") : ""; }

    function skipped(i) {
        const id = steps[i].id;
        return (id === "network" && Probe.online) || (id === "data" && dataRows.length === 0);
    }
    function next() {
        if (current === "install") { primary(); return; }
        if (!valid(current)) { show(current); return; }
        if (current === "review") {
            // Review's Edit lets a step be left half-changed (Back doesn't check
            // everything a refresh can break either): re-check every earlier step
            // before anything is erased, and send the user to the first bad one.
            const bad = V.firstInvalid(steps.slice(0, step).map((s, i) => ({ skipped: skipped(i), valid: valid(s.id) })));
            if (bad >= 0) { show(steps[bad].id); returnTo = step; step = bad; return; }
            step = indexOf("install"); Run.start(answers()); return;
        }
        if (returnTo >= 0) { step = returnTo; returnTo = -1; return; }
        let i = step + 1;
        while (i < steps.length - 1 && skipped(i)) i++;
        step = i;
    }
    function back() {
        if (current === "install") return;
        // Back from Review's Edit returns to Review, so it must not carry a
        // half-edited step (an unconfirmed password, an unconfirmed disk) there.
        if (returnTo >= 0) {
            if (!valid(current)) { show(current); return; }
            step = returnTo; returnTo = -1; return;
        }
        let i = step - 1;
        while (i > 0 && skipped(i)) i--;
        step = Math.max(i, 0);
    }
    function edit(id) { returnTo = step; step = indexOf(id); }
    // The Installing page's main button, also on Return.
    function primary() {
        if (Run.state === "done") Run.reboot();
        else if (Run.state === "desktopFailed") Run.retryDesktop();
        else if (Run.state === "failed") Run.cleanup(() => { Probe.refresh(); step = indexOf("review"); });
    }

    // The answers file mbm-install reads (lib/Answers.js).
    function answers() {
        return A.text({ disk: disk, hostname: hostname, timezone: timezone, username: username,
                        password: password, sameLuks: sameLuks, luks: luks, layout: layout, variant: variant,
                        mounts: dataRows.filter(r => mounts[r.uuid]?.on).map(r => ({ uuid: r.uuid, path: mounts[r.uuid].path })) });
    }

    // The installer layer steps aside (Frame.qml) while the terminal is open.
    property bool terminal: false
    function openTerminal() { terminal = true; term.running = true; }
    Process {
        id: term
        command: root.dev ? ["kitty"] : ["foot", "--title", "terminal", "sh", "-c",
            "echo 'A root console is on Ctrl+Alt+F2 (log in as root, no password).'; exec bash -l"]
        onExited: root.terminal = false
    }
}
