# Protocols beyond DLNA — an assessment

Written 2026-09-05, with every milestone in `implementation-plan.md` built.
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
| **Bluetooth** | None. Every phone, no app, no network. | **Unknown — resolve first** |
| **AirPlay** | None for iPhone. Built into Control Centre. | Yes, with caveats |
| **Chromecast** | None for Android. Built into Spotify, YouTube Music. | Effectively no |
| DLNA | High. Needs a controller app and knowledge. | Built |
| OpenHome / SlimProto | High. Owner-only. | Yes |

The two that matter most for the actual goal are the two the first pass
dismissed hardest.

---

## The four, reconsidered

### Bluetooth — highest value, and the biggest unknown

Under the household model this is **the** guest path. Universal, zero setup,
works from any phone anyone brings, needs no explanation to anybody. The
fidelity objection is irrelevant: nobody pairing over Bluetooth expects
bit-perfect, and the app would say so plainly on screen.

What stands is the platform question, and it is asserted here from memory
rather than measurement. `A2DP_SINK` is a system-side profile on Android: disabled in most
stock builds, enabled by a system overlay rather than an app permission, and
where the sink role does run, the Bluetooth stack decodes into the audio HAL
with no supported API handing an app raw PCM — which is the only form this
engine takes.

**This is the single most important thing to resolve, and it is cheap.** A
short spike on the Redmi: attempt
`BluetoothAdapter.getProfileProxy(context, listener, BluetoothProfile.A2DP_SINK)`
and see whether it binds; if it does, find out where the audio actually routes.
Perhaps an hour. It either opens the most valuable protocol on the list or
closes it on facts, and every other decision here is cheaper to make once it is
answered.

If it is blocked, that is worth saying in the app rather than leaving people to
wonder why the obvious thing is missing.

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
- **Licence.** Confirm `shairport-sync`'s terms. Not verified here; check.
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

If Bluetooth works, it covers this need well enough that Chromecast stops
mattering — another reason to answer that question first.

### Tidal Connect — still the owner's problem, already solved

Proprietary, licensed hardware partners only, no public specification. And it
serves the owner, not guests — who already reaches Tidal through BubbleUPnP
Server proxying into DLNA, the path the session logs show working.

---

## The owner-lane options, demoted

**OpenHome** and **SlimProto** are both good, and neither adds a new person to
the household. OpenHome fixes something real — the renderer depends on the
controller staying alive to advance a playlist — but that improves a lane that
already works, for someone already served. SlimProto is the only protocol that
would carry 384 kHz to this DAC, which matters if fidelity ever becomes the
driver, but it reaches fewer people than any guest path.

Keep both. Neither is next.

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

**The audio plane needs almost nothing.** Protocols come in two shapes and both
are already implemented:

- **Pull** (DLNA, OpenHome, Cast, SlimProto): the protocol yields a URL →
  `HttpStreamPlayback` unchanged.
- **Push** (AirPlay, Bluetooth): the protocol yields decoded PCM →
  `nativeStartPcmStream` / `nativePushPcm`, already built for AAC.

---

## Recommendation

1. **Answer the Bluetooth question.** About an hour of spike work on the Redmi.
   Highest-value guest path, only genuine unknown, and everything else is
   cheaper to decide once it is settled.
2. **Decide the arbitration policy.** Who wins when a guest arrives, how the
   owner gets back, what the screen says.
3. **Extract the appliance shell**, with that policy designed in.
4. **Build the guest path**: Bluetooth if the spike says yes, AirPlay
   otherwise — or AirPlay regardless, since it is the iPhone half of the
   household and Bluetooth cannot cover that as gracefully.
5. **OpenHome** afterwards, as an owner-lane improvement.
6. **Chromecast** only if Google's position changed; **Tidal Connect** never,
   absent a commercial relationship.

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
