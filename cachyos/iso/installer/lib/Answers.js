.pragma library
.import "Validate.js" as V

// Typed to confirm the erase. Disks without a model (virtio) use their name.
function confirmWord(d) { return d ? (d.model || d.path.split("/").pop()) : ""; }

// KEY=value lines for mbm-install, END-terminated (it reads until END).
// a.mounts: the ticked data disks, [{ uuid, path }] with path as typed (~ ok).
function text(a) {
    const home = "/home/" + a.username;
    const dm = a.mounts.map(m => m.uuid + ":" + V.expand(m.path, home)).join(",");
    return ["DISK=" + a.disk, "DISK_CONFIRMED=yes", "HOSTNAME=" + a.hostname, "TIMEZONE=" + a.timezone,
            "USERNAME=" + a.username, "USER_PASSWORD=" + a.password,
            "LUKS_PASSPHRASE=" + (a.sameLuks ? a.password : a.luks),
            "XKB_LAYOUT=" + a.layout, "XKB_VARIANT=" + a.variant, "DATA_MOUNTS=" + dm, "END", ""].join("\n");
}
