#!/usr/bin/env python3
"""Ask xdg-desktop-portal for a screencast the way an app (Discord, a browser)
does, and print the outcome: "ok <node ids>" when a stream was granted,
"cancelled" or "failed <code>" otherwise. Exit 0 only for "ok".
Run inside the session (verify-shell.sh); the portal runs the picker.
  portal-screencast.py [--timeout SECONDS]
"""
import sys

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

BUS = Gio.bus_get_sync(Gio.BusType.SESSION)
SENDER = BUS.get_unique_name()[1:].replace(".", "_")
PORTAL = ("org.freedesktop.portal.Desktop", "/org/freedesktop/portal/desktop")
IFACE = "org.freedesktop.portal.ScreenCast"
loop = GLib.MainLoop()
result = {"out": "failed timeout"}
counter = 0


def request(method, sig, args, on_ok):
    """Calls a portal method and waits for its Request's Response signal."""
    global counter
    counter += 1
    token = f"fledge{counter}"
    path = f"/org/freedesktop/portal/desktop/request/{SENDER}/{token}"

    def on_response(_c, _s, _p, _i, _sig, params):
        BUS.signal_unsubscribe(sub)
        code, res = params.unpack()
        if code == 0:
            on_ok(res)
        else:
            result["out"] = "cancelled" if code == 1 else f"failed {code}"
            loop.quit()

    sub = BUS.signal_subscribe(PORTAL[0], "org.freedesktop.portal.Request", "Response", path,
                               None, Gio.DBusSignalFlags.NO_MATCH_RULE, on_response)
    args[-1]["handle_token"] = GLib.Variant("s", token)
    BUS.call_sync(PORTAL[0], PORTAL[1], IFACE, method,
                  GLib.Variant(sig, tuple(args)),
                  None, Gio.DBusCallFlags.NONE, -1, None)


def main():
    timeout = 60
    if len(sys.argv) == 3 and sys.argv[1] == "--timeout":
        timeout = int(sys.argv[2])
    GLib.timeout_add_seconds(timeout, loop.quit)

    def started(res):
        nodes = [str(s[0]) for s in res.get("streams", [])]
        result["out"] = "ok " + " ".join(nodes) if nodes else "failed no-streams"
        loop.quit()

    def selected(_res, session):
        request("Start", "(osa{sv})", [session, "", {}], started)

    def created(res):
        session = res["session_handle"]
        # types 1|2: monitors and windows, as Discord asks.
        request("SelectSources", "(oa{sv})", [session, {"types": GLib.Variant("u", 3)}], lambda r: selected(r, session))

    request("CreateSession", "(a{sv})", [{"session_handle_token": GLib.Variant("s", "fledge")}], created)
    loop.run()
    print(result["out"])
    return 0 if result["out"].startswith("ok ") else 1


if __name__ == "__main__":
    sys.exit(main())
