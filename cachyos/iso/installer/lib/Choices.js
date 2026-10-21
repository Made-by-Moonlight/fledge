.pragma library
.import "Validate.js" as V
.import "Drives.js" as D

// The Data disks step: what to do with each drive besides the target, as pure
// functions over the installer's state (Installer.qml wraps them; it can't be
// loaded in a unit test). s = { facts, disk, home, choices, mounts, wipes }:
//   choices  disk path -> "leave" | "mount" | "wipe", only what the person picked
//   mounts   uuid -> { on, path, edited }
//   wipes    disk path -> { on, path, label, pathEdited, labelEdited, confirmed }
// A wipe's on always matches its drive's choice being "wipe", and a mount is on
// only on a drive whose choice is "mount" (names() keeps both true).
// Setters return the next { choices, mounts, wipes }, names recomputed, or null
// when nothing changes.

// A facts file from before drives[] (an old dev fixture) has no cards.
function drives(facts) { return facts?.drives ?? []; }
function dataDrives(facts, disk) { return drives(facts).filter(d => d.path !== disk); }
// Disk paths of the drives being wiped (never the target).
function wiped(s) { return dataDrives(s.facts, s.disk).filter(d => s.wipes[d.path]?.on).map(d => d.path); }
// The filesystems that can be mounted: not on the target, not on a drive being wiped.
function dataRows(facts, disk, wipedDisks) {
    return facts ? facts.datafs.filter(f => f.disk !== disk && !wipedDisks.includes(f.disk)) : [];
}

// What the person picked, else the default: Mount when profile.sh names a
// filesystem on the drive (those rows come ticked), else Leave alone. Never Wipe.
function choice(s, disk) {
    if (s.choices[disk]) return s.choices[disk];
    return s.facts && s.facts.datafs.some(f => f.disk === disk && f.mount) ? "mount" : "leave";
}

// The mounts and wipes that will happen, for the answers file.
function chosen(s) {
    return {
        mounts: dataRows(s.facts, s.disk, wiped(s)).filter(r => s.mounts[r.uuid]?.on).map(r => ({ uuid: r.uuid, path: s.mounts[r.uuid].path })),
        wipes: wiped(s).map(d => ({ disk: d, path: s.wipes[d].path, label: s.wipes[d].label }))
    };
}

// Fill in every row's and drive's folder (and a wipe's label), keeping choices
// and typed names across a probe refresh. A suggestion is not a reservation:
// an active item (a ticked mount, a wipe, off the target) keeps the folder it
// had when it became active, but an inactive one is re-suggested every time
// from what is taken now, so nothing idle holds a number.
function names(s) {
    const f = s.facts;
    if (!f) return { choices: s.choices, mounts: s.mounts, wipes: s.wipes };
    const home = s.home;
    const present = drives(f).map(d => d.path);
    const kind = {};
    for (const d of drives(f)) kind[d.path] = d.kind;
    const choices = {};
    for (const k in s.choices) if (present.includes(k)) choices[k] = s.choices[k];
    const t = { facts: f, disk: s.disk, choices: choices };

    const wipes = {};
    for (const d of drives(f)) {
        wipes[d.path] = Object.assign({ on: false, path: "", label: "", pathEdited: false, labelEdited: false, confirmed: false },
                                      s.wipes[d.path], { on: choices[d.path] === "wipe" });
    }
    const mounts = {};
    for (const r of f.datafs) {
        const m = Object.assign({}, s.mounts[r.uuid] ?? { on: !!r.mount, path: r.mount || "", edited: false });
        if (choice(t, r.disk) !== "mount") m.on = false;
        mounts[r.uuid] = m;
    }

    // Every folder item: a mount row or a drive's wipe.
    const items = f.datafs.map(r => ({ m: mounts[r.uuid], disk: r.disk, edited: mounts[r.uuid].edited, fixed: r.mount }))
        .concat(drives(f).map(d => ({ w: wipes[d.path], disk: d.path, edited: wipes[d.path].pathEdited, fixed: null })));
    const it = i => i.m || i.w;
    const active = i => i.disk !== s.disk && it(i).on;
    const defaults = f.datafs.filter(r => r.disk !== s.disk && r.mount).map(r => V.expand(r.mount, home));
    // Labels a new wipe's name must not take: every label on a drive that stays.
    // A drive's own labels never count against its wipe: the idle suggestion
    // is the one it keeps when Wipe is picked, and by then they're gone.
    const kept = drives(f).filter(d => d.path !== s.disk && !wipes[d.path].on);
    const labelsOn = d => d.parts.map(p => (p.label || "").toLowerCase()).filter(l => l);
    const partLabels = disk => [].concat(...kept.filter(d => d.path !== disk).map(labelsOn));

    // Names that are settled first (typed, a profile default, or an active
    // item's), then the rest against them: active ones before idle ones.
    const settled = i => i.edited || !!i.fixed || (active(i) && it(i).path !== "");
    for (const i of items) {
        if (i.edited) continue;
        if (i.fixed) it(i).path = i.fixed;
    }
    const pending = items.filter(i => !settled(i)).sort((a, b) => active(b) - active(a));
    for (const i of pending) {
        const others = items.filter(o => o !== i && active(o));
        const used = defaults.concat(others.map(o => V.expand(it(o).path, home)));
        const label = w => w.labelEdited ? w.label : D.labelFor(w.path);
        const labels = partLabels(i.w ? i.disk : null).concat(others.filter(o => o.w).map(o => label(o.w).toLowerCase()));
        it(i).path = D.suggest(kind[i.disk] || "hdd", home, used, labels);
    }
    for (const d of drives(f)) if (!wipes[d.path].labelEdited) wipes[d.path].label = D.labelFor(wipes[d.path].path);
    return { choices: choices, mounts: mounts, wipes: wipes };
}

function copy(s) {
    return { facts: s.facts, disk: s.disk, home: s.home, choices: Object.assign({}, s.choices),
             mounts: Object.assign({}, s.mounts), wipes: Object.assign({}, s.wipes) };
}

// "wipe" un-ticks the drive's mounts (they won't exist) and needs a fresh
// confirmation; "leave" un-ticks them too; "mount" ticks none by itself. Wipe is
// refused on the target and on a drive the live system is using.
function setChoice(s, disk, c) {
    const d = drives(s.facts).find(x => x.path === disk);
    if (!d || !["leave", "mount", "wipe"].includes(c) || choice(s, disk) === c) return null;
    if (c === "wipe" && (d.busy || disk === s.disk)) return null;
    const n = copy(s);
    n.choices[disk] = c;
    n.wipes[disk] = Object.assign({}, n.wipes[disk], { on: c === "wipe", confirmed: false });
    if (c !== "mount")
        for (const r of s.facts.datafs) if (r.disk === disk && n.mounts[r.uuid]) n.mounts[r.uuid] = Object.assign({}, n.mounts[r.uuid], { on: false });
    return names(n);
}

// edited left out: a path that differs from the stored one counts as typed.
// Ticking a row picks Mount for its drive.
function setMount(s, uuid, on, path, edited) {
    const r = s.mounts[uuid];
    const ed = edited === undefined ? (!!r?.edited || (!!r && r.path !== path)) : edited;
    // Unchanged: no new object, so DataDisks' bound field writing back its own
    // text doesn't re-trigger its binding (a binding loop).
    if (r && r.on === on && r.path === path && !!r.edited === ed) return null;
    const n = copy(s);
    n.mounts[uuid] = { on: on, path: path, edited: ed };
    const row = s.facts?.datafs.find(x => x.uuid === uuid);
    if (on && row && choice(s, row.disk) !== "mount") {
        n.choices[row.disk] = "mount";
        n.wipes[row.disk] = Object.assign({}, n.wipes[row.disk], { on: false, confirmed: false });
    }
    return names(n);
}

// Same text: no change, so a field bound to the suggestion writing it back
// doesn't mark it typed. The label follows the folder until it is typed itself.
function setWipePath(s, disk, path) {
    const w = s.wipes[disk];
    if (!w || w.path === path) return null;
    const n = copy(s);
    n.wipes[disk] = Object.assign({}, w, { path: path, pathEdited: true });
    return names(n);
}
function setWipeLabel(s, disk, label) {
    const w = s.wipes[disk];
    if (!w || w.label === label) return null;
    const n = copy(s);
    n.wipes[disk] = Object.assign({}, w, { label: label, labelEdited: true });
    return names(n);
}
function confirmWipe(s, disk) {
    const w = s.wipes[disk];
    if (!w || !w.on || w.confirmed || disk === s.disk) return null;
    const n = copy(s);
    n.wipes[disk] = Object.assign({}, w, { confirmed: true });
    return names(n);
}

// A new target: a wipe chosen on it drops out (wiped() and dataDrives skip the
// target) and needs confirming again should the target move back, like diskConfirmed.
function retarget(s) {
    const n = copy(s);
    if (n.wipes[s.disk]) n.wipes[s.disk] = Object.assign({}, n.wipes[s.disk], { confirmed: false });
    return names(n);
}

// The Data disks step's errors: { field: message }, keyed by uuid for a mount
// row and "wipe:", "label:", "confirm:" + disk path for a wipe.
function errors(s) {
    const e = {};
    const home = s.home;
    const w = wiped(s);
    const items = dataRows(s.facts, s.disk, w).filter(r => s.mounts[r.uuid]?.on).map(r => ({ key: r.uuid, path: s.mounts[r.uuid].path }))
        .concat(w.map(d => ({ key: "wipe:" + d, path: s.wipes[d].path })));
    for (const i of items) {
        const abs = V.expand(i.path, home);
        const m = V.mountPath(i.path, home) || (items.some(o => o !== i && V.expand(o.path, home) === abs) ? "Two disks can't share a folder" : "");
        if (m) e[i.key] = m;
    }
    // Labels on the target or another wiped drive go with it: only kept drives' count.
    const kept = dataDrives(s.facts, s.disk).filter(d => !w.includes(d.path));
    const taken = [].concat(...kept.map(d => d.parts.map(p => (p.label || "").toLowerCase()).filter(l => l)));
    for (const d of w) {
        const l = s.wipes[d].label;
        const clash = taken.includes(l.toLowerCase()) || w.some(o => o !== d && s.wipes[o].label.toLowerCase() === l.toLowerCase());
        const m = V.dataLabel(l) || (clash ? "Another drive is already called " + l : "");
        if (m) e["label:" + d] = m;
        if (!s.wipes[d].confirmed) e["confirm:" + d] = "Confirm the erase to continue";
    }
    return e;
}
