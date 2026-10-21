.pragma library

// The main monitor and which monitors show a bar. mons: the enabled monitors as
// [{key, x, y}] (key: Layout.js keyFor, x/y: Hyprland's layout position).

// The main monitor's key: mainKey when that monitor is there, else the top-left one
// (smallest y, then smallest x), so focus never moves it. "" with no monitors.
function pick(mons, mainKey) {
    if (mainKey && mons.some(m => m.key === mainKey)) return mainKey;
    let best = null;
    for (const m of mons)
        if (!best || m.y < best.y || (m.y === best.y && m.x < best.x)) best = m;
    return best ? best.key : "";
}

// The main monitor always shows the bar, even when hidden lists it; the others unless hidden.
function showsBar(key, mons, mainKey, hidden) {
    return key === pick(mons, mainKey) || !(hidden ?? []).includes(key);
}
