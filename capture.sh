#!/usr/bin/env bash
#
# 抓取手柄插拔瞬间的 USB 身份。
#
# 目的：确认北通 BTP-KP20D 有线插入时，是否会短暂地以 20bc:xxxx
#      （Beitong/Betop XInput 人格）出现，然后才掉回 057e:2009
#      （Nintendo Switch Pro Controller 人格）。
#
# 用法：
#   ./capture.sh            # 抓 30 秒，日志写到当前目录
#   ./capture.sh 45 /tmp/x.log
#
set -uo pipefail

DUR="${1:-30}"
OUT="${2:-$PWD/beitong-usb-capture.log}"

echo "== 抓取 ${DUR} 秒，日志：${OUT} =="
echo "== 3 秒后开始记录，请在这段时间内【拔掉手柄再插上】 =="
sleep 3

: >"${OUT}"
prev=""
end=$((SECONDS + DUR))

while (( SECONDS < end )); do
    cur="$(lsusb 2>/dev/null | grep -Ei '057e|20bc|045e|beitong|betop|nintendo' | sort)"
    if [[ "${cur}" != "${prev}" ]]; then
        {
            echo "[$(date +%T)]"
            echo "${cur:-<无匹配设备>}"
            echo
        } | tee -a "${OUT}" >/dev/null
        echo "[$(date +%T)] ${cur:-<无匹配设备>}"
        prev="${cur}"
    fi
    sleep 0.1
done

echo
echo "== 抓取结束 =="
if grep -q '20bc' "${OUT}"; then
    echo "✅ 日志里出现过 20bc:xxxx —— Xbox/XInput 人格确实存在过，"
    echo "   补丁后的 xpad 有机会在它消失前完成握手。"
else
    echo "⚠️  全程只看到 057e:2009 —— 有线连接似乎根本不进入 Xbox 人格。"
    echo "   补丁模块大概率无效，需要改用 Steam Input / Switch 模式方案。"
fi
echo "完整日志：${OUT}"
