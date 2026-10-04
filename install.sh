#!/usr/bin/env bash
#
# xpad-beitong —— 让北通/Beitong KP 系列手柄（含 BTP-KP20D）留在 XInput 模式。
#
# 用法：
#   sudo ./install.sh                     # DKMS，目标内核自动探测（推荐）
#   sudo ./install.sh manual              # 不走 DKMS，直接编译塞进 /updates
#   sudo ./install.sh dkms 7.2.8-arch1-2  # 显式指定目标内核
#
# 卸载： sudo ./uninstall.sh
#
set -euo pipefail

PKG="xpad-beitong"
VER="1.0"
MODE="${1:-dkms}"

SRC_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DST_DIR="/usr/src/${PKG}-${VER}"
RUNNING="$(uname -r)"

die()  { printf '\033[31m错误: %s\033[0m\n' "$*" >&2; exit 1; }
info() { printf '\033[36m==> %s\033[0m\n' "$*"; }

# 目标内核：优先当前运行内核；如果它的头文件已经不存在（典型场景：
# 刚升级完内核还没重启，旧内核的 /usr/lib/modules/<kver> 已被删掉），
# 就退回到已安装且带头文件的最新内核。
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
    printf '\n\033[33m!! 目标内核 %s 不是当前运行的内核 %s。\n' "${KVER}" "${RUNNING}"
    printf '   模块已为 %s 编译安装，但【必须重启】后才会生效。\033[0m\n\n' "${KVER}"
}

reload() {
    if [[ "${KVER}" != "${RUNNING}" ]]; then
        warn_restart
        return
    fi
    info "重新加载 xpad"
    modprobe -r xpad 2>/dev/null || true
    modprobe xpad
}

[[ "${EUID}" -eq 0 ]] || die "请用 root 运行： sudo $0"
[[ -f "${SRC_DIR}/xpad.c" ]] || die "找不到 ${SRC_DIR}/xpad.c"

info "运行内核：${RUNNING}"
info "目标内核：${KVER}"
[[ "${KVER}" != "${RUNNING}" ]] && warn_restart

[[ -e "${KDIR}" ]] || die "缺少内核头文件 ${KDIR}
    已安装的内核：$(ls -1 /usr/lib/modules 2>/dev/null | tr '\n' ' ')
    请先执行： sudo pacman -S --needed linux-headers dkms base-devel
    或显式指定： sudo $0 ${MODE} <内核版本>"

if [[ "${MODE}" == "manual" ]]; then
    command -v make >/dev/null || die "缺少 make"
    BUILD_DIR="$(mktemp -d)"
    trap 'rm -rf "${BUILD_DIR}"' EXIT
    install -m 0644 "${SRC_DIR}/xpad.c" "${SRC_DIR}/Makefile" "${BUILD_DIR}/"

    info "编译（out-of-tree，目标 ${KVER}）"
    make -C "${KDIR}" M="${BUILD_DIR}" modules

    info "安装到 /usr/lib/modules/${KVER}/updates/"
    install -d -m 0755 "/usr/lib/modules/${KVER}/updates"
    install -m 0644 "${BUILD_DIR}/xpad.ko" "/usr/lib/modules/${KVER}/updates/xpad.ko"
    depmod -a "${KVER}"
    reload
else
    command -v dkms >/dev/null || die "缺少 dkms
    请先执行： sudo pacman -S --needed linux-headers dkms"

    info "安装源码到 ${DST_DIR}"
    install -d -m 0755 "${DST_DIR}"
    install -m 0644 "${SRC_DIR}/xpad.c"    "${DST_DIR}/xpad.c"
    install -m 0644 "${SRC_DIR}/Makefile"  "${DST_DIR}/Makefile"
    install -m 0644 "${SRC_DIR}/dkms.conf" "${DST_DIR}/dkms.conf"

    info "清理旧的 DKMS 记录（若有）"
    dkms remove "${PKG}/${VER}" --all >/dev/null 2>&1 || true

    info "DKMS add / build / install"
    dkms add     "${PKG}/${VER}"
    dkms build   "${PKG}/${VER}" -k "${KVER}"
    dkms install "${PKG}/${VER}" -k "${KVER}" --force

    depmod -a "${KVER}"
    reload
fi

echo
if [[ "${KVER}" == "${RUNNING}" ]]; then
    info "当前 xpad 实际加载的文件："
    modinfo -F filename xpad || true
    echo
    info "模块参数（应能看到 beitong_force_init）："
    modinfo -F parm xpad | grep -i beitong || echo "  （未找到，说明加载的还是原版模块！）"
else
    info "已为 ${KVER} 安装的 xpad："
    modinfo -k "${KVER}" -F filename xpad 2>/dev/null || \
        ls -l "/usr/lib/modules/${KVER}/updates/" 2>/dev/null || true
    echo
    info "已为 ${KVER} 安装的模块参数："
    modinfo -k "${KVER}" -F parm xpad 2>/dev/null | grep -i beitong || echo "  （未找到）"
fi

if [[ "${KVER}" == "${RUNNING}" ]]; then
    cat <<'EOF'

== 下一步 ==
1) 拔掉手柄，等 2 秒，再插上。
2) 检查身份：
     lsusb | grep -Ei '057e|20bc'
   出现 20bc:xxxx  => 成功进入 XInput。
   仍是 057e:2009  => 手柄没有走 Xbox 人格，见 README 的「排障」。
3) 看内核日志：
     sudo dmesg | tail -40

== 回滚 ==
     sudo ./uninstall.sh
EOF
else
    cat <<EOF

== 下一步 ==
1) 【重启】进入 ${KVER}（当前还在跑 ${RUNNING}）。
2) 重启后拔插一次手柄，然后检查身份：
     lsusb | grep -Ei '057e|20bc'
   出现 20bc:xxxx  => 成功进入 XInput。
   仍是 057e:2009  => 手柄没有走 Xbox 人格，见 README 的「排障」。

== 回滚 ==
     sudo ./uninstall.sh
EOF
fi
