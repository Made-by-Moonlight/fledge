.pragma library

// xdg-desktop-portal-hyprland's window list and picker answer (SharePicker.qml).

// XDPH_WINDOW_SHARING_LIST: <handle>[HC>]<class>[HT>]<title>[HE>]<address>[HA>], repeated.
// A malformed entry is skipped rather than failing the whole list.
function parse(list) {
    const out = [];
    for (const e of (list ?? "").split("[HA>]")) {
        const m = e.match(/^([^[]+)\[HC>\]([\s\S]*)\[HT>\]([\s\S]*)\[HE>\]([\s\S]*)$/);
        if (m) out.push({ handle: m[1], cls: m[2], title: m[3], address: m[4] });
    }
    return out;
}

// Whether a Hyprland toplevel (its address: bare hex, "55b8f3e90fd0") is the list's window (its
// address in decimal, "94252854480848"). Window addresses fit a double's 53 bits exactly.
function sameWindow(hyprAddress, listAddress) {
    if (!/^(0x)?[0-9a-f]+$/i.test(hyprAddress ?? "") || !/^[0-9]+$/.test(listAddress ?? "")) return false;
    return parseInt(hyprAddress.replace(/^0x/i, ""), 16) === Number(listAddress);
}

// The line the picker answers with, without xdph's "[SELECTION]" prefix (lib/screenshare.sh adds it):
// "r" lets the app keep a restore token. kind: "window" (id: the list's handle) or "screen" (an output name).
function answer(kind, id, remember) {
    return (remember ? "r" : "") + "/" + kind + ":" + id;
}
