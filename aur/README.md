# xpad-beitong-dkms

**Temporary** DKMS package with a patched `xpad` for Beitong (北通) / Betop
KP-series controllers that refuse to stay in their XInput personality on Linux.
Deprecated once the fix lands upstream.

## Problem

These controllers boot into an Xbox personality and stay there only if the host
performs the handshake Windows does while enumerating. Linux USB core never does,
so the firmware power-cycles through its remaining personalities and finally
settles on Nintendo Switch Pro Controller emulation (`057e:2009`). Steam then
reports a "Nintendo" controller and XInput-only software cannot see the pad.

Captured on a wired BTP-KP20D — each step lasts ~2s and the cycle repeats 3x
before it stops on the last one:

```
20bc:5158  "BTP-KP20D XINPUT WIRED"     <- xpad binds here, then it gives up
057e:2069  "BTP-KP20D NS WIRED"
057e:2009  "Switch Pro Controller"      <- final state
```

**Symptoms**

- 2.4G receiver (`20bc:5127`): the USB device cycles connect/disconnect continuously.
- Wired KP20D (`20bc:5158`): enumerates cleanly, then silently becomes a Nintendo
  Switch Pro Controller about two seconds later.

## Fix

Two parts, both required:

1. **Microsoft OS descriptor request at index 0xEE** — the request Windows issues
   while discovering the `XUSB10` compatible ID. This is what the firmware is
   actually waiting for. Verified on hardware: it answers the raw vendor form
   (`bRequest=0xEE`, `wValue=0`, `wIndex=4`) with success, and the device then
   stays on `20bc:5158` indefinitely. This firmware does *not* answer the standard
   `GET_DESCRIPTOR(STRING, 0xEE)` form (it times out), so that path is only a
   fallback for other KP models.
2. **Xbox One GIP init packets** (`FLAG_FORCE_INIT`, from Zixing Liu's patch),
   kept for the other KP models.

The handshake runs from `xpad_probe()` as well as on input open: the firmware's
decision window is only ~2 seconds, which userspace opening `/dev/input/eventX`
cannot be relied on to beat.

> GIP packets alone (what 1.0 shipped) are **not** sufficient. With 1.0 loaded,
> `xpad` does bind to `20bc:5158` and the packets do go out, yet the device still
> switches away ~2s later.

## Installation

```bash
yay -S xpad-beitong-dkms
```

Then unplug and replug the controller. Verify:

```bash
lsusb | grep -Ei '057e|20bc'          # expect a stable 20bc:xxxx
sudo dmesg | grep 'Beitong XInput'    # expect: MS OS (raw=0 ...)
```

## Requirements

- `dkms`
- Kernel headers matching your running kernel (`linux-headers`,
  `linux-zen-headers`, `linux-cachyos-headers`, ...)

## How it works

1. Fetches `xpad.c` from the kernel tag named by `_kbase` in the PKGBUILD.
   It deliberately does **not** read driver sources out of `linux-headers`:
   Arch ships headers only, so that approach can never succeed.
2. Applies `beitong-ms-os-xinput.patch` (10 hunks).
3. Hands the result to DKMS, which rebuilds it automatically on kernel updates.

When Arch bumps the kernel, bump `_kbase` and its `sha256sums` entry. The patch
is small and applies with offsets, so a slightly newer base usually works
unchanged.

The quirk can be disabled at runtime with `options xpad beitong_force_init=0` in
`/etc/modprobe.d/`.

## Compatible devices

VID `0x20bc` in XInput mode: `5125-5128`, `512f-5130`, `5133-5134`, `5145-5146`,
`5149-514a`, `5150-5153`, `5154-5155`, `5158-5159`, `515b-515e`, `515f-5160`,
`5169-516a`.

Verified end-to-end on `20bc:5158` (wired BTP-KP20D): the device stays on
`20bc:5158`, binds `xpad`, and exposes `/dev/input/js0` + `/dev/input/event20`.

## Upstream status

| Item | Status |
|------|--------|
| GIP-packet half | Zixing Liu, v3 2026-07-17, pending review |
| MS OS descriptor half | Not submitted yet |
| This DKMS package | Deprecated once both halves are upstream |

## Links

- [Wiki page with full investigation log](https://github.com/675076143/notes/wiki/beitong-btp-kp40a-linux-usb-disconnect)
- [Upstream patch discussion (linux-input)](https://lore.kernel.org/linux-input/20260102030154.197749-2-liushuyu@aosc.io/)
- [Aaron Ma's MS OS descriptor patch for the KP20D](https://lkml.iu.edu/2607.3/02396.html)
- [Arch Wiki - Gamepad (ShanWan section)](https://wiki.archlinux.org/title/Gamepad)
