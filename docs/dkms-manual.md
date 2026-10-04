# Manual build, verification and troubleshooting

This is the out-of-tree / DKMS route for the patched `xpad`. For the problem
statement, the hardware evidence and the root cause, see the
[project README](../README.md).

It applies to the **BEITONG BTP-KP20D** (北通 鲲鹏20) and the rest of the KP
series (KP20A, KP40x, KP50x, KP70A).

## Prerequisites

```bash
sudo pacman -S --needed linux-headers dkms base-devel
```

The `linux-headers` version must match the **target kernel** exactly; DKMS
enforces this.

### Kernel upgraded but not rebooted yet

After `pacman -Syu` installs a new kernel, the old kernel's
`/usr/lib/modules/<old-kver>/` is removed. `uname -r` still reports the old
version, but that kernel no longer has headers. `install.sh` detects this,
builds for the **newest installed kernel that still has headers**, and tells you
to reboot:

```
$ sudo ./install.sh
==> running kernel: 7.2.4-arch1-2
==> target kernel:  7.2.8-arch1-2
!! target kernel 7.2.8-arch1-2 is not the running kernel 7.2.4-arch1-2.
   The module was built and installed for 7.2.8-arch1-2, but it only takes
   effect after a REBOOT.
```

The module takes effect on the next boot; no second run is needed. You can also
name the target kernel explicitly:
`sudo ./install.sh dkms 7.2.8-arch1-2`

## Steps

**Step 0 (strongly recommended): confirm the XInput identity actually appears**

```bash
./capture.sh
```

It asks you to unplug and replug the controller during a three-second window.
If `20bc:xxxx` shows up in the log, the controller really does enter the Xbox
identity briefly, and the patch has something to work with. If only `057e:2009`
ever appears, the wired connection never enters that identity, in which case no
kernel-side change can help - use the Steam Input route under Troubleshooting.

**Step 1: install**

```bash
sudo ./install.sh          # recommended: DKMS, rebuilt automatically on kernel updates
sudo ./install.sh manual   # alternative: build straight into /updates, rerun after kernel updates
```

**Step 2: verify**

```bash
lsusb | grep -Ei '057e|20bc'
```

- `20bc:xxxx` (BETOP/Beitong) -> success, the controller is in XInput mode.
- still `057e:2009` -> see Troubleshooting below.

```bash
modinfo -F filename xpad     # must point at the module under /usr/lib/modules/.../updates/
modinfo -F parm xpad         # must list beitong_force_init
```

## Troubleshooting

**1. `modinfo -F filename xpad` still points at `/kernel/drivers/input/joystick/xpad.ko`**

The stock module was not displaced. Run
`sudo depmod -a && sudo modprobe -r xpad && sudo modprobe xpad` and check again.
If DKMS reports an error, use `sudo ./install.sh manual`.

**2. The patched module is loaded, but the controller still shows up as `057e:2009`**

The handshake is not landing. In order:

```bash
# see whether the kernel complains
sudo dmesg | tail -40

# re-enable the quirk explicitly
sudo modprobe -r xpad && sudo modprobe xpad beitong_force_init=1
```

If `capture.sh` never showed `20bc` at all, the firmware does not offer an Xbox
identity over the wire and no kernel-side change can help. Use the controller in
Switch mode instead:

- Steam -> Settings -> Controller -> enable "Enable Steam Input for Xbox
  controllers" and "Nintendo Switch Controller Support".
- The Steam client ships a `Nintendo Switch Pro Controller` mapping; gyro and
  rumble both work.
- Do **not** `modprobe -r hid_nintendo` or blacklist it in the hope of getting
  XInput. That only lets `hid-generic` take over and leaves you with a generic
  DInput pad without rumble or gyro.

**3. Other `0x20bc` devices behave oddly (for example KP50B/KP50C wireless receivers)**

`beitong_force_init` applies to the whole `0x20bc` vendor ID by default. Turn it
off with:

```bash
sudo modprobe -r xpad && sudo modprobe xpad beitong_force_init=0
```

To disable it permanently, put `options xpad beitong_force_init=0` in
`/etc/modprobe.d/xpad-beitong.conf`.

## Rollback

```bash
sudo ./uninstall.sh
```

## How this patch differs from the upstream submission

It is based on Zixing Liu's
`[PATCH 1/1] Input: xpad - add support for Beitong KP-series controllers`
(<https://patchew.org/linux/20260102030154.197749-2-liushuyu@aosc.io/>).

Differences:

1. Upstream only calls `xpad_prepare_next_init_packet()`, which *stages* a
   packet. This patch instead does
   `xpad->init_seq = 0; xpad_try_sending_next_out_packet();`, so the init
   packets are actually submitted on the interrupt OUT endpoint.
2. Adds the `beitong_force_init` module parameter (on by default) for a
   one-command rollback.
3. Applies the behaviour to **any** `0x20bc` device rather than only the IDs
   listed in the device table, because a wired BTP-KP20D does not necessarily
   use a known product ID.
4. Leaves the existing `0x5134` / `0x514a` "BETOP ... Xinput Dongle" entries
   alone instead of adding duplicates (the device table matches on the first
   entry).
5. Runs the handshake from `xpad_probe()` as well as from `xpad_start_input()`.
   The XInput identity only survives for about two seconds, too short to rely on
   userspace opening the input device.
6. Adds `xpad_query_ms_os_descriptor()`, which issues the Microsoft OS
   descriptor requests as early as possible in probe. Hardware result on a wired
   BTP-KP20D:

   - vendor request, `bmRequestType 0xC0`, `bRequest 0xEE`, `wValue 0`,
     `wIndex 4`, 40 bytes -> returns `0`, and the controller then stays on
     `20bc:5158` indefinitely
   - standard `GET_DESCRIPTOR(String, 0xEE)` -> not implemented by this
     firmware, returns `-EAGAIN` (the request times out)

   The vendor request is therefore sent first, while the two-second window is
   still open. The standard OS string descriptor and the XUSB10 compatible-ID
   fetch are kept as fallbacks for other KP models.

   Note: these requests must go through `usb_control_msg_recv()`, which bounces
   the buffer through `kmemdup()`. Calling `usb_get_descriptor()` or
   `usb_control_msg()` directly hands a stack buffer to the HCD for DMA mapping
   and trips `transfer buffer is on stack` - fixed here.

Compile-verified on `7.2.8-arch1-2` (out-of-tree build, exit status 0, BTF
generated) and verified on hardware: the controller stays on `20bc:5158`, binds
`xpad`, and exposes `/dev/input/js0` and `/dev/input/event20`.

## Measured behaviour: the identity cycle

What `capture.sh` recorded on real hardware. Each step lasts about two seconds,
and the sequence repeats three times before stopping on the last entry:

```
[07:36:38] Device 036: ID 20bc:5158 ShenZhen ShanWan ... BTP-KP20D XINPUT WIRED
[07:36:40] Device 037: ID 057e:2069 Nintendo Co., Ltd   BTP-KP20D NS WIRED
[07:36:43] Device 038: ID 057e:2009 Nintendo Co., Ltd   Switch Pro Controller
[07:36:46] Device 039: ID 20bc:5158 ... BTP-KP20D XINPUT WIRED     <- cycle 2
[07:36:55] Device 042: ID 20bc:5158 ... BTP-KP20D XINPUT WIRED     <- cycle 3
[07:37:00] Device 044: ID 057e:2009 ... Switch Pro Controller      <- final state
```

This matches the upstream cover letter's description (the controller resets
itself and, after more than three attempts, moves on to the next supported
mode), and confirms that the wired KP20D's XInput identity is `20bc:5158` - the
entry the patch's device table already carries.

## Known limitations

- The patch only makes the controller willing to *stay* in XInput. It cannot
  conjure up an Xbox identity that the firmware never offers.
- After a kernel upgrade, a `manual` install must be re-run (`install.sh`).
- Both the Xbox One init packets and the MS OS / XUSB10 descriptor path
  (<https://lkml.iu.edu/2607.3/02396.html>) are implemented, because the three
  upstream authors disagree about what the firmware waits for.
- If neither path works, the firmware has no usable XInput identity in wired
  mode and the problem cannot be solved on the kernel side. Fall back to Steam
  Input with Switch mode (Troubleshooting, item 2).
