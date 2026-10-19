#!/bin/bash
# Demo add-on - bootstrap / seed refresh. Run by playbook 19 (as root) after the
# new copy is in place, on EVERY install and update; everything here is idempotent.
#   ADDON_NAME ADDON_VERSION ADDON_DIR ADDON_DB come from playbook 19.
set -euo pipefail
ADDON_DIR="${ADDON_DIR:-/home/trilivyapp/addons/demo}"
ADDON_DB="${ADDON_DB:-addon_demo}"
PY=/usr/local/bin/python3.13
[ -x "$PY" ] || PY=python3

# seed: features, moments, settings, pitch cards, operators, the timers' account
ADDON_DIR="$ADDON_DIR" ADDON_DB="$ADDON_DB" "$PY" "$ADDON_DIR/py/seed.py"

# where the Demo Console writes "Export to package" (read by the fleet's seed-pull)
install -d -o trilivy -g trilivy -m 2770 /var/lib/trilivy/addon-exports/demo
# runtime backups (install/backup.sh, daily timer)
install -d -o root -g root -m 0700 /home/trilivy_backups/demo
echo "bootstrap ok (demo ${ADDON_VERSION:-?})"
