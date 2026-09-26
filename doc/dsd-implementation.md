# DSD: implementation plan (DoP)

[`dsd.md`](dsd.md) made the decision: **build DoP as 1.1, refuse native DSD on
principle, decline DSD→PCM.** This document is the "how" — the container
algorithms, the exact DoP byte layout, and a file-by-file change list checked
against the code as it stands, not as it stood when that memo was written.
Nothing here revisits the decision.

Out of scope, per the memo: **native DSD** (UAC2's format bit means only "Type
I Raw Data" — there is no defined DSD wire layout without a VID/PID quirks
table, which the project refuses on principle) and **DSD→PCM** (a decimating
FIR filter with an audible, arguable filter choice — declined for now).

## Container formats

Both DSF and DFF need parsing from nothing, so both get worked out here in
enough detail to write directly against. They share almost nothing structurally
despite both being "DSD in a file" — treat every assumption carried over from
the WAV/AIFF precedent as a thing to re-check, not a thing to reuse.

### DSF (Sony DSD Stream File)

- Magic `"DSD "` at offset 0 — **not** `"RIFF"`/`"FORM"`. The chunk-size fields
  throughout DSF are **8 bytes**, not 4 — this is the single detail most likely
  to be copy-pasted wrong from `PcmDecoder`'s WAV/AIFF chunk walk, so treat
  every `size` read in this container as 64-bit from the start.
- Top chunk (`"DSD "`, 28 bytes): total file size, and a pointer to an id3v2
  tag block to be ignored.
- `"fmt "` chunk (52 bytes) carries: format version, format ID (must be 0 =
  DSD raw), channel type, channel count, sampling frequency, **bit-order
  field** (1 = LSB-first, 8 = MSB-first), **sample count** (total DSD samples
  per channel), and block size per channel (always 4096 in practice).
- `"data"` chunk: audio is **block-interleaved**, not sample-interleaved —
  each channel's entire 4096-byte block comes before the next channel's block,
  cycling. A decoder pulling a continuous per-frame stream needs a small
  per-channel block buffer (`channels × 4096` bytes), refilled together each
  time every channel's buffer is exhausted at the same offset.
- The last block group is typically padded to 4096 bytes with `0x69`
  ("silence" pattern for DSD). Use the header's **sample count**, not the
  chunk's declared size, to know exactly where real audio ends — trusting the
  block padding would play a fraction of a second of noise-shaped silence as
  if it were program material, which is harmless-sounding but wrong.
- Bit order: if the fmt chunk says LSB-first, **bit-reverse every byte** before
  DoP packing (see below) — DoP's marker/data framing assumes the byte's bit 7
  is the earliest sample in time, which is DFF's native order and not
  necessarily DSF's.

### DFF (Philips DSDIFF)

- Magic `"FRM8"` at offset 0 (like AIFF's `"FORM"`), with form type `"DSD "`
  at offset 12. Chunk-size fields are **8-byte big-endian** throughout, same
  gotcha as DSF but for a different historical reason (SDDS/Philips vs. Sony).
- Walk chunks: `"FVER"` (skip), `"PROP"` containing `"SND "` sub-chunks
  including `"FS  "` (4-byte big-endian sample rate) and `"CHNL"` (channel
  count + channel ID tags), and `"CMPR"` (4-byte compression ID).
- **Refuse explicitly, with a reason, unless `CMPR` = `"DSD "`** (uncompressed).
  `"DST "` is DST-compressed and out of scope — decline it the way an
  unsupported AIFC encoding is already declined in `PcmDecoder`, not by
  attempting to decode it into noise.
- The `"DSD "` data chunk (distinct from the top-level form type of the same
  name) is **byte-interleaved per channel**: one byte per channel, round-robin
  — for stereo, `L0 R0 L1 R1 L2 R2 ...`, each byte holding 8 samples for that
  channel. No block deinterleaving needed, and always MSB-first — DFF has no
  bit-order flag because it only ever writes one order.
- Net effect: DFF's audio layout is *simpler* to decode than DSF's despite
  being the less common of the two formats in the wild.

### One decoder, two containers

Follow the precedent `PcmDecoder` already set for WAV vs. AIFF: sniff the
first 16 bytes for `"DSD "` (DSF) vs. `"FRM8"` + `"DSD "` at offset 12 (DFF),
branch into `readDsfHeader()` / `readDffHeader()`, and share one DoP-packing
`read()`. `DsdDecoder` is one class, matching `Decoder`'s interface exactly
like every other format here.

## DoP packing

- 16 DSD bits (2 bytes) per output frame per channel. Output frame rate = DSD
  rate ÷ 16:

  | DSD rate | Output (DoP) rate |
  |---|---|
  | DSD64 — 2.8224 MHz | 176.4 kHz |
  | DSD128 — 5.6448 MHz | 352.8 kHz |
  | DSD256 — 11.2896 MHz | 705.6 kHz |
  | DSD512 — 22.5792 MHz | 1.4112 MHz — refused; past the reference DAC's 768 kHz ceiling, the same way an over-rate FLAC already is |

- Frame layout, left-justified in the decoder's normal `int32_t` output (every
  decoder here shares this convention — see `Decoder.h`):

  ```
  bits 31-24   marker byte     0x05 / 0xFA, alternating every output frame
  bits 23-16   DSD byte n      8 samples, MSB first
  bits 15-8    DSD byte n+1    8 samples, MSB first
  bits 7-0     0x00            zero pad
  ```

  `bits_ = 24` (the marker + 2 data bytes are the significant 24 bits; the low
  byte is padding, exactly like a 16-bit source zero-padded into a wider slot
  elsewhere in this codebase).

- **Marker phase is decoder state, not per-call state.** The 0x05/0xFA
  alternation must continue unbroken across `read()` calls, across seeks, and
  across a gapless hand-off into the next DSD track — resetting it mid-stream
  drops the DAC out of DSD mode, per `dsd.md`. It does *not* need to survive a
  full sink reconfigure (a rate change stops DSD mode anyway).

- **Why no `UsbSink` change is needed**, worked out rather than assumed:
  `UsbSink` narrows a source to the DAC's subslot with
  `shiftDown = 32 - subslot*8`. For a 24-bit-in-4-byte alt-setting (the
  ordinary case — see `chooseAltSetting`'s narrowest-sufficient-container
  rule), `shiftDown = 0`, so the marker byte lands unchanged in the wire's top
  byte. The packet-rate math (`rate_ × bytesPerFrame_`) already governs
  ordinary 24-bit PCM at 176.4/352.8/705.6 kHz — rates the existing sweep has
  already proven clean on the reference AL400 — so DoP is, at the sink layer,
  indistinguishable from PCM it already handles.

- **Confidence caveat.** This byte layout is written from the DoP Open
  Standard 1.1 spec as recalled, not re-derived from a byte-verified reference
  capture. Before trusting host-test fixtures as ground truth, confirm the
  marker values and byte order against either the spec document or one real
  DoP-capable player's output — this is exactly the class of assumption the
  project's own rule ("test it rather than inspect it," `dsd.md`) exists to
  catch, because backwards bit order produces full-scale noise, not an
  obvious failure.

## File-by-file change list

Verified against `main` as of this writing (paths and line numbers below are
current, not carried over from `dsd.md`).

| File | Change |
|---|---|
| `cpp/decode/DsdDecoder.h` / `.cpp` (new) | DSF + DFF parsing, DoP packing — ~450 lines, modeled directly on `PcmDecoder.{h,cpp}` |
| `cpp/decode/Decoder.h` | Add `SourceFormat::Dsd` to the enum (`Decoder.h:38`) |
| `cpp/decode/Decoder.cpp` | `formatFromMime` (`Decoder.cpp:12`) matches `x-dsd`/`dsd`; `formatName` (`:30`) adds the case |
| `cpp/StreamPlayer.cpp` | `decodeLoop`'s format dispatch (~`:391-417`) gets a `SourceFormat::Dsd` branch alongside the existing `Pcm`/`Mp3`/`Flac` ones, constructing `DsdDecoder` the same way |
| `usb/UsbSink.cpp` | **No change.** Packet math and subslot narrowing already handle this shape — see reasoning above |
| `usb/UacCapabilities.cpp` | **No change.** `chooseAltSetting` (`:150`) continues to skip non-PCM alt-settings; DoP rides an ordinary PCM alt-setting, so the capability model is untouched |
| `upnp/SinkFormats.kt` | In `build()` (`SinkFormats.kt:58`), add `audio/x-dsd` conditionally — gated on `playableRates(caps).any { it >= 176400 }` — rather than adding it to the unconditional `NATIVE` list (`:32`). Reuses the existing `playableRates` helper (`:119`) |
| `usb/HttpStreamPlayback.kt` | **No change.** `usePlatformDecoder` (`:60`) is a deny-list; `audio/x-dsd` already falls through every `contains()` check to `false` today, keeping it off MediaCodec with no edit |
| `MainActivity.kt` | `mimeFromName` (`:360`) gets two new cases: `"dsf"` / `"dff"` → `"audio/x-dsd"`. The picker's `EXTRA_MIME_TYPES` (`:139`, already `["audio/*", "application/octet-stream"]`) needs no change — it's broad enough to surface `.dsf`/`.dff` already |
| `test/native/run.sh` | Add a build+run step for a new `dsd_decoder_test.cpp`, same shape as the existing `pcm_decoder_test` step |
| `test/native/dsd_decoder_test.cpp` (new) | Host tests — see below |
| `test/widget_test.dart:342` | Currently uses a `.dsf` / `audio/dsd` pick as an arbitrary *refusal* fixture, unrelated to any DSD-specific behavior. Once `.dsf` is accepted this test would start failing for the wrong reason — swap its fixture for a genuinely unsupported format so it keeps testing what it says it tests |
| `doc/dac-capabilities-al400.md:68` | Replace "alt 3 is DSD and stays deferred" with the principled answer: alt 3 (native DSD) stays refused; DSD plays via DoP over alt 1/2 (ordinary PCM) instead |

## Test plan

1. **Host tests first** (`test/native/`, no phone or DAC required) — extend
   with hand-built minimal DSF and DFF fixtures whose DoP output is known
   byte-for-byte:
   - Both bit orders (DSF LSB-first and MSB-first fmt flag).
   - Marker alternation carried correctly across a DSF 4096-byte block
     boundary — the one place internal buffering could silently reset phase.
   - A DST-compressed DFF (`CMPR` ≠ `"DSD "`) refuses with a stated reason,
     never decodes into noise.
   - A short/truncated file of each container fails cleanly, matching the
     existing decoders' behavior on truncated headers.
2. **`SinkFormats` gating** — a DAC capability JSON with only 44.1/48 kHz
   omits `audio/x-dsd`; one including 176400+ includes it. Cheap to write as a
   unit test since `playableRates` already has this shape of test coverage
   elsewhere.
3. **Reject paths** — DSD128 against a capability JSON capped below 176400 kHz
   refuses from metadata before a byte is fetched, reusing the same refusal
   path high-rate FLAC already uses (`Problem.kt`'s `forAnnouncedRate`/
   `isRealRate`, per the existing rate-negotiation logic).
4. **On the Redmi + AL400**:
   - Play DSD64 and DSD128 from a real controller; confirm from the status
     JSON that rate reads 176400/352800 and the alt-setting matches an
     ordinary 24-bit PCM alt (not alt 3).
   - Confirm on the DAC's own front panel that it reports DSD — this is the
     only independent evidence the markers were actually recognised; the
     app's own counters can't see past the USB packet layer.
   - Screencap the now-playing screen, not only the status JSON.
   - Check `GetProtocolInfo` with the DAC attached and detached, and the
     PCM-only ("accept only PCM streams") switch both ways.
   - One soak at 176.4 kHz, alongside the existing 96 kHz baseline soak.
5. Log the ring-buffer note rather than let it surprise someone: at 705.6 kHz
   the 8 MiB ring ceiling (`UsbSink.cpp:171`) gives ~1.4 s of buffer, not the
   nominal 2 s every other rate gets. Adequate, but worth a log line so it
   isn't mistaken for a bug later.

## Ordered implementation steps

1. `DsdDecoder` — both containers, following `PcmDecoder`'s precedent of one
   class multiplexing formats behind sniffed signatures. Get the DSF block
   deinterleave and DFF byte-interleave right first, against host tests, before
   touching anything hardware-facing.
2. `SourceFormat::Dsd` + MIME matching in `Decoder.{h,cpp}`.
3. Dispatch branch in `StreamPlayer.cpp`'s `decodeLoop`.
4. `.dsf`/`.dff` → `audio/x-dsd` in `MainActivity.kt`'s `mimeFromName`.
5. Conditional advertisement in `SinkFormats.kt`, gated on probed DAC rate.
6. Update `doc/dac-capabilities-al400.md`'s alt-3 note.
7. Host tests (can and should happen alongside step 1, not after).
8. Hardware verification per the checklist above.
