# xpad-beitong

Keep Beitong (北通) / Betop KP-series controllers in **XInput mode** on Linux.

The mainline `xpad` driver cannot hold these controllers in their Xbox identity,
so the firmware falls back to Nintendo Switch Pro Controller emulation: Steam
reports a "Nintendo" controller and XInput-only software cannot see the pad at
all.

This repository contains the patch, the **hardware evidence** behind it, and
fixed packaging for the AUR package `xpad-beitong-dkms`. Verified end to end on
a wired **BTP-KP20D** (`20bc:5158`).

## The problem

These controllers power up presenting an Xbox identity — a vendor-specific USB
interface (`bInterfaceClass 0xFF`, `bInterfaceSubClass 0x5D`, `bInterfaceProtocol
0x01`/`0x81`) that `xpad` matches as an Xbox 360 type — and they stay there only
if the host completes the same handshake Windows performs during enumeration.
The Linux USB core never issues it, so the firmware disconnects and
re-enumerates through its remaining identities, finally settling on Switch Pro
Controller emulation (`057e:2009`).

The full cycle, captured on real hardware. Each step lasts about two seconds and
the sequence repeats three times before it stops on the last one. Raw log:
[`evidence/beitong-usb-capture.log`](evidence/beitong-usb-capture.log).

```
[07:36:38] 20bc:5158  ShenZhen ShanWan ... BTP-KP20D XINPUT WIRED
[07:36:40] 057e:2069  Nintendo Co., Ltd    BTP-KP20D NS WIRED
[07:36:43] 057e:2009  Nintendo Co., Ltd    Switch Pro Controller
[07:36:46] 20bc:5158  ... XINPUT WIRED                    <- cycle 2
[07:36:55] 20bc:5158  ... XINPUT WIRED                    <- cycle 3
[07:37:00] 057e:2009  ... Switch Pro Controller           <- final state
```

The log was captured with an earlier revision of `capture.sh`; its
`<无匹配设备>` placeholder means "no matching device" (the current script prints
`<no matching device>`).

The USB device number changes between steps, so this is a real detach and
re-attach, not a soft reset.

**Symptoms**

- 2.4 GHz receiver (`20bc:5127`): the USB device connects and disconnects continuously.
- Wired KP20D (`20bc:5158`): enumerates cleanly, then silently turns into a
  Nintendo Switch Pro Controller roughly two seconds later.

## Root cause, settled with return codes

Three upstream submissions disagree about what the firmware waits for: two
authors say Microsoft OS descriptors, one says Xbox One GIP initialisation
packets. The hardware gives an unambiguous answer.

| Request | Result | Conclusion |
|---|---|---|
| Vendor request, `bmRequestType 0xC0`, `bRequest 0xEE`, `wValue 0`, `wIndex 4`, 40 bytes | `0` | ✅ this is what the firmware waits for |
| Standard `GET_DESCRIPTOR(String, 0xEE)` sent first | `-EAGAIN` | not implemented by this firmware; the request times out |
| Xbox One GIP init packets (generic Xbox One sequence plus `ACK`/`ANNOUNCE` probes) | `xpad` binds and no submit error is logged | ❌ insufficient on its own: the device still switches about two seconds later |

Both halves are therefore required:

1. The **vendor request at Microsoft OS descriptor index `0xEE`** — the request
   Windows issues to retrieve a device's Extended Compat ID descriptor, the one
   that carries the `XUSB10` compatible ID. On this firmware the descriptor's
   `bMS_VendorCode` is `0xEE` rather than the usual `0x01`, which is why the
   request uses `bRequest = 0xEE`. It must be sent **first**, because the
   firmware's decision window is only about two seconds wide.
2. The **Xbox One GIP init packets**, kept for the other KP-series models.

The handshake runs from `xpad_probe()` as well as when the input device is
opened, because userspace opening `/dev/input/eventX` cannot be relied upon to
happen inside that window.

> Related finding: these requests must be issued through
> `usb_control_msg_recv()`, which bounces the buffer through `kmemdup()`.
> Calling `usb_get_descriptor()` or `usb_control_msg()` directly hands a
> stack buffer to the HCD for DMA mapping and trips `transfer buffer is on
> stack` in `drivers/usb/core/hcd.c`.

## Repository layout

| Path | Contents |
|---|---|
| [`xpad.c`](xpad.c) | Patched driver source, based on Linux v7.2.8 |
| [`xpad-beitong.patch`](xpad-beitong.patch) | 10-hunk unified diff against pristine v7.2.8 |
| [`Makefile`](Makefile) / [`dkms.conf`](dkms.conf) | Out-of-tree module build and DKMS configuration |
| [`install.sh`](install.sh) / [`uninstall.sh`](uninstall.sh) | Local DKMS install and rollback |
| [`capture.sh`](capture.sh) | Diagnostic that captures the USB identity during plug and unplug |
| [`docs/dkms-manual.md`](docs/dkms-manual.md) | Manual build, verification and troubleshooting |
| [`evidence/`](evidence/) | The captured identity cycle |
| [`aur/`](aur/) | Fixed packaging for AUR `xpad-beitong-dkms`, plus a ready-to-send `0001-*.patch` |
| [`LICENSE`](LICENSE) | GPL-2.0-only (derived from the kernel's `xpad.c`) |

## Usage

### Arch Linux: through the AUR packaging (recommended)

Details in [`aur/README.md`](aur/README.md). Short version:

```bash
cd aur
makepkg -si
# then unplug and replug the controller
lsusb | grep -Ei '057e|20bc'          # expect a stable 20bc:xxxx
sudo dmesg | grep 'Beitong XInput'    # expect: MS OS (raw=0 ...)
```

### Any distribution: build the module out of tree

Requires kernel headers for the running kernel. Detailed steps and
troubleshooting are in [`docs/dkms-manual.md`](docs/dkms-manual.md).

```bash
sudo ./install.sh
# unplug and replug, then verify with the commands above
sudo ./uninstall.sh        # rollback
```

The quirk can be disabled at runtime with
`options xpad beitong_force_init=0` in `/etc/modprobe.d/`.

## Upstream status

| Part | Status |
|---|---|
| GIP init packets | Zixing Liu, v3 2026-07-17, under review |
| Microsoft OS descriptor half | not submitted yet (the main contribution here) |
| AUR `xpad-beitong-dkms` | 1.0 **does not build** and patches the wrong path; [`aur/`](aur/) is the fixed version |

## References

- [Zixing Liu's GIP patch (linux-input)](https://lore.kernel.org/linux-input/20260102030154.197749-2-liushuyu@aosc.io/)
- [Aaron Ma: query the MS OS descriptor for the BTP-KP20D](https://lkml.iu.edu/2607.3/02396.html)
- [VegetablCat: Beitong KP-series support (includes the 0xEE vendor request)](https://lkml.iu.edu/2607.3/03221.html)
- [AUR: xpad-beitong-dkms](https://aur.archlinux.org/packages/xpad-beitong-dkms)

## License

`xpad.c` and its patch are derived from the Linux kernel (GPL-2.0-only), so this
repository is released under GPL-2.0-only. See [`LICENSE`](LICENSE).
