#!/usr/bin/env bash
#
# xpad-beitong - keep Beitong/Betop KP-series controllers (including the wired
# BTP-KP20D) in XInput mode.
#
# Usage:
#   sudo ./install.sh                     # DKMS, target kernel auto-detected (recommended)
#   sudo ./install.sh manual              # skip DKMS, build straight into /updates
#   sudo ./install.sh dkms 7.2.8-arch1-2  # explicit target kernel
#
# Uninstall: sudo ./uninstall.sh
#
set -euo pipefail

PKG="xpad-beitong"
VER="1.0"
MODE="${1:-dkms}"

SRC_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DST_DIR="/usr/src/${PKG}-${VER}"
RUNNING="$(uname -r)"

die()  { printf '\033[31merror: %s\033[0m\n' "$*" >&2; exit 1; }
info() { printf '\033[36m==> %s\033[0m\n' "$*"; }

# Target kernel: prefer the running one. If its headers are already gone - the
# usual case right after a kernel upgrade and before rebooting, when
# /usr/lib/modules/<old-kver> has been removed - fall back to the newest
# installed kernel that does have headers.
detect_kver() {
    local k
    if [[ -e "/lib/modules/${RUNNING}/build" ]]; then
        printf '%s\n' "${RUNNING}"
        return
    fi
    for k in $(ls -1 /usr/lib/modules 2>/dev/null | sort -Vr); do
        if [[ -e "/lib/modules/${k}/build" ]]; then
            printf '%s\n' "${k}"
            return
        fi
    done
    printf '%s\n' "${RUNNING}"
}

KVER="${2:-$(detect_kver)}"
KDIR="/lib/modules/${KVER}/build"

warn_restart() {
    printf '\n\033[33m!! target kernel %s is not the running kernel %s.\n' "${KVER}" "${RUNNING}"
    printf '   The module was built and installed for %s, but it only\n' "${KVER}"
    printf '   takes effect after a REBOOT.\033[0m\n\n'
}

reload() {
    if [[ "${KVER}" != "${RUNNING}" ]]; then
        warn_restart
        return
    fi
    info "reloading xpad"
    modprobe -r xpad 2>/dev/null || true
    modprobe xpad
}

[[ "${EUID}" -eq 0 ]] || die "must run as root: sudo $0"
[[ -f "${SRC_DIR}/xpad.c" ]] || die "${SRC_DIR}/xpad.c not found"

info "running kernel: ${RUNNING}"
info "target kernel:  ${KVER}"
[[ "${KVER}" != "${RUNNING}" ]] && warn_restart

[[ -e "${KDIR}" ]] || die "missing kernel headers: ${KDIR}
    installed kernels: $(ls -1 /usr/lib/modules 2>/dev/null | tr '\n' ' ')
    install them first: sudo pacman -S --needed linux-headers dkms base-devel
    or name the target kernel explicitly: sudo $0 ${MODE} <kernel-version>"

if [[ "${MODE}" == "manual" ]]; then
    command -v make >/dev/null || die "make not found"
    BUILD_DIR="$(mktemp -d)"
    trap 'rm -rf "${BUILD_DIR}"' EXIT
    install -m 0644 "${SRC_DIR}/xpad.c" "${SRC_DIR}/Makefile" "${BUILD_DIR}/"

    info "building out of tree for ${KVER}"
    make -C "${KDIR}" M="${BUILD_DIR}" modules

    info "installing to /usr/lib/modules/${KVER}/updates/"
    install -d -m 0755 "/usr/lib/modules/${KVER}/updates"
    install -m 0644 "${BUILD_DIR}/xpad.ko" "/usr/lib/modules/${KVER}/updates/xpad.ko"
    depmod -a "${KVER}"
    reload
else
    command -v dkms >/dev/null || die "dkms not found
    install it first: sudo pacman -S --needed linux-headers dkms"

    info "installing sources to ${DST_DIR}"
    install -d -m 0755 "${DST_DIR}"
    install -m 0644 "${SRC_DIR}/xpad.c"    "${DST_DIR}/xpad.c"
    install -m 0644 "${SRC_DIR}/Makefile"  "${DST_DIR}/Makefile"
    install -m 0644 "${SRC_DIR}/dkms.conf" "${DST_DIR}/dkms.conf"

    info "removing any previous DKMS registration"
    dkms remove "${PKG}/${VER}" --all >/dev/null 2>&1 || true

    info "dkms add / build / install"
    dkms add     "${PKG}/${VER}"
    dkms build   "${PKG}/${VER}" -k "${KVER}"
    dkms install "${PKG}/${VER}" -k "${KVER}" --force

    depmod -a "${KVER}"
    reload
fi

echo
if [[ "${KVER}" == "${RUNNING}" ]]; then
    info "xpad is actually loaded from:"
    modinfo -F filename xpad || true
    echo
    info "module parameters (beitong_force_init should be listed):"
    modinfo -F parm xpad | grep -i beitong || echo "  (not found - the stock module is still loaded!)"
else
    info "xpad installed for ${KVER}:"
    modinfo -k "${KVER}" -F filename xpad 2>/dev/null || \
        ls -l "/usr/lib/modules/${KVER}/updates/" 2>/dev/null || true
    echo
    info "module parameters installed for ${KVER}:"
    modinfo -k "${KVER}" -F parm xpad 2>/dev/null | grep -i beitong || echo "  (not found)"
fi

if [[ "${KVER}" == "${RUNNING}" ]]; then
    cat <<'EOF'

== next steps ==
1) Unplug the controller, wait two seconds, plug it back in.
2) Check its identity:
     lsusb | grep -Ei '057e|20bc'
   20bc:xxxx  => it is in XInput mode.
   057e:2009  => the Xbox handshake did not happen; see Troubleshooting in
                 docs/dkms-manual.md
3) Check the kernel log:
     sudo dmesg | tail -40

== rollback ==
     sudo ./uninstall.sh
EOF
else
    cat <<EOF

== next steps ==
1) REBOOT into ${KVER} (still running ${RUNNING}).
2) Unplug and replug the controller, then check its identity:
     lsusb | grep -Ei '057e|20bc'
   20bc:xxxx  => it is in XInput mode.
   057e:2009  => the Xbox handshake did not happen; see Troubleshooting in
                 docs/dkms-manual.md

== rollback ==
     sudo ./uninstall.sh
EOF
fi
