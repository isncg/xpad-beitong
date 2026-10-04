#!/usr/bin/env bash
#
# Capture the controller's USB identity around a plug/unplug.
#
# Purpose: confirm that a wired BTP-KP20D briefly appears as 20bc:xxxx (the
# Beitong/Betop XInput identity) before falling back to 057e:2009 (Nintendo
# Switch Pro Controller emulation).
#
# Usage:
#   ./capture.sh            # capture for 30s, log written to the current directory
#   ./capture.sh 45 /tmp/x.log
#
set -uo pipefail

DUR="${1:-30}"
OUT="${2:-$PWD/beitong-usb-capture.log}"

echo "== capturing for ${DUR}s, log: ${OUT} =="
echo "== recording starts in 3s - unplug and replug the controller during that window =="
sleep 3

: >"${OUT}"
prev=""
end=$((SECONDS + DUR))

while (( SECONDS < end )); do
    cur="$(lsusb 2>/dev/null | grep -Ei '057e|20bc|045e|beitong|betop|nintendo' | sort)"
    if [[ "${cur}" != "${prev}" ]]; then
        {
            echo "[$(date +%T)]"
            echo "${cur:-<no matching device>}"
            echo
        } | tee -a "${OUT}" >/dev/null
        echo "[$(date +%T)] ${cur:-<no matching device>}"
        prev="${cur}"
    fi
    sleep 0.1
done

echo
echo "== capture finished =="
if grep -q '20bc' "${OUT}"; then
    echo "OK: 20bc:xxxx appeared, so the Xbox/XInput identity does exist and a"
    echo "    patched xpad has a chance to complete the handshake before it goes away."
else
    echo "NOTE: only 057e:2009 was seen, so the wired connection never enters the"
    echo "      Xbox identity. The patched module cannot help; use Steam Input with"
    echo "      Switch mode instead (see Troubleshooting in docs/dkms-manual.md)."
fi
echo "full log: ${OUT}"
