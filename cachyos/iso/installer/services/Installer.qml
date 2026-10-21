pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "../lib/Validate.js" as V
import "../lib/Answers.js" as A
import "../lib/Choices.js" as C

// Every answer and the step machine. Steps only read and set these; nothing
// leaves the UI until Review's "Erase and install" hands answers() to fledge-install.
Singleton {
    id: root
    readonly property bool dev: Quickshell.env("FLEDGE_INSTALLER_DEV") === "1"
    readonly property string repo: Quickshell.env("FLEDGE_REPO") || "/usr/share/fledge"
    // The white render (build-assets.sh): owl.svg is fill="currentColor", which Qt draws black.
    readonly property string owl: "file://" + repo + "/dot-local/share/fledge/assets/owl.png"

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
    // The Data disks step (lib/Choices.js): a choice per drive, its mounts and its wipe.
    property var choices: ({})         // disk path -> "leave" | "mount" | "wipe", as picked
    property var mounts: ({})          // uuid -> { on, path, edited }
    property var wipes: ({})           // disk path -> { on, path, label, pathEdited, labelEdited, confirmed }

    readonly property var facts: Probe.facts
    readonly property var diskInfo: facts ? (facts.disks.find(d => d.path === disk) ?? null) : null
    readonly property string confirmWord: A.confirmWord(diskInfo)
    readonly property var dataDrives: C.dataDrives(facts, disk)   // the Data disks cards
    // The wiped drives as a string: it signals only when the set changes, so
    // dataRows (a Repeater model) isn't rebuilt on every keystroke in a folder.
    readonly property string wiped: C.wiped({ facts: facts, disk: disk, wipes: wipes }).join("\n")
    readonly property var dataRows: C.dataRows(facts, disk, wiped ? wiped.split("\n") : [])
    readonly property string home: "/home/" + (username || "you")

    onDiskChanged: { diskConfirmed = false; apply(C.retarget(st())); }
    onLayoutChanged: Xkb.apply(layout, variant)
    onVariantChanged: Xkb.apply(layout, variant)
    onFactsChanged: {
        if (!facts) return;
        if (timezone === "") timezone = facts.timezone;
        // Keeps choices and typed names across a refresh; new filesystems get the
        // profile default (ticked) or the next free ~/<kind><n> (unticked).
        apply(C.names(st()));
    }
    function st() { return { facts: facts, disk: disk, home: home, choices: choices, mounts: mounts, wipes: wipes }; }
    // Assign only what changed: a new object re-runs every binding on it.
    function apply(n) {
        if (!n) return;
        if (JSON.stringify(n.choices) !== JSON.stringify(choices)) choices = n.choices;
        if (JSON.stringify(n.mounts) !== JSON.stringify(mounts)) mounts = n.mounts;
        if (JSON.stringify(n.wipes) !== JSON.stringify(wipes)) wipes = n.wipes;
    }
    function choice(disk) { return C.choice(st(), disk); }
    function setChoice(disk, c) { apply(C.setChoice(st(), disk, c)); }
    // edited left out: a path that differs from the stored one counts as typed.
    // Unchanged is a no-op (Choices.setMount), so DataDisks' bound field writing
    // back its own text doesn't re-trigger its binding (a binding loop).
    function setMount(uuid, on, path, edited) { apply(C.setMount(st(), uuid, on, path, edited)); }
    function setWipePath(disk, path) { apply(C.setWipePath(st(), disk, path)); }
    function setWipeLabel(disk, label) { apply(C.setWipeLabel(st(), disk, label)); }
    function confirmWipe(disk) { apply(C.confirmWipe(st(), disk)); }
    function names() { apply(C.names(st())); }

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
        case "data": Object.assign(e, C.errors(st())); break;
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
        return (id === "network" && Probe.online) || (id === "data" && dataDrives.length === 0);
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

    // The answers file fledge-install reads (lib/Answers.js).
    function answers() {
        const c = C.chosen(st());
        return A.text({ disk: disk, hostname: hostname, timezone: timezone, username: username,
                        password: password, sameLuks: sameLuks, luks: luks, layout: layout, variant: variant,
                        mounts: c.mounts, wipes: c.wipes });
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
