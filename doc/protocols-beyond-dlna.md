# Protocols beyond DLNA — an assessment

Written 2026-09-05, with every milestone in `implementation-plan.md` built.
Bluetooth spiked and closed 2026-09-06; that section is now measurement rather
than recollection, and the recommendation below moved with it. **OpenHome was
built the same day** -- out of order, because it answers the spec's own
local-playlist requirement rather than the reach question this document is
about. What it settled along the way is recorded below.
**Nothing here is committed to.** It is a decision record for the point at
which a second protocol is worth starting, and it records the reasoning so the
next person does not have to redo it — including the reasoning that turned out
to be wrong.

## Context

The next question after "it works" is reach. But "reach" turns out to mean
something specific here, and it changes the answer.

**This is an appliance in a home, and a home has more than one person in it.**
The owner is the audiophile: they care about bit-perfect, they set up the DAC,
they read the verification reports. Everyone else — a partner, a teenager, a
guest at dinner — just wants their music to come out of the good speakers,
from the phone in their hand, without being told what DLNA is.

Those are two different products sharing one box. The owner's path already
exists and is the reason the app exists. What is missing is the second one.

The first pass at this document judged each protocol by whether it dilutes the
bit-perfect claim. That is the right axis for a single-user instrument and the
wrong one here: **a guest path never claims bit-perfect in the first place, so it cannot
dilute anything** — provided the app says which path is live, which it already
does. `RendererState.output` and `bitPerfect` exist, the Oboe fallback is
already an honestly-labelled not-bit-perfect path, and the now-playing screen
already renders the distinction.

So the guest-path metric is not fidelity. It is **friction**: can someone who
has never heard of this app play something in under thirty seconds, with no
setup, no app install, and nothing to join?

By that metric the ranking inverts almost completely.

---

## Ranked by friction for a guest

| Protocol | Guest friction | Buildable? |
|---|---|---|
| **Bluetooth** | None. Every phone, no app, no network. | **No — closed on facts, 2026-09-06** |
| **AirPlay** | None for iPhone. Built into Control Centre. | Yes, with caveats |
| **Chromecast** | None for Android. Built into Spotify, YouTube Music. | Effectively no |
| DLNA | High. Needs a controller app and knowledge. | Built |
| **OpenHome** | High. Owner-only. | **Built 2026-09-06** |
| SlimProto | High. Owner-only. | Yes |

The two that matter most for the actual goal are the two the first pass
dismissed hardest.

---

## The four, reconsidered

### Bluetooth — closed, on facts

Under the household model this *would* be **the** guest path: universal, zero
setup, works from any phone anyone brings. The fidelity objection was never the
problem — nobody pairing over Bluetooth expects bit-perfect, and the app would
say so plainly on screen.

**Spiked 2026-09-06 on the Redmi (M2101K6G, Android 13, MIUI V140). The answer
is no, on two independent grounds — and the second holds on every device, not
just this one.**

**1. The profile is not enabled here, and no app can enable it.** Android 13
gates profile services on `bluetooth.profile.*` system properties. This build
sets `a2dp.source.enabled=true`, sets `avrcp.controller.enabled=false`
explicitly, and has no `a2dp.sink.enabled` key at all. The running service set
matches exactly: `A2dpService` is up, `A2dpSinkService` and
`AvrcpControllerService` are not.

They are not missing from the build — both are declared in `Bluetooth.apk`.
They are *disabled components*, which intent resolution shows directly:

| Profile action | resolveSystemService | enabled | incl. disabled |
|---|---|---|---|
| `IBluetoothA2dp` (control) | resolves | 1 | 1 |
| `IBluetoothHeadset` (control) | resolves | 1 | 1 |
| `IBluetoothA2dpSink` | **null** | **0** | 1 |
| `IBluetoothAvrcpController` | **null** | **0** | 1 |

Present in the package, switched off. Flipping that needs
`CHANGE_COMPONENT_ENABLED_STATE`, which is `signature|privileged` — a build or
overlay change, not something an app can request. The first pass called this a
system overlay rather than an app permission, and that was right.

**2. Even where the sink does run, no API hands an app PCM.** This is the part
that generalises, and it is what actually closes the option. The complete
public surface of `BluetoothA2dpSink` is:

```
connect            disconnect              getConnectionState
getConnectedDevices                        getDevicesMatchingConnectionStates
getConnectionPolicy                        setConnectionPolicy
getPriority        setPriority             isAudioPlaying
getAudioConfig
```

Connection management, end to end. `getAudioConfig` returns a
`BluetoothAudioConfig` — sample rate, channel config, encoding — which
*describes* the stream and hands over none of it. No read call, no callback, no
file descriptor. The stack decodes SBC internally and puts the result into the
audio HAL.

So the audio never reaches this engine, which only consumes PCM
(`nativePushPcm`). And the best case is worse than useless: Android's own mixer
routes the decoded stream to the USB DAC — resampled, not bit-perfect — while
`UsbPlayback` holds an exclusive claim on the same interfaces, which is the
collision `HttpStreamPlayback` already documents at 14 transfer errors and 107
bad packets. The app would be bypassed and broken at the same time.

**What the spike could not show, and why it does not matter.**
`getProfileProxy(context, listener, A2DP_SINK)` returned `true` and then never
called `onServiceConnected` — but so did the A2DP *source* control, because the
probe ran under `app_process`, which has no app record and therefore cannot
complete `bindService` (`SecurityException: Unable to find app for caller`).
That result is evidence of nothing, which is exactly what the controls were
there to reveal. The two findings above rest on intent resolution and the API
surface instead, which the harness measures cleanly and which the controls pass.

**Reproducing it** needs no app install and about a minute:

```sh
adb shell getprop | grep bluetooth.profile      # no a2dp.sink key
adb shell svc bluetooth enable
adb shell dumpsys activity services com.android.bluetooth | grep -i sink   # nothing
```

The doc's own earlier suggestion now stands as work: **say this in the app**,
rather than leaving people to wonder why the obvious thing is missing.

### AirPlay — the buildable guest path

For an iPhone guest this is exactly as frictionless as Bluetooth: it is in
Control Centre, everyone already knows how to use it, nothing to install.

`shairport-sync` is a mature reference implementation, and AirPlay 1 is
well-understood — `_raop._tcp` mDNS, RTSP handshake, AES-encrypted ALAC over
RTP. A port rather than a research project.

**The 44.1/16 objection raised in the first pass was answering the wrong
question.** For a guest path
that ceiling is irrelevant — and it is lossless ALAC, so this guest path would
incidentally be *better* than Bluetooth, not worse. It only looks like an odd
shape if you picture the owner using it, and the owner has DLNA.

The push-PCM entry point it needs already exists: `nativeStartPcmStream` /
`nativePushPcm` / `nativePcmEndOfStream`, built for MediaCodec AAC in
`usb/AacDecoder.kt`. Its hardcoded 16-bit (`StreamPlayer.cpp`,
`sourceBits_ = 16`) is a limitation for everything else and **exactly right
for AirPlay 1**.

To establish before committing:
- **License.** Confirm `shairport-sync`'s terms. Not verified here; check.
- **Legal posture.** RAOP receivers rest on a published private key — widely
  tolerated, not obviously licensed.
- **Port surface.** It assumes ALSA/PulseAudio, Avahi, libconfig, libdaemon.
  Output becomes `UsbSink`; discovery becomes Android NSD. That is the work.

### Chromecast — high value, still not feasible

The value went *up* with the household framing: for an Android guest, casting
from Spotify or YouTube Music is the natural gesture, and it is the gap
Bluetooth would otherwise have to fill alone.

Feasibility did not move. There is no supported route — Google wound down the
third-party Cast-for-audio receiver programme *(verify; this changes quietly)*
— and an unofficial receiver means mDNS, a TLS server with a device
certificate, the protobuf CASTV2 protocol, the receiver and media-namespace
state machines, and then tracking whatever Google changes, with the sender side
wholly under their control.

The fallback argument is now gone. This section previously rested on "if
Bluetooth works, it covers this need well enough that Chromecast stops
mattering" — Bluetooth does not work, so nothing covers it. **The Android guest
is the half of the household with no buildable path at all**: AirPlay serves the
iPhone, DLNA serves the owner, and the person holding an Android phone with
Spotify open has neither. That is a real gap, and the honest position is that it
stays open rather than that it was closed.

### Tidal Connect — still the owner's problem, already solved

Proprietary, licensed hardware partners only, no public specification. And it
serves the owner, not guests — who already reaches Tidal through BubbleUPnP
Server proxying into DLNA, the path the session logs show working.

---

## The owner-lane options, demoted

**OpenHome** and **SlimProto** are both good, and neither adds a new person to
the household. SlimProto is the only protocol that would carry 384 kHz to this
DAC, which matters if fidelity ever becomes the driver, but it reaches fewer
people than any guest path. Keep it; it is still not next.

**OpenHome was built on 2026-09-06**, ahead of everything here, and the reason
is worth being precise about because this document had it slightly wrong. It
was ranked by *reach* -- "improves a lane that already works, for someone
already served" -- and by that measure the ranking stands. But reach was the
wrong test for it. `doc/hifirend.md` asks for something this app did not have:

> The app should implement local playlists so that the app keeps playing the
> playlist even if the DLNA controller is no longer present.

AVTransport cannot deliver that, and no amount of care on this side changes it:
a controller only ever announces the current track and, if it bothers, the next
one, so `PlaylistQueue` can only ever hold what it has been told. Playback
surviving the controller was approximated, not achieved. OpenHome hands the
renderer the entire list up front, which turns the requirement into something
the renderer simply owns. That is a *specification gap*, not a reach
improvement, and it outranks everything in this document.

---

## The design problem that only appears now

Multiple sources introduce a question the app has never had to answer: **two
people want the speakers at once.**

Today the renderer assumes one source. `UsbPlayback` force-claims the audio
interfaces, the transport refuses a tone or a file test while the renderer is
playing, and `HttpStreamPlayback` documents what happens when two paths grab
the same descriptor — 14 transfer errors and 107 bad packets at hand-over,
which is why that guard exists at all.

A guest path turns that from a developer footgun into a Tuesday evening. It
needs a stated policy, and the policy is a product decision:

- Does a guest connecting interrupt the owner's stream, or get refused?
- If interrupted, how does the owner get back — automatically, or by hand?
- Does the DAC volume the owner set survive a guest session? (`VolumeMemory`
  remembers per-DAC and never starts at full scale, which is the right
  foundation, but a source arriving mid-session is new.)
- What does the screen say while a guest is connected? This is where the
  existing indicator earns its keep: the owner glancing across the room should
  see *"AirPlay — not bit-perfect"* and understand at once why it does not look
  the way it usually does.

**Worth deciding before any protocol is built**, because it shapes the
appliance shell rather than the protocol front-end, and retrofitting an
arbitration policy is worse than designing one.

**Partly answered, 2026-09-06.** Building OpenHome forced the question early,
and it turned out not to need inventing: OpenHome's own Product service models
a device as a set of *sources* of which exactly one is active, and selecting a
source stops the last. So DLNA became a source ("UPnP AV") alongside the
playlist, and the arbitration is the specification's rather than this app's.
Measured on the Redmi: an OpenHome playlist playing, a DLNA controller then
calling SetAVTransportURI, and the log reads `source changed: 0 -> 1` /
`OH.Playlist.Stop` / `AVTransport.Play` with **zero transfer errors and zero
bad packets** across the hand-over -- the collision this section worried about,
not happening.

What that settles is *who wins*: the arriving source, always, and the screen
follows because both write the same `RendererState`. What it does **not**
settle is the rest of the list above -- how the owner gets back, whether a
guest should be able to interrupt at all, and what the volume does across a
switch. Those are still open, and they are still product decisions. A guest
path makes them urgent in a way a second owner-lane protocol does not: being
interrupted by yourself is an annoyance, being interrupted by a dinner guest is
the design problem.

---

## What any second protocol costs first

**All appliance behaviour currently lives inside the UPnP service.**
`RendererUpnpService` extends `AndroidUpnpServiceImpl`, and hanging off it are:
the foreground service and notification, boot start, wake locks, screen policy,
the USB attach/detach watcher, network rebinding, widget refresh,
`ServiceHealth`, and the `RendererState` publishing every screen reads. None of
it is UPnP-specific and all of it is needed by a second protocol.

The extraction: an appliance shell that owns the lifecycle, the DAC, the
arbitration policy, the state and the notification — with protocol front-ends
registering against it. The seam already exists and is well shaped:
`PlaybackController` (`upnp/RendererAvTransport.kt:33`) is already the abstract
play/stop/pause/seek/position boundary and mentions nothing about UPnP.

**OpenHome did not need it, and that is not a counter-example.** Its five
services are additional services on the *same* UPnP `LocalDevice`, hosted by
the same jUPnP stack the DLNA services already use, so every piece of appliance
behaviour listed above came along untouched. `PlaybackController` was indeed
the right seam and took the second protocol with no change beyond routing the
engine callbacks to whichever source started the stream. A protocol that is not
UPnP -- AirPlay, with its own mDNS advertisement, its own RTSP server and its
own lifecycle -- gets none of that for free. **The extraction is still owed;
OpenHome just was not the protocol that had to pay for it.**

**The audio plane needs almost nothing.** Protocols come in two shapes and both
are already implemented:

- **Pull** (DLNA, OpenHome, Cast, SlimProto): the protocol yields a URL →
  `HttpStreamPlayback` unchanged.
- **Push** (AirPlay): the protocol yields decoded PCM →
  `nativeStartPcmStream` / `nativePushPcm`, already built for AAC. Bluetooth
  belonged in this row until the spike showed the sink profile never yields the
  PCM to an app at all — which is precisely why it is not buildable here.

---

## Recommendation

1. ~~Answer the Bluetooth question.~~ **Done 2026-09-06: no.** Not available
   on this build, and not reachable by any app on any build, because the sink
   profile exposes no PCM.
2. **Decide the arbitration policy.** Who wins when a guest arrives, how the
   owner gets back, what the screen says. Unchanged, and now unblocked.
3. **Extract the appliance shell**, with that policy designed in.
4. **Build the guest path: AirPlay.** No longer a choice between two — it is the
   only frictionless guest path that can actually be built, and it happens to be
   lossless. Confirm the `shairport-sync` license and legal posture first, as
   the section above sets out.
5. **Say that Bluetooth is unavailable, in the app.** Cheap, and it stops both
   classes of user hunting for a setting that cannot exist.
6. ~~OpenHome afterwards, as an owner-lane improvement.~~ **Built 2026-09-06**,
   ahead of the rest, because it was the only way to satisfy the spec's
   local-playlist requirement rather than approximate it. It also answered the
   who-wins half of item 2 for free.
7. **Chromecast** — reopen only if Google's position changed. It is now the only
   candidate for the Android guest, so it is worth a look rather than a
   dismissal, even though the feasibility finding has not moved.
8. **Tidal Connect** never, absent a commercial relationship.

The thing to hold onto: the guest path does not compete with the bit-perfect
claim, it protects it. Without one, the owner ends up unplugging the DAC and
handing over an aux cable — or being asked to make the good path convenient at
the good path's expense. A clearly-labelled lossy lane is what lets the
untouched lane stay uncompromised.

---

## Verification (whichever is chosen)

- **Existing suites stay green**: `flutter test` (54) and
  `./test/native/run.sh` (53 host checks).
- **Interop against two independent senders**, per the plan's existing DLNA
  standard — not just the one that worked first.
- **Regression on the bit-perfect claim**: the DAC's own rate indication must
  still follow the source across rates, and `dumpsys media.audio_flinger` must
  still show no active output stream for the app *on the owner's path*.
- **Run the sweep and a soak after any audio-path change.** A refactor that
  quietly costs a few packets per second shows there and nowhere else.
- **The screen must always say which path is live.** A guest source that does
  not visibly mark itself not-bit-perfect is the app doing the exact thing it
  exists to expose in other people's hardware.
- **Arbitration tested deliberately**: guest connects mid-playback, guest
  disconnects, both sources present, DAC unplugged during a guest session.
