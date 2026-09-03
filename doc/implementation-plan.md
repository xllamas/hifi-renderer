# HiFi Renderer — Implementation Plan

## Context

`hifirend.md` specifies a dedicated DLNA/UPnP audio renderer that turns an unused phone into a
bit-perfect USB audio transport. The project directory is currently empty apart from that spec —
this is greenfield.

The problem being solved: consumer phones resample everything through the Android audio mixer, so a
phone cannot normally act as a hi-fi source. A true bit-perfect path to an external USB DAC needs to
bypass the Android audio stack entirely. Android 14 added a supported bit-perfect API
(`AudioMixerAttributes`), but the spec explicitly targets *pre-14* devices, which leaves exactly one
route: talk to the DAC over raw USB from native code.

The intended outcome is an appliance-like app: boots with the phone, always advertises itself on the
network as a MediaRenderer, plays whatever a DLNA controller sends it at native rate and depth, keeps
playing its queue after the controller disconnects, and shows a clean now-playing screen plus a 4×2
home-screen widget.

### Decisions taken during planning

| Decision | Choice | Reason |
|---|---|---|
| Platforms | **Android only** | iOS gives third-party apps no USB host access whatsoever; the headline feature is impossible there, and always-on background behaviour is heavily restricted. |
| No-DAC behaviour | **Fall back to Android audio**, clearly flagged as not bit-perfect | Makes the renderer, playlist, widget and UI fully testable without hardware attached. |
| v1 codecs | WAV/LPCM, FLAC, MP3, AAC | DSD/DoP explicitly deferred. |
| Target | **Any Android phone**, minSdk 26 (Android 8.0) | Nothing in the feature set requires more than Flutter's own floor of 24; 26 is chosen because notification channels, AAudio and consistent USB-host behaviour all line up there, avoiding split code paths for ~1–2% of devices whose OTG audio is unreliable anyway. |
| Reference hardware | Xiaomi Redmi Note 10 Pro + SMSL AL400 | **Test hardware, not the spec.** Everything must be driven by runtime capability detection, never by assumptions about this phone or this DAC. |
| UPnP stack | **Kotlin + jUPnP**, inside the foreground service | Renderer = UPnP *device* side; pub.dev packages are all control-point/client side. jUPnP is a maintained Cling fork already proven against real controllers. Flutter becomes the UI/config layer. |
| Background killers | Vendor Intent table + runtime self-diagnosis | Every major OEM kills background services differently, and only the Xiaomi can be tested directly. |

### Toolchain (verified present)

Flutter 3.41.5 / Dart 3.11.3 · Android SDK with NDK 28.2.13676358 and CMake 3.22.1 · Android Studio
JBR. System `java` is JDK 8, which **cannot** run modern AGP — Gradle must be pointed at the Studio
JBR via `org.gradle.java.home` in `android/gradle.properties`. No device attached at planning time.

Verified floors: `FlutterExtension.minSdkVersion = 24` in this Flutter install, and NDK 28's
`meta/platforms.json` reports `min: 21`. So minSdk 26 is comfortably above both.

**ABIs: `arm64-v8a` + `armeabi-v7a` are both mandatory**, not optional — targeting Android 8.0 means
32-bit-only devices are in scope, and they are exactly the "unused old phone" the app is for. Add
`x86_64` for emulator work on the fallback sink (the emulator cannot pass through USB audio, so it can
only ever exercise the Oboe path).

Note: `/Users/xavier/StudioProjects` is a symlink to `/Volumes/DevEnvironments/StudioProjects` —
same directory, not two copies. Work in the `/Volumes/...` path.

### Design rule: capability-driven, and honest about it

Two rules that override convenience everywhere in this codebase:

1. **Never branch on VID/PID.** Every decision — alt-setting choice, bit depth,
   sample rate, whether volume is offered at all — comes from what was parsed from
   the attached device at runtime. The reference DAC is one sample, not the spec.
2. **Degrade gracefully and say so.** When a DAC cannot do something, the app does
   the best available thing *and tells the user what it did and why*.

Rule 2 has a concrete, user-visible form: a **DAC capabilities screen** in the
configuration section, showing what the connected hardware actually supports —
measured from its own descriptors, not from its documentation.

This is not a developer diagnostic dressed up as a feature. The reference AL400's
documentation never mentions that the host cannot set its volume, and that gap cost
real hours of fruitless configuration before the probe revealed it. Manufacturer
documentation is routinely silent on exactly the properties that determine whether
the app can do what the user is asking of it. The app can measure them in
milliseconds, so it should, and it should say so in plain language.

The capability model is therefore **structured data** (`probeUsbAudioDevice()` emits
JSON), consumed by three layers with different needs: the audio engine picks an
alt-setting from it, the settings screen renders it as prose, and logcat gets a dump
for support. Facts live in the parser; wording lives in the UI.

### Consequence of targeting a device population

Two things stop being fixed facts and become runtime-detected variables:

- **The DAC.** The UAC capability table must be built by parsing whatever is attached — UAC1 and UAC2,
  any alt-setting set, with or without a Feature Unit volume control, adaptive or asynchronous
  endpoints. The AL400 is one sample, and the code must not encode anything specific to it.
- **The OEM.** Boot-start and background survival differ per vendor, and only Xiaomi/MIUI is directly
  testable. The app must therefore *detect and report* its own failures rather than assume its
  workarounds succeeded.

---

## Architecture

Four layers, from top to bottom:

```
Flutter / Dart  ── UI only: now-playing, settings, first-run onboarding
      │  MethodChannel (commands) + EventChannel (state stream)
Kotlin service  ── RendererService (foreground, always-on)
      │            ├─ jUPnP MediaRenderer device (SSDP/SOAP/GENA)
      │            ├─ Playlist / transport state machine
      │            ├─ MediaSession + 4×2 AppWidget updates
      │            ├─ OkHttp source fetch → JNI byte push
      │            └─ UsbManager: permission + device fd
      │  JNI
C++ engine      ── decoder threads → lock-free ring buffer → AudioSink
      │            AudioSink = UsbSink (libusb isochronous) | OboeSink (fallback)
      ▼
USB DAC
```

The Flutter engine may be destroyed at any time; **nothing** load-bearing lives in Dart. The service
owns all state and survives alone.

### Layer 1 — Flutter UI (`lib/`)

- `lib/main.dart` — app entry, routes.
- `lib/screens/now_playing.dart` — album art, title/artist/album, a format badge (`FLAC 24/192`), a
  bit-perfect/system-audio indicator, and a small settings button (per spec).
- `lib/screens/settings.dart` — renderer friendly name for v1; structured so USB/DLNA options slot in
  later.
- `lib/screens/onboarding.dart` — first-run permission flow (below).
- `lib/services/renderer_channel.dart` — the single `MethodChannel`/`EventChannel` wrapper. All UI
  state derives from the event stream; the UI holds no authoritative state of its own.
- State management: **Riverpod** (`flutter_riverpod`), one provider fed by the event stream.

Keep the screen policy in Kotlin, not Dart, so it works when the UI is backgrounded.

### Layer 2 — Kotlin service (`android/app/src/main/kotlin/.../`)

**`RendererService.kt`** — foreground service, `android:foregroundServiceType="mediaPlayback"`,
`START_STICKY`, persistent notification. Owns everything below. Started by the activity and by boot.

**`upnp/` — jUPnP MediaRenderer device.** Register a `MediaRenderer:1` device exposing three services:

- `AVTransport:1` — `SetAVTransportURI`, `SetNextAVTransportURI`, `Play`/`Pause`/`Stop`/`Seek`,
  `GetPositionInfo`, `GetTransportInfo`, `GetMediaInfo`, plus `LastChange` eventing.
- `RenderingControl:1` — `GetVolume`/`SetVolume`, `GetMute`/`SetMute`, `LastChange`.
- `ConnectionManager:1` — `GetProtocolInfo`. This is where supported formats are advertised to
  controllers; get the DLNA profile strings right (`http-get:*:audio/flac:*`,
  `audio/L16;rate=44100;channels=2`, `audio/mpeg`, `audio/mp4`) or controllers will refuse to send
  tracks.

Parse `CurrentURIMetaData` (DIDL-Lite XML) for title / artist / album / `albumArtURI`.

**Risk to spike first:** jUPnP's Android support module may be stale against modern AGP/Android.
Milestone 2 starts with a throwaway spike — if it doesn't come up cleanly on the device, fall back to
hand-rolling SSDP (`MulticastSocket` on 239.255.255.250:1900) + a small SOAP/GENA HTTP server. Decide
this before building anything on top of it.

**`playlist/PlaylistController.kt`** — the local queue that satisfies "keeps playing even if the DLNA
controller is no longer present". Controllers push tracks one at a time via `SetAVTransportURI` /
`SetNextAVTransportURI`; accumulate them into a persisted queue and advance autonomously on track end.

**`usb/UsbDeviceManager.kt`** — enumerate `UsbManager` devices, filter for audio class, request
permission, register `ACTION_USB_DEVICE_ATTACHED`/`DETACHED`, and hand
`UsbDeviceConnection.getFileDescriptor()` to native. Also add a `<usb-device>` intent filter with a
`device_filter.xml` so attaching the DAC can launch the app.

**`source/HttpSource.kt`** — OkHttp fetch of the media URL, pushed into the native ring buffer over
JNI with backpressure. Seek = HTTP `Range` request. Keeping HTTP in Kotlin avoids embedding a TLS/HTTP
stack in C.

**`power/PowerController.kt`**
- `PARTIAL_WAKE_LOCK` held while playing; `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`.
- Screen off after an inactivity timeout: drop `FLAG_KEEP_SCREEN_ON` and let the system sleep.
- Screen **on** at playback start: launch/resume the activity with `setShowWhenLocked(true)` +
  `setTurnScreenOn(true)` (the supported modern path, API 27+), falling back on API 26 to the
  deprecated `FLAG_SHOW_WHEN_LOCKED`/`FLAG_TURN_SCREEN_ON` window flags, and to an
  `ACQUIRE_CAUSES_WAKEUP` wake lock if neither takes effect.

This 26-vs-27 split is essentially the *only* compat branch minSdk 26 costs us. `NotificationChannel`
is required across the whole supported range so it needs no branch, and AAudio is present throughout —
which is precisely the argument for this floor over 24.

**`BootReceiver.kt`** — `RECEIVE_BOOT_COMPLETED` → start `RendererService`.

**`widget/RendererWidgetProvider.kt`** — 4×2 `AppWidgetProvider` driven by `RemoteViews`, updated
directly from the service (no Flutter round-trip, so it works when the UI is dead). **Gotcha:** album
art must be downscaled before it goes into `RemoteViews` or the binder transaction blows the ~1 MB
limit — decode with `inSampleSize` to widget size.

**`MediaSessionCompat`** — gives lockscreen/notification controls and routes hardware volume keys to
`RenderingControl`.

### Layer 3 — C++ audio engine (`android/app/src/main/cpp/`)

Built via CMake, linked as `libhifirend.so`. This layer exists for one reason:

> Android's `UsbDeviceConnection` exposes only control, bulk and interrupt transfers. USB Audio Class
> streaming is **isochronous**, which the Java API does not support at all. libusb reaches isochronous
> via usbfs `SUBMITURB` ioctls on the file descriptor. There is no Java-only path to this.

**`usb/UsbAudioDevice.cpp`** — libusb built for `arm64-v8a` + `armeabi-v7a`. Because Android apps
can't scan usbfs, initialise with `libusb_set_option(LIBUSB_OPTION_NO_DEVICE_DISCOVERY)` and adopt the
fd with `libusb_wrap_sys_device()`.

**`usb/UacDescriptorParser.cpp`** — walk the configuration descriptors to build a capability table:
AudioControl + AudioStreaming interfaces, every alt-setting's (format, bit depth, channel count,
supported sample rates), the isochronous OUT endpoint, any async feedback IN endpoint, and the Feature
Unit's Volume Control with its `GET_MIN`/`GET_MAX`/`GET_RES`. **UAC1 and UAC2 differ** and both must
be handled: UAC2 sets sample rate via a Clock Source entity, UAC1 via an endpoint control request.

This parser is the app's entire model of the outside world, so it must tolerate malformed and unusual
descriptors rather than trust them — unknown descriptor subtypes skipped by length, zero/absent
`bInterval`, vendor-specific interfaces interleaved with audio ones, and devices advertising rates
they cannot actually clock. Surface the parsed table in a diagnostics screen: it is the only way to
debug a user's DAC that we do not physically have. Expect a small quirks table keyed on VID/PID to
accumulate over time; keep it data, not branching logic.

**`usb/UsbSink.cpp`** — `SET_INTERFACE` to the alt-setting matching the track, set the sample rate,
then keep a pool of ~4–8 iso transfers × 8–16 packets continuously in flight from a dedicated
high-priority thread. For asynchronous endpoints, read the feedback endpoint and vary packet sizes to
track the DAC's clock — **skipping this produces periodic dropouts**, so it is not optional.

**`sink/OboeSink.cpp`** — the fallback. Define an `AudioSink` interface with `UsbSink` and `OboeSink`
implementations so the fallback is nearly free and the decoder path is identical.

**`decode/`** — single-header C libraries, dropped in with no build system of their own:
`dr_wav.h`, `dr_flac.h`, `minimp3.h`. **AAC routes through Android MediaCodec instead** — MediaCodec
is a decoder, not the mixer, so its raw PCM output fed straight to USB is still bit-perfect, and it
avoids fdk-aac's size and licensing awkwardness. That hybrid also gives a free path for any future
exotic format.

**`RingBuffer.h`** — lock-free SPSC ring between decoder and sink threads.

**Volume — a per-device capability, not a guarantee.** The spec already hedges this correctly: pass
volume changes to the DAC *"if accepted by the device"*. Implement as UAC Feature Unit `SET_CUR` on
Volume Control (a *control* transfer, so it never disturbs the iso stream), honouring the device's own
`GET_MIN`/`GET_MAX`/`GET_RES` rather than assuming a 0–100 range.

Plenty of DACs — integrated amps with a physical knob especially, likely including the AL400 — expose
no Feature Unit volume at all. Treat that as a **normal outcome, not an error**: report "hardware
volume only" in the UI, and have `RenderingControl.SetVolume` either no-op or, behind a config option
that is off by default, apply software attenuation with the bit-perfect indicator switched off. The
UPnP layer must still answer `GetVolume`/`SetVolume` sanely either way, because controllers will call
them regardless.

### Layer 4 — first-run onboarding

Spec requires asking for permissions on first run. The generic Android path is necessary but not
sufficient — most OEMs kill background services regardless — so the flow is:

1. `POST_NOTIFICATIONS` (Android 13+) — needed for the foreground service notification.
2. Battery optimisation exemption (`ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`).
3. **Vendor autostart**, via a `Build.MANUFACTURER` → `Intent` table covering the main offenders:
   Xiaomi (MIUI/HyperOS Security app), Samsung (Device Care sleeping-apps), Huawei (EMUI app launch),
   Oppo/Realme (ColorOS startup manager), Vivo (iManager background), OnePlus (OxygenOS battery
   optimisation). **Every one of these is an undocumented internal Intent that can vanish between OS
   versions**, so each must be `resolveActivity`-checked and fall back to the generic battery dialog
   plus written instructions — never crash on an untested device.
4. USB device permission — requested on attach rather than up front.
5. **Self-diagnosis.** The service records its own start reason and unexpected-death count in
   `SharedPreferences`; if it is being killed, the now-playing screen surfaces a warning linking back
   to the vendor step. Since the device matrix cannot be tested directly, the app has to be able to
   tell the user it is failing.

Keep the vendor table as **data** (a list of manufacturer/package/class triples), not branching logic,
so adding a vendor is a one-line change and the untestable surface stays small.

---

## Feature: DAC verification

Promoted from an M2 development harness to a shipped feature. The audience for
this app is hi-fi enthusiasts, who want evidence rather than assurance — and the
app is uniquely placed to provide it, because it already talks to the DAC
directly and knows what the hardware claims about itself.

It is the natural companion to the capabilities screen: that one reports what the
DAC **claims**, this one verifies what it actually **does**.

### Rate sweep (the core)

Walk every sample rate the DAC advertises. For each one:

1. Configure the stream and set the clock to that rate.
2. Confirm the device actually locks — the feedback endpoint must report the
   requested rate within a small tolerance. **A DAC advertising a rate it cannot
   clock is exactly the kind of undocumented gap this feature exists to expose**,
   and it is the same class of problem as the AL400's missing volume control.
3. Stream a generated signal for a few seconds.
4. Record underruns, per-packet errors, transfer errors and the measured rate.

Produce a per-rate pass/fail table. Include the alt-setting and container chosen
for each, so a user can see that (say) their 16-bit material travels in a 24-bit
slot and why that is still bit-perfect.

The report must be copyable as text: it is the single most useful thing a user on
hardware we do not own can send us.

### Sources

- **Generated signals** (default). No files, no permissions, no setup — and the
  only way to test rates the user owns no music for, such as the AL400's 705.6
  and 768 kHz. Generate tones at an exact submultiple of the sample rate so the
  loop point is phase-continuous and does not click.
- **The user's own file**, via a picker, for "does my actual library play
  cleanly". Restricted to whatever rates that material happens to contain.

### Stability soak

An optional extended run at one rate, surfacing the plan's 10-minute
zero-dropout requirement as a user-facing test. This is what catches slow drift,
thermal throttling and rare scheduler stalls, none of which a few seconds shows.

### Report honestly, including what it cannot see

The report covers the **digital** path only. During M2 a round of clearly audible
glitches turned out to be analogue interference from nearby power cables, with
every transport counter reading clean — the digital stream was perfect throughout.

So when a sweep passes and the user still hears problems, the report should say
so plainly: the data reached the DAC intact, and the fault is after conversion —
cabling, grounding, or the amplifier. That single sentence would have saved real
debugging time here, and it is exactly the kind of thing the app knows and the
user cannot easily determine.

---

## Status (2026-09-03)

Working end to end on the reference hardware: a DLNA controller discovers the
renderer, sends a track, and it plays bit-perfectly to the USB DAC.

| Milestone | State |
|---|---|
| M0 skeleton | ✅ |
| M1 USB capability probe | ✅ — second device still untested |
| M2 bit-perfect playback | ✅ — 30 min soak, zero dropouts |
| M3 DLNA renderer | ✅ — discovery, transport, DIDL, LastChange eventing |
| M4 full audio path | ✅ FLAC/WAV/MP3/AAC, seek, volume · ❌ gapless, Oboe fallback |
| M5 UI | ✅ now-playing, settings, DAC capabilities · ❌ first-run onboarding |
| M6 appliance | ✅ foreground service, boot start, wake locks, vendor autostart |
| M7 widget | ❌ not started |
| M8 DAC verification | ❌ specified, not built |

### Verified on hardware

- 30 minutes continuous at 96 kHz/24-bit: 14.8 M isochronous packets, zero
  errors, rate held to ±0.002%.
- FLAC, MP3 and AAC from a real controller (BubbleUPnP proxying Tidal), mixed
  playlists, auto-advance across a sample-rate change, pause/resume, seek.
- Survives `am kill`; starts at boot once MIUI autostart is granted.

### Known gaps

- **Only one DAC has ever been tested.** The parser, the alt-setting choice and
  the capability screen all make promises about hardware we do not own.
- **DAC volume is unverified.** The AL400 has no Feature Unit, so the UAC
  volume read/write path has never executed. Written from the spec only.
- **Gapless is absent.** There is a real gap between tracks; unavoidable across
  a rate change, but not within one.
- **No fallback without a DAC.** Playback simply fails; the plan calls for an
  Oboe path clearly marked as not bit-perfect.
- **USB permission prompts on every replug** on MIUI, which offers no "use by
  default" checkbox. Expected to behave better on stock Android — worth
  confirming before documenting compatibility.

### Next up

M7 (4×2 widget), gapless, the Oboe fallback, first-run onboarding, and M8.

---

## Milestones

Ordered so the riskiest unknown is resolved first, and so everything after M1 is testable without
touching hardware.

**M0 — Project skeleton.** `flutter create` with Kotlin, minSdk 26 / compileSdk latest, NDK/CMake
wired up, `org.gradle.java.home` pointed at the Studio JBR, `libusb` and Oboe vendored, empty
`libhifirend.so` building for `arm64-v8a`, `armeabi-v7a` and `x86_64`. *Done when:* the app installs on
the Redmi and the native lib loads on both a 64-bit device and a 32-bit ABI build.

**M1 — USB descriptor spike (highest risk, do first).** Enumerate the attached DAC, request
permission, pass the fd to native, parse and dump the full UAC capability table to logcat and to a
diagnostics screen. *Done when:* the parser reports UAC version, alt-settings/rates/depths, endpoint
sync type and Feature Unit volume presence — for the AL400 **and** for at least one other class-
compliant device (any UAC gadget, a USB headset, or a cheap dongle DAC) to prove it is not
single-device code.

**M2 — Bit-perfect playback of a local WAV. ✅ COMPLETE.** UsbSink, iso transfer pool, feedback endpoint handling,
`dr_wav`. No DLNA, no UI. *Done when:* a 44.1/16 and a 96/24 WAV play through the AL400 with no
dropouts for 10+ minutes and the DAC's own display reports the correct native rate — the real proof of
bit-perfect, since a resampled stream would show a fixed 48 kHz.

**M3 — DLNA renderer.** jUPnP spike, then the three services, DIDL-Lite parsing, foreground service.
*Done when:* BubbleUPnP (and one other controller) discovers "HiFi Renderer" and can play/pause/stop a
FLAC from a media server.

**M4 — Full audio path.** FLAC/MP3 native decoders, AAC via MediaCodec, OboeSink fallback with the
not-bit-perfect indicator, gapless-ish transitions, DAC volume via Feature Unit.

**M5 — UI.** Now-playing screen, settings (renderer name), onboarding incl. the vendor autostart table,
and the USB diagnostics screen from M1 (kept — it is the only remote-debugging tool for unknown DACs).

**M6 — Appliance behaviour.** Boot receiver, wake locks, screen on/off policy, local playlist
continuation after controller disconnect, MediaSession, service self-diagnosis counters.

**M7 — Widget.** 4×2 AppWidget with downscaled album art.

**M8 — DAC verification feature.** Rate sweep with pass/fail report, generated
signals plus file picker, optional stability soak, copyable report. Specified
above. The M2 harness (`lib/screens/playback_test_screen.dart`) is the starting
point — it already drives playback and surfaces stream health.

---

## Verification

**Bit-perfect (the claim that matters).** Three independent checks, because a resampled stream can
still sound fine:
1. The AL400's own rate indication must follow the source file's rate across 44.1 / 48 / 88.2 / 96 /
   176.4 / 192 kHz. A mixer-routed stream pins to one rate.
2. `adb shell dumpsys media.audio_flinger` must show **no** active output stream for our app during
   USB playback — if AudioFlinger sees us, we are not bypassing it.
3. Null test: play a known WAV, capture the DAC's analogue out (or a loopback if available), confirm
   bit-identical/near-null against the source.

**Dropouts.** 30-minute continuous playback with the screen off and the phone otherwise idle;
instrument the native engine to count underruns and log them.

> **PASSED 2026-09-03** at 96 kHz/24-bit: 30.9 min, 14,837,480 isochronous packets with zero
> errors, zero underruns, 1,851,342 feedback readings with none rejected, and rate held within
> ±0.002%. Full figures in `doc/dac-capabilities-al400.md`.
>
> Two lessons for future instrumentation. **Count per-packet status, not just transfer status** —
> an isochronous transfer reports COMPLETED while packets inside it fail, so transfer-level
> counters are blind to most real dropouts. And **never log from the libusb event thread**:
> `__android_log_print` can block for milliseconds and causes the very dropouts it is measuring.
> Still to do at 192 kHz, which is four times the bus bandwidth of this run.

**DLNA interop.** Test against at least two controllers with different quirks — BubbleUPnP (Android)
and one desktop controller (foobar2000 UPnP or JRiver). Verify discovery, transport controls, metadata
display, volume, and that `GetProtocolInfo` advertises formats the controller will actually send.

**Playlist continuation.** Queue several tracks, then force-stop the controller app / disable the
controller's Wi-Fi. Playback must continue through the remaining queue.

**Always-on.** `adb reboot`, wait, confirm the renderer reappears on the network without opening the
app. Then leave it 12+ hours idle and confirm it is still discoverable — the real vendor-killer test.

**Device-matrix honesty.** Only the Redmi + AL400 combination can be verified directly, so the rest of
the matrix is covered by *defensive behaviour* rather than testing: every vendor Intent
`resolveActivity`-checked, the descriptor parser fuzzed against malformed input, and both the parsed
UAC table and the service restart counters exposed in-app so a user on hardware we do not have can
report something actionable. Treat any claim of "works on all Android phones" as unproven until such
reports exist. Adding a second cheap class-compliant DAC (a ~£10 dongle) is the highest-value
verification purchase available, since it converts the parser from single-device to genuinely generic.

**Screen policy.** Confirm the screen sleeps after the inactivity timeout and wakes on playback start
triggered remotely from a controller.

**Fallback.** Unplug the DAC mid-session: playback should move to OboeSink and the UI must show the
not-bit-perfect state. Replug: it should return to USB.

**Widget.** Verify it updates with the UI process killed (`adb shell am kill <pkg>`), and that a large
album art JPEG doesn't trigger a `TransactionTooLargeException`.

---

## Principal risks

1. **Isochronous streaming stability** is the hard part of this whole project. Async feedback endpoint
   handling and URB queue depth tuning are where dropouts live. M1/M2 exist to hit this first.
2. **jUPnP's Android support may be stale.** Spike it before building on it; hand-rolled SSDP/SOAP is
   the fallback and the plan survives either way.
3. **OEM background killing — the biggest untestable risk.** Even with autostart granted, vendors kill
   long-idle services, and the workaround Intents are undocumented and version-fragile. If the 12-hour
   test fails, add a periodic self-heal (`AlarmManager` restart check). Accept that "always on" will be
   best-effort on hardware we cannot test.
4. **DAC diversity.** Real-world USB audio devices are far messier than the spec implies: adaptive vs
   asynchronous endpoints, UAC1 vs UAC2, phantom sample rates, devices needing a settling delay after
   `SET_INTERFACE`, and hubs/OTG cables that cannot supply enough current. The parser and the sink must
   degrade gracefully — refuse a track with a clear reason rather than emit noise.
5. **Volume may be unavailable** on a given DAC, making that spec bullet hardware-dependent by nature.
   The spec's own "if accepted by the device" wording already anticipates this; the software-attenuation
   option is the documented escape hatch.
6. **JDK 8 on PATH** will break the Gradle build until `org.gradle.java.home` is set. Trivial, but it
   will be the very first error hit.
