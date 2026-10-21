#!/usr/bin/env bash
# Unit tests for the graphical installer's JavaScript (installer/lib/*.js):
# validation, answers file, progress parsing, the Data disks choices. No display needed.
#   bash cachyos/iso/test-installer-qml.sh
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNNER="${QMLTESTRUNNER:-/usr/lib/qt6/bin/qmltestrunner}"   # qt6-declarative
[[ -x "$RUNNER" ]] || { echo "qmltestrunner not found at $RUNNER" >&2; exit 1; }

# qmltestrunner exits non-zero when any test function fails.
QT_QPA_PLATFORM=offscreen "$RUNNER" -input "$DIR/installer/test/tst_validate.qml"
QT_QPA_PLATFORM=offscreen "$RUNNER" -input "$DIR/installer/test/tst_choices.qml"
