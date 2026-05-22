#!/bin/sh
#
# Ekrano multi-vebus mod — uninstaller. Removes the overlay-fs mount, deletes the
# upper layer, and strips the rc.local hook. Stock gui-v2 files are untouched the
# whole time, so the rollback is just "tear down what install set up".
#
# Usage:
#   ./custom-gui-uninstall.sh          full uninstall
#   ./custom-gui-uninstall.sh --keep   leave upper layer on disk, only unmount + rc.local cleanup

set -eu

GUI_DIR="/opt/victronenergy/gui-v2/Victron/VenusOS"
OVERLAY_ROOT="/data/apps/overlay-fs/gui-v2-multi-vebus"
RC_LOCAL="/data/rc.local"
RC_MARK="# >>> gui-v2-multi-vebus overlay >>>"
RC_END="# <<< gui-v2-multi-vebus overlay <<<"

KEEP_UPPER=0
[ "${1:-}" = "--keep" ] && KEEP_UPPER=1

log()  { printf '%s\n' "$*"; }
err()  { printf 'error: %s\n' "$*" >&2; }
die()  { err "$*"; exit 1; }

is_mounted() {
    awk -v t="$1" '$2 == t { found = 1 } END { exit !found }' /proc/mounts
}

[ "$(id -u)" = "0" ] || die "must run as root"

did_anything=0

log "[1/3] unmounting overlay (if mounted)"
if is_mounted "${GUI_DIR}"; then
    umount "${GUI_DIR}" || die "umount ${GUI_DIR} failed; is something keeping the dir busy?"
    did_anything=1
else
    log "  not mounted, skipping"
fi

log "[2/3] removing rc.local hook (if present)"
if [ -f "${RC_LOCAL}" ] && grep -q "${RC_MARK}" "${RC_LOCAL}"; then
    awk -v s="${RC_MARK}" -v e="${RC_END}" '
        $0 == s { skip = 1; next }
        $0 == e { skip = 0; next }
        !skip
    ' "${RC_LOCAL}" > "${RC_LOCAL}.tmp"
    mv "${RC_LOCAL}.tmp" "${RC_LOCAL}"
    chmod 0755 "${RC_LOCAL}"
    did_anything=1
else
    log "  no hook in ${RC_LOCAL}, skipping"
fi

if [ "${KEEP_UPPER}" -eq 0 ]; then
    log "[3/3] removing upper layer at ${OVERLAY_ROOT}"
    if [ -d "${OVERLAY_ROOT}" ]; then
        rm -rf "${OVERLAY_ROOT}"
        did_anything=1
    else
        log "  not present, skipping"
    fi
else
    log "[3/3] --keep specified, leaving ${OVERLAY_ROOT} in place"
fi

if [ "${did_anything}" -eq 0 ]; then
    log "nothing to do — mod did not appear to be installed."
    exit 0
fi

log "restarting gui-v2 service"
if [ -d /service/gui-v2 ]; then
    svc -t /service/gui-v2
elif [ -d /service/start-gui ]; then
    svc -t /service/start-gui
else
    log "no gui-v2 service found under /service; reboot if needed"
fi

log "done. Stock gui-v2 is back."
