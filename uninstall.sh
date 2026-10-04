#!/usr/bin/env bash
#
# 卸载 xpad-beitong，恢复发行版自带的 xpad。
#
set -euo pipefail

PKG="xpad-beitong"
VER="1.0"
KVER="$(uname -r)"

die()  { printf '\033[31m错误: %s\033[0m\n' "$*" >&2; exit 1; }
info() { printf '\033[36m==> %s\033[0m\n' "$*"; }

[[ "${EUID}" -eq 0 ]] || die "请用 root 运行： sudo $0"

if command -v dkms >/dev/null; then
    info "移除 DKMS 模块 ${PKG}/${VER}"
    dkms remove "${PKG}/${VER}" --all >/dev/null 2>&1 || true
fi

if [[ -f "/usr/lib/modules/${KVER}/updates/xpad.ko" ]]; then
    info "移除手动安装的 /usr/lib/modules/${KVER}/updates/xpad.ko"
    rm -f "/usr/lib/modules/${KVER}/updates/xpad.ko"
    rmdir "/usr/lib/modules/${KVER}/updates" 2>/dev/null || true
fi

info "更新模块依赖并重载"
depmod -a "${KVER}"
modprobe -r xpad 2>/dev/null || true
modprobe xpad

echo
info "现在加载的 xpad："
modinfo -F filename xpad || true
echo
echo "记得拔插一次手柄。"
