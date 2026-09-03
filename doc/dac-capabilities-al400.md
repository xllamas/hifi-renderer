# Reference DAC: SMSL AL400 — measured capabilities

Captured by the M1 probe on a Redmi Note 10 Pro (Android 13, MIUI 14).
**This is one sample, not the specification.** Everything the app does must come
from runtime capability detection; nothing below may be hard-coded.

## Identity

| | |
|---|---|
| VID:PID | `152a:85dd` (Thesycon — XMOS-based firmware) |
| Strings | SMSL / "SMSL USB AUDIO" |
| USB | 2.0, high speed (480 Mbps), bDeviceClass 239 (composite/IAD) |
| Configurations | **2** — only config #1 parsed; XMOS devices commonly expose a UAC1 fallback in the second |
| Class | **UAC 2.0** |

## Interfaces (config #1)

| if | class | purpose |
|---|---|---|
| 0 | AUDIO / AudioControl | clock + terminals |
| 1 | AUDIO / AudioStreaming | alt 0–3, the playback path |
| 2 | 0xFE APP-SPECIFIC sub 1 | DFU (firmware update) |
| 3 | HID, `ep 0x83 IN` interrupt | **input only** — DAC's knob/remote reports *to* the host |

## Streaming alt-settings (interface 1)

| alt | format | bits | subslot | endpoint |
|---|---|---|---|---|
| 0 | — | — | — | zero-bandwidth |
| 1 | PCM | 32 | 4 | `0x01` OUT ISO **ASYNC** |
| 2 | PCM | 24 | 4 | `0x01` OUT ISO **ASYNC** |
| 3 | **RAW/DSD** | 32 | 4 | `0x01` OUT ISO **ASYNC** |

Feedback endpoint on every alt: `ep 0x81 IN ISO, maxPacket=4, interval=4`.
Data endpoint: `maxPacket=776, interval=1` (125 µs microframes).

## Clocking

- `CLOCK_SOURCE` id **41**, `bmAttributes=0x03` (internal programmable, not SOF-synced),
  `bmControls=0x07` → frequency is **host-programmable**.
- `CLOCK_SELECTOR` id 40 sits between the terminals and the source.
- Rates (live `GET_RANGE`): **44100 48000 88200 96000 176400 192000 352800 384000 705600 768000**
- Current rate at probe time: 48000.

## Volume — not available on this DAC

The AudioControl block is 54 bytes and decodes with **no `FEATURE_UNIT` descriptor**:
output terminal 20's `bSourceID` is input terminal 2, directly. The HID interface
has only an interrupt IN endpoint, so it cannot accept volume either.

**Conclusion: the host cannot set this DAC's volume by any route.** This is the
"if accepted by the device" case the spec anticipated. `RenderingControl.SetVolume`
must answer sanely but has nothing to forward.

An interesting inversion: the HID IN endpoint means the DAC's own knob/remote could
*drive* the renderer's volume state (and hence DLNA `LastChange` events). Worth
considering later; not in scope now.

## Consequences for M2

1. **Feedback-endpoint clock tracking is mandatory**, not optional — the endpoint is
   asynchronous and the DAC runs its own clock. Confirmed by hardware, not assumed.
2. **There is no 16-bit alt-setting.** 16/44.1 content (ordinary CD-sourced FLAC) must
   be padded into a 24- or 32-bit subslot. Zero-padding preserves sample values
   exactly, so this stays bit-perfect — but it is a required conversion, not optional.
3. Set the rate with `SET_CUR` on clock entity **41** (host-programmable per `bmControls`).
4. Pick alt 2 for 24-bit, alt 1 for 32-bit; alt 3 is DSD and stays deferred.
5. Capability ceiling is far above the plan's assumption: **768 kHz**, both the 44.1
   and 48 kHz families.

## Host-side requirement discovered

The AudioControl interface must be claimed with Android's
`UsbDeviceConnection.claimInterface(itf, force = true)` before any class control
transfer will work — `force=true` detaches the kernel's `snd-usb-audio` driver.
Without it, the clock `GET_RANGE` fails with `LIBUSB_ERROR_IO`. The interface must
be released afterwards or the DAC stays detached from system audio.

## Soak test result (2026-09-03)

30.9 minutes of continuous 96 kHz / 24-bit playback, release build, screen
allowed to sleep:

| Measure | Result |
|---|---|
| Frames | 178,049,411 |
| Isochronous packets | 14,837,480, **0 errors** |
| Underruns / transfer errors | **0 / 0** |
| Feedback readings | 1,851,342 accepted, **0 rejected** |
| Stats samples with any fault | **0 of 927** |
| Reported rate | 95998.0 – 96000.0 Hz (**±0.002%**, ~20 ppm) |

The rate spread is the most informative number: ±2 ppm-scale deviation around
nominal is the DAC's own crystal being tracked by the feedback loop. Neither
pinned rigidly to nominal (which would mean feedback was being ignored) nor
drifting (the ratchet bug). This is what a correct asynchronous endpoint looks
like.

This also confirmed the playback wake lock: the run survived well past the
phone's 5-minute screen timeout, which had previously been expected to suspend
the process.

## Platform note

`adb shell dumpsys usb` **crashes** on this bus with `IllegalArgumentException` in
`UsbDescriptorParser.parseDescriptors` → `ByteStream.<init>` — Android's own
descriptor parser. Independent justification for parsing defensively rather than
trusting descriptors or the platform.
