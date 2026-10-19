.pragma library
// Monitor arrangement maths for Settings › Displays. No Qt types.
//   mon:  { key, px: [w, h], mm: [w, h], scale, transform }   px = mode, mm = reported; both of the
//         unrotated panel (Hyprland still says 600×340 for a portrait BenQ).
//   rect: { key, x, y, w, h }   millimetres on the canvas, y down.
//   pos:  { key: [x, y] }       logical pixels, what Hyprland's monitor position takes.
// The canvas is drawn at physical size; Hyprland places monitors in logical px, and the cursor
// only crosses where edges meet exactly. So toLogical() takes the axis along a shared edge from
// the neighbour's logical edge (exact, whatever the densities) and only the offset across it
// from millimetres, at the neighbour's px per mm. Two monitors touch when they share an edge
// segment longer than EPS (0.5 mm; 0 in px); a corner alone doesn't count.

const EPS = 0.5;
const MM_PER_PX = 25.4 / 96;   // the 96 dpi fallback for a size we can't trust
const MIN_SHARE = 1;           // mm of edge settle() leaves shared, at least

function odd(m) { return (m.transform & 1) === 1; }
function swap(wh, m) { return odd(m) ? [wh[1], wh[0]] : [wh[0], wh[1]]; }

// Integer, like Hyprland's: a scale that doesn't divide the mode is Hyprland's to refuse.
function logical(m) { return swap([Math.round(m.px[0] / m.scale), Math.round(m.px[1] / m.scale)], m); }

// Zero (virtual outputs, projectors) or an aspect ratio 10% off the mode's (TVs): made up.
function trusted(m) {
    const mw = m.mm[0], mh = m.mm[1];
    if (!(mw > 0 && mh > 0 && m.px[0] > 0 && m.px[1] > 0)) return false;
    return Math.abs((mw / mh) / (m.px[0] / m.px[1]) - 1) <= 0.1;
}

function physical(m) {
    if (trusted(m)) return swap(m.mm, m);
    const l = logical(m);
    return [l[0] * MM_PER_PX, l[1] * MM_PER_PX];
}

// Logical px per mm.
function ppm(m) { return logical(m)[0] / physical(m)[0]; }

// "desc:Acer Technologies X34" -> "Acer Technologies X34"; a connector stays as it is.
function label(key) { return String(key).replace(/^desc:/, ""); }

function span(a0, a1, b0, b1) { return Math.min(a1, b1) - Math.max(a0, b0); }

// Which way b meets a: "x" (a vertical edge: side by side), "y" (one above the other) or "".
function meet(a, b, eps) {
    if (eps === undefined) eps = EPS;
    const side = Math.abs(a.x + a.w - b.x) <= eps || Math.abs(b.x + b.w - a.x) <= eps;
    if (side && span(a.y, a.y + a.h, b.y, b.y + b.h) > eps) return "x";
    const stack = Math.abs(a.y + a.h - b.y) <= eps || Math.abs(b.y + b.h - a.y) <= eps;
    if (stack && span(a.x, a.x + a.w, b.x, b.x + b.w) > eps) return "y";
    return "";
}

function touching(a, b, eps) { return meet(a, b, eps) !== ""; }

function overlaps(a, b, eps) {
    if (eps === undefined) eps = EPS;
    return span(a.x, a.x + a.w, b.x, b.x + b.w) > eps && span(a.y, a.y + a.h, b.y, b.y + b.h) > eps;
}

function copy(rects) { return rects.map(q => ({ key: q.key, x: q.x, y: q.y, w: q.w, h: q.h })); }

// Overlap, floating and unreachable messages, worded as toLogical() refuses them. Two pairs
// that each touch but not each other are refused too: the cursor must reach every screen.
function problems(rects, eps) {
    const out = [];
    for (let i = 0; i < rects.length; i++)
        for (let j = i + 1; j < rects.length; j++)
            if (overlaps(rects[i], rects[j], eps)) out.push(label(rects[i].key) + " and " + label(rects[j].key) + " overlap");
    if (rects.length < 2) return out;
    const alone = rects.filter(a => !rects.some(b => b !== a && touching(a, b, eps)));
    for (const a of alone) out.push(label(a.key) + " doesn't touch another monitor");
    const reached = new Set([rects[0]]), queue = [rects[0]];
    while (queue.length) {
        const a = queue.shift();
        for (const b of rects)
            if (!reached.has(b) && touching(a, b, eps)) { reached.add(b); queue.push(b); }
    }
    for (const a of rects)
        if (!reached.has(a) && !alone.includes(a)) out.push(label(a.key) + " can't be reached from " + label(rects[0].key));
    return out;
}

function byKeyOrder(a, b) { return a.key < b.key ? -1 : a.key > b.key ? 1 : 0; }

// Grows the placed set one monitor at a time over pairs that meet (eps as in meet()), always
// taking the pair whose offset across the shared edge is smallest (aligned edges first), ties
// by key: Hyprland lists monitors in no fixed order, and the result mustn't depend on it.
// place(p, c, axis) positions c from placed p; rects should be sorted by key.
function grow(rects, placed, eps, place) {
    for (;;) {
        let best = null;
        for (const p of rects) {
            if (!placed.has(p.key)) continue;
            for (const c of rects) {
                if (placed.has(c.key)) continue;
                const axis = meet(p, c, eps);
                if (!axis) continue;
                const off = axis === "x"
                    ? Math.min(Math.abs(c.y - p.y), Math.abs(c.y + c.h - p.y - p.h))
                    : Math.min(Math.abs(c.x - p.x), Math.abs(c.x + c.w - p.x - p.w));
                if (!best || off < best.off) best = { p: p, c: c, axis: axis, off: off };
            }
        }
        if (!best) return;
        place(best.p, best.c, best.axis);
        placed.add(best.c.key);
    }
}

// Logical positions -> mm rects. Anchor: the monitor at 0,0 (else the first), first in the result
// so toLogical() keeps it there. Each monitor is placed from a neighbour it touches in px:
// flush against its mm edge, offset across it at the neighbour's density. One touching nothing
// is placed from the anchor's density, so a hand-set gap or overlap still draws.
function fromLogical(mons, pos) {
    if (mons.length === 0) return [];
    const at = m => pos[m.key] || [0, 0];
    const px = {}, mm = {}, byKey = {};
    for (const m of mons) {
        const l = logical(m), p = physical(m);
        byKey[m.key] = m;
        px[m.key] = { key: m.key, x: at(m)[0], y: at(m)[1], w: l[0], h: l[1] };
        mm[m.key] = { key: m.key, x: 0, y: 0, w: p[0], h: p[1] };
    }
    const anchor = mons.find(m => at(m)[0] === 0 && at(m)[1] === 0) || mons[0];
    const list = Object.keys(px).map(k => px[k]).sort(byKeyOrder);
    const placed = new Set([anchor.key]);
    const place = (P, C, axis) => {
        const Q = mm[P.key], R = mm[C.key], d = ppm(byKey[P.key]);
        if (axis === "x") {
            R.x = C.x > P.x ? Q.x + Q.w : Q.x - R.w;
            R.y = Q.y + (C.y - P.y) / d;
        } else {
            R.y = C.y > P.y ? Q.y + Q.h : Q.y - R.h;
            R.x = Q.x + (C.x - P.x) / d;
        }
        // Also touching a placed one on the other axis (a wide monitor over two narrow
        // ones): flush against it too, as toLogical() lines it up.
        const other = axis === "x" ? "y" : "x";
        const q = list.find(o => o !== P && placed.has(o.key) && meet(o, C, 0) === other);
        if (q) {
            const O = mm[q.key];
            if (other === "x") R.x = C.x > q.x ? O.x + O.w : O.x - R.w;
            else R.y = C.y > q.y ? O.y + O.h : O.y - R.h;
        }
    };
    grow(list, placed, 0, place);
    const A = px[anchor.key], d = ppm(anchor);
    for (const C of list) {
        if (placed.has(C.key)) continue;
        mm[C.key].x = (C.x - A.x) / d;
        mm[C.key].y = (C.y - A.y) / d;
        placed.add(C.key);
        grow(list, placed, 0, place);
    }
    return [mm[anchor.key]].concat(mons.filter(m => m !== anchor).map(m => mm[m.key]));
}

// mm rects -> logical positions, rects[0] at 0,0: { ok, pos, error }. Grows outward over touching
// pairs; along the shared edge the parent's logical edge exactly, across it the mm offset
// rounded at the parent's density. A monitor that also touches a placed one on the other axis
// (a 2×2 grid) takes that axis from it exactly. Then checked in px: no overlap, nothing floating,
// every monitor reachable from rects[0], and every pair touching on the canvas touching exactly;
// else ok is false and error says why.
function toLogical(mons, rects) {
    const byKey = {};
    for (const m of mons) byKey[m.key] = m;
    const missing = rects.find(q => !byKey[q.key]);
    if (missing) return { ok: false, pos: {}, error: label(missing.key) + " isn't connected" };
    if (rects.length === 0) return { ok: true, pos: {}, error: "" };
    const pos = {}, from = {}, order = [];
    const size = k => logical(byKey[k]);
    const set = (k, x, y, src) => { pos[k] = [x, y]; from[k] = src; order.push(k); };
    // Placed in px, from parent p on axis: the edge exactly, the other axis from mm.
    const fromParent = (p, c, axis) => {
        const P = pos[p.key], d = ppm(byKey[p.key]), lp = size(p.key), lc = size(c.key);
        if (axis === "x") return [c.x > p.x ? P[0] + lp[0] : P[0] - lc[0], P[1] + Math.round((c.y - p.y) * d)];
        return [P[0] + Math.round((c.x - p.x) * d), c.y > p.y ? P[1] + lp[1] : P[1] - lc[1]];
    };
    const list = rects.slice().sort(byKeyOrder);
    const placed = new Set();
    const place = (p, c, axis) => {
        const xy = fromParent(p, c, axis), src = [p.key];
        const other = axis === "x" ? "y" : "x";
        const q = list.find(o => o !== p && placed.has(o.key) && meet(o, c) === other);
        if (q) {
            const xy2 = fromParent(q, c, other), i = other === "x" ? 0 : 1;
            xy[i] = xy2[i];
            src.push(q.key);
        }
        set(c.key, xy[0], xy[1], src);
    };
    const anchor = rects[0];
    set(anchor.key, 0, 0, []);
    placed.add(anchor.key);
    grow(list, placed, EPS, place);
    // Not reached from the anchor: placed from its density, for the checks below to name.
    const d = ppm(byKey[anchor.key]);
    for (const q of list) {
        if (placed.has(q.key)) continue;
        set(q.key, Math.round((q.x - anchor.x) * d), Math.round((q.y - anchor.y) * d), []);
        placed.add(q.key);
        grow(list, placed, EPS, place);
    }
    const px = rects.map(q => {
        const l = size(q.key);
        return { key: q.key, x: pos[q.key][0], y: pos[q.key][1], w: l[0], h: l[1] };
    });
    const found = problems(px, 0);
    if (found.length) return { ok: false, pos: pos, error: found[0] };
    for (let i = 0; i < rects.length; i++)
        for (let j = i + 1; j < rects.length; j++) {
            if (!touching(rects[i], rects[j]) || touching(px[i], px[j], 0)) continue;
            // Name the later-placed one and what else it lined up with.
            const [c, o] = order.indexOf(rects[i].key) > order.indexOf(rects[j].key)
                ? [rects[i].key, rects[j].key] : [rects[j].key, rects[i].key];
            const other = from[c].find(k => k !== o);
            return { ok: false, pos: pos, error: other !== undefined
                ? label(c) + " can't line up with both " + label(other) + " and " + label(o)
                : label(c) + " can't line up with " + label(o) };
        }
    return { ok: true, pos: pos, error: "" };
}

// Push r out of every overlap, each time the shortest way; a few passes for chains.
function pushOut(rects, r) {
    for (let pass = 0; pass < 4; pass++) {
        let moved = false;
        for (const o of rects) {
            if (o === r || !overlaps(r, o)) continue;
            const moves = [[o.x - r.w - r.x, 0], [o.x + o.w - r.x, 0], [0, o.y - r.h - r.y], [0, o.y + o.h - r.y]];
            moves.sort((a, b) => Math.abs(a[0] + a[1]) - Math.abs(b[0] + b[1]));
            r.x += moves[0][0];
            r.y += moves[0][1];
            moved = true;
        }
        if (!moved) break;
    }
}

function gap(a0, a1, b0, b1) { return Math.max(0, -span(a0, a1, b0, b1)); }

// The nearest snap target for one axis (edges meeting, edges or centres aligned) within snapMm
// of v, from monitors no further than snapMm away across the other axis.
function snapAxis(rects, r, v, snapMm, horizontal) {
    let best = v, dist = snapMm;
    for (const o of rects) {
        if (o === r) continue;
        const [o0, ol, rl] = horizontal ? [o.x, o.w, r.w] : [o.y, o.h, r.h];
        const across = horizontal ? gap(r.y, r.y + r.h, o.y, o.y + o.h) : gap(r.x, r.x + r.w, o.x, o.x + o.w);
        if (across > snapMm) continue;
        for (const t of [o0 + ol, o0 - rl, o0, o0 + ol - rl, o0 + ol / 2 - rl / 2]) {
            if (Math.abs(t - v) <= dist) { dist = Math.abs(t - v); best = t; }
        }
    }
    return best;
}

// Move key to x, y, snap within snapMm, then out of any overlap. New array; inputs untouched.
function drag(rects, key, x, y, snapMm) {
    const out = copy(rects), r = out.find(q => q.key === key);
    if (!r) return out;
    r.x = x;
    r.y = y;
    r.x = snapAxis(out, r, x, snapMm, true);
    r.y = snapAxis(out, r, y, snapMm, false);
    pushOut(out, r);
    return out;
}

// Out of any overlap, then, touching nothing, slid the shortest way until it shares at least
// MIN_SHARE of edge with some monitor (without landing on another).
function settle(rects, key) {
    const out = copy(rects), r = out.find(q => q.key === key);
    if (!r) return out;
    pushOut(out, r);
    if (out.length < 2 || out.some(o => o !== r && touching(r, o))) return out;
    const clamp = (v, lo, hi) => Math.min(Math.max(v, lo), hi);
    let best = null;
    for (const o of out) {
        if (o === r) continue;
        const sx = Math.min(MIN_SHARE, r.w, o.w), sy = Math.min(MIN_SHARE, r.h, o.h);
        const ys = [clamp(r.y, o.y - r.h + sy, o.y + o.h - sy), o.y - r.h + sy, o.y + o.h - sy];
        const xs = [clamp(r.x, o.x - r.w + sx, o.x + o.w - sx), o.x - r.w + sx, o.x + o.w - sx];
        const spots = [];
        for (const y of ys) spots.push([o.x - r.w, y], [o.x + o.w, y]);
        for (const x of xs) spots.push([x, o.y - r.h], [x, o.y + o.h]);
        for (const [x, y] of spots) {
            const c = { key: r.key, x: x, y: y, w: r.w, h: r.h };
            if (out.some(q => q !== r && overlaps(c, q))) continue;
            const dist = Math.hypot(x - r.x, y - r.y);
            if (!best || dist < best.dist) best = { x: x, y: y, dist: dist };
        }
    }
    if (best) {
        r.x = best.x;
        r.y = best.y;
    }
    return out;
}

// New size w × h about the same centre (a rotation, or a new mode or scale), then settled.
function rotate(rects, key, w, h) {
    const out = copy(rects), r = out.find(q => q.key === key);
    if (!r) return out;
    r.x += (r.w - w) / 2;
    r.y += (r.h - h) / 2;
    r.w = w;
    r.h = h;
    return settle(out, key);
}

// Canvas transform fitting every rect in width × height inside margin, centred:
// canvas = (ox + x * scale, oy + y * scale).
function fit(rects, width, height, margin) {
    if (rects.length === 0) return { scale: 1, ox: width / 2, oy: height / 2 };
    const x0 = Math.min(...rects.map(q => q.x)), x1 = Math.max(...rects.map(q => q.x + q.w));
    const y0 = Math.min(...rects.map(q => q.y)), y1 = Math.max(...rects.map(q => q.y + q.h));
    const scale = Math.max(0, Math.min((width - 2 * margin) / Math.max(x1 - x0, 1), (height - 2 * margin) / Math.max(y1 - y0, 1)));
    return { scale: scale, ox: (width - (x1 - x0) * scale) / 2 - x0 * scale, oy: (height - (y1 - y0) * scale) / 2 - y0 * scale };
}
