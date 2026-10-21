.pragma library
.import "Validate.js" as V

// How a drive kind (from the probe: nvme, ssd, hdd, usb) reads on screen.
const kinds = { nvme: "NVMe", ssd: "SATA SSD", hdd: "Hard disk", usb: "USB" };
function kindName(kind) { return kinds[kind] || kind; }

// The model when the drive reports one, else its device name (virtio has none).
function name(d) { return d.model || d.path.split("/").pop(); }

// The default folder for a new data drive: "~/<kind><n>" with the smallest n that
// is free. A folder is taken when its absolute path is in usedAbs; a label is
// taken when the folder's name (lowercased) is in usedLabels, since the label
// has to be unique on the machine and defaults to that name.
function suggest(kind, home, usedAbs, usedLabels) {
    for (let n = 1; ; n++) {
        const base = kind + n;
        if (usedAbs.includes(V.expand("~/" + base, home))) continue;
        if (usedLabels.includes(base.toLowerCase())) continue;
        return "~/" + base;
    }
}

// The default label: the folder's name, cut to the 16 bytes a filesystem label
// allows. Folder names are ASCII (V.mountPath), so a character cut is a byte cut.
function labelFor(path) { return path.split("/").pop().slice(0, 16); }
