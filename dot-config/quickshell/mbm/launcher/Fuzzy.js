.pragma library
// Subsequence match: 0 = no match; higher is better. Prefix and word-start
// hits beat scattered letters, so "fir" ranks Firefox above "Font Viewer".
function score(query, text) {
    if (!query) return 1;
    const q = query.toLowerCase(), t = (text || "").toLowerCase();
    if (t.startsWith(q)) return 100 - Math.min(t.length, 50) / 10;
    const i = t.indexOf(q);
    if (i >= 0) return 60 - i / 10 + (/[\s\-_.]/.test(t[i - 1]) ? 20 : 0);
    let ti = 0, s = 0;
    for (const c of q) {
        const k = t.indexOf(c, ti);
        if (k < 0) return 0;
        s += k === ti ? 2 : 1;
        ti = k + 1;
    }
    return 10 + s;
}
