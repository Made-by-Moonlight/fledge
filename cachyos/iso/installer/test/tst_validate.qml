import QtQuick
import QtTest
import "../lib/Validate.js" as V
import "../lib/Progress.js" as P
import "../lib/Answers.js" as A
import "../lib/Drives.js" as D

TestCase {
    name: "installer"
    function test_drivesNames() {
        compare(D.kindName("ssd"), "SATA SSD");
        compare(D.name({ path: "/dev/vdc", model: "" }), "vdc");
        compare(D.suggest("nvme", "/home/e", ["/home/e/nvme2"], []), "~/nvme1");
        compare(D.suggest("nvme", "/home/e", ["/home/e/nvme1", "/home/e/nvme2"], []), "~/nvme3");
        compare(D.suggest("ssd", "/home/e", [], ["ssd1"]), "~/ssd2");
        compare(D.labelFor("~/games"), "games");
        compare(D.labelFor("/data/abcdefghijklmnopqrst"), "abcdefghijklmnop");
    }
    function test_dataLabel() {
        compare(V.dataLabel("nvme1"), ""); compare(V.dataLabel("Game Drive"), "");
        verify(V.dataLabel("") !== ""); verify(V.dataLabel(" x") !== "");
        verify(V.dataLabel("abcdefghijklmnopq") !== ""); verify(V.dataLabel("a:b") !== "");
    }
    function test_answersWipes() {
        const t = A.text({ disk: "/dev/vda", hostname: "h", timezone: "UTC", username: "e", password: "a",
                           sameLuks: true, luks: "", layout: "us", variant: "", mounts: [],
                           wipes: [{ disk: "/dev/vdc", path: "~/hdd1", label: "hdd1" }] });
        verify(t.endsWith("DATA_WIPES=hdd1:/home/e/hdd1:/dev/vdc\nEND\n"));
    }
    function test_username() {
        verify(V.username("ethan")); verify(V.username("_svc")); verify(V.username("e_b-2"));
        verify(!V.username("Ethan")); verify(!V.username("2e")); verify(!V.username("root"));
        verify(!V.username("systemd-x")); verify(!V.username(""));
    }
    function test_hostname() {
        verify(V.hostname("glaux")); verify(!V.hostname("Glaux")); verify(!V.hostname("-a")); verify(!V.hostname("a.b"));
    }
    function test_mountPath() {
        const h = "/home/ethan";
        compare(V.mountPath("~/storage1", h), "");
        compare(V.mountPath("/data", h), "");
        compare(V.mountPath("/mnt/games", h), "");
        verify(V.mountPath("~", h) !== "");
        verify(V.mountPath("/home/ethan", h) !== "");
        verify(V.mountPath("/home", h) !== "");
        verify(V.mountPath("/mnt", h) !== "");
        verify(V.mountPath("/var/x", h) !== "");
        verify(V.mountPath("storage", h) !== "");
        verify(V.mountPath("/data/", h) !== "");
        verify(V.mountPath("/a/../b", h) !== "");
        verify(V.mountPath("/my disk", h) !== "");
        verify(V.mountPath("~/.config", h) !== "");
        verify(V.mountPath("~/.local/share/x", h) !== "");
        verify(V.mountPath("/.data", h) !== "");
        compare(V.mountPath("/data/games.old", h), "");
        verify(V.mountPath("~/proj", h) !== "");
        verify(V.mountPath("~/proj/fledge", h) !== "");
        verify(V.mountPath("/home/other/proj", h) !== "");
        compare(V.mountPath("~/projects", h), "");
        compare(V.mountPath("~/storage1/proj", h), "");
        compare(V.expand("~/s", h), "/home/ethan/s");
        compare(V.expand("/x/~", h), "/x/~");
    }
    function test_firstInvalid() {
        compare(V.firstInvalid([]), -1);
        compare(V.firstInvalid([{ skipped: false, valid: true }, { skipped: true, valid: false }]), -1);
        compare(V.firstInvalid([{ skipped: false, valid: true }, { skipped: false, valid: false }, { skipped: false, valid: false }]), 1);
        compare(V.firstInvalid([{ skipped: true, valid: false }, { skipped: false, valid: false }]), 1);
    }
    function test_progress() {
        compare(P.parse("hello"), null);
        compare(P.parse("@@fledge stage base Base system").id, "base");
        compare(P.parse("@@fledge count 3 40").n, 3);
        compare(P.parse("@@fledge count 3 40").m, 40);
        compare(P.parse("@@fledge fail desktop").kind, "fail");
        compare(P.parse("@@fledge done").kind, "done");
        const ids = ["prepare", "disk", "base", "config", "boot", "desktop", "finish"];
        compare(P.fraction(ids, {}, "", 0, 0), 0);
        compare(P.fraction(ids, { prepare: true, disk: true, base: true, config: true, boot: true, desktop: true, finish: true }, "", 0, 0), 1);
        const half = P.fraction(ids, { prepare: true, disk: true }, "base", 20, 40);
        verify(half > 0.2 && half < 0.3);
    }
    function test_confirmWord() {
        compare(A.confirmWord({ path: "/dev/nvme2n1", model: "WD Blue SN570 1TB" }), "WD Blue SN570 1TB");
        compare(A.confirmWord({ path: "/dev/vda", model: "" }), "vda");
        compare(A.confirmWord(null), "");
    }
    function test_answers() {
        const t = A.text({ disk: "/dev/vda", hostname: "glaux", timezone: "Europe/London", username: "ethan",
                           password: "pw one", sameLuks: true, luks: "", layout: "gb", variant: "",
                           mounts: [{ uuid: "u-1", path: "~/storage1" }, { uuid: "u-2", path: "/data" }] });
        compare(t, "DISK=/dev/vda\nDISK_CONFIRMED=yes\nHOSTNAME=glaux\nTIMEZONE=Europe/London\nUSERNAME=ethan\n"
                 + "USER_PASSWORD=pw one\nLUKS_PASSPHRASE=pw one\nXKB_LAYOUT=gb\nXKB_VARIANT=\n"
                 + "DATA_MOUNTS=u-1:/home/ethan/storage1,u-2:/data\nDATA_WIPES=\nEND\n");
        const own = A.text({ disk: "/dev/vda", hostname: "h", timezone: "UTC", username: "e", password: "a",
                             sameLuks: false, luks: "b", layout: "us", variant: "", mounts: [] });
        verify(own.includes("LUKS_PASSPHRASE=b\n"));
        verify(own.includes("DATA_MOUNTS=\n"));
    }
    // A pasted or IPC-set value must not add a KEY= line or end the file early.
    function test_answersNoNewlines() {
        const t = A.text({ disk: "/dev/vda", hostname: "glaux", timezone: "UTC", username: "ethan",
                           password: "pw\nEND\nDISK=/dev/sda", sameLuks: true, luks: "", layout: "us\r\n", variant: "",
                           mounts: [{ uuid: "u-1\n", path: "/data\r" }] });
        compare(t.split("\n").length, 13);
        compare(t.indexOf("\r"), -1);
        verify(t.includes("USER_PASSWORD=pwENDDISK=/dev/sda\n"));
        verify(t.includes("LUKS_PASSPHRASE=pwENDDISK=/dev/sda\n"));
        verify(t.includes("XKB_LAYOUT=us\n"));
        verify(t.includes("DATA_MOUNTS=u-1:/data\n"));
    }
}
