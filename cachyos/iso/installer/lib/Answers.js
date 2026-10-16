.pragma library
.import "Validate.js" as V

// How the target disk is named on screen. Disks without a model (virtio) use their name.
function confirmWord(d) { return d ? (d.model || d.path.split("/").pop()) : ""; }

// KEY=value lines for mbm-install, END-terminated (it reads until END).
// a.mounts: the ticked data disks, [{ uuid, path }] with path as typed (~ ok).
// Every value loses \r and \n: a pasted or IPC-set value must not be able to add
// a KEY= line of its own or an early END.
function text(a) {
    const one = v => String(v).replace(/[\r\n]/g, "");
    const home = "/home/" + a.username;
    const dm = a.mounts.map(m => m.uuid + ":" + V.expand(m.path, home)).join(",");
    const kv = [["DISK", a.disk], ["DISK_CONFIRMED", "yes"], ["HOSTNAME", a.hostname], ["TIMEZONE", a.timezone],
                ["USERNAME", a.username], ["USER_PASSWORD", a.password],
                ["LUKS_PASSPHRASE", a.sameLuks ? a.password : a.luks],
                ["XKB_LAYOUT", a.layout], ["XKB_VARIANT", a.variant], ["DATA_MOUNTS", dm]];
    return kv.map(([k, v]) => k + "=" + one(v)).concat(["END", ""]).join("\n");
}
