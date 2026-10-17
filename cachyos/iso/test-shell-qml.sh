#!/usr/bin/env bash
# Unit tests for the fledge shell's JavaScript (dot-config/quickshell/fledge/settings/*.js):
# the keybind editor's dispatcher short form. No display needed.
#   bash cachyos/iso/test-shell-qml.sh
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNNER="${QMLTESTRUNNER:-/usr/lib/qt6/bin/qmltestrunner}"   # qt6-declarative
[[ -x "$RUNNER" ]] || { echo "qmltestrunner not found at $RUNNER" >&2; exit 1; }

# qmltestrunner exits non-zero when any test function fails.
# File reads let a test check every shipped bind (defaults/settings.json).
QML_XHR_ALLOW_FILE_READ=1 QT_QPA_PLATFORM=offscreen "$RUNNER" -input "$DIR/../../dot-config/quickshell/fledge/test/tst_dspshort.qml"
