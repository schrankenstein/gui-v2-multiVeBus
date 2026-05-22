#!/bin/sh
#
# Ekrano multi-vebus mod — installer for the local Venus OS display (gui-v2)
#
# Run this on the GX device (root). It installs the modified InverterChargerWidget.qml
# and AcLoadsWidget.qml into an overlay-fs layer on top of /opt/victronenergy/gui-v2/,
# so the original stock files stay untouched and survive a Venus OS update. The mod
# persists across reboots via an entry in /data/rc.local.
#
# Usage:
#   ./custom-gui-install.sh           install/refresh the mod
#   ./custom-gui-install.sh --status  print install state and exit
#
# Expects the two modded QML files to live next to this script:
#   ./qml/components/widgets/InverterChargerWidget.qml
#   ./qml/components/widgets/AcLoadsWidget.qml
#
# Tested against Venus OS 3.80 on Ekrano GX. Should work on other GX devices that
# ship gui-v2 with the same layout.

set -eu

GUI_DIR="/opt/victronenergy/gui-v2/Victron/VenusOS"
OVERLAY_ROOT="/data/apps/overlay-fs/gui-v2-multi-vebus"
UPPER="${OVERLAY_ROOT}/upper"
WORK="${OVERLAY_ROOT}/work"
RC_LOCAL="/data/rc.local"
RC_MARK="# >>> gui-v2-multi-vebus overlay >>>"
RC_END="# <<< gui-v2-multi-vebus overlay <<<"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
QML_SRC="${SCRIPT_DIR}/qml"

log()  { printf '%s\n' "$*"; }
err()  { printf 'error: %s\n' "$*" >&2; }
die()  { err "$*"; exit 1; }

is_mounted() {
    awk -v t="$1" '$2 == t { found = 1 } END { exit !found }' /proc/mounts
}

cmd_status() {
    log "GUI dir: ${GUI_DIR}"
    if is_mounted "${GUI_DIR}"; then
        log "overlay: MOUNTED"
    else
        log "overlay: not mounted"
    fi
    if [ -d "${UPPER}" ]; then
        log "upper: ${UPPER} (contents below)"
        find "${UPPER}" -type f | sed 's|^|  |'
    else
        log "upper: not present"
    fi
    if [ -f "${RC_LOCAL}" ] && grep -q "${RC_MARK}" "${RC_LOCAL}"; then
        log "rc.local: hook present"
    else
        log "rc.local: hook absent"
    fi
}

if [ "${1:-}" = "--status" ]; then
    cmd_status
    exit 0
fi

[ "$(id -u)" = "0" ] || die "must run as root"
[ -d "${GUI_DIR}" ] || die "expected ${GUI_DIR} to exist; is this a Venus OS GX device with gui-v2?"
[ -d "${QML_SRC}/components/widgets" ] || die "modded QML not found at ${QML_SRC}/components/widgets"

for f in components/widgets/InverterChargerWidget.qml components/widgets/AcLoadsWidget.qml; do
    [ -f "${QML_SRC}/${f}" ] || die "missing modded file: ${QML_SRC}/${f}"
    [ -f "${GUI_DIR}/${f}" ] || die "target file missing on device: ${GUI_DIR}/${f}"
done

log "[1/5] preparing overlay dirs at ${OVERLAY_ROOT}"
mkdir -p "${UPPER}/components/widgets" "${WORK}"

log "[2/5] copying modded QML into the upper layer"
cp "${QML_SRC}/components/widgets/InverterChargerWidget.qml" "${UPPER}/components/widgets/"
cp "${QML_SRC}/components/widgets/AcLoadsWidget.qml"          "${UPPER}/components/widgets/"

log "[3/5] mounting overlay over ${GUI_DIR}"
# Remount root rw if needed (only briefly; rc.local handles persistence)
if ! touch "${GUI_DIR}/.write-probe" 2>/dev/null; then
    /opt/victronenergy/swupdate-scripts/remount-rw.sh
else
    rm -f "${GUI_DIR}/.write-probe"
fi

# If a stale overlay is already mounted, refresh by unmounting first.
if is_mounted "${GUI_DIR}"; then
    log "  found existing mount on ${GUI_DIR}; unmounting first"
    umount "${GUI_DIR}" || die "could not unmount existing overlay"
fi

mount -t overlay overlay \
    -o "lowerdir=${GUI_DIR},upperdir=${UPPER},workdir=${WORK}" \
    "${GUI_DIR}" \
    || die "overlay mount failed"

log "[4/5] writing rc.local hook for persistence"
# Ensure rc.local exists and is executable
if [ ! -f "${RC_LOCAL}" ]; then
    printf '#!/bin/sh\n' > "${RC_LOCAL}"
    chmod 0755 "${RC_LOCAL}"
fi
# Replace any existing hook block, then append a fresh one.
if grep -q "${RC_MARK}" "${RC_LOCAL}"; then
    # Strip lines between markers (inclusive).
    awk -v s="${RC_MARK}" -v e="${RC_END}" '
        $0 == s { skip = 1; next }
        $0 == e { skip = 0; next }
        !skip
    ' "${RC_LOCAL}" > "${RC_LOCAL}.tmp"
    mv "${RC_LOCAL}.tmp" "${RC_LOCAL}"
fi
cat >> "${RC_LOCAL}" <<EOF
${RC_MARK}
if [ -d "${UPPER}" ] && [ -d "${GUI_DIR}" ] && ! awk '\$2 == "${GUI_DIR}" { f=1 } END { exit !f }' /proc/mounts; then
    mkdir -p "${WORK}"
    mount -t overlay overlay -o "lowerdir=${GUI_DIR},upperdir=${UPPER},workdir=${WORK}" "${GUI_DIR}" || true
fi
${RC_END}
EOF
chmod 0755 "${RC_LOCAL}"

log "[5/5] restarting gui-v2 service"
if [ -d /service/gui-v2 ]; then
    svc -t /service/gui-v2
elif [ -d /service/start-gui ]; then
    svc -t /service/start-gui
else
    log "  no gui-v2 service found under /service; you may need to reboot to pick up changes"
fi

log "done. Run \`./custom-gui-install.sh --status\` to verify."
