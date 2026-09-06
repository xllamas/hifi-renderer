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

Three rules that override convenience everywhere in this codebase:

1. **Never branch on VID/PID.** Every decision — alt-setting choice, bit depth,
   sample rate, whether volume is offered at all — comes from what was parsed from
   the attached device at runtime. The reference DAC is one sample, not the spec.
2. **Degrade gracefully and say so.** When a DAC cannot do something, the app does
   the best available thing *and tells the user what it did and why*.
3. **The deliverable is the app, not results about this hardware.** The gear
   here — one Redmi, two DACs — is three samples of a population this app will
   mostly never see, and it is here to exercise the tool, not to be certified
   by it. A feature is finished when the app can *perform* its test; whether a
   particular DAC passes is a question for whoever owns that DAC, answered
   later with the finished app. So no milestone depends on how a device
   behaved, and no hardware measurement is ever outstanding project work.

   The corollary is how to read a result. When a verification test fails on a
   DAC, that is the feature working — it found something the descriptors did
   not admit to, which is the entire reason the feature exists. A green run
   proves the code path executes; it is close to no evidence about hardware in
   general. Report both that way round.

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
  endpoints. The AL400 is one sample, and the code must not encode anything specific to it. Nor
  should any *conclusion*: "it works" means it works on the two DACs in this room, and saying more
  than that is the same error as branching on VID/PID, committed in prose instead of code.
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

**Built 2026-09-05** (`lib/screens/onboarding_screen.dart`,
`android/.../Onboarding.kt`). Every step is offered, checked live, and
skippable; Finish is always available, because a step that is impossible on
hardware nobody here owns must not trap the user in setup. Three states, not
two: granted, not granted, and **cannot be checked** — the vendor screens
report nothing back, so that step never ticks rather than claiming a result the
app did not earn. A phone with no known Intent gets written instructions
instead of a button that would do nothing.

Building it found that `POST_NOTIFICATIONS` was declared in the manifest and
never requested. On Android 13+ that silently costs the foreground-service
notification, which is the renderer's only visible sign of life. Notification
state is now read from the notification manager rather than the permission,
because a user who granted it and later switched notifications off is in the
same position as one who never granted it.

Step 5's self-diagnosis lives in settings, above the permissions that fix it,
because it is the reason someone opens that section. It is also the only
manufacturer-independent signal the app has: the vendor step is inferred from
`Build.MANUFACTURER` being in a table, while this is the service observing that
it was actually killed — which is what makes it the part that works on phones
nobody here owns.

The vendor step is worded as the inference it is. The app cannot detect a
background-app restriction; there is no API for it. It knows the make of the
phone and whether a known Intent resolves, so it says phones from this maker
*usually* add such restrictions, and says outright that it cannot detect them.
Claiming otherwise would be design rule 2 broken in the copy.

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
  Built through the streaming engine so every decoder is available, not just
  WAV.

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

## Status (2026-09-05)

Working end to end on the reference hardware: a DLNA controller discovers the
renderer, sends a track, and it plays bit-perfectly to the USB DAC.

| Milestone | State |
|---|---|
| M0 skeleton | ✅ |
| M1 USB capability probe | ✅ — verified against a second, UAC1 device |
| M2 bit-perfect playback | ✅ — 30 min soak, zero dropouts |
| M3 DLNA renderer | ✅ — discovery, transport, DIDL, LastChange eventing |
| M4 full audio path | ✅ FLAC/MP3/AAC, L16/L24, WAV, AIFF, seek, volume, gapless, Oboe fallback |
| M5 UI | ✅ now-playing, settings, DAC capabilities, first-run onboarding |
| M6 appliance | ✅ foreground service, boot start, wake locks, vendor autostart |
| M7 widget | ✅ 4x2, art, transport, pushed from the service |
| Device icon | ✅ launcher + DLNA iconList (PNG/JPEG, 48 and 120) |
| M8 DAC verification | ✅ rate sweep, stability soak, file source, verdicts and reports |

### Exercised on hardware

Not certifications of these devices — see design rule 3. Each entry is
evidence that a code path runs against real hardware, recorded with the sample
it ran on.

- 30 minutes continuous at 96 kHz/24-bit: 14.8 M isochronous packets, zero
  errors, rate held to ±0.002%.
- FLAC, MP3 and AAC from a real controller (BubbleUPnP proxying Tidal), mixed
  playlists, auto-advance across a sample-rate change, pause/resume, seek.
- Survives `am kill`; starts at boot once MIUI autostart is granted.
- **L16 from a transcoding server plays** on the UAC1 device: BubbleUPnP Server
  converting FLAC to `audio/L16;rate=44100;channels=2` over
  `/ffmpegpcmdecode/stream/`, with "accept only PCM" on.
- **The rate sweep passes all ten AL400 rates**, 44.1 kHz to 768 kHz, at
  32-bit — every one clean and clock-confirmed:

  | Rate | Measured | Underruns | Packet errors |
  |---|---|---|---|
  | 44.1 kHz | 44,099.6 Hz | 0 | 0 / 32,080 |
  | 48 kHz | 48,000.0 Hz | 0 | 0 / 32,072 |
  | 88.2 kHz | 88,199.2 Hz | 0 | 0 / 32,088 |
  | 96 kHz | 95,999.0 Hz | 0 | 0 / 32,136 |
  | 176.4 kHz | 176,399.4 Hz | 0 | 0 / 32,160 |
  | 192 kHz | 191,999.0 Hz | 0 | 0 / 32,152 |
  | 352.8 kHz | 352,797.9 Hz | 0 | 0 / 32,152 |
  | 384 kHz | 383,996.1 Hz | 0 | 0 / 32,072 |
  | 705.6 kHz | 705,594.7 Hz | 0 | 0 / 32,080 |
  | 768 kHz | 767,992.2 Hz | 0 | 0 / 32,088 |

  Worst deviation 0.001%, alt 1 (32-bit in a 4-byte slot) throughout, feedback
  accepted with none rejected. **This closes the M2 note that 192 kHz was still
  untested** — and goes four times past it. 768 kHz stereo at 32 bits is
  6.1 MB/s over the bus, sixteen times the bandwidth of the 96/24 soak, held
  for four seconds with nothing dropped.

  Read the right way round, this is the *least* informative outcome the sweep
  can produce (design rule 3): it says this AL400 is well behaved and nothing
  about anyone else's hardware. The sweep has not yet been run on the UAC1
  dongle, where every verdict would be `unverified` for want of a feedback
  endpoint.
- **First-run setup shown on a genuine first run**, 2026-09-05, with live
  state correct: notifications unticked and offering Allow, the battery
  exemption already ticked from an earlier grant, and the vendor step naming
  Xiaomi from `Build.MANUFACTURER`.
- **Ten-minute soak passed at 96 kHz/32-bit**, 2026-09-05: 10m 03s, 58,091,844
  frames, 4,817,304 isochronous packets with none bad, zero underruns, zero
  transfer errors, and 586,171 feedback readings with none rejected. The clock
  held 95,999.0 Hz for effectively the whole run and read 96,000.0 Hz at the
  end — a spread of 1 Hz, 0.001%, which is arguably the feedback quantum
  rather than the clock moving. Ring fill never fell below 99%, so the feeder
  was never close to falling behind.

  This clears the project's ten-minute zero-dropout bar, and at 32-bit rather
  than the 24-bit of the original M2 soak. What it demonstrates for the project
  is that the soak works: it holds a rate, samples it, and reports honestly for
  ten minutes without losing the stream. Whether this AL400 would also survive
  ten minutes at 768 kHz is a question about that DAC, and the app is now the
  thing that answers it.

### Known gaps

- **Two DACs have now been tested** — the UAC2 AL400 and a UAC1 dongle. The
  second one immediately found three real faults (see below), so the parser and
  alt-setting choice are better evidenced than they were; they still make
  promises about hardware we do not own.
- **DAC volume now executes**, on the UAC1 device's Feature Unit. The AL400 has
  none, so this path had never run: it used the UAC2 request codes throughout,
  and UAC1 puts the direction in the code itself (GET_MIN is 0x82, not 0x02),
  so every read asked the device to SET what it meant to GET. Written from the
  spec, and wrong — exactly the risk this section existed to record.
- **Volume is remembered per DAC and never starts at full scale.** An unknown
  device starts at 10. The previous behaviour was to inherit whatever the
  hardware held, which on a device with unreadable volume is its maximum — a
  first track at full scale into an amplifier, before anyone can reach a
  control.
- **Gapless works within a rate.** The next track is started when the decoder
  runs out of source rather than when the ring empties, and is decoded into the
  same running stream. Measured on the AL400: hand-over in 22 ms against 3.8 s
  of tail still buffered, with the frame counter continuous and no underrun.
  Across a rate change the stream is still rebuilt, which is unavoidable.
- **Falling back without a DAC now works.** Playback moves to Oboe and the UI
  marks it as not bit-perfect, which closes the gap this list used to record.
- **USB permission prompts on every replug** on MIUI, which offers no "use by
  default" checkbox. Expected to behave better on stock Android — worth
  confirming before documenting compatibility.
- **AIFF is implemented but has never met a real file.** The container parser
  and both its byte orders are covered by host tests; no actual AIFF has been
  played. AIFC's `sowt` is the variant most worth distrusting, because it is
  little-endian inside a big-endian container.
- **Seeking a server-converted stream fails.** `ensureHeader` looks for a FLAC
  header and refuses without one, which also means MP3 has never been
  seekable. For raw L16 the byte offset is exactly computable, so this is
  cheap to fix and simply has not been.
- **`bitPerfect` reports true on a transcoded stream.** Honest by the field's
  own definition — nothing alters samples after the decoder — but the server
  may well have resampled upstream, and the badge does not distinguish the two.
- **The sweep cannot confirm the clock on an adaptive DAC.** Not a defect in
  the sweep; there is nothing to read. It is called out because a screen full
  of green ticks would otherwise be read as proof it cannot give.
- **No JVM test source set.** `SinkFormats`, `Problem` and the transport are
  untested except through the app. The Dart and native sides both have
  harnesses now; Kotlin is the gap.

### What the second DAC taught us

Worth recording, because all three were invisible with one device attached:

- **A failure after Play had been answered reached nobody.** The engine
  configures on the decoder thread, once the source's real rate and depth are
  known — after SetAVTransportURI and Play have both returned. A failure there
  left the transport PLAYING, the screen and widget showing a running track,
  and silence as the only symptom.
- **libusb collapses most ioctl failures into LIBUSB_ERROR_OTHER**, keeping the
  errno in an internal log that goes nowhere on Android. Routing it into logcat
  is what turned "set_alt_setting failed" into "the device stalled it with
  EPIPE".
- **Hardware lies in ways that survive a naive check.** The UAC1 device accepts
  SET_CUR and audibly changes volume, then answers GET_CUR with junk —
  alternating between 0 dB and a value outside the range it declared itself.
  Two checks were written and both passed while the bug was live: one probed a
  single time, and this firmware echoes correctly on the read immediately
  after a write; the next compared a single write against its readback, and
  passed at 99% because a fixed 0 dB answer sits within one step of the -1 dB
  written. Proof now needs two clearly different values, and until a device has
  given it the app's own last written value is authoritative.
- **State that describes the device must outlive the stream.** The sink is
  rebuilt for every track, and it was carrying what had been learned about the
  DAC. Every track boundary reset it, so the fix looked correct inside a single
  track and failed in ordinary use. Any test of a device-level fact has to
  cross a track change.
- **Firmware can wedge.** The UAC1 device stopped answering *any* control
  transfer — including string descriptors — and stayed that way across app
  restarts until it was replugged. The control experiment that established it
  was device-specific rather than environmental: the other DAC on the same hub
  answered normally throughout, which is only visible because the capability
  dump covers every attached device rather than just the selected one.

### What the converting server taught us

The "let the server convert" switch had never been turned on with a server
that took it up. When it was, it failed every time — and the reason was on
our side.

- **We advertised a format we could not decode.** The switch withholds every
  container format the app decodes so the server transcodes instead, and what
  BubbleUPnP Server transcodes to is L16. `formatFromMime` already classified
  L16 as PCM, but the decode loop only ever constructed an MP3 or FLAC
  decoder, so it fell into the branch that tries FLAC and gives up. The one
  setting whose entire purpose is "make everything playable" was the one
  setting that guaranteed nothing would play.
- **The same hole was open in two more places, unnoticed.** Streamed WAV was
  advertised and equally undecodable — dr_wav only ever ran in the local file
  player. AIFF was advertised and decodable by nothing at all: not the stream
  path, not the file player, not MediaCodec. Nobody had hit either, because
  nobody had sent them.
- **An advertisement is a promise, and nothing was checking it.** Every one of
  these was a line in a list of MIME types that no code path could honour. The
  advertisement is now logged entry by entry rather than counted, because when
  it is wrong the symptom surfaces somewhere else entirely — as a track that
  will not play, or one converted when it needed no converting.
- **Byte order is the failure that does not announce itself.** L16, L24 and
  AIFF are big-endian; WAV and AIFC's `sowt` are little-endian; 8-bit is
  unsigned in WAV and signed in AIFF. Read any of them the wrong way round and
  the decoder produces full-scale noise rather than an error. That is not
  something to discover through a pair of speakers, so all of it is covered by
  host tests (`test/native/run.sh`) that need neither a phone nor a DAC.
- **The engine's own words are not a user interface.** A refusal reached the
  now-playing screen as `unsupported or unrecognised audio format
  (audio/L16;rate=44100;channels=2)`, in twelve-point grey, on a screen whose
  stated job is being read from across a room. Both audiences are real, so the
  screen now carries a plain sentence at a size that survives the distance and
  keeps the engine's wording beneath it.

### What building the sweep taught us

- **A failed rate would have been the better result.** All ten AL400 rates came
  back clean, which is the least informative outcome available: it says this
  DAC is fine and nothing about the population. The sweep earns its keep the first time it tells a stranger their
  DAC advertises a rate it cannot clock — so a red row is the feature working,
  and the screen and report should never be tuned to make red rarer.
- **Two verdicts were not enough.** Pass and fail assume something measured the
  clock. The UAC1 device has no feedback endpoint and reports its rate to
  nobody, so a clean sweep there proves the digital path was faultless and
  proves nothing whatever about the clock. Calling that a pass would be the app
  asserting what it cannot see, which is the failure mode this whole document
  keeps warning about — so it is its own verdict, `unverified`, said plainly
  rather than footnoted.
- **Start-up noise is not device noise.** An isochronous stream that is still
  filling reports glitches that say nothing about the hardware. Measurement
  begins after a settle and counts only what accrues from there; folding the
  two together would fail every device for the cost of starting up.
- **A test signal has to loop in phase.** The sweep needs rates no music exists
  at, so the tone is generated — and a tone whose period does not divide the
  rate clicks once per loop. A click is indistinguishable from the dropout the
  sweep exists to detect, so getting it wrong would not look untidy, it would
  make the test lie. The period is chosen first, as a whole number of frames,
  and the frequency derived from it.

### Format negotiation, as measured

The renderer advertises the attached DAC's real capabilities and refuses what
falls outside them. What a controller does with that is the controller's
choice, and at least one common one ignores it.

BubbleUPnP, playing from Tidal, called `GetProtocolInfo` six times in a single
session, was answered each time with LPCM at 44.1/48 kHz and no FLAC, and sent
192 kHz FLAC anyway. Its URI carried `proxy=false` — a direct link, so it was
never in the stream path and could not have transcoded whatever it had been
told. Restarting the controller between attempts ruled out caching; the
`GetProtocolInfo` logging ruled out it never having asked.

The conclusion is that automatic rate negotiation cannot be relied on, so the
renderer's own refusal is the mechanism that matters: declined from the
metadata before any bytes are fetched, with the reason on screen. Fetching
first was costing megabytes of a stream that could not play, repeated on every
controller retry, over a metered connection.

There is now a second mechanism, and unlike negotiation it works. With "accept
only PCM streams" on, the renderer advertises nothing but LPCM at the rates the
DAC can clock, and a **server** — as opposed to a controller — does convert to
fit what it was told. The rate ceiling then stops being something a track can
violate, because every track is converted to a rate inside it before it is ever
sent. Measured on the UAC1 device: six entries offered, L16 and L24 at 44.1 and
48 kHz, and BubbleUPnP Server duly sent L16 at 44.1.

That only holds while the advertisement is exactly and only what the DAC can
clock. A stray container format would be sent as-is and might exceed the
ceiling. A stray rate would be worse: the server would transcode *to* something
unplayable, having spent its effort producing a stream that cannot play, and
the failure would look like ours.

The two modes are a real trade and the switch now says so rather than naming
only its consequence. Off, files arrive untouched and impossible ones are
refused. On, everything plays and nothing is bit-perfect — including tracks the
DAC could have played untouched.

### Next up

Every milestone in this plan is built, and M9 (OpenHome) closed the last gap
between the app and `doc/hifirend.md`: local playlists that survive the
controller leaving are now a thing the renderer owns rather than something
approximated from what a controller happened to announce.

What is left is not a feature list: it is use. The app exists to be pointed at
hardware nobody here owns, and the reports it produces are the only thing that
can turn "works on two DACs in one room" into evidence.

The open question beyond that is a second way in, assessed in
`doc/protocols-beyond-dlna.md`. The short of it: this is an appliance in a
home, and a home has guests who will not learn what DLNA is. That is a
different product from the owner's, sharing one box — and the guest path does
not compete with the bit-perfect claim, it protects it. **Bluetooth is closed**
— spiked and refused on facts, twice over. AirPlay is the buildable guest path,
and the first thing it owes is the appliance-shell extraction that OpenHome was
able to skip.

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
above. The M2 harness (`lib/screens/playback_test_screen.dart`) was the starting
point and is still reachable from the new screen.

*Built:* the sweep itself (`lib/screens/dac_verification_screen.dart`), the
verdicts and report (`lib/usb/rate_sweep.dart`), and the generated tone
(`android/app/src/main/cpp/ToneSource.cpp`, reached through `playTone`).
Verdicts are pass / fail / **unverified**, the last for a DAC with no feedback
endpoint to confirm the clock with.

The stability soak (`lib/screens/stability_soak_screen.dart`,
`lib/usb/stability_soak.dart`) holds one rate — the DAC's highest by default —
for 10, 30 or 60 minutes, sampling every five seconds. It reports the counters,
the *time of the first fault*, and the clock's drift as a spread rather than a
single worst reading, because the shape of the wander is what a short test
cannot see. Ten minutes clean is surfaced as `meetsBar`, so the plan's own
requirement is something the app answers rather than something this document
asserts.

The file source (`lib/screens/playback_test_screen.dart`) answers the different
question — "does my actual library play cleanly" — from a document picked
through the storage framework, so it needs no storage permission and no
plugin. A picked file goes through the *streaming* engine rather than the file
player, because that is where the decoders are: the file player only knows WAV,
and a real library is FLAC. The MIME type is taken from the file's extension in
preference to the provider's answer, since providers routinely report a FLAC as
`application/octet-stream` and the decoder is chosen from that string. Its
verdict is a `RateResult`, the same three-way judgement a swept rate gets,
because it asks the same question of one rate.

M8 is complete: the app can run each of these against whatever is plugged in.
Hardware outcomes are what the finished tool is *for*, not a condition of
finishing it — see design rule 3.

**M9 — OpenHome. ✅ COMPLETE (2026-09-06).** Five services on the existing
`LocalDevice` — Product, Playlist, Info, Time, Volume, in the
`av-openhome-org` namespace alongside the three DLNA ones
(`upnp/openhome/`).

The reason is the spec's own requirement, not reach: *"the app should implement
local playlists so that the app keeps playing the playlist even if the DLNA
controller is no longer present."* AVTransport cannot deliver that, because a
controller only announces the current track and at best the next one —
`PlaylistQueue` can hold only what it was told. OpenHome's Playlist service
takes the whole list up front, so the renderer owns it: `OpenHomeTrackList`
holds up to 1000 tracks with never-reused ids, the evented `IdArray`, repeat
and shuffle.

Two protocols now want one DAC, and `UsbPlayback` force-claims the interfaces,
so the arbitration is OpenHome's own: Product exposes two **sources**
("Playlist" and "UPnP AV"), exactly one is active, and starting playback claims
it — which stops the other. `PlaybackController` proved to be the right seam
and needed no change; only the engine callbacks route to whichever source
started the stream.

*Verified on the Redmi with the SMSL DAC (`ohplay.py` in the test rig).* Three
tracks at three rates pushed in one go, the controller then exited: gapless
44.1/16 FLAC → 48 kHz MP3 → 96/24 FLAC, the DAC reconfigured at each boundary,
`OH playlist exhausted; stopping` at the end — **0 underruns, 0 transfer
errors, 0 bad packets throughout**, with nothing connected. A DLNA controller
interrupting mid-playlist logged `source changed: 0 -> 1` / `OH.Playlist.Stop`
/ `AVTransport.Play` with no collision.

**Confirmed by the owner on a real playlist, 2026-09-06:** filled from a NAS,
the controller killed outright, playback continued to the end, and when the
controller came back it picked up the correct now-playing state and could stop
it. That is the requirement met, not approximated.

**One caveat that will trip up anyone testing this, and is not a renderer
problem.** The guarantee is that the renderer does not need the controller *for
control*. It cannot conjure audio the controller alone could serve. The first
attempt at this test used a Tidal playlist through BubbleUPnP, whose `res` URLs
point back at BubbleUPnP's own proxy — it holds the Tidal credentials, so it
must proxy — and killing the controller therefore removed the media server too.
Every track failed, correctly. **Before any leave-the-controller test, check
which host serves the tracks** (`ohplay.py list` in the test rig prints it): if
that host dies with the controller, the test can only fail and says nothing
about the renderer. For Tidal specifically the property holds only when
BubbleUPnP *Server* runs somewhere persistent rather than as the phone app.

**A failed track is skipped, up to three in a row.** One dead link in a
fifty-track album should cost that track, not the evening — stopping there is
the controller-dependent behaviour this milestone exists to remove. But a
source that has gone away fails *every* remaining track, and skipping blindly
would tear through the list in seconds and land on "stopped" with the reason
scrolled away. So the playlist gives up after three consecutive failures and
says so in those terms — *"Stopped after 3 tracks in a row could not be
played."* — because the shape of the failure is the useful part: three in a row
points at the source, one points at a file. A track that plays to its end, or
any deliberate command, forgives the run. Reaching the end having skipped
something reports that too, rather than ending in silence as though nothing had
happened. Verified on the phone: a 404 mid-playlist is stepped over and the
next track plays; a playlist of dead links stops after exactly three, leaving
the remaining tracks untouched.

**Two faults found by a renderer that played on while vanishing from every
controller, 2026-09-06.** They were independent, and the shape of the report --
audio fine, DLNA gone -- is what pointed at both: SOAP is served by Jetty's own
thread pool, so anything already connected keeps working while the UPnP
discovery side dies quietly.

*The renderer was behaving as a control point.* jUPnP runs both halves of
UPnP, and this app only ever needed to be a device -- nothing in it touches a
remote device, a control point or a registry listener. But every `ssdp:alive`
on the network made it fetch that device's description, and BubbleUPnP
advertises `127.0.0.1` and a VPN address alongside its real one. Each
announcement therefore queued fetches that blocked six or seven seconds before
failing, for ever. Incoming M-SEARCH is handled on that same async executor and
must be answered inside the controller's MX window, a second or two, so once
enough dead fetches were queued ahead of it the renderer stopped being found at
all. Measured: unicast M-SEARCH answered, multicast M-SEARCH ignored while
eight other devices replied, the SSDP socket bound and the group joined in
`/proc/net/igmp` — a renderer that was listening and simply never got a thread
in time. `DeviceOnlyProtocolFactory` now drops remote-device chatter at the
router's door; searches *for* us are untouched. Fetch attempts went from dozens
to zero.

*Eventing was broken by a name collision.* jUPnP resolves an evented state
variable's accessor by name and prefers a **field** over the getter, so
`OpenHomeInfo`'s private `trackCount: Int` bound in preference to
`getTrackCount(): UnsignedIntegerFourBytes`. Every event then tried to write a
raw Integer into a `ui4`, and GENA died on the first track change with "Value
is not valid: 1" — controllers that lose their subscription drop the renderer.
Nothing failed at binding time and every action worked, which is why the
binding tests passed throughout. The counters are renamed, and the new test
reads every evented variable through *jUPnP's own accessor* and asserts its
datatype accepts the result: checking the getters would have passed, because
the getters were never the problem.

**The screen policy was connected, 2026-09-06.** It had been half-built:
`MainActivity` added `FLAG_KEEP_SCREEN_ON` in `onCreate` and nothing ever
removed it, because nothing subscribed to `ScreenPolicy.onKeepScreenOnChanged`.
The idle timer therefore fired into a listener that did not exist, logging
"idle timeout reached" while flipping a boolean nobody read — so the panel
never blanked. `noteActivity()` and `setIdleTimeoutMinutes()` had no callers at
all, leaving the timeout stuck at its 3-minute default.

The decision is now a pure `ScreenIdlePolicy`, driven from the service's
existing 500 ms tick rather than a timer of its own. That tick already knows
whether anything is playing, whichever protocol is driving, so there is one
place that cannot disagree with the screen — and passing the state on every
tick rather than on transitions means a missed edge cannot strand the panel lit
all night or dark mid-album, which the old design did: it posted a delayed
blank when playback *started* and never refreshed it, so the screen went out
three minutes into every album.

**Playing counts as activity**, so the countdown only begins when playback
stops; the default is five minutes. `ScreenState` carries the decision from the
service, which owns playback, to the activity, which owns the window — as
state rather than a listener, because neither reliably outlives the other and
depending on which started first is how the previous attempt broke.

**The timeout is a setting** — 1, 2, 5, 10 or 30 minutes, or Never — because
the right answer belongs to the room rather than the app: a phone across a
listening room wants to go dark quickly, one on a desk being read wants to stay
up. Never is offered and is reasonable on a permanently powered phone, with the
warning it deserves, since an OLED showing the same now-playing screen for
months is how it acquires a permanent one. Changing it restarts the countdown
from the change rather than from the last track, so shortening the timeout
cannot blank the panel under the hand of the person who just shortened it.

*Measured on the Redmi:* the panel was released after 295 s idle and the window
flag genuinely cleared, then re-held the moment playback started — and the
owner confirmed the screen did go dark and woke on the next track. **What the
app can do here stops at the flag.** Turning the panel off is the system's
decision, taken on its own display timeout counting from the last touch (10
minutes on this phone), so the observed delay is ours plus whatever the system
has left. For an appliance nobody touches that is usually immediate, but it is
not exact, and it never blanks at all if the phone's display timeout is set to
Never. Actually forcing it off would need device-admin `lockNow()` or a
black overlay; neither is built.

**The format badge goes when playback stops.** It describes a stream that is
*running*; leaving "FLAC 24/96 — bit-perfect" up after a stop states something
about a DAC that is now idle, and that is the one claim this app may not make
loosely — it exists to show when the path is bit-perfect, so a badge outliving
the audio undermines the only thing it is for. Pause keeps it, because the
stream is still open and the DAC still configured. The track identity survives
either way, or a failure would have nothing to point at.

**The now-playing screen gains previous/next** — but only for a local playlist.
A DLNA source is told one track at a time and genuinely does not know what comes
next, so the buttons are absent there rather than present and useless. At the
ends of a list they are disabled rather than hidden, so the controls do not
change shape under a thumb as the playlist advances; repeat makes both ends
reachable again.

38 JVM unit tests cover the parts that fail silently rather than loudly
(`android/app/src/test/kotlin/`): the IdArray byte order, insert-after
semantics, id reuse, shuffle as a permutation, the skip policy's two opposite
cases — and that jUPnP can bind every service, since a bad annotation is caught
by the registration try/catch and shows up only as a renderer that never
appears on the network.

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
>
> **192 kHz and beyond settled 2026-09-05** by the M8 rate sweep: all ten AL400
> rates to 768 kHz at 32-bit, zero underruns, zero packet errors, worst clock
> deviation 0.001%. Four seconds each rather than 30 minutes, so this answers
> bandwidth, not endurance. Endurance was exercised separately the same day by
> the M8 soak — ten minutes clean at 96 kHz/32-bit. Both figures describe this
> AL400; what they establish for the project is that the sweep and the soak
> run.

**Native decoding, off-device.** `test/native/run.sh` builds `PcmDecoder` and
`ToneSource` on the host against a small `android/log.h` shim and runs 53
checks. Both units fail *silently* rather than loudly — a byte order or sign
read backwards is noise, not a crash, and a tone that does not loop in phase is
a click — so they are exactly the code worth checking without a phone, a DAC
and a media server in the loop. Neither needs any of the three.

**DLNA interop.** Test against at least two controllers with different quirks — BubbleUPnP (Android)
and one desktop controller (foobar2000 UPnP or JRiver). Verify discovery, transport controls, metadata
display, volume, and that `GetProtocolInfo` advertises formats the controller will actually send.

**Playlist continuation.** Queue several tracks, then force-stop the controller app / disable the
controller's Wi-Fi. Playback must continue through the remaining queue.

**Always-on.** `adb reboot`, wait, confirm the renderer reappears on the network without opening the
app. Then leave it 12+ hours idle and confirm it is still discoverable — the real vendor-killer test.

**Device-matrix honesty.** Only the Redmi + AL400 combination is here to test against, so the rest of
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
