#!/usr/bin/env bash
#
# Remove xpad-beitong and go back to the distribution's own xpad.
#
set -euo pipefail

PKG="xpad-beitong"
VER="1.0"
KVER="$(uname -r)"

die()  { printf '\033[31merror: %s\033[0m\n' "$*" >&2; exit 1; }
info() { printf '\033[36m==> %s\033[0m\n' "$*"; }

[[ "${EUID}" -eq 0 ]] || die "must run as root: sudo $0"

if command -v dkms >/dev/null; then
    info "removing DKMS module ${PKG}/${VER}"
    dkms remove "${PKG}/${VER}" --all >/dev/null 2>&1 || true
fi

if [[ -f "/usr/lib/modules/${KVER}/updates/xpad.ko" ]]; then
    info "removing manually installed /usr/lib/modules/${KVER}/updates/xpad.ko"
    rm -f "/usr/lib/modules/${KVER}/updates/xpad.ko"
    rmdir "/usr/lib/modules/${KVER}/updates" 2>/dev/null || true
fi

info "updating module dependencies and reloading"
depmod -a "${KVER}"
modprobe -r xpad 2>/dev/null || true
modprobe xpad

echo
info "xpad now loaded from:"
modinfo -F filename xpad || true
echo
echo "Remember to unplug and replug the controller."
