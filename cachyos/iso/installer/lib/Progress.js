.pragma library
// The installer's @@mbm marker lines (cachyos/install/lib/progress.sh).
function parse(line) {
    const m = /^@@mbm (stage|count|fail|done)(?: (\S+))?(?: (.*))?$/.exec(line);
    if (!m) return null;
    if (m[1] === "count") return { kind: "count", n: parseInt(m[2]), m: parseInt(m[3]) };
    return { kind: m[1], id: m[2] ?? "" };
}
// Rough share of the total time each stage takes; package stages dominate.
const weight = { prepare: 2, disk: 5, base: 35, config: 6, boot: 4, desktop: 43, finish: 5 };
function fraction(ids, done, current, n, m) {
    let total = 0, got = 0;
    for (const id of ids) {
        total += weight[id];
        if (done[id]) got += weight[id];
        else if (id === current) got += weight[id] * (m > 0 ? n / m : 0.1);
    }
    return total ? got / total : 0;
}
