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

1. **The audio layer.** Bind the three UDP ports, decrypt AES-128-CBC, decode
   ALAC, push into `nativeStartPcmStream` / `nativePushPcm`. The RTSP layer
   already hands over everything it needs as `RaopSessionParams`, which is why
   it could be finished first.
2. **Source arbitration.** AirPlay becomes a third source alongside
   `SOURCE_PLAYLIST` and `SOURCE_UPNP_AV`, through the existing `claim` /
   `onSourceSelected` seam. A guest arriving mid-album is the case to design,
   not the case to discover.
3. **Say it is not bit-perfect**, on the screen, whenever this path is live.
   The plan is explicit that a guest source which does not visibly mark itself
   is the app doing the thing it exists to expose in other people's hardware.
4. **The appliance-shell extraction**, which the protocol doc says is owed and
   which this protocol is the one to pay for. Deliberately deferred until there
   is a real second-shape protocol to extract *against* rather than a guessed
   one.
