# AirPlay — the guest path

Why this and not something else is settled in
[protocols-beyond-dlna.md](protocols-beyond-dlna.md): AirPlay is the only
frictionless guest path that can actually be built, Bluetooth having been ruled
out by measurement and Chromecast by Google. It is lossless ALAC at 44.1/16,
which makes it better than the Bluetooth it replaces and irrelevant to the
owner, who has DLNA.

## What was decided, and what changed

The earlier analysis imagined porting `shairport-sync`. Two things were
established before starting, both of which it flagged as open:

- **Licence: MIT.** No copyleft problem, so vendoring any part of it is fine.
  `alac.c`, `tinysvcmdns` and `tinyhttp` carry their own separate licences.
- **AirPlay 1 is still current enough.** `shairport-sync` still builds a
  "classic" AirPlay 1 receiver and describes the protocol as older but
  supported. **Confirmed against macOS on 2026-09-07**, and no longer an
  assumption: a current Mac offered this receiver in its AirPlay list, sent an
  `Apple-Challenge`, accepted the response and went on to `ANNOUNCE`. The guest
  path is viable.

The port was not the route taken. `shairport-sync` is a Unix daemon --
ALSA, Avahi, libconfig, libdaemon, forking, signals -- and almost all of that
would have to be stripped before any of it ran on Android. The protocol itself
is small: mDNS, an RTSP handshake, RSA and AES, RTP, ALAC. It is written here
in Kotlin against Android's own NSD and the push-PCM entry point that already
exists, with only the ALAC decoder to be vendored as C.

## The key

**A RAOP receiver has to prove it is an AirPort Express.** iOS sends an
`Apple-Challenge` on `OPTIONS` and refuses the session unless the answer is
signed with the private key Apple shipped in that hardware, and it encrypts the
AES session key to the same pair. There is no certificate programme to join and
no way to generate an acceptable key. Every open-source receiver, this one
included, depends on the key recovered from the device years ago.

**It is not in this repository.** It is loaded from
`android/app/src/main/assets/airplay/raop_key.pkcs8`, unencrypted PKCS#8 DER,
which the build has to supply. Three reasons: key material does not belong in
source control whatever its provenance; its licence position is genuinely
unclear, unlike the MIT code around it; and keeping it at arm's length makes
including it a deliberate act rather than something that arrives with a
dependency.

Without the asset everything still compiles, the renderer still advertises and
still answers RTSP -- it declines the challenge, which is the honest behaviour
for a receiver that cannot prove what it claims, and it says so in the log.
That is also what lets discovery and framing be tested without the key present
at all, which is how the work below was done.

To supply it, convert `shairport-sync`'s PEM copy:

    openssl pkcs8 -topk8 -nocrypt -inform PEM -outform DER \
        -in airport_express.pem \
        -out android/app/src/main/assets/airplay/raop_key.pkcs8

## What works today

Discovery and the full RTSP handshake, verified 2026-09-07 against the phone
from the Mac.

The renderer appears as a `_raop._tcp` service beside a real AirPlay device on
the same network, with the capability record senders actually read:

    D24CA6786B69@HiFi Renderer._raop._tcp.local. -> Android_...:43075
    txtvers=1 ch=2 cn=0,1 da=true et=0,1 md=0,1,2 pw=false sm=false
    sr=44100 ss=16 sv=false tp=UDP vn=3 vs=105.1

and completes `OPTIONS` → `ANNOUNCE` → `SETUP` → `TEARDOWN`, parsing the SDP
and reaching a negotiated session:

    airplay: session negotiated, key=false iv=false
             fmtp='96 352 0 16 40 10 14 2 255 0 0 44100'

`key=false` there is the missing asset, and `server_port=0` in the SETUP reply
is the audio layer not existing yet.

**With the key in place, a real sender gets further.** macOS, 2026-09-07:

    OPTIONS  x4    challenge answered with a 2048-bit signature, accepted
    ANNOUNCE       announced [rtpmap, fmtp, rsaaeskey, aesiv,
                               min-latency, max-latency]
    SETUP
    session negotiated, key=true iv=true
                   fmtp='96 352 0 16 40 10 14 2 255 0 0 44100'
    session ended

`key=true iv=true` is the important part: the AES session key was RSA-OAEP
decrypted, so **both** uses of the RAOP key are proven, not just the challenge.
The session then ends at `SETUP`, because the reply still offers
`server_port=0` and the sender has nowhere to send RTP. That is the only thing
now standing between this and audio.

**With the ports bound, the sender stays and streams.** macOS again, the same
day, once SETUP could answer with real ports:

    SETUP -> audio=38401 control=42489 timing=47959
    RECORD
    SET_PARAMETER
    first audio packet, 722 bytes on the wire, 710 decrypted,
        first element CPE (stereo)
    ...
    session ended after 4354 packets, 2075021 bytes decrypted, 0 undecryptable

That is the decryption confirmed, not merely attempted. `CPE (stereo)` is the
ALAC channel-pair element a stereo stream must open with; a wrong key or a
wrong IV gives plausible-looking noise here, not an error, so it is the
cheapest tell available. **Zero undecryptable packets across 4354.**

The rates agree with the format too: 117 packets a second against the 125.3 the
`fmtp` implies for 352-frame packets at 44.1 kHz, and an average payload of 477
bytes against 1408 uncompressed -- 34%, which is ALAC doing what ALAC does.

Two things that test settled which no amount of reading would have:

- **The sender connects over IPv6.** macOS came in on a link-local
  `fe80::6ccc:...` and then a global `2806:2f0:...`. The RTP sockets have to
  work there, and the address baked into the challenge response is the
  connection's local address, whichever family that is.
- **This phone has no ALAC decoder.** Nothing in `/vendor/etc/media_codecs*.xml`
  offers `audio/alac`, so MediaCodec cannot be used for it and the decoder has
  to be vendored as C after all -- which is what the plan assumed, now for a
  measured reason rather than a guessed one.

Two details are load-bearing and were got wrong first in every other
implementation worth reading:

- **The instance name must be `<twelve hex digits>@<name>`.** Senders parse the
  prefix as a hardware address. It is derived from the renderer's UDN, because
  Android no longer hands out the real MAC and the UDN is already this
  appliance's identity everywhere else.
- **`CSeq` must be echoed on every reply.** Losing it ends the session at once
  and without explanation, and senders disagree about its capitalisation, so
  header lookup is case-insensitive.

## What is next

1. ~~Bind the three UDP ports and decrypt AES-128-CBC.~~ **Done**, and
   confirmed against macOS as above.
2. ~~Decode ALAC and push the PCM.~~ **Done 2026-09-07, and it plays.**

   Apple's reference decoder is vendored (Apache 2.0, `third_party/alac`)
   because this hardware offers no `audio/alac` at all, and because a decoder
   bug produces noise rather than an error -- not something to hand-write.
   Configuration comes from the SDP, since RAOP sends bare frames with no
   container; `RaopFormat` parses the eleven `fmtp` fields into named ones and
   is tested against the exact line macOS sends, because a transposition there
   decodes noise and gets blamed on everything else first.

   Measured over 72 seconds of music from a Mac:

       source changed: 0 -> 2                       (AirPlay claimed the output)
       alac: 44100 Hz 16-bit 2ch, 352 frames per packet
       configure: 44100 Hz, source 16-bit -> alt 2, async +feedback
       9001 frames decoded, 1408 bytes of PCM in the last one
       underruns=0 xferErr=0

   Every packet decoded to exactly 1408 bytes -- 352 frames of stereo 16-bit,
   the full frame the `fmtp` promises, never a partial one. 125.3 frames a
   second against the 125.3 the format implies, so no loss at all across the
   run, and no decode failures.

   Decoding happens in native code and pushes straight into the stream, rather
   than returning PCM to Kotlin to hand back down: two JNI crossings and two
   copies of every packet, 117 times a second, for samples nothing on the Java
   side wants to look at.
3. **Sync and retransmission.** The control and timing sockets are bound and
   drained but unread. They are what separate "plays" from "plays without
   dropouts", and a guest path that stutters is worse than none.
4. **Source arbitration.** AirPlay becomes a third source alongside
   `SOURCE_PLAYLIST` and `SOURCE_UPNP_AV`, through the existing `claim` /
   `onSourceSelected` seam. A guest arriving mid-album is the case to design,
   not the case to discover.
5. ~~Say it is not bit-perfect, on the screen, whenever this path is live.~~
   **Done 2026-09-08.**

   `UsbSink::bitPerfect()` was a hardcoded `true`, and the sinks published that
   as `"bitPerfect"` in their own status. Both halves were wrong in the same
   way: bit-perfect is a property of the whole path, and a sink cannot see past
   its own input. The USB sink was *honest* about itself -- it does alter
   nothing -- which is exactly why it must not be the one asked about the
   stream.

   So the sinks no longer publish the key at all. `StreamPlayer::status()`
   composes it, being the only layer that sees both the sink and where the
   samples came from:

       const bool exact = sink_->bitPerfect() && !senderAltered_;

   `senderAltered` is declared at each call site rather than inferred, and
   `NativeBridge.startPcmStream` deliberately has no default for it -- a
   default would have to be `false`, which is the *claiming* answer, and the
   whole of this bug was one path inheriting a claim nobody made for it.

   The screen half turned out to be a second, separate defect, and the
   screenshot is what found it. `publishEngineState()` runs only inside
   HttpStreamPlayback's track watcher, which the guest path never enters --
   AirPlay opens the output and pushes PCM directly. So through an entire guest
   session the now-playing screen sat blank: no format, no transport, a
   stopped-looking renderer while ALAC was plainly decoding to the DAC. A blank
   screen answers the bit-perfect question no better than a wrong badge does.
   `publishGuestStream()` now publishes the session, reading `bitPerfect` and
   `senderAltered` back *from the engine* rather than recomposing them in
   Kotlin -- composing them twice is how two answers drift apart.

   Verified on the Redmi against a real macOS sender, same SMSL DAC, minutes
   apart:

       configure: 44100 Hz, source 16-bit -> alt 2, async +feedback
       pcm: 44100 Hz 2ch pushed in (already resampled by the sender: NOT bit-perfect)
       airplay: screen says ALAC 16/44.1, bitPerfect=false senderAltered=true out=usb

   and the screen reads `ALAC 16/44.1` beside an amber *AirPlay - sender
   resampled*, where a local FLAC on the same DAC still reads `FLAC 16/44.1`
   beside the green tick.

   One defect surfaced only in a second screenshot, once a local track had
   played *before* the guest arrived: the screen kept the owner's title,
   artist, album and cover art and hung them on the guest's stream. The
   playlist stops when the guest claims the source but deliberately remembers
   which track it stopped on, and nothing on this path cleared it -- so
   publishing a transport and a badge over the top assembled the stale fields
   into a convincing, wrong now-playing card. Worse than the tick it replaced:
   that overstated quality, this named a track that was not playing.
   `publishGuestStream()` clears the track first, which is load-bearing --
   `clearTrack()` reaches `clearFormat()`, so anything written before it is
   thrown away.

   The guest's track name is dealt with below, in *Metadata*, and the answer
   turned out to be about the sender rather than about parsing.
6. **The appliance-shell extraction**, which the protocol doc says is owed and
   which this protocol is the one to pay for. Deliberately deferred until there
   is a real second-shape protocol to extract *against* rather than a guessed
   one.

## Metadata

AirPlay carries nothing about the track in the audio stream -- RAOP sends bare
ALAC frames -- so everything the screen can say about a guest's music arrives
out of band, as a `SET_PARAMETER` whose body is DMAP: Apple's tag-length-value
encoding, four ASCII bytes of tag, four big-endian bytes of length, then the
payload. `DaapMetadata` reads it, keeping `minm` (title), `asar` (artist),
`asal` (album), `asgn` (genre) and `astm` (duration, in milliseconds).

Parsed rather than scanned for. Lengths are what separate one field from the
next, so a reader that hunts for `minm` and takes bytes until the next
printable run returns half a title, or a title with the next tag glued on, and
the result looks like a bug in the *sender*. Every length is checked against
what is actually left in the buffer, and a length that overruns ends the walk
rather than reading past it. The tests are weighted accordingly: the happy path
is one of eleven, and the rest are truncation, an overrunning length, junk
where a tag should be, and an empty `minm` between tracks that must not blank a
title already on screen.

Senders disagree about wrapping -- iOS and macOS send a `mlit` container,
several third-party senders send the fields bare -- so both are read. Nesting
is followed only into a closed set of known container tags, because there is no
flag in the encoding saying whether a payload is nested, and a UTF-8 title of
the right length looks like valid DMAP often enough to matter. An unknown
container is skipped whole: fields are lost, never invented.

`publishGuestMetadata()` is guarded on the guest still holding the output.
Senders keep the RTSP connection alive across a source change and go on
announcing tracks after the owner has taken the DAC back -- a phone left paused
in a pocket does exactly this -- and writing that through would put a guest's
title on the owner's music. The same fault as leaving the owner's title on a
guest's stream, in the other direction. Fields are applied one at a time, so a
later message carrying only an album does not erase the title.

### macOS cannot exercise any of it

Measured 2026-09-08 against macOS 26.6.2. A session established, played
cleanly, and sent this:

    SET_PARAMETER type=text/parameters            20 bytes
    SET_PARAMETER type=image/none                  0 bytes
    SET_PARAMETER type=application/x-dmap-tagged  82 bytes
    metadata carried nothing to show (82 bytes,
      tags=[mlit, mper, asal, asar, ascp, asgn, minm, asdk, caps])

The walk found all nine tags in the right order, so the container handling is
proven against a real sender. The string fields are simply *empty*: 82 bytes is
exactly the nine headers plus `mper` (8), `asdk` (1) and `caps` (1), leaving
zero bytes for `minm`, `asar`, `asal`, `asgn` and `ascp`. `image/none, 0 bytes`
says the same about artwork.

That is `coreaudiod`'s signature, and it is a property of the route rather than
a fault. On macOS 26 an AirPlay 1 receiver is reachable **only** through
Control Centre's sound output, where the sender is the system audio daemon --
which has no concept of a track and sends the envelope with nothing in it.
Music and Tidal never offer the renderer at all:

    Music.app's AirPlay device list:   Walrus only
    _airplay._tcp advertisers:         Walrus only     (AirPlay 2)
    HiFi Renderer advertises:          _raop._tcp only (AirPlay 1)

`am=AirPort10,115` was added on the theory that the missing model field was
what excluded us -- shairport-sync sets it and we did not. It is on the wire
and it changed nothing: Music's list was identical across four polls. Kept
anyway, because iOS senders read it and it is consistent with the AirPort
Express key this receiver already authenticates with, but **it is not a fix for
anything** and should not be read as one.

So the empty-field guard is doing the real work on this route: it leaves
"Unknown track" standing rather than replacing it with blank strings. The
string-reading path remains unverified in the field, and an iOS sender is the
way to verify it -- iPhones still speak AirPlay 1 to legacy receivers and send
DAAP, artwork and progress.

### There is no sender name in the headers

PhairPlay shows "Audio from <sender>" where this shows "Unknown track", which
is a better answer and a more useful one -- when unexpected music starts, the
owner mostly wants to know *who* has the output, not what the track is called.
Whether that is reachable over AirPlay 1 was worth measuring rather than
guessing, so every request's headers are now logged once per method per
connection (never bodies: the ANNOUNCE body carries the AES key).

macOS 26 sends four headers and no more, on every method:

    cseq, dacp-id: 20BC6070E22D669E, active-remote: 4266753127,
    user-agent: AirPlay/960.13.1

No `X-Apple-Client-Name`, no `Client-Instance`, no friendly name anywhere. The
obvious implementation would have read a header that does not exist.

The name is still reachable, by a longer route. `dacp-id` names a Bonjour
service the sender advertises for its own remote control, and resolving it
gives the sender's host:

    $ dns-sd -B _dacp._tcp local
    iTunes_Ctrl_20BC6070E22D669E
    $ dns-sd -L iTunes_Ctrl_20BC6070E22D669E _dacp._tcp local
    ... can be reached at Walrus.local.:57047

`Walrus` is the sending Mac -- but that name is in the SRV record's *target*,
and `NsdManager` resolves it away. Asked to resolve the same service, Android
returns `192.168.100.134` and no name, which is what the first implementation
got and correctly refused to show. Both shortcuts out are dead ends, measured:
the phone cannot resolve `Walrus.local` at all (`ping: unknown host`), and the
Mac answers a reverse PTR for its own address with `No Such Record`.

What works is a second hop. `_companion-link._tcp` -- Apple's Continuity
service, advertised by Macs and iPhones alike -- carries the friendly name as
its *instance* name, which `NsdManager` does expose. So the sender's address
comes from the DACP service and the name comes from whichever Continuity
advertisement shares that address:

    _dacp._tcp   iTunes_Ctrl_20BC6070E22D669E -> 192.168.100.134
    _companion-link._tcp   "Walrus"           -> 192.168.100.134   match

Both hops anchor on addresses returned by the same resolver rather than on the
RTSP peer address: senders connect over IPv6 -- macOS was seen doing it -- and
matching an IPv6 peer against an IPv4 advertisement would never hit, in a way
that would look like "it works for some senders". Verified on the Redmi against
macOS 26: `airplay: sender is 'Walrus' at 192.168.100.134`, and the screen
reads *AirPlay from Walrus*.

That same channel is the other way to metadata, and a more promising one than
DAAP on this route: DACP is a remote-control protocol, so a receiver holding
`dacp-id` and `active-remote` can ask the *sender* what is playing rather than
wait to be told, and can send play/pause/next back. Probing it here got as far
as proving the endpoint is live and no further -- `/server-info` 404,
`/ctrl-int/1/playstatusupdate` 400 -- so the request shape needs real work
rather than a guess. Worth knowing it exists; not worth assuming it is easy.

## AirPlay 2: assessed, not attempted

Appearing in Music's and Tidal's own device pickers means being an AirPlay 2
receiver on `_airplay._tcp`. Scoped 2026-09-08, and the conclusion stands --
but the *first* version of this section gave the wrong reason and is corrected
below, because the wrong reason would have sent the next reader down a blind
alley.

### The reason it is not PTP

The original claim here was that AirPlay 2 needs PTP (IEEE 1588) on UDP 319
and 320, that an unprivileged Android process cannot bind those, and that this
blocks AirPlay 2 outright. The measurement is real and repeatable:

    $ adb shell toybox nc -l -p 319
    nc: bind: Permission denied
    $ adb shell toybox nc -l -p 33190
    (blocks -- bound fine)

The *inference drawn from it was wrong*. PhairPlay -- an open-source AirPlay 2
receiver for Android TV, Kotlin, unrooted, sideloaded -- does AirPlay 2
discovery, HomeKit-style pairing, FairPlay key decryption, RTSP and
mirroring-with-audio on a stock Android device. Its timing is Apple's
simplified NTP-over-UDP on an ordinary high port:

    TimingHandler -- Responds to Apple NTP timing probes for A/V synchronization
    handler.start(scope)   // listens on TIMING_PORT (6002)

No privileged port anywhere in it. It advertises with the same `NsdManager`
this app already uses, registering *both* services on port 7000:

    _airplay._tcp   deviceid, features=0x5A7FFFF7,0x1E, model, srcvers,
                    vv=2, pi=<persistent uuid>, flags=0x4
    _raop._tcp      cn=0,1,2,3  et=0,3,5  md=0,1,2  vn=65537  tp=UDP  am=<model>

So the achievable surface of AirPlay 2 on unrooted Android is much larger than
this document first claimed, and the pairing and FairPlay work -- the part that
looked most forbidding -- is demonstrably writable in Kotlin.

### The reason it is still not worth doing here

Two things, and neither is about privilege.

**The role we want is the one nobody has finished.** Music and Tidal address a
speaker through *buffered audio*, AirPlay 2 stream type 103 -- not the realtime
or mirroring paths. PhairPlay's own README: "Buffered audio (AirPlay 2 type
103) is accepted but not yet played back", listed as in progress. That is the
furthest along an open Android AirPlay 2 receiver has got, and type 103
playback is precisely the piece still missing. Whether PTP is what makes that
piece hard is an open question this document should not answer twice.

**The achievable part is the part this app does not want.** Mirroring audio is
AAC-ELD or AAC-LC. This renderer exists to put untouched samples into a DAC,
and it already receives *lossless ALAC* over AirPlay 1. Implementing AirPlay 2
mirroring would be a large piece of work whose reward is a worse codec than the
one already arriving. Only type 103 carries lossless audio, and type 103 is the
unfinished part.

So: not blocked, but poorly aimed. If AirPlay 2 is ever revisited, PhairPlay is
the reference to read first -- <https://github.com/mazer666/PhairPlay> -- and
the question to answer before writing anything is what type 103 playback
actually requires for timing.

**The reframe that matters, unchanged.** This is the guest path on a household
appliance, and a guest is far likelier to be holding an iPhone than sitting at
the owner's Mac. iOS senders use AirPlay 1 and do send metadata, so the case
that matters most may already work with what is written -- untested only
because the one sender to hand is structurally the one that cannot exercise it.
Verify with an iPhone before spending anything here.
