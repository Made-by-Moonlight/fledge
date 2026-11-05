# Bluetooth pairing in quick settings

Date: 2026-11-05. Branch: `bluetooth-pairing-ui`.

The Bluetooth picker must pair devices without sending the user to a terminal.
This replaces the no-agent limitation in the original shell design.

Quickshell 0.3.2 exposes devices but no BlueZ agent. A small Python helper
registers an `org.bluez.Agent1` with `KeyboardDisplay` capability and initiates
pairing on that same D-Bus connection. It is an application agent, not the
system default: it handles only requests from pairing started by this shell.
The helper lives with the shell and exchanges newline-delimited JSON over
stdin/stdout. It exits on EOF; no additional service runs after the shell exits.
Explicit bootstrap dependencies are python-dbus and python-gobject.

Quick settings retains its device list and connect/disconnect behavior. A
separate modal shows the device name/address, PIN/passkey input, confirmation,
or a code to type on the remote device. Numeric codes preserve leading zeroes.
Nothing is silently approved. Cancel, timeout, locking, and another modal
opening reject pending requests. Requests carry IDs so a late button press
cannot approve a different request. Input is validated in both UI and helper.
Pairing success retains the existing trust-and-connect behavior. Failures show
the actual BlueZ error with a retry hint, never a claim that every error needs
a PIN. The helper reconnects after BlueZ restarts, and failure to start is shown
in the picker. No host configuration is changed during development.

Device names can be missing or whitespace-only. The list and connected-device
summary then show the Bluetooth address. Named rows also show the address on
a second line so identical names remain distinguishable. Names are never
invented for devices that do not advertise one.
BlueZ address aliases (including hyphenated addresses) count as unnamed too.
Connected and paired devices sort first, followed by named devices. Unnamed,
unpaired devices are hidden behind a toggle with a count. Connected, paired,
and actively pairing devices remain visible. The list has no arbitrary device
limit: quick settings already scrolls, so discovered devices cannot push a
named device out of the list entirely.

Validation: helper callback/protocol tests in the VM, QML loading in the VM,
and a real-device pairing check after the user applies the update. A VM without
a Bluetooth adapter can check registration failures and UI behavior but cannot
prove physical pairing.
