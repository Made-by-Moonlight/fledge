#!/usr/bin/env bash
# Dev stand-in for fledge-install (FLEDGE_INSTALLER_DEV=1): reads the answers the way
# fledge-install does, then replays a short fake install with progress markers.
# Username "fail" fails the Base system stage; "faildesktop" fails the Desktop
# stage with exit 3 (as install-cachyos.sh does), and --desktop-only then works.
set -euo pipefail

stage() { echo "@@fledge stage $1 $2"; echo "== $2 =="; sleep 0.6; }
packages() { local i; for i in $(seq 1 "$1"); do echo "( $i/$1) installing pkg$i"; echo "@@fledge count $i $1"; sleep 0.05; done; }

if [[ "${1:-}" == --desktop-only ]]; then
  stage desktop Desktop; packages 30; stage finish Finish; echo "@@fledge done"; exit 0
fi
user=""
while IFS= read -r line; do
  [[ "$line" == END ]] && break
  [[ "$line" == USERNAME=* ]] && user="${line#USERNAME=}"
  echo "answer: ${line%%=*}"            # keys only: values may be passwords
done
stage prepare Prepare; stage disk "Partition & encrypt"; stage base "Base system"; packages 40
if [[ "$user" == fail ]]; then echo "error: failed to commit transaction (dev)"; echo "@@fledge fail base"; exit 1; fi
stage config Configure; stage boot Bootloader; stage desktop Desktop; packages 60
if [[ "$user" == faildesktop ]]; then echo "bootstrap failed (dev)"; echo "@@fledge fail desktop"; exit 3; fi
stage finish Finish; echo "@@fledge done"
