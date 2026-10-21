import QtQuick
import QtTest
import "../lib/Choices.js" as C
import "../lib/Answers.js" as A

// The Data disks step's state (lib/Choices.js). Installer.qml is a Quickshell
// singleton qmltestrunner can't load, so ins mirrors its wrappers over Choices.js.
TestCase {
    name: "choices"

    QtObject {
        id: ins
        property var facts: null
        property string disk: ""
        readonly property string home: "/home/e"
        property var choices: ({})
        property var mounts: ({})
        property var wipes: ({})
        property var shown: ({})
        readonly property var dataDrives: C.dataDrives(facts, disk)
        readonly property string wiped: C.wiped({ facts: facts, disk: disk, wipes: wipes }).join("\n")
        readonly property var dataRows: C.dataRows(facts, disk, wiped ? wiped.split("\n") : [])
        function st() { return { facts: facts, disk: disk, home: home, choices: choices, mounts: mounts, wipes: wipes }; }
        function apply(n) {
            if (!n) return;
            if (JSON.stringify(n.choices) !== JSON.stringify(choices)) choices = n.choices;
            if (JSON.stringify(n.mounts) !== JSON.stringify(mounts)) mounts = n.mounts;
            if (JSON.stringify(n.wipes) !== JSON.stringify(wipes)) wipes = n.wipes;
        }
        onFactsChanged: apply(C.names(st()))
        onDiskChanged: apply(C.retarget(st()))
        function choice(d) { return C.choice(st(), d); }
        function setChoice(d, c) { apply(C.setChoice(st(), d, c)); }
        function setMount(u, on, p, ed) { apply(C.setMount(st(), u, on, p, ed)); }
        function setWipePath(d, p) { apply(C.setWipePath(st(), d, p)); }
        function setWipeLabel(d, l) { apply(C.setWipeLabel(st(), d, l)); }
        function confirmWipe(d) { apply(C.confirmWipe(st(), d)); }
        function errors(id) { return id === "data" ? C.errors(st()) : {}; }
        function show(id) { const s = Object.assign({}, shown); s[id] = true; shown = s; }
        function err(id, field) { return shown[id] ? (errors(id)[field] ?? "") : ""; }
        function answers() {
            const c = C.chosen(st());
            return A.text({ disk: disk, hostname: "h", timezone: "UTC", username: "e", password: "a", sameLuks: true,
                            luks: "", layout: "us", variant: "", mounts: c.mounts, wipes: c.wipes });
        }
    }

    // The user's machine: the Predator is the target, the SN570 holds only an old
    // LUKS install, the Rocket and the MX500 have profile.sh defaults.
    function drive(path, kind, parts, busy) {
        return { path: path, size: 1e12, model: path.split("/").pop().toUpperCase(), tran: kind === "nvme" ? "nvme" : "sata",
                 kind: kind, busy: busy || "", parts: parts };
    }
    function stub(order) {
        const d = {
            "/dev/nvme1n1": drive("/dev/nvme1n1", "nvme", []),
            "/dev/nvme0n1": drive("/dev/nvme0n1", "nvme", [{ path: "/dev/nvme0n1p2", size: 1e12, fstype: "crypto_LUKS", label: "" }]),
            "/dev/nvme2n1": drive("/dev/nvme2n1", "nvme", [{ path: "/dev/nvme2n1p1", size: 1e12, fstype: "ext4", label: "rocket" }]),
            "/dev/sdb": drive("/dev/sdb", "ssd", [{ path: "/dev/sdb1", size: 2e12, fstype: "ext4", label: "ssd2" }])
        };
        return { timezone: "UTC", disks: [],
                 drives: (order || ["/dev/nvme1n1", "/dev/nvme0n1", "/dev/nvme2n1", "/dev/sdb"]).map(p => d[p]),
                 datafs: [{ uuid: "S", fstype: "ext4", label: "rocket", size: 1e12, disk: "/dev/nvme2n1", mount: "~/nvme2" },
                          { uuid: "C", fstype: "ext4", label: "ssd2", size: 2e12, disk: "/dev/sdb", mount: "~/ssd1" }] };
    }
    function reset(order) {
        ins.facts = null; ins.disk = ""; ins.choices = {}; ins.mounts = {}; ins.wipes = {}; ins.shown = {};
        ins.facts = stub(order);
        ins.disk = "/dev/nvme1n1";
    }
    function init() { reset(); }

    function test_sn570GetsNvme1() {
        ins.disk = "/dev/nvme1n1"; ins.setChoice("/dev/nvme0n1", "wipe");
        compare(ins.wipes["/dev/nvme0n1"].path, "~/nvme1"); compare(ins.wipes["/dev/nvme0n1"].label, "nvme1");
    }
    function test_sn570AnyOrder() {
        reset(["/dev/sdb", "/dev/nvme2n1", "/dev/nvme0n1", "/dev/nvme1n1"]);
        ins.setChoice("/dev/nvme0n1", "wipe");
        compare(ins.wipes["/dev/nvme0n1"].path, "~/nvme1"); compare(ins.wipes["/dev/nvme0n1"].label, "nvme1");
    }
    function test_labelFollowsFolderUntilTyped() {
        ins.setChoice("/dev/nvme0n1", "wipe");
        ins.setWipePath("/dev/nvme0n1", "~/games"); compare(ins.wipes["/dev/nvme0n1"].label, "games");
        ins.setWipeLabel("/dev/nvme0n1", "Fast"); ins.setWipePath("/dev/nvme0n1", "~/g2"); compare(ins.wipes["/dev/nvme0n1"].label, "Fast");
    }
    function test_labelClashIgnoresCase() {
        ins.setChoice("/dev/nvme0n1", "wipe");
        ins.setWipeLabel("/dev/nvme0n1", "SSD2"); ins.show("data");
        compare(ins.err("data", "label:/dev/nvme0n1"), "Another drive is already called SSD2");
    }
    function test_confirmRequired() {
        ins.setChoice("/dev/nvme0n1", "wipe");
        verify(ins.errors("data")["confirm:/dev/nvme0n1"] !== undefined); ins.confirmWipe("/dev/nvme0n1");
        compare(ins.errors("data")["confirm:/dev/nvme0n1"], undefined);
    }
    function test_choiceSwitching() {
        ins.setChoice("/dev/nvme2n1", "wipe"); compare(ins.mounts["S"].on, false);
        ins.confirmWipe("/dev/nvme2n1");
        ins.setChoice("/dev/nvme2n1", "mount"); ins.setChoice("/dev/nvme2n1", "wipe"); compare(ins.wipes["/dev/nvme2n1"].confirmed, false);
    }
    function test_wipeHidesItsRows() {
        ins.setChoice("/dev/nvme2n1", "wipe");
        verify(!ins.dataRows.some(r => r.uuid === "S"));
    }
    function test_targetDropsWipe() {
        ins.setChoice("/dev/nvme0n1", "wipe"); ins.confirmWipe("/dev/nvme0n1");
        ins.disk = "/dev/nvme0n1"; verify(ins.answers().includes("DATA_WIPES=\n"));
        ins.disk = "/dev/nvme1n1"; compare(ins.wipes["/dev/nvme0n1"].confirmed, false);
    }
    function test_refreshKeepsChoices() {
        ins.setChoice("/dev/nvme0n1", "wipe");
        ins.setWipePath("/dev/nvme0n1", "~/fast");
        const f = stub(); f.drives.push(drive("/dev/sdc", "usb", [])); ins.facts = f;
        compare(ins.wipes["/dev/nvme0n1"].path, "~/fast"); compare(ins.choice("/dev/nvme0n1"), "wipe");
    }
    function test_neverWipeByDefault() {
        verify(Object.values(ins.wipes).every(w => !w.on));
        verify(Object.keys(ins.wipes).length > 0);
    }

    // Beyond the brief: the rulings (stored choice, defaults, busy, names that
    // aren't reservations) and the answers.
    function test_choiceDefaults() {
        compare(ins.choice("/dev/nvme2n1"), "mount"); compare(ins.choice("/dev/sdb"), "mount");
        compare(ins.choice("/dev/nvme0n1"), "leave");
        compare(ins.mounts["S"].on, true); compare(ins.mounts["S"].path, "~/nvme2");
    }
    function test_mountWithNothingTicked() {
        ins.setMount("S", false, "~/nvme2");
        compare(ins.choice("/dev/nvme2n1"), "mount");
        verify(!ins.answers().includes("S:"));
    }
    function test_leaveUnticks() {
        ins.setChoice("/dev/sdb", "leave"); compare(ins.mounts["C"].on, false);
        verify(ins.answers().includes("DATA_MOUNTS=S:/home/e/nvme2\n"));
        ins.setChoice("/dev/sdb", "mount"); compare(ins.mounts["C"].on, false);   // "mount" ticks none by itself
    }
    function test_tickingPicksMount() {
        ins.setChoice("/dev/sdb", "leave"); ins.setMount("C", true, "~/ssd1");
        compare(ins.choice("/dev/sdb"), "mount");
        verify(ins.answers().includes("DATA_MOUNTS=S:/home/e/nvme2,C:/home/e/ssd1\n"));
    }
    function test_busyRefused() {
        const f = stub(); f.drives[1].busy = "lvm"; ins.facts = f;
        ins.setChoice("/dev/nvme0n1", "wipe");
        compare(ins.choice("/dev/nvme0n1"), "leave"); compare(ins.wipes["/dev/nvme0n1"].on, false);
    }
    function test_targetRefused() {
        ins.setChoice("/dev/nvme1n1", "wipe"); compare(ins.wipes["/dev/nvme1n1"].on, false);
    }
    function test_suggestionsAreNotReservations() {
        // The SN570, wiped first, holds ~/nvme1; the Rocket then takes the next name
        // free of profile defaults (its own ~/nvme2 counts: it's off the target).
        ins.setChoice("/dev/nvme0n1", "wipe");
        ins.setChoice("/dev/nvme2n1", "wipe");
        compare(ins.wipes["/dev/nvme0n1"].path, "~/nvme1");
        compare(ins.wipes["/dev/nvme2n1"].path, "~/nvme3");
        // Left alone again, the SN570 shows a fresh suggestion; the active Rocket keeps its name.
        ins.setChoice("/dev/nvme0n1", "leave");
        compare(ins.wipes["/dev/nvme0n1"].path, "~/nvme1");
        ins.setChoice("/dev/nvme0n1", "wipe");
        compare(ins.wipes["/dev/nvme2n1"].path, "~/nvme3");
        compare(ins.wipes["/dev/nvme0n1"].path, "~/nvme1");
    }
    function test_editedMountSticks() {
        ins.setMount("S", true, "~/games");
        compare(ins.mounts["S"].edited, true);
        ins.facts = stub(); compare(ins.mounts["S"].path, "~/games");
    }
    function test_wipeFolderClash() {
        ins.setChoice("/dev/nvme0n1", "wipe"); ins.setWipePath("/dev/nvme0n1", "~/ssd1");
        compare(ins.errors("data")["wipe:/dev/nvme0n1"], "Two disks can't share a folder");
        compare(ins.errors("data")["C"], "Two disks can't share a folder");
        ins.setWipePath("/dev/nvme0n1", "/etc/x");
        compare(ins.errors("data")["wipe:/dev/nvme0n1"], "That's a system folder");
    }
    function test_wipedLabelsDontClash() {
        // The Rocket's "rocket" label goes with the Rocket when it's wiped too.
        ins.setChoice("/dev/nvme2n1", "wipe"); ins.setChoice("/dev/nvme0n1", "wipe");
        ins.setWipeLabel("/dev/nvme0n1", "Rocket");
        compare(ins.errors("data")["label:/dev/nvme0n1"], undefined);
        ins.setWipeLabel("/dev/nvme2n1", "rocket");
        compare(ins.errors("data")["label:/dev/nvme0n1"], "Another drive is already called Rocket");
    }
    function test_answersWipes() {
        ins.setChoice("/dev/nvme0n1", "wipe"); ins.confirmWipe("/dev/nvme0n1");
        verify(ins.answers().includes("DATA_WIPES=nvme1:/home/e/nvme1:/dev/nvme0n1\n"));
    }
}
