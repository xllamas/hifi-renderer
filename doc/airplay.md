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

   Still missing: the guest's track name. The sender does send one over
   `SET_PARAMETER`, so the screen says "Unknown track" rather than naming it.
   Parsing that DAAP payload is its own piece of work and belongs with the rest
   of the metadata, not with the fidelity claim.
6. **The appliance-shell extraction**, which the protocol doc says is owed and
   which this protocol is the one to pay for. Deliberately deferred until there
   is a real second-shape protocol to extract *against* rather than a guessed
   one.
