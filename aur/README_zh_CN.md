# xpad-beitong-dkms

为北通 / Beitong·Betop KP 系列手柄打补丁的 **临时** DKMS 包：这些手柄在 Linux 上
无法停留在 XInput 人格。修复合入上游后本包即弃用。

## 问题

这类手柄开机先进 Xbox 人格，只有在枚举阶段收到**Windows 会做的那套握手**时才肯留下。
Linux 的 USB core 从不做这套握手，于是固件自我断电重启、逐个尝试剩下的模式，
最后停在任天堂 Switch Pro Controller 模拟（`057e:2009`）。Steam 因此显示为
"Nintendo" 控制器，只认 XInput 的软件也看不到它。

有线 BTP-KP20D 的实测序列（每段约 2 秒，重复 3 次后停在最后一项）：

```
20bc:5158  "BTP-KP20D XINPUT WIRED"     ← xpad 在这里绑定，然后它放弃了
057e:2069  "BTP-KP20D NS WIRED"
057e:2009  "Switch Pro Controller"      ← 最终状态
```

**症状**

- 2.4G 接收器（`20bc:5127`）：USB 设备持续断连重连。
- 有线 KP20D（`20bc:5158`）：枚举正常，约两秒后悄悄变成任天堂手柄。

## 修复

两部分缺一不可：

1. **索引 0xEE 的 Microsoft OS 描述符请求**——Windows 在探测 `XUSB10` 兼容 ID 时
   发出的请求，也是固件真正在等的信号。真机实测：原始厂商形式
   （`bRequest=0xEE`、`wValue=0`、`wIndex=4`）返回成功，设备随即无限期稳定在
   `20bc:5158`。本固件**不响应**标准的 `GET_DESCRIPTOR(STRING, 0xEE)`（会超时），
   所以那条只作为其他 KP 型号的兜底。
2. **Xbox One GIP 初始化包**（`FLAG_FORCE_INIT`，来自 Zixing Liu 的补丁），
   为其他 KP 型号保留。

握手除了在打开输入设备时执行，也在 `xpad_probe()` 中执行：固件的决策窗口只有约 2 秒，
不能指望用户态及时 open `/dev/input/eventX`。

> 只发 GIP 包（1.0 的做法）**不够**。装 1.0 时 `xpad` 确实绑定到了 `20bc:5158`
> 且包也确实发了出去，设备仍在约 2 秒后切换。

## 安装

```bash
yay -S xpad-beitong-dkms
```

然后拔插一次手柄。验证：

```bash
lsusb | grep -Ei '057e|20bc'          # 期望稳定在 20bc:xxxx
sudo dmesg | grep 'Beitong XInput'    # 期望 MS OS (raw=0 ...)
```

## 依赖

- `dkms`
- 与运行内核匹配的 headers（`linux-headers`、`linux-zen-headers`、
  `linux-cachyos-headers` 等）

## 工作原理

1. 按 PKGBUILD 里的 `_kbase` 从对应内核 tag 下载 `xpad.c`。
   **刻意不从 `linux-headers` 里取驱动源码**——Arch 的 headers 不含 `.c` 文件，
   那条路根本走不通。
2. 应用 `beitong-ms-os-xinput.patch`（10 个 hunk）。
3. 交给 DKMS，内核更新后自动重编。

Arch 升级内核时，把 `_kbase` 和对应的 `sha256sums` 一起更新即可。补丁很小、
可以带偏移应用，所以稍新的 base 通常无需改动。

运行时可用 `/etc/modprobe.d/` 里的 `options xpad beitong_force_init=0` 关闭该行为。

## 兼容设备

XInput 模式下 VID 为 `0x20bc` 的：`5125-5128`、`512f-5130`、`5133-5134`、
`5145-5146`、`5149-514a`、`5150-5153`、`5154-5155`、`5158-5159`、`515b-515e`、
`515f-5160`、`5169-516a`。

`20bc:5158`（有线 BTP-KP20D）已端到端验证：稳定停在 `20bc:5158`、绑定 `xpad`、
生成 `/dev/input/js0` 与 `/dev/input/event20`。

## 上游状态

| 项目 | 状态 |
|------|------|
| GIP 包部分 | Zixing Liu，v3 2026-07-17，待评审 |
| MS OS 描述符部分 | 尚未提交 |
| 本 DKMS 包 | 两部分都合入后弃用 |

## 链接

- [完整排查记录（Wiki）](https://github.com/675076143/notes/wiki/beitong-btp-kp40a-linux-usb-disconnect)
- [上游补丁讨论 (linux-input)](https://lore.kernel.org/linux-input/20260102030154.197749-2-liushuyu@aosc.io/)
- [Aaron Ma 针对 KP20D 的 MS OS 描述符补丁](https://lkml.iu.edu/2607.3/02396.html)
- [Arch Wiki - Gamepad（ShanWan 章节）](https://archlinux.org/title/Gamepad)
