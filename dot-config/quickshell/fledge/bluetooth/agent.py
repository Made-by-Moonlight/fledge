#!/usr/bin/env python3
"""BlueZ application agent; JSON lines belong only to the parent shell."""
import json
import os
import sys

import dbus
import dbus.service
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib

PATH = "/org/fledge/BluetoothAgent"
IFACE = "org.bluez.Agent1"


def emit(**event):
    print(json.dumps(event), flush=True)


class Rejected(dbus.DBusException):
    _dbus_error_name = "org.bluez.Error.Rejected"


class Agent(dbus.service.Object):
    def __init__(self, bus):
        super().__init__(bus, PATH)
        self.bus = bus
        self.pending = None
        self.serial = 0
        self.timer = None
        self.device = None
        self.address = ""
        self.ready = False
        self.operation = 0

    def clear(self, reject=False):
        pending, self.pending = self.pending, None
        if self.timer is not None:
            GLib.source_remove(self.timer)
            self.timer = None
        emit(event="clear")
        if reject and pending and pending[2]:
            pending[2](Rejected("Pairing cancelled"))

    def prompt(self, kind, device, reply=None, error=None, **fields):
        if self.pending and self.pending[2]:
            if error:
                error(Rejected("Another pairing request is open"))
            return
        self.clear()
        self.serial += 1
        self.pending = (kind, reply, error)
        try:
            props = dbus.Interface(self.bus.get_object("org.bluez", device),
                                   "org.freedesktop.DBus.Properties")
            address = str(props.Get("org.bluez.Device1", "Address"))
            name = str(props.Get("org.bluez.Device1", "Alias")).strip() or address
        except dbus.DBusException:
            name, address = "Bluetooth device", self.address
        emit(event="prompt", id=self.serial, kind=kind, name=name,
             address=address, **fields)
        self.timer = GLib.timeout_add_seconds(60, self.expire)

    def expire(self):
        self.timer = None
        self.cancel()
        return False

    def cancel(self):
        self.clear(reject=True)
        if self.device:
            self.device.CancelPairing(reply_handler=lambda: None,
                                      error_handler=lambda error: None)

    def respond(self, message):
        if not self.pending or message.get("id") != self.serial:
            return
        kind, reply, error = self.pending
        if not message.get("accept"):
            self.cancel()
            return
        value = message.get("value", "")
        if kind == "pin" and (not isinstance(value, str) or not 1 <= len(value) <= 16):
            return
        if kind == "passkey" and (not isinstance(value, str) or not value.isascii()
                                  or not value.isdigit() or len(value) > 6):
            return
        self.clear()
        if kind == "pin":
            reply(value)
        elif kind == "passkey":
            reply(dbus.UInt32(int(value)))
        elif reply:
            reply()

    def pair(self, address):
        if not self.ready or self.device:
            emit(event="failed", address=address, message="Bluetooth pairing is not ready")
            return
        manager = dbus.Interface(self.bus.get_object("org.bluez", "/"),
                                 "org.freedesktop.DBus.ObjectManager")
        for path, interfaces in manager.GetManagedObjects().items():
            if str(interfaces.get("org.bluez.Device1", {}).get("Address", "")) != address:
                continue
            self.address = address
            self.operation += 1
            operation = self.operation
            self.device = dbus.Interface(self.bus.get_object("org.bluez", path),
                                         "org.bluez.Device1")
            self.device.Pair(reply_handler=lambda: self.finished(operation),
                             error_handler=lambda error: self.finished(operation, str(error)),
                             timeout=120)
            return
        emit(event="failed", address=address, message="Device disappeared. Put it in pairing mode and retry.")

    def finished(self, operation, error=None):
        if operation != self.operation:
            return
        self.clear(reject=True)
        self.device = None
        emit(event="failed" if error else "paired", address=self.address,
             message=error or "")
        self.address = ""

    @dbus.service.method(IFACE, in_signature="", out_signature="")
    def Release(self):
        self.ready = False
        self.cancel()
        emit(event="ready", ready=False)

    @dbus.service.method(IFACE, in_signature="", out_signature="")
    def Cancel(self):
        self.clear(reject=True)

    @dbus.service.method(IFACE, in_signature="o", out_signature="s", async_callbacks=("reply", "error"))
    def RequestPinCode(self, device, reply, error):
        self.prompt("pin", device, reply, error)

    @dbus.service.method(IFACE, in_signature="o", out_signature="u", async_callbacks=("reply", "error"))
    def RequestPasskey(self, device, reply, error):
        self.prompt("passkey", device, reply, error)

    @dbus.service.method(IFACE, in_signature="ou", out_signature="", async_callbacks=("reply", "error"))
    def RequestConfirmation(self, device, passkey, reply, error):
        self.prompt("confirm", device, reply, error, code=f"{int(passkey):06d}")

    @dbus.service.method(IFACE, in_signature="o", out_signature="", async_callbacks=("reply", "error"))
    def RequestAuthorization(self, device, reply, error):
        self.prompt("authorize", device, reply, error)

    @dbus.service.method(IFACE, in_signature="os", out_signature="", async_callbacks=("reply", "error"))
    def AuthorizeService(self, device, uuid, reply, error):
        self.prompt("authorize", device, reply, error, service=str(uuid))

    @dbus.service.method(IFACE, in_signature="os", out_signature="")
    def DisplayPinCode(self, device, pincode):
        self.prompt("display", device, code=str(pincode))

    @dbus.service.method(IFACE, in_signature="ouq", out_signature="")
    def DisplayPasskey(self, device, passkey, entered):
        self.prompt("display", device, code=f"{int(passkey):06d}", entered=int(entered))

    def owner_changed(self, owner):
        self.operation += 1
        self.ready = False
        self.clear(reject=True)
        self.device = None
        if owner:
            try:
                manager = dbus.Interface(self.bus.get_object("org.bluez", "/org/bluez"),
                                         "org.bluez.AgentManager1")
                manager.RegisterAgent(PATH, "KeyboardDisplay")
                self.ready = True
            except dbus.DBusException as error:
                emit(event="error", message=str(error))
        emit(event="ready", ready=self.ready)


def main():
    DBusGMainLoop(set_as_default=True)
    bus = dbus.SystemBus()
    agent = Agent(bus)
    loop = GLib.MainLoop()
    bus.watch_name_owner("org.bluez", agent.owner_changed)
    buffered = b""

    def read_line(source, condition):
        nonlocal buffered
        chunk = os.read(source.fileno(), 4096)
        if not chunk:
            agent.cancel()
            loop.quit()
            return False
        buffered += chunk
        while b"\n" in buffered:
            line, buffered = buffered.split(b"\n", 1)
            message = {}
            try:
                message = json.loads(line)
                if message.get("command") == "pair":
                    agent.pair(message["address"])
                elif message.get("command") == "respond":
                    agent.respond(message)
                elif message.get("command") == "cancel":
                    agent.cancel()
            except (ValueError, KeyError, AttributeError, dbus.DBusException) as error:
                if isinstance(message, dict) and message.get("command") == "pair":
                    if agent.device:
                        agent.finished(agent.operation, str(error))
                    else:
                        emit(event="failed", address=message.get("address", ""), message=str(error))
                else:
                    emit(event="error", message=str(error))
        return True

    GLib.io_add_watch(sys.stdin, GLib.IO_IN | GLib.IO_HUP, read_line)
    loop.run()


if __name__ == "__main__":
    main()
