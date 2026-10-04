# xpad-beitong

北通 / Beitong·Betop KP 系列手柄在 Linux 上的 **XInput** 修复。

主线内核的 `xpad` 目前无法让这些手柄停留在 Xbox 人格，于是它们最终退化成
任天堂 Switch Pro Controller 模拟：Steam 显示为「Nintendo 控制器」，
只认 XInput 的软件也看不到它。

本仓库包含修复补丁、**真机验证证据**，以及一份可直接替换 AUR 包
`xpad-beitong-dkms` 的打包改动。已在有线 **BTP-KP20D**（`20bc:5158`）上端到端验证。

## 问题

手柄开机先进 Xbox 人格，只有在枚举阶段收到「Windows 会做的那套握手」时才肯留下。
Linux 的 USB core 从不做这套握手，固件便自我断电重启、逐个尝试剩下的模式，
最后停在 `057e:2009`。

真机抓到的完整循环（每段约 2 秒，重复 3 次后停在最后一项），原始日志见
[`evidence/beitong-usb-capture.log`](evidence/beitong-usb-capture.log)：

```
[07:36:38] 20bc:5158  ShenZhen ShanWan ... BTP-KP20D XINPUT WIRED
[07:36:40] 057e:2069  Nintendo Co., Ltd    BTP-KP20D NS WIRED
[07:36:43] 057e:2009  Nintendo Co., Ltd    Switch Pro Controller
[07:36:46] 20bc:5158  ... XINPUT WIRED                    <- 第 2 轮
[07:36:55] 20bc:5158  ... XINPUT WIRED                    <- 第 3 轮
[07:37:00] 057e:2009  ... Switch Pro Controller           <- 最终停留
```

**症状**

- 2.4G 接收器（`20bc:5127`）：USB 设备持续断连重连。
- 有线 KP20D（`20bc:5158`）：枚举正常，约两秒后悄悄变成任天堂手柄。

## 根因：用返回码定案

上游有三份互相冲突的提交：两位作者认为关键是 **Microsoft OS 描述符**，
一位认为是 **Xbox One GIP 初始化包**。我们让硬件给出答案：

| 请求 | 返回码 | 结论 |
|---|---|---|
| 厂商 `bRequest=0xEE`, `wValue=0`, `wIndex=4`, 40 bytes | **`0`** | ✅ 固件真正在等的就是它 |
| 标准 `GET_DESCRIPTOR(STRING, 0xEE)` | `-11` | 固件不实现，超时 |
| Xbox One GIP 初始化包（ACK / ANNOUNCE） | 成功发出 | ❌ 单独使用无效：`xpad` 已绑定、包已发出，设备仍在约 2 秒后切换 |

所以修复必须两件一起做：发 0xEE 厂商请求（**必须排在最前**，固件的决策窗口只有约
2 秒），并保留 GIP 包作为其他 KP 型号的兼容路径。握手同时放进 `xpad_probe()`，
不能只依赖用户态打开 `/dev/input/eventX`。

> 附带发现：这些请求**只能**走 `usb_control_msg_recv()`（内部 `kmemdup` bounce
> buffer）。裸 `usb_get_descriptor()` / `usb_control_msg()` 会把栈上的缓冲区交给
> HCD 做 DMA 映射，触发 `transfer buffer is on stack` 告警。

## 仓库内容

| 路径 | 说明 |
|---|---|
| [`xpad.c`](xpad.c) | 打过补丁的驱动源码（基于 Linux v7.2.8） |
| [`xpad-beitong.patch`](xpad-beitong.patch) | 相对 pristine v7.2.8 的 10-hunk unified diff |
| [`Makefile`](Makefile) / [`dkms.conf`](dkms.conf) | 外部模块构建与 DKMS 配置 |
| [`install.sh`](install.sh) / [`uninstall.sh`](uninstall.sh) | 本地 DKMS 安装与回滚 |
| [`capture.sh`](capture.sh) | 抓插拔瞬间 USB 身份的诊断脚本 |
| [`docs/dkms-manual.md`](docs/dkms-manual.md) | 手动构建/安装的详细步骤与排障 |
| [`evidence/`](evidence/) | 真机抓到的模式循环日志 |
| [`aur/`](aur/) | AUR `xpad-beitong-dkms` 的修复版打包文件，含可发送的 `0001-*.patch` |
| [`LICENSE`](LICENSE) | GPL-2.0-only（派生自内核 `xpad.c`） |

## 使用

### Arch：走 AUR 打包（推荐）

细节见 [`aur/README.md`](aur/README.md)。简版：

```bash
cd aur
makepkg -si
# 然后拔插手柄
lsusb | grep -Ei '057e|20bc'          # 期望稳定在 20bc:xxxx
sudo dmesg | grep 'Beitong XInput'    # 期望 MS OS (raw=0 ...)
```

### 任意发行版：直接编外部模块

需要对应内核的 headers。详细步骤与排障见
[`docs/dkms-manual.md`](docs/dkms-manual.md)。

```bash
sudo ./install.sh
# 拔插手柄后用上面的命令验证
sudo ./uninstall.sh        # 回滚
```

运行时可用 `/etc/modprobe.d/` 中的 `options xpad beitong_force_init=0` 关闭该行为。

## 上游状态

| 部分 | 状态 |
|---|---|
| GIP 初始化包 | Zixing Liu，v3 2026-07-17，待评审 |
| MS OS 描述符 | 尚未提交（本仓库的核心贡献） |
| AUR `xpad-beitong-dkms` | 1.0 版**无法构建**且路线错误；[`aur/`](aur/) 是修复版 |

## 参考

- [Zixing Liu 的 GIP 补丁（linux-input）](https://lore.kernel.org/linux-input/20260102030154.197749-2-liushuyu@aosc.io/)
- [Aaron Ma：为 BTP-KP20D 查询 MS OS 描述符](https://lkml.iu.edu/2607.3/02396.html)
- [VegetablCat：Beitong KP 系列支持（含 0xEE 厂商请求）](https://lkml.iu.edu/2607.3/03221.html)
- [AUR: xpad-beitong-dkms](https://aur.archlinux.org/packages/xpad-beitong-dkms)

## 许可

`xpad.c` 及其补丁派生自 Linux 内核（GPL-2.0-only），因此本仓库整体以
GPL-2.0-only 发布，见 [`LICENSE`](LICENSE)。
