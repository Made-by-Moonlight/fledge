import QtQuick
import QtTest
import "../lib/Validate.js" as V
import "../lib/Progress.js" as P

TestCase {
    name: "installer"
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
        compare(V.expand("~/s", h), "/home/ethan/s");
        compare(V.expand("/x/~", h), "/x/~");
    }
    function test_progress() {
        compare(P.parse("hello"), null);
        compare(P.parse("@@mbm stage base Base system").id, "base");
        compare(P.parse("@@mbm count 3 40").n, 3);
        compare(P.parse("@@mbm count 3 40").m, 40);
        compare(P.parse("@@mbm fail desktop").kind, "fail");
        compare(P.parse("@@mbm done").kind, "done");
        const ids = ["prepare", "disk", "base", "config", "boot", "desktop", "finish"];
        compare(P.fraction(ids, {}, "", 0, 0), 0);
        compare(P.fraction(ids, { prepare: true, disk: true, base: true, config: true, boot: true, desktop: true, finish: true }, "", 0, 0), 1);
        const half = P.fraction(ids, { prepare: true, disk: true }, "base", 20, 40);
        verify(half > 0.2 && half < 0.3);
    }
}
