.pragma library
// The keybind editor's short form for a Hyprland dispatcher action (settings v2 `{dsp, args}`):
//   window.move workspace=3 follow=false   -> {dsp: "window.move", args: {workspace: 3, follow: false}}
//   layout togglesplit                     -> {dsp: "layout", args: "togglesplit"}  (one bare word: positional)
//   window.cycle_next; window.bring_to_top -> a list of actions
// Unquoted numbers and true/false are typed; quote a value to keep it text ("3", "a b").
// format() is the inverse, quoting whatever parse() would otherwise read differently, so a
// bind shown in the editor saves back unchanged. `mbm settings check` validates again.

const NAME = /^[a-z_]+(\.[a-z_]+)?$/;
const KEY = /^[A-Za-z_][A-Za-z0-9_]*$/;
const NUMBER = /^-?\d+(\.\d+)?$/;

// Text -> words, splitting on whitespace and `;` outside double quotes (\" and \\ escape).
// Each word: { text, quoted, eq }, eq = index of the first `=` before any quote (-1: none).
// `;` becomes its own { sep: true } word.
function words(s) {
    const out = [];
    let cur = null, inq = false;
    const start = () => { if (!cur) cur = { text: "", quoted: false, eq: -1 }; };
    const end = () => { if (cur) out.push(cur); cur = null; };
    for (let i = 0; i < s.length; i++) {
        const c = s[i];
        if (inq) {
            if (c === "\\" && i + 1 < s.length) cur.text += s[++i];
            else if (c === "\"") inq = false;
            else cur.text += c;
        } else if (c === "\"") { start(); cur.quoted = true; inq = true; }
        else if (/\s/.test(c)) end();
        else if (c === ";") { end(); out.push({ sep: true }); }
        else {
            start();
            if (c === "=" && cur.eq < 0 && !cur.quoted) cur.eq = cur.text.length;
            cur.text += c;
        }
    }
    if (inq) return null;
    end();
    return out;
}

function typed(text, quoted) {
    if (quoted) return text;
    if (text === "true") return true;
    if (text === "false") return false;
    if (NUMBER.test(text)) return Number(text);
    return text;
}

function parseOne(ws) {
    if (ws.length === 0) return { error: "empty dispatcher" };
    const head = ws[0];
    if (head.quoted || !NAME.test(head.text)) return { error: "\"" + head.text + "\" is not a dispatcher name (e.g. window.move)" };
    const action = { dsp: head.text };
    const rest = ws.slice(1);
    if (rest.length === 0) return action;
    const keyed = rest.filter(w => w.eq >= 0);
    if (keyed.length === 0) {
        if (rest.length > 1) return { error: "one bare argument at most: quote text with spaces (\"a b\")" };
        action.args = typed(rest[0].text, rest[0].quoted);
        return action;
    }
    if (keyed.length !== rest.length) return { error: "use either one bare argument or key=value pairs, not both" };
    const args = {};
    for (const w of rest) {
        const key = w.text.slice(0, w.eq), value = w.text.slice(w.eq + 1);
        if (!KEY.test(key)) return { error: "\"" + key + "\" is not an argument name" };
        if (value === "" && !w.quoted) return { error: key + "= needs a value" };
        if (Object.prototype.hasOwnProperty.call(args, key)) return { error: key + " is given twice" };
        args[key] = typed(value, w.quoted);
    }
    action.args = args;
    return action;
}

// Text -> {dsp[, args]}, a list of them (`;`), or {error: "…"}.
function parse(text) {
    const ws = words(String(text ?? ""));
    if (ws === null) return { error: "unterminated quote" };
    const groups = [[]];
    for (const w of ws) w.sep ? groups.push([]) : groups[groups.length - 1].push(w);
    if (groups.length === 1 && groups[0].length === 0) return { error: "empty dispatcher" };
    const actions = [];
    for (const g of groups) {
        const a = parseOne(g);
        if (a.error) return a;
        actions.push(a);
    }
    return actions.length === 1 ? actions[0] : actions;
}

function value(v) {
    if (typeof v === "number" || typeof v === "boolean") return String(v);
    if (typeof v !== "string") return JSON.stringify(v);   // not valid settings; shown as is
    // Bare only when parse() would read it back as this same text.
    if (/^[^\s";=\\]+$/.test(v) && typed(v, false) === v) return v;
    return "\"" + v.replace(/[\\"]/g, c => "\\" + c) + "\"";
}

function formatOne(a) {
    if (!a || typeof a !== "object" || typeof a.dsp !== "string") return "";
    if (a.args === undefined) return a.dsp;
    if (a.args !== null && typeof a.args === "object" && !Array.isArray(a.args))
        return [a.dsp, ...Object.keys(a.args).map(k => k + "=" + value(a.args[k]))].join(" ");
    return a.dsp + " " + value(a.args);
}

// Action (or list) -> short form; "" when it isn't made only of dispatchers (exec, shell).
function format(action) {
    const list = Array.isArray(action) ? action : [action];
    const parts = list.map(formatOne);
    return list.length > 0 && parts.every(p => p !== "") ? parts.join("; ") : "";
}

function valid(name, names) { return Array.isArray(names) && names.includes(name); }

// "" when the text parses and names only known dispatchers, else the message to show.
function check(text, names) {
    const p = parse(text);
    if (p.error) return p.error;
    for (const a of Array.isArray(p) ? p : [p])
        if (!valid(a.dsp, names)) return "unknown dispatcher \"" + a.dsp + "\"";
    return "";
}
