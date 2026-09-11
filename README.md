# HiFi Renderer

Turn a spare Android phone into a dedicated DLNA/UPnP audio renderer with
**bit-perfect USB output** to an external DAC.

Consumer phones resample everything through the Android audio mixer, so a phone
cannot normally act as a hi-fi source. This app bypasses the Android audio stack
entirely and streams to the DAC over raw USB, at the source file's native sample
rate and bit depth.

> **Status: working end to end on the reference hardware.** A DLNA or OpenHome
> controller discovers the renderer and it plays FLAC, MP3, AAC and raw PCM
> bit-perfectly to a USB DAC — with transport control, seeking, gapless
> transitions within a rate, per-DAC volume memory, boot start, a home-screen
> widget, first-run onboarding, an Oboe fallback when no DAC is attached, and
> an interface in nine languages. AirPlay is in as a guest path: it plays, and
> it says plainly that it is not bit-perfect. Not yet done: AirPlay clock sync
> and retransmission, source arbitration between the owner's playlist and a
> guest, and seeking inside a server-converted stream.

## How it works

Android's `UsbDeviceConnection` exposes only control, bulk and interrupt
transfers, but USB Audio Class streaming is **isochronous** — which the Java API
does not support at all. The only route is libusb over the usbfs file descriptor
from `getFileDescriptor()`, from native code. That is why this is a Flutter app
with a substantial C++ and Kotlin core rather than a pure Dart one.

```
Flutter / Dart  ── UI, configuration, DAC capability display, language choice
Kotlin service  ── UPnP MediaRenderer + OpenHome, playlist, AirPlay receiver,
                   USB permission, screen policy, always-on lifecycle
C++ engine      ── decoders → ring buffer → USB isochronous sink (libusb)
                                          └ Oboe fallback (not bit-perfect)
USB DAC
```

## Formats

| Format | Decoder | Notes |
|---|---|---|
| FLAC | dr_flac (native) | The main case; lossless throughout |
| WAV (local file) | dr_wav (native) | No decode step at all |
| L16 / L24 | PcmDecoder (native) | What a server transcodes to; big-endian per RFC 2586 |
| WAV / AIFF (streamed) | PcmDecoder (native) | Chunk list parsed, then the same raw samples |
| MP3 | minimp3 (native) | Lossy source, but never resampled |
| ALAC | Apple's reference decoder (native) | The AirPlay guest path; this phone offers no `audio/alac` at all |
| AAC / M4A | Android MediaCodec | See below |
| Anything else the platform knows | Android MediaCodec | Opus and Vorbis where the device supports them |

The three raw-PCM rows share one decoder, because past the header they are the
same thing. What differs is what must not be guessed: L16, L24 and AIFF are
big-endian, WAV and AIFC's `sowt` are little-endian, and 8-bit samples are
unsigned in WAV and signed everywhere else. Getting any of those backwards
produces full-scale noise rather than an obvious failure, so each combination
is covered by a test rather than by inspection: `test/native/run.sh` builds the
decoder on the host and checks every one of them.

L16 matters more than its obscurity suggests: it is what a media server
converts *to* when "let the server convert" is on, so without it that switch
withholds every format the renderer can decode and leaves only one it cannot.

AAC uses the platform decoder rather than a bundled one. That costs nothing in
fidelity: MediaCodec is a *decoder*, not the system mixer, so its PCM output
still reaches the DAC untouched at the source's own sample rate. Routing through
`AudioTrack` would resample; decoding does not.

## Compatibility

**USB Audio Class 1.0 and 2.0.** UAC1 was initially assumed dead and turned out
not to be: class-compliant UAC1 dongles are still sold and still work. They are
supported, with the limits the class itself imposes — full-speed USB caps the
bandwidth well below what a UAC2 DAC offers, and such devices are commonly
*adaptive*, taking their timing from the phone rather than running their own
clock. Playback is still bit-perfect at the rates they do support.

What decides whether a device is usable is not its class version but whether it
offers PCM out over an isochronous endpoint. A USB microphone, or the capture
half of a headset adapter, does not — and the app says so plainly rather than
failing obscurely.

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

## When the DAC cannot play a track

The renderer reports what the attached DAC can actually do, and refuses
anything outside it with a reason. It never resamples to make a track fit —
that would defeat the point of the app — and it does not pretend a limitation
away.

`protocolInfo`, the list of formats a renderer advertises, carries the DAC's
real sample rates for LPCM. It cannot do the same for FLAC: the DLNA profiles
for compressed and lossless containers have no rate constraint, so there is no
way to advertise "FLAC, but only up to 48 kHz". The renderer therefore
advertises the formats it can decode — which is true, it can decode them — and
enforces the rate ceiling by refusing tracks above it.

A refusal is immediate and cheap. Servers state the sample rate in the metadata
they send, so a track the DAC cannot clock is declined before any of it is
fetched, and the now-playing screen says why:

> ⚠️ This DAC cannot play 192 kHz; its highest rate is 48 kHz.

The advertised list follows the attached DAC, and changing the output device
re-announces the renderer on SSDP as well as firing the evented
`SinkProtocolInfo`, since controllers otherwise keep whatever they read at
discovery.

**Whether a controller respects any of this is up to the controller.** Measured
against BubbleUPnP with a Tidal source: it requested `GetProtocolInfo` six times
in one session, was told the renderer accepted only LPCM at 44.1 and 48 kHz, and
sent 192 kHz FLAC regardless — with a direct link rather than through its own
proxy, so it was not in the stream path and could not have converted anything.
It read the truth and sent the file anyway. There is a setting to withhold the
container formats entirely, which is what would make a *transcoding* server
convert instead; it is off by default, because it costs bit-perfect playback of
every file the DAC could have played untouched, and it does not change the
behaviour of a controller that does not consult the list.

## Controllers, and who owns the playlist

The renderer answers **UPnP AV/DLNA** and **OpenHome** at the same time, from
one device description. A controller uses whichever it knows.

AVTransport takes one track at a time, so with a DLNA controller the queue
lives in the controller: close the app and the music stops at the end of the
current track. OpenHome moves the playlist onto the renderer — the controller
fills it once and is then free to leave the network, and advancing, repeat and
shuffle all happen here with nothing else involved. That is what makes this an
appliance rather than a speaker driven by a phone, and it is the last gap
between the app and its original objective.

## AirPlay: the guest path

A house has guests, and a guest will not learn what DLNA is. AirPlay is the
guest path: it appears in Control Centre beside real AirPlay devices, and a
visitor sends audio to it without installing or configuring anything. The
alternatives were assessed and closed — Bluetooth by measurement, Chromecast by
Google — and the reasoning is in
[`doc/protocols-beyond-dlna.md`](doc/protocols-beyond-dlna.md).

It is written directly against Android's NSD and the engine's push-PCM entry
point rather than ported from `shairport-sync`: mDNS, the RTSP handshake, RSA
and AES, RTP and ALAC. Only Apple's reference ALAC decoder is vendored, because
this phone's MediaCodec offers no `audio/alac` at all.

**It is lossless, and it is not bit-perfect, and the app says so.** ALAC over
RAOP is 44.1 kHz / 16-bit, whatever the sender started from — so anything else
was resampled before it arrived, and nothing downstream can undo that. The
now-playing screen reads `ALAC 16/44.1` beside an amber *AirPlay — sender
resampled*, where a local FLAC on the same DAC reads `FLAC 16/44.1` beside the
green tick. Bit-perfectness is composed by the one layer that sees both the
sink and where the samples came from; a sink cannot answer it about a stream it
did not originate.

**The RAOP key is not in this repository.** A receiver has to prove it is an
AirPort Express, using the private key recovered from that hardware years ago;
its licence position is unclear and key material does not belong in source
control. The build supplies it at
`android/app/src/main/assets/airplay/raop_key.pkcs8`. Without it everything
still compiles, advertises and answers RTSP — it declines the challenge, which
is the honest behaviour for a receiver that cannot prove what it claims. See
[`doc/airplay.md`](doc/airplay.md) for the conversion command and for what is
measured.

## The home-screen widget

A 4×2 widget carrying the same information as the now-playing screen: album art,
title, artist and album, elapsed and total time, and the format badge with the
bit-perfect mark. Tapping it opens the app; the play/pause button drives the same
transport the network controllers use, and starts the renderer if it is not
running.

It is drawn by the service rather than by Flutter, and updated as the state
changes rather than on the system's widget alarm — which has a 30-minute floor
and would be useless for a now-playing display. On a phone dedicated to this job
the UI process spends most of its life destroyed, so a widget that depended on it
would go stale exactly when it is the only thing on screen.

## Languages

The interface exists in nine: English, Spanish, Portuguese, French, German,
Italian, Japanese, Korean and Chinese — ten translations, European and
Brazilian Portuguese being separate ones.

The default is the phone's own language, which is the right default for this
appliance rather than a shortcut — the renderer is a box on a shelf, and the
phone reading it may not be the phone that set it up. A guest who picks it up
should find their own language with nobody having configured anything. The
override in settings exists for the opposite case, just as real: a renderer set
up on a spare phone inherits whatever language that phone happens to be in, and
changing the whole phone to fix one app is a poor trade.

The choice is stored on the Android side, because the service outlives the UI:
the widget and the notification are drawn with no Flutter engine running and
cannot ask Dart what language it settled on. For the same reason the engine
sends the screen a **failure code**, never an English sentence — the wording
lives once, in `lib/l10n/app_en.arb`, and the diagnostic detail stays as the
engine wrote it, because that ends up in bug reports.

## Staying up

A renderer nobody can see is broken however well it decodes.

The app watches its own SSDP traffic and rejoins the multicast group when it
stops hearing any — a membership can lapse above the app, in the Wi-Fi driver
or the access point's IGMP snooping, and every counter inside the process keeps
looking healthy while the renderer is invisible. Silence is judged against how
busy the network has actually been, so a genuinely quiet one is not condemned
on the same clock as one running better than an announcement a second. Measured
overnight: eight lapses in fourteen hours, cut from several minutes of
invisibility each to about ninety seconds.

The panel blanks after a few minutes of inactivity and wakes when playback
starts, which is what makes it feel like an appliance rather than a phone left
on a shelf. That is display policy only — the CPU is held awake separately,
because a suspended process cannot meet isochronous deadlines.

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

**Run a release build on a device before shipping it.** Almost everything this
app does across a boundary is resolved by name at runtime — JNI links C symbols
to Kotlin method names, and jUPnP builds its service descriptions by reflecting
over the OpenHome annotations — and none of it looks used to R8.
`proguard-rules.pro` keeps what must not be renamed, and the failure mode if
something is missed is not a broken build: it builds, installs, and then the
renderer is invisible to controllers or dies with `UnsatisfiedLinkError` the
first time a track plays.

## Documentation

- [`doc/hifirend.md`](doc/hifirend.md) — the original objective and feature list
- [`doc/implementation-plan.md`](doc/implementation-plan.md) — architecture, milestones, verification
- [`doc/dac-capabilities-al400.md`](doc/dac-capabilities-al400.md) — measured capabilities of the reference DAC
- [`doc/protocols-beyond-dlna.md`](doc/protocols-beyond-dlna.md) — the guest-path question, and why Bluetooth and Chromecast are closed
- [`doc/airplay.md`](doc/airplay.md) — the AirPlay receiver: what is measured, what is missing, and the key

## Third-party code

- [libusb](https://libusb.info) 1.0.28 (LGPL-2.1-or-later), vendored under
  `android/app/src/main/cpp/third_party/libusb`
- [Apple ALAC](https://github.com/macosforge/alac) (Apache-2.0), vendored under
  `android/app/src/main/cpp/third_party/alac`
- [dr_libs](https://github.com/mackron/dr_libs) `dr_flac` and `dr_wav`
  (public domain / MIT-0), and [minimp3](https://github.com/lieff/minimp3)
  (CC0), vendored under `android/app/src/main/cpp/third_party`
- [Oboe](https://github.com/google/oboe) (Apache-2.0), via Gradle
- [jUPnP](https://github.com/jupnp/jupnp) 3.0.3 (CDDL-1.0), via Gradle

## Licence

Apache License 2.0 — see [LICENSE](LICENSE). Third-party attributions are
collected in [NOTICE](NOTICE).

The strictest licence in the tree is libusb's LGPL-2.1, which reaches the native
library it is linked into but not this project's own code. Publishing the
complete source here is what satisfies its relinking clause.
