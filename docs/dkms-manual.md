# xpad-beitong —— 让北通 KP 系列手柄留在 XInput 模式

针对 **北通 鲲鹏20 / BEITONG BTP-KP20D**（以及同系列 KP20A/KP40x/KP50x/KP70A）在
Linux 上被 Steam 识别成 **Nintendo Switch Pro Controller** 的问题。

## 为什么会出现这个现象

北通 KP 系列开机后**先进入 Xbox 人格**，只有在 probe 阶段收到主机发来的
Xbox One 初始化握手包时才会留在那里（之后用 Xbox 360 协议上报输入）。
收不到这些包，手柄会自我断电重启，**重启超过 3 次后自动切到下一个支持的模式**
（Nintendo Switch 模式），于是枚举成 `057e:2009`，被内核 `hid_nintendo` 接管，
Steam 按 VID/PID 如实显示为 "Nintendo Switch Pro Controller"。

Windows 的 XInput 驱动会立刻完成这套握手，Linux 的 `usb` core 不会，而发行版
`xpad` 的设备表里又没有这些北通 ID，于是握手永远不发生。

本补丁让 `xpad` 对 `VID 0x20bc` 的 Beitong/Betop 设备也发送 Xbox One 初始化
序列（`xboxone_power_on` / `led_on` / `auth_done` + 北通专用的
ACK / ANNOUNCE 探测包），从而把手柄钉在 XInput 模式。

## 目录内容

| 文件 | 作用 |
|---|---|
| `xpad.c` | 打过补丁的 `xpad` 驱动源码（基于 Linux v7.2.8，共 8 个 hunk） |
| `xpad-beitong.patch` | 相对原始 `v7.2.8` 源码的 unified diff，便于核对 |
| `Makefile` / `dkms.conf` | 外部模块构建与 DKMS 配置 |
| `capture.sh` | 抓插拔瞬间的 USB 身份（**建议先跑**） |
| `install.sh` | 安装（DKMS 或手动两种模式） |
| `uninstall.sh` | 回滚到发行版自带 `xpad` |

## 前置条件

```bash
sudo pacman -S --needed linux-headers dkms base-devel
```

`linux-headers` 版本必须与**目标内核**完全一致（DKMS 会强制检查）。

### 刚升级过内核、还没重启

`pacman -Syu` 升级内核后，旧内核的 `/usr/lib/modules/<旧版本>/` 会被删掉，
此时 `uname -r` 仍是旧版本，但它已经没有头文件了。`install.sh` 会自动探测，
改为针对**已安装且带头文件的最新内核**构建，并提示重启：

```
$ sudo ./install.sh
==> 运行内核：7.2.4-arch1-2
==> 目标内核：7.2.8-arch1-2
!! 目标内核 7.2.8-arch1-2 不是当前运行的内核 7.2.4-arch1-2。
   模块已为 7.2.8-arch1-2 编译安装，但【必须重启】后才会生效。
```

重启后模块自动生效，无需再跑一次。也可显式指定：
`sudo ./install.sh dkms 7.2.8-arch1-2`

## 步骤

**第 0 步（强烈建议）先确认 XInput 人格真实存在**

```bash
./capture.sh
```

它会提示你在 3 秒后开始记录时拔插手柄。如果日志里出现 **`20bc:xxxx`**，
说明手柄确实短暂进入过 Xbox 人格 —— 补丁有意义。
如果全程只有 `057e:2009`，说明有线连接根本不走 Xbox 人格，补丁不会生效，
请改用 Steam Input 方案（见下方「排障」）。

**第 1 步 安装**

```bash
sudo ./install.sh          # 推荐：DKMS，内核升级后自动重建
sudo ./install.sh manual   # 备选：直接编译塞进 /updates，内核升级后需重跑
```

**第 2 步 验证**

```bash
lsusb | grep -Ei '057e|20bc'
```

- 出现 `20bc:xxxx`（BETOP/Beitong）→ 成功，手柄现在是 XInput。
- 仍是 `057e:2009` → 见下。

```bash
modinfo -F filename xpad     # 必须指向 /usr/lib/modules/.../updates/ 下的模块
modinfo -F parm xpad         # 应含 beitong_force_init
```

## 排障

**1. `modinfo -F filename xpad` 还指向 `/kernel/drivers/input/joystick/xpad.ko`**

模块没顶掉自带的。执行 `sudo depmod -a && sudo modprobe -r xpad && sudo modprobe xpad`，
再确认。若 DKMS 报错，用 `sudo ./install.sh manual`。

**2. 模块已加载，但插上后仍是 `057e:2009`**

说明握手后手柄还是掉回了 Switch 模式。依次尝试：

```bash
# 看看内核有没有抱怨
sudo dmesg | tail -40

# 关掉本补丁的行为，确认是否反而有副作用
sudo modprobe -r xpad && sudo modprobe xpad beitong_force_init=1
```

如果 `capture.sh` 显示根本没有出现过 `20bc`，那就是手柄固件在有线模式下
不提供 Xbox 人格，内核侧无解。此时请直接用 Switch Pro Controller 模式：

- Steam → 设置 → 控制器 → 勾选「为 Xbox 控制器启用 Steam 输入」
  和「Nintendo Switch 控制器支持」。
- Steam 客户端自带 `Nintendo Switch Pro Controller` 映射，体感和震动都可用。
- **不要**为了「变成 XInput」去 `modprobe -r hid_nintendo` 或 blacklist 它 ——
  那只会让 `hid-generic` 接管，退化成一个没有震动/体感的通用 DInput 手柄。

**3. 其他 0x20bc 设备（如 KP50B/50C 无线接收器）行为异常**

`beitong_force_init` 默认对整个 `0x20bc` 厂商 ID 生效。可以关掉：

```bash
sudo modprobe -r xpad && sudo modprobe xpad beitong_force_init=0
```

永久关闭：在 `/etc/modprobe.d/xpad-beitong.conf` 里写
`options xpad beitong_force_init=0`。

## 回滚

```bash
sudo ./uninstall.sh
```

## 补丁来源与差异

补丁基于 Zixing Liu 提交到 linux-input 的
`[PATCH 1/1] Input: xpad - add support for Beitong KP-series controllers`
（<https://patchew.org/linux/20260102030154.197749-2-liushuyu@aosc.io/>）。

与上游版本的差异：

1. 上游用 `xpad_prepare_next_init_packet()` 只把包**准备好**；本补丁改为
   `xpad->init_seq = 0; xpad_try_sending_next_out_packet();`，
   确保初始化包真的从 interrupt OUT 端点发出去。
2. 增加 `beitong_force_init` 模块参数（默认开），便于一键回退行为。
3. 除了设备表里的显式条目，还对**任意** `VID 0x20bc` 设备启用该行为 ——
   因为有线 BTP-KP20D 的 Product ID 未必在已知列表里。
4. 已存在 `0x5134` / `0x514a` 两条 "BETOP ... Xinput Dongle" 条目保持不变，
   不重复添加（内核设备表按第一个匹配项生效）。
5. 除 `xpad_start_input()` 外，**在 `xpad_probe()` 里也直接触发一次握手**。
   实测（见下）XInput 人格只存在约 2 秒，等用户态 open 输入设备太晚。
6. 增加 `xpad_query_ms_os_descriptor()`，在 probe 最早期发 Microsoft OS 描述符
   请求。**硬件实测结论**（wired BTP-KP20D）：

   - 标准 `GET_DESCRIPTOR(STRING, 0xEE)` → 固件**不响应**，超时（`-11`）
   - 原始厂商请求 `bRequest=0xEE, wValue=0, wIndex=4, 40 bytes` → **`0` 成功**，
     手柄随即稳定停在 `20bc:5158`

   所以这条原始请求排在最前（趁 2 秒窗口还在），标准形式与 XUSB10
   Compatible ID 形式保留为其他 KP 型号的兜底。
   日志：`Beitong XInput handshake: MS OS (raw=0 str=-11 code=0x01/-32)`

   ⚠️ 这些请求必须走 `usb_control_msg_recv()`（内部 `kmemdup` bounce buffer）。
   裸 `usb_get_descriptor()` / `usb_control_msg()` 会把栈上的 `buf` 直接交给
   HCD 做 DMA 映射，触发 `transfer buffer is on stack` 告警 —— 已修。

已在 `7.2.8-arch1-2` 上完成 out-of-tree 编译验证（退出码 0，BTF 正常生成），
并在真机上验证手柄稳定停在 `20bc:5158`、绑定 `xpad`、生成 `/dev/input/js0`
与 `/dev/input/event20`。

## 实测：手柄的模式循环

`capture.sh` 在真实机器上抓到的序列（每段约 2 秒，循环 3 次后停在最后一项）：

```
[07:36:38] Device 036: ID 20bc:5158 ShenZhen ShanWan ... BTP-KP20D XINPUT WIRED
[07:36:40] Device 037: ID 057e:2069 Nintendo Co., Ltd   BTP-KP20D NS WIRED
[07:36:43] Device 038: ID 057e:2009 Nintendo Co., Ltd   Switch Pro Controller
[07:36:46] Device 039: ID 20bc:5158 ... BTP-KP20D XINPUT WIRED     <- 第 2 轮
[07:36:55] Device 042: ID 20bc:5158 ... BTP-KP20D XINPUT WIRED     <- 第 3 轮
[07:37:00] Device 044: ID 057e:2009 ... Switch Pro Controller      <- 最终停留
```

这直接印证了上游补丁 cover letter 里「手柄会自我断电重启，超过三次后切到
下一个模式」的描述，也确认有线 KP20D 在 XInput 模式下的 ID 就是
**`20bc:5158`** —— 正是本补丁设备表里的那一条。

## 已知限制

- 本补丁只解决「手柄愿意留在 XInput」的问题，不会凭空创造 Xbox 人格。
- 内核升级后若用 `manual` 模式安装，需要重新执行 `install.sh`。
- Xbox One 初始化包与 MS OS / XUSB10 描述符读取（
  <https://lkml.iu.edu/2607.3/02396.html>）两条路径都已实现，因为三个上游
  作者对「手柄到底在等什么」说法不一致。
- 若两条路径都无效，说明该固件在有线模式下没有可用的 XInput 人格，
  内核侧无解 —— 只能按上文「排障 2」改用 Steam Input + Switch 模式。
