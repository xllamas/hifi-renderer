# DSD: effort, usefulness, and the decision

Assessed 2026-09-11. **Verdict: build DoP as 1.1. Refuse native DSD on principle.
Decline DSD→PCM.**

## Why this came up

DSD is not an oversight. The app recognises it end to end and refuses it on purpose:

- `cpp/usb/UacCapabilities.cpp:91` parses UAC2 `bmFormats` bit 31 → `"DSD"`
- `cpp/usb/UacCapabilities.cpp:150` — `if (!a.isPcm()) continue;  // DSD is out of scope`
- `lib/usb/dac_capabilities.dart:200` → the capability screen row and note
- `lib/l10n/app_localizations_en.dart:505` — *"This DAC accepts native DSD. The app does
  not play DSD **yet**."*, in ten languages

Deferred twice deliberately (`doc/implementation-plan.md:26`,
`doc/dac-capabilities-al400.md:68`), never attempted. The reference AL400 exposes
`alt 3 = RAW/DSD`, 32-bit, subslot 4, on the same async iso endpoint already in use.

So the question is whether to close a promise the app is already making.

## Effort

### The expensive part is already built

DSD is costly in most Android apps because it needs raw isochronous USB control the
platform does not expose. Here that is `cpp/usb/UsbSink.cpp`, and the rate sweep has
already proven it past what DSD needs:

| Proven on the reference rig | Result |
|---|---|
| All ten AL400 rates to 768 kHz / 32-bit | 0 packet errors |
| Worst clock deviation across the sweep | 0.001% |
| Throughput at 768 kHz / 32-bit | 6.1 MB/s |
| 30.9-minute soak, 96 kHz / 24-bit | 14,837,480 packets, 0 errors |

DoP needs 176.4, 352.8 and 705.6 kHz — three rates already in that clean sweep.

### Why DoP is nearly free here

DoP carries DSD inside ordinary 24-bit PCM frames with a marker byte that alternates
`0x05`/`0xFA`. One word, left-justified into the AL400's 4-byte subslot:

```
bits 31-24   0x05 / 0xFA     marker, alternating each frame
bits 23-16   DSD byte n      8 one-bit samples, MSB first
bits 15-8    DSD byte n+1    8 one-bit samples, MSB first
bits 7-0     0x00            zero pad, as 16-bit PCM already gets
```

Sixteen DSD bits per frame, so the frame rate is the DSD rate ÷ 16. To the sink this is
indistinguishable from PCM — the packet maths is `rate_ × bytesPerFrame_`
(`UsbSink.cpp:296-313`) and **needs no change at all**.

| | DSD clock | Frame rate | USB load | Status |
|---|---|---|---|---|
| DSD64 | 2.8224 MHz | 176.4 kHz | 1.41 MB/s | swept clean |
| DSD128 | 5.6448 MHz | 352.8 kHz | 2.82 MB/s | swept clean |
| DSD256 | 11.2896 MHz | 705.6 kHz | 5.64 MB/s | swept clean |
| DSD512 | 22.5792 MHz | 1.4112 MHz | 11.3 MB/s | past the DAC's 768 kHz ceiling — refused |

### What has to be written

| Piece | File | Lines |
|---|---|---|
| DSF container — header, 4096-byte per-channel blocks, LSB-first | `cpp/decode/DsdDecoder.cpp` (new) | 250 |
| DFF container — `FRM8` chunk walk, MSB-first, refuse DST | same | 200 |
| DoP packer, `SourceFormat::Dsd`, MIME matching | `cpp/decode/Decoder.{h,cpp}` | 120 |
| Dispatch branch | `cpp/StreamPlayer.cpp:389` | 15 |
| Advertise, gated on DAC rate ≥ 176400 | `upnp/SinkFormats.kt:32` | 30 |
| Keep off MediaCodec; `.dsf`/`.dff` in the picker | `HttpStreamPlayback.kt`, `MainActivity.kt:353` | 10 |
| Host tests — both containers, both bit orders, marker phase | `test/native/run.sh` | 200 |
| | **Total** | **~825** |

Three to five days including hardware verification. Bit-perfect survives honestly: DoP
alters no DSD bit, so `UsbSink::bitPerfect()` stays true as written.

## Native DSD: blocked by a principle, not by difficulty

The code is modest — relax `playable()` and `chooseAltSetting`, pack into `DSD_U32`, use
alt 3. Two days.

It cannot be driven from descriptors. DSD is specified in UAC3; UAC2's bit 31 means only
"Type I Raw Data", with **no defined DSD wire layout**. Linux's `snd-usb-audio` therefore
handles native DSD through a VID/PID quirks table — a long-standing complaint in its own
right. That collides directly with:

> **DACs generally.** Nothing in the codebase branches on vendor or product ID.
> — `README.md:82`

Supporting it means shipping a vendor table or guessing the wire format from one DAC
sample. **Refuse it, and write the refusal down** — that turns a gap into a position.

## DSD→PCM: decline for now

A multi-stage decimating FIR would make DSD play on every DAC, including the 48 kHz UAC1
dongles the README supports. ~350 lines plus coefficient design, and the filter choice is
audible and arguable. It is the one feature needing a careful public explanation of why it
counts as a decode rather than a compromise.

## Usefulness and user base

**For**

- The audience overlaps almost exactly — the owner is the audiophile who sets up the DAC,
  which is the demographic holding SACD rips and NativeDSD purchases.
- The promise is already shipping, with the word *yet* in it.
- Cheapest now: the 768 kHz-proven iso path exists and is warm.
- Advertising `audio/x-dsd` **stops servers transcoding** — MinimServer and Asset convert
  DSD to PCM unless the renderer claims it. The protocolInfo entry earns its keep alone.
- UAPP does all three tiers; absent DSD is a predictable one-star review in this niche.

**Against**

- The library is small and frozen. No streaming service delivers DSD; SACD is closed.
- DLNA is the weak link, not the DAC. BubbleUPnP was measured reading `GetProtocolInfo`
  six times and sending 192 kHz FLAC to a renderer that said 48 kHz only. DSD adds a
  format more controllers will mishandle, and the failure looks like ours.
- It serves one user class — the guest never touches DSD.
- It is not the biggest gap. AirPlay clock sync, source arbitration and seeking inside a
  server-converted stream affect everyone.

**Size, honestly.** Of people who would install a phone-as-UPnP-renderer *and* own a USB
DAC, perhaps 10–20% own any DSD files and fewer play them routinely. Small in absolute
terms, but over-represented among the people who write the reviews that decide whether an
app like this gets found.

## Decision

**Ship 1.0 without DSD.** The signed AAB is built and the listing reserved; the "does not
play DSD yet" string is honest in the meantime, and nothing gets harder for waiting.

**DoP lands as 1.1**, in this order:

1. Write `cpp/decode/DsdDecoder` — one class, both containers, following the `PcmDecoder`
   precedent that already multiplexes WAV/AIFF/L16/L24 behind one decoder. Sets
   `rate_ = dsdRate / 16`, `bits_ = 24`, emits DoP left-justified into `int32_t`.
2. Get the bit order right and **test** it rather than inspect it. DSF carries a bit-order
   flag, DFF is MSB-first; backwards yields full-scale noise, the exact hazard `Decoder.h`
   already warns about for endianness.
3. Refuse DST compression explicitly — declined with a reason, never decoded into noise.
4. Carry marker phase across seeks and gapless transitions. The `0x05`/`0xFA` alternation
   is stateful; resetting it mid-stream drops the DAC out of DSD mode.
5. Advertise conditionally — DSD MIMEs into `SinkFormats.NATIVE` **only** when the probed
   rates include ≥ 176400. Advertising DSD to a 48 kHz dongle stops the server transcoding
   and turns working playback into a refusal. Putting them in `NATIVE` also makes the
   existing PCM-only switch drop them for free.
6. Reuse the refusal path so "this DAC cannot play DSD128" is declined from metadata before
   a byte is fetched, as high-rate FLAC already is.
7. Replace "alt 3 is DSD and stays deferred" in the DAC notes with the principled answer.

## Verification

- **Host tests first** — extend `test/native/run.sh` (already builds `PcmDecoder` against
  the log shim) with DSF and DFF fixtures whose DoP output is known byte-for-byte,
  covering both bit orders and marker alternation across a block boundary. Cheap, and it
  catches the noise-versus-music failures.
- **Reject paths** — a DST-compressed DFF, and DSD128 against a 48 kHz capability JSON,
  must both refuse with a reason.
- **Flip the existing expectation** — `test/widget_test.dart:342` uses a `.dsf` file as
  the *refusal* fixture today.
- **On the Redmi + AL400** — play DSD64 and DSD128 from a controller; confirm from the
  status JSON that rate is 176400/352800, alt-setting is 2, packet errors 0; then confirm
  the DAC's own front panel reads DSD. That panel is the only independent evidence the
  markers were recognised.
- **Screencap the now-playing screen**, not only the status JSON.
- **Check `GetProtocolInfo`** with the DAC attached and detached, and the PCM-only switch
  both ways.
- **One soak at 176.4 kHz**, alongside the existing 96 kHz baseline.

**Note:** the ring buffer asks for two seconds and clips against its 8 MB ceiling
(`UsbSink.cpp:170`) at 705.6 kHz, giving ~1.4 s instead. Adequate — but log it rather than
let it surprise someone later.
