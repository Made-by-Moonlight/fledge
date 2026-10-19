import QtQuick
import QtTest
import "../settings/Layout.js" as L

TestCase {
    name: "layout"
    // The user's desk (hyprctl monitors -j, 2026-10-19): mm are the unrotated panel's.
    readonly property var acer: ({ key: "desc:Acer", px: [3440, 1440], mm: [800, 350], scale: 1, transform: 0 })
    readonly property var benqL: ({ key: "desc:BenqL", px: [2560, 1440], mm: [600, 340], scale: 1, transform: 1 })
    readonly property var benqR: ({ key: "desc:BenqR", px: [2560, 1440], mm: [600, 340], scale: 1, transform: 3 })

    function r(key, x, y, w, h) { return { key: key, x: x, y: y, w: w, h: h }; }
    function find(rects, key) { return rects.find(q => q.key === key); }
    function overlapping(rects) {
        for (let i = 0; i < rects.length; i++)
            for (let j = i + 1; j < rects.length; j++)
                if (L.overlaps(rects[i], rects[j])) return true;
        return false;
    }
    function permutations(xs) {
        if (xs.length <= 1) return [xs];
        const out = [];
        xs.forEach((x, i) => {
            for (const rest of permutations(xs.slice(0, i).concat(xs.slice(i + 1)))) out.push([x].concat(rest));
        });
        return out;
    }
    // Hyprland lists monitors in no fixed order: every order draws the same valid layout and
    // gives it back.
    function roundTripsInAnyOrder(mons, pos) {
        const drawn = rects => rects.slice().sort((a, b) => a.key < b.key ? -1 : 1)
            .map(q => [q.key, q.x, q.y, q.w, q.h].map(v => typeof v === "number" ? Math.round(v * 1000) / 1000 : v));
        let first = null;
        for (const order of permutations(mons)) {
            const tag = order.map(m => m.key).join(",");
            const rects = L.fromLogical(order, pos);
            if (first === null) first = drawn(rects);
            compare(drawn(rects), first, tag);
            compare(L.problems(rects), [], tag);
            // Placed from where the anchor is now (as the page does), whether that's 0,0 or not.
            const origin = pos[rects[0].key];
            const out = L.toLogical(order, rects, origin);
            verify(out.ok, tag + ": " + out.error);
            compare(out.pos, pos, tag);
            // The canvas keeps the anchor first; the rest come in whatever order.
            const back = L.toLogical(order, [rects[0]].concat(rects.slice(1).reverse()), origin);
            compare(back.pos, pos, tag + " (reversed)");
        }
    }
    function touchesAny(rects, key) {
        const a = find(rects, key);
        return rects.some(b => b.key !== key && L.touching(a, b));
    }

    function test_sizes() {
        compare(L.logical(benqL), [1440, 2560]);
        compare(L.physical(benqL), [340, 600]);
        compare(L.logical({ key: "k", px: [3840, 2160], mm: [600, 340], scale: 1.5, transform: 0 }), [2560, 1440]);
        verify(L.trusted(acer));
        verify(!L.trusted({ key: "k", px: [1920, 1080], mm: [0, 0], scale: 1, transform: 0 }));
        // A portrait panel claiming landscape mm: the aspect ratios disagree.
        verify(!L.trusted({ key: "k", px: [1440, 2560], mm: [160, 90], scale: 1, transform: 0 }));
        compare(L.physical({ key: "k", px: [1920, 1080], mm: [0, 0], scale: 1, transform: 0 }), [508, 285.75]);
    }
    // A 16:9 mode on the 21:9 Acer: still its real size, judged by the native mode.
    function test_trust_follows_native_mode() {
        const hd = { key: "desc:Acer", px: [1920, 1080], mm: [800, 350], scale: 1, transform: 0, native: [3440, 1440] };
        verify(L.trusted(hd));
        compare(L.physical(hd), [800, 350]);
        fuzzyCompare(L.ppm(hd), 1920 / 800, 1e-9);
        // Without a native mode the current one stands in.
        verify(!L.trusted({ key: "desc:Acer", px: [1920, 1080], mm: [800, 350], scale: 1, transform: 0 }));
    }
    // Only scales that divide the mode: Hyprland swaps any other (1.75 on 1080p) for a nearby one.
    function test_scales() {
        const hd = L.scales([1920, 1080], 0.5, 3);
        verify(hd.indexOf(1.25) >= 0 && hd.indexOf(1.5) >= 0 && hd.indexOf(2) >= 0 && hd.indexOf(1.6) >= 0);
        verify(hd.indexOf(1.75) < 0);
        compare(hd[0], 0.5);
        compare(hd[hd.length - 1], 3);
        for (const s of hd) {
            verify(Math.abs(1920 / s - Math.round(1920 / s)) < 1e-9 && Math.abs(1080 / s - Math.round(1080 / s)) < 1e-9, String(s));
        }
        verify(L.scales([1280, 800], 0.5, 3).indexOf(1.5) < 0);
        compare(L.nearestScale([1920, 1080], 1.75, 0.5, 3), 1.6666666666666667);
        compare(L.nearestScale([1280, 800], 1.5, 0.5, 3), 1.6);
        compare(L.nearestScale([1920, 1080], 2, 0.5, 3), 2);
    }
    // Two identical panels with no serial share a description: each keeps its connector, or one
    // desc: rule (and one canvas rect) would stand for both.
    function test_key_for_twins() {
        const a = { name: "DP-1", description: "BenQ GW2780" }, b = { name: "DP-2", description: "BenQ GW2780" };
        const c = { name: "HDMI-A-1", description: "Acer X34" };
        compare(L.keyFor(a, [a, b, c]), "DP-1");
        compare(L.keyFor(b, [a, b, c]), "DP-2");
        compare(L.keyFor(c, [a, b, c]), "desc:Acer X34");
        compare(L.keyFor(a, [a, c]), "desc:BenQ GW2780");
        compare(L.keyFor({ name: "DP-3", description: "Odd, Inc. Panel" }, []), "DP-3");
        compare(L.keyFor({ name: "HEADLESS-2", description: "" }, []), "HEADLESS-2");
    }
    // The anchor stays where it is: undocked, the laptop (saved right of the external at 2560x0)
    // changes scale and keeps 2560x0, so re-docking doesn't land the external on it.
    function test_anchor_keeps_position() {
        const laptop = { key: "eDP-1", px: [2880, 1800], mm: [300, 190], scale: 2, transform: 0 };
        let rects = L.fromLogical([laptop], { "eDP-1": [2560, 0] });
        const scaled = Object.assign({}, laptop, { scale: 1.5 });
        rects = L.rotate(rects, "eDP-1", L.physical(scaled)[0], L.physical(scaled)[1]);
        let out = L.toLogical([scaled], rects, [2560, 0]);
        verify(out.ok, out.error);
        compare(out.pos["eDP-1"], [2560, 0]);
        // Docked with no monitor at 0,0: moving the other one leaves the anchor put.
        const ext = { key: "desc:Ext", px: [2560, 1440], mm: [600, 340], scale: 1, transform: 0 };
        rects = L.fromLogical([laptop, ext], { "eDP-1": [100, 50], "desc:Ext": [1540, 50] });
        rects = L.drag(rects, "desc:Ext", rects[0].x + rects[0].w, rects[0].y - 40, 0);
        out = L.toLogical([laptop, ext], rects, [100, 50]);
        verify(out.ok, out.error);
        compare(out.pos["eDP-1"], [100, 50]);
        compare(out.pos["desc:Ext"][0], 1540);
        // The user's desk moved off the origin round-trips in any order, whichever is the anchor.
        const pos = { "desc:Acer": [500, 200], "desc:BenqL": [-940, -363], "desc:BenqR": [3940, -363] };
        for (const order of permutations([acer, benqL, benqR])) {
            const rs = L.fromLogical(order, pos);
            const back = L.toLogical(order, rs, pos[rs[0].key]);
            verify(back.ok, back.error);
            compare(back.pos, pos, order.map(m => m.key).join(","));
        }
    }
    function test_user_desk_round_trip() {
        const mons = [acer, benqL, benqR];
        const pos = { "desc:Acer": [0, 0], "desc:BenqL": [-1440, -560], "desc:BenqR": [3440, -560] };
        const rects = L.fromLogical(mons, pos);
        compare(rects.length, 3);
        compare(rects[0].key, "desc:Acer");
        compare(L.problems(rects), []);
        const out = L.toLogical(mons, rects);
        verify(out.ok, out.error);
        for (const k of Object.keys(pos)) {
            verify(Math.abs(out.pos[k][0] - pos[k][0]) <= 1, k + " x " + out.pos[k][0]);
            verify(Math.abs(out.pos[k][1] - pos[k][1]) <= 1, k + " y " + out.pos[k][1]);
        }
        roundTripsInAnyOrder(mons, { "desc:Acer": [0, 0], "desc:BenqL": [-1440, -563], "desc:BenqR": [3440, -563] });
        compare(benqL.transform, 1);
        compare(benqR.transform, 3);
    }
    // Along the shared edge exact logical px; across it the mm offset at the parent's density.
    function test_physical_alignment() {
        const out = L.toLogical([acer, benqL], [r("desc:Acer", 0, 0, 800, 350), r("desc:BenqL", -340, -131, 340, 600)]);
        verify(out.ok, out.error);
        compare(out.pos["desc:Acer"], [0, 0]);
        compare(out.pos["desc:BenqL"], [-1440, Math.round(-131 * 3440 / 800)]);
        compare(out.pos["desc:BenqL"][1], -563);
    }
    function test_mixed_scale() {
        const small = { key: "desc:Small", px: [1920, 1080], mm: [530, 300], scale: 1, transform: 0 };
        const big = { key: "desc:Big", px: [3840, 2160], mm: [600, 340], scale: 1.5, transform: 0 };
        const out = L.toLogical([small, big], [r("desc:Small", 0, 0, 530, 300), r("desc:Big", 530, 0, 600, 340)]);
        verify(out.ok, out.error);
        compare(out.pos["desc:Big"][0], 1920);
    }
    // The cursor can't cross a corner.
    function test_corner_not_touching() {
        const a = r("desc:Acer", 0, 0, 800, 350), b = r("desc:BenqR", 800, 350, 340, 600);
        verify(!L.touching(a, b));
        const p = L.problems([a, b]);
        verify(p.length > 0);
        verify(p.some(m => m.indexOf("BenqR") >= 0 && m.indexOf("doesn't touch") >= 0), p.join("; "));
    }
    function test_overlap_pushout() {
        const rects = [r("desc:Acer", 0, 0, 800, 350), r("desc:BenqR", 900, 0, 340, 600)];
        const out = L.drag(rects, "desc:BenqR", 230, -125, 12);
        verify(!overlapping(out));
        verify(L.touching(find(out, "desc:Acer"), find(out, "desc:BenqR")));
        compare(rects[1].x, 900);   // inputs untouched
    }
    function test_float_settles() {
        const out = L.settle([r("desc:Acer", 0, 0, 800, 350), r("desc:BenqR", 1000, -131, 340, 600)], "desc:BenqR");
        verify(L.touching(find(out, "desc:Acer"), find(out, "desc:BenqR")));
        compare(L.problems(out), []);
    }
    // Enabled again after the layout changed: its saved place is now taken.
    function test_enable_into_overlap() {
        const rects = [r("desc:Acer", 0, 0, 800, 350), r("desc:BenqL", -340, -131, 340, 600), r("desc:BenqR", 700, -100, 340, 600)];
        const out = L.settle(rects, "desc:BenqR");
        verify(!overlapping(out));
        verify(touchesAny(out, "desc:BenqR"));
        compare(L.problems(out), []);
    }
    function test_rotate_about_centre() {
        // Alone, settle has nothing to do: the centre stays exactly.
        const lone = L.rotate([r("desc:Acer", 0, 0, 800, 350)], "desc:Acer", 350, 800);
        const a = lone[0];
        compare([a.w, a.h], [350, 800]);
        compare([a.x + a.w / 2, a.y + a.h / 2], [400, 175]);
        // Between the BenQs it may move, but ends up placed properly.
        const out = L.rotate([r("desc:Acer", 0, 0, 800, 350), r("desc:BenqL", -340, -131, 340, 600), r("desc:BenqR", 800, -131, 340, 600)],
                             "desc:Acer", 350, 800);
        verify(!overlapping(out));
        verify(touchesAny(out, "desc:Acer"));
    }
    // Each monitor touches two placed neighbours, one per axis.
    function test_grid_cycle() {
        const m = k => ({ key: k, px: [1920, 1080], mm: [530, 300], scale: 1, transform: 0 });
        const out = L.toLogical([m("A"), m("B"), m("C"), m("D")],
                                [r("A", 0, 0, 530, 300), r("B", 530, 0, 530, 300), r("C", 0, 300, 530, 300), r("D", 530, 300, 530, 300)]);
        verify(out.ok, out.error);
        compare(out.pos, { A: [0, 0], B: [1920, 0], C: [0, 1080], D: [1920, 1080] });
    }
    function test_refused() {
        const two = [acer, benqR];
        let out = L.toLogical(two, [r("desc:Acer", 0, 0, 800, 350), r("desc:BenqR", 700, 0, 340, 600)]);
        verify(!out.ok);
        compare(out.error, "Acer and BenqR overlap");
        out = L.toLogical(two, [r("desc:Acer", 0, 0, 800, 350), r("desc:BenqR", 900, 0, 340, 600)]);
        verify(!out.ok);
        compare(out.error, "Acer doesn't touch another monitor");
        // Same mm width, but C is twice A's logical width: D can't sit flush against both B and C.
        const hd = k => ({ key: k, px: [1920, 1080], mm: [530, 300], scale: 1, transform: 0 });
        const uhd = k => ({ key: k, px: [3840, 2160], mm: [530, 298], scale: 1, transform: 0 });
        out = L.toLogical([hd("A"), hd("B"), uhd("C"), uhd("D")],
                          [r("A", 0, 0, 530, 300), r("B", 530, 0, 530, 300), r("C", 0, 300, 530, 298), r("D", 530, 300, 530, 298)]);
        verify(!out.ok);
        compare(out.error, "D can't line up with both C and B");
    }
    // A wide monitor over two narrower, denser ones: the second lines up with the first in mm
    // too, not only with the wide one at its density (which would overlap them on the canvas).
    function test_wide_over_two_round_trip() {
        const x = k => ({ key: k, px: [1920, 1080], mm: [530, 300], scale: 1, transform: 0 });
        const mons = [acer, x("X1"), x("X2")];
        const pos = { "desc:Acer": [0, 0], X1: [0, 1440], X2: [1920, 1440] };
        roundTripsInAnyOrder(mons, pos);
    }
    // Two pairs that each touch but not each other: the cursor can't reach the second pair.
    function test_disconnected_pairs() {
        const m = k => ({ key: k, px: [1920, 1080], mm: [530, 300], scale: 1, transform: 0 });
        const rects = [r("A", 0, 0, 530, 300), r("B", 530, 0, 530, 300), r("C", 0, 500, 530, 300), r("D", 530, 500, 530, 300)];
        compare(L.problems(rects), ["C can't be reached from A", "D can't be reached from A"]);
        const out = L.toLogical([m("A"), m("B"), m("C"), m("D")], rects);
        verify(!out.ok);
        compare(out.error, "C can't be reached from A");
    }
    // A hand-set gap: still drawn, with the problem named, rather than a throw.
    function test_broken_layout_draws() {
        const rects = L.fromLogical([acer, benqL, benqR], { "desc:Acer": [0, 0], "desc:BenqL": [-1540, -560], "desc:BenqR": [3440, -560] });
        compare(rects.length, 3);
        const p = L.problems(rects);
        verify(p.length > 0);
        verify(p.some(m => m.indexOf("BenqL") >= 0), p.join("; "));
    }
    function test_fit() {
        const f = L.fit([r("A", 0, 0, 800, 350), r("B", -340, -131, 340, 600)], 1000, 600, 20);
        // Bounding box 1140 x 600 mm: width-bound.
        fuzzyCompare(f.scale, 960 / 1140, 1e-9);
        fuzzyCompare(f.ox + -340 * f.scale, 20, 1e-9);
        fuzzyCompare(f.oy + -131 * f.scale + 600 * f.scale / 2, 300, 1e-9);
    }
}
