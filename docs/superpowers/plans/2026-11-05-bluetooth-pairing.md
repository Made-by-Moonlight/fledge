# Bluetooth pairing implementation

1. Add the BlueZ application agent helper, asynchronous pairing, bounded
   requests, cancellation, validation, and service restart handling.
2. Wire helper status and requests into Bt; route new pairs through it.
3. Add a pairing modal matching the shell, integrate focus/lock behavior,
   and replace the terminal-only failure hint with actual errors.
4. Declare bootstrap dependencies and test agent callbacks and protocol in
   the VM. Load the shell there and inspect its log. Record limitations.

Validation completed in `cachyos-test`, booted from the existing live ISO
because the attached disks had no bootable OS:

- 65 existing QML cases and 10 agent tests passed.
- Full shell loaded in the live Wayland session; no QML loading errors.
- Passkey confirmation and PIN entry previews were captured and inspected.
- Helper registered with real BlueZ (`ready: true`) and exited on stdin EOF.
- The live session lacks normal desktop services/assets, causing unrelated
  PipeWire, UPower, polkit/session and missing-tool warnings during shell load.
- No physical Bluetooth adapter is passed through, so real JBL pairing still
  needs a hardware check after applying the update.

Follow-up: removed the 12-device cap and sorted named devices before address
aliases. Unpaired unnamed devices now sit behind a counted toggle; known and
actively pairing devices remain visible. Six QML test cases passed in the VM,
including a named JBL following 20 unnamed devices and hyphenated address aliases.
