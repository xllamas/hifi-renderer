# HiFi Renderer

Turn a spare Android phone into a dedicated DLNA/UPnP audio renderer with
**bit-perfect USB output** to an external DAC.

Consumer phones resample everything through the Android audio mixer, so a phone
cannot normally act as a hi-fi source. This app bypasses the Android audio stack
entirely and streams to the DAC over raw USB, at the source file's native sample
rate and bit depth.

> **Status: early development.** The renderer is discoverable, plays FLAC, MP3
> and AAC bit-perfectly to a USB DAC, and supports transport control, playlists
> and seeking. Not yet done: gapless transitions, the no-DAC fallback, the
> home-screen widget and boot-start.

## How it works

Android's `UsbDeviceConnection` exposes only control, bulk and interrupt
transfers, but USB Audio Class streaming is **isochronous** — which the Java API
does not support at all. The only route is libusb over the usbfs file descriptor
from `getFileDescriptor()`, from native code. That is why this is a Flutter app
with a substantial C++ and Kotlin core rather than a pure Dart one.

```
Flutter / Dart  ── UI, configuration, DAC capability display
Kotlin service  ── UPnP MediaRenderer, playlist, USB permission, always-on lifecycle
C++ engine      ── decoders → ring buffer → USB isochronous sink (libusb)
                                          └ Oboe fallback (not bit-perfect)
USB DAC
```

## Formats

| Format | Decoder | Notes |
|---|---|---|
| FLAC | dr_flac (native) | The main case; lossless throughout |
| WAV / LPCM | dr_wav (native) | No decode step at all |
| MP3 | minimp3 (native) | Lossy source, but never resampled |
| AAC / M4A | Android MediaCodec | See below |
| Anything else the platform knows | Android MediaCodec | Opus, Vorbis, ALAC where supported |

AAC uses the platform decoder rather than a bundled one. That costs nothing in
fidelity: MediaCodec is a *decoder*, not the system mixer, so its PCM output
still reaches the DAC untouched at the source's own sample rate. Routing through
`AudioTrack` would resample; decoding does not.

## Compatibility

**USB Audio Class 2.0 only.** UAC 1.0 is a 1998-era specification capped at
24-bit/96 kHz over full-speed USB, and is effectively absent from the DACs anyone
would pair with a bit-perfect renderer. UAC1 devices are still detected and
identified, and the app says plainly that it cannot use them, rather than failing
obscurely.

**Android 8.0 (API 26) and above**, `arm64-v8a` and `armeabi-v7a`. USB host (OTG)
support is required.

**DACs generally.** Nothing in the codebase branches on vendor or product ID.
Every decision — alt-setting, bit depth, sample rate, whether volume can be
offered at all — is derived from descriptors parsed from the attached device at
runtime.

## The DAC capabilities screen

The app probes the connected DAC and reports, in plain language, what it can
actually do — measured from its USB descriptors rather than taken from its
documentation.

This exists because manufacturer documentation is routinely silent about the
properties that decide whether the app can do what is being asked of it. The
reference DAC used in development (an SMSL AL400) has **no host-controllable
volume at all** — a fact its manual never mentions, and which costs real time to
discover the hard way. The app measures it in milliseconds, so it does, and says
so:

> ⚠️ **Volume is controlled by the DAC, not this app**
> This device exposes no USB volume control. It does report its own knob or
> remote to the phone, but that is one-way: nothing sent from here can change its
> volume. Use the physical control.

## DAC verification

The companion to the capabilities screen: that one reports what the DAC claims,
this one verifies what it does. It sweeps every sample rate the device
advertises, confirms it genuinely locks to each, streams a test signal, and
reports underruns and per-packet errors — producing a pass/fail table you can
copy and share.

A DAC advertising a rate it cannot actually clock is precisely the sort of
undocumented gap this is for.

The report is explicit that it covers the digital path only. If a sweep passes
and something still sounds wrong, the data reached the DAC intact and the problem
lies after conversion — cabling, grounding, or the amplifier.

## Building

Requires Flutter 3.41+, the Android SDK with NDK 28.2 and CMake 3.22+, and a
**JDK 17 or newer** on Gradle's path.

```sh
flutter pub get
flutter build apk --debug
flutter test
```

If your system `java` is older than 17, point Gradle at a modern JDK via
`org.gradle.java.home` in `~/.gradle/gradle.properties` (machine-specific
settings belong there, not in the repository).

To build a genuinely single-ABI APK, use `--split-per-abi`. Note that
`--target-platform` only restricts `libflutter.so`; it does **not** propagate to
the CMake or prefab native libraries.

## Documentation

- [`doc/hifirend.md`](doc/hifirend.md) — the original objective and feature list
- [`doc/implementation-plan.md`](doc/implementation-plan.md) — architecture, milestones, verification
- [`doc/dac-capabilities-al400.md`](doc/dac-capabilities-al400.md) — measured capabilities of the reference DAC

## Third-party code

- [libusb](https://libusb.info) 1.0.28 (LGPL-2.1-or-later), vendored under
  `android/app/src/main/cpp/third_party/libusb`
- [Oboe](https://github.com/google/oboe) (Apache-2.0), via Gradle
