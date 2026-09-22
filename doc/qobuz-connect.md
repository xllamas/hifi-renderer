# Qobuz Connect -- an assessment

Written 2026-09-18, prompted by
[leolobato/qobuz-proxy](https://github.com/leolobato/qobuz-proxy) (read at
`b1d2ca4`, 2026-09-15). qobuz-proxy is a Python daemon that shows up in the Qobuz
app as a Connect speaker and forwards the audio to DLNA renderers or a local sound card.
Its protocol work comes from [StreamCore32](https://github.com/tobiasguyer/StreamCore32)
(read at `62075a3`), a C++ Connect implementation for the ESP32. Both were cloned
and read for this document. **Nothing here is committed to.** Like
[protocols-beyond-dlna.md](protocols-beyond-dlna.md), this is a decision record
for when the question comes up again.

## The short answer

**The engineering is easy, the product fit is good, and it cannot ship.** A Qobuz
Connect receiver is a pull protocol. Everything below the protocol front-end
already exists here and has been measured at 192 kHz. But no open implementation
can play a single track without using an application secret that Qobuz issued to
someone else. Qobuz's API terms forbid exactly that, and the resulting app would
breach Google Play's policy on unauthorized access to third-party services. So this
is not a technical problem to engineer around. The only route that changes the
verdict is asking Qobuz.

---

## Why it is tempting

Using the household model from
[protocols-beyond-dlna.md](protocols-beyond-dlna.md), Qobuz Connect is unusual
because it serves **both** classes of user.

**The guest with a Qobuz subscription.** The renderer would appear in the device
list the Qobuz app already shows, with nothing to install and nothing to join. On
connecting, the phone *hands the renderer its own session*: the `connect-to-qconnect`
POST carries a WebSocket JWT and an API JWT (qobuz-proxy
`connect/discovery.py:214-269`). StreamCore32 then uses that API JWT as a bearer
token to resolve tracks when no local login exists (`QobuzStream.cpp:384-388`). If
that works, a guest plays *their* account on the good speakers and the appliance
needs no login of its own. *Not verified here: qobuz-proxy never uses the API JWT
and logs in separately.*

This also reaches into the gap that document left open: "the Android guest is the
half of the household with no buildable path at all". The Qobuz Android app casts
only to Chromecast and Qobuz Connect; it has no DLNA. An Android guest with Qobuz
has no route to this renderer today, and Connect would give them one. It helps only
Qobuz subscribers, though. The Spotify and YouTube Music guest gap is unchanged.

**The owner.** Native Qobuz app control at up to 24/192 over a pull path, so
bit-perfect by construction. The queue lives in Qobuz's cloud, not in the phone, so
playback outlives the controller. That is the property
`doc/hifirend.md` asks for and OpenHome was built to deliver.

**What already reaches Qobuz today**, for comparison:

| Who | Path | Quality |
|---|---|---|
| iPhone guest | Qobuz app → AirPlay | 44.1/16 ALAC, labelled not bit-perfect |
| Owner | BubbleUPnP / mConnect / Kazoo (Qobuz built in) → DLNA or OpenHome | up to 24/192, bit-perfect |
| Android guest | none | -- |

So for the owner, Connect is a convenience: the official app instead of a third-party
controller. For the Android guest who has Qobuz, it is the only path.

---

## How Qobuz Connect works

Drawn from the qobuz-proxy source. Qobuz publishes no specification, so this is
what the reverse-engineered implementations do, not a spec.

1. **Discovery.** mDNS `_qobuz-connect._tcp` on an HTTP port, with TXT
   `path=/streamcore`, `type=SPEAKER`, `Name`, `device_uuid` and `sdk_version`
   (`connect/discovery.py:23`, `:287-293`). The `/streamcore` path is inherited
   from StreamCore32. *Whether the Qobuz app accepts any device that advertises this
   way, or checks it against a partner list, is not verified.*
2. **Handshake.** Three HTTP endpoints under that path: `GET get-display-info`
   (name, brand, maximum quality), `GET get-connect-info` (app ID, current session),
   and `POST connect-to-qconnect`, where the app delivers the session ID and the two
   JWTs (`discovery.py:150-152`, `:180-269`).
3. **Cloud WebSocket.** The renderer connects to the endpoint named in the WebSocket
   JWT. There it sends Authenticate and then Subscribe, and from then on exchanges
   Payload frames wrapping a protobuf `QConnectBatch` (`protos/qconnect_envelope.proto`).
   There are about fifty message types: the renderer reports join, state, volume and
   quality, and the server sends set-state, set-volume, set-active, loop, shuffle and
   the queue operations (`protos/qconnect_payload.proto:15-84`).
4. **Playback.** The server sends *track IDs*, not URLs. The renderer resolves each
   one itself: `session/start` and then `track/getFileUrl`, both signed with an MD5
   `request_sig` over the method, the sorted parameters, a timestamp **and the
   application secret** (`auth/api_client.py:133-140`, `:250-266`). The result is a
   signed CDN URL for a plain FLAC file with Range support, plus the bit depth,
   sample rate and an opaque `blob`.
5. **Reporting.** `track/reportStreamingStart` and `reportStreamingEndJson` register
   the play (listening history, Last.fm) (`api_client.py:313-374`). A position
   report is `{timestamp, value}`, and the app interpolates between them.
6. **Token lifetime.** The WebSocket JWT lasts about 60 minutes. qobuz-proxy adds a
   full OAuth login so it can mint its own tokens (`qws/createToken` /
   `refreshToken`, `api_client.py:173-233`) and outlive the phone. Without that,
   the renderer depends on the phone reconnecting.

---

## The blocker: authorization

This section is kept apart from the engineering on purpose, so that it is not read as
one more technical obstacle.

**Every open implementation uses Qobuz's own app credentials without permission.**

- qobuz-proxy hard-codes the Qobuz *desktop app's* ID, private key and secret,
  under a comment that says exactly that (`auth/oauth.py:16-19`). It uses them for
  every call (`app.py:143-144`).
- StreamCore32 downloads the Qobuz web player's JavaScript bundles at runtime and
  scrapes the secrets out of them (`QobuzConfig.cpp:650`,
  `FetchClientAppSecrets`).

Neither is sloppiness. Step 4 above cannot be done any other way: the signature
covers the secret, and without a valid signature there is no stream. A clean-room
implementation has the same dependency.

**Qobuz's terms forbid it in so many words.** The
[Qobuz API Terms of Use](https://static.qobuz.com/apps/api/QobuzAPI-TermsofUse.pdf),
*Definitions*: "You are not allowed to access the API without such application ID
and application secret" -- meaning ones Qobuz granted *you* -- and "The application
ID and the Application secret shall not in any circumstance be shared, whether
voluntarily or no, to a third party." *Restrictions* (i) also forbids "accessing …
the Service or Content in any other way than through the API in accordance with the
Terms of Use". On Connect specifically, the
[help centre](https://help.qobuz.com/en/articles/313603-can-qobuz-connect-be-used-via-a-third-party-app)
says: "only Qobuz apps can control devices via Qobuz Connect. Third-party apps are
not supported." The legitimate route is the
[partner programme](https://community.qobuz.com/press-en/qobuz-connect-celebrates-over-100-partners):
more than 100 hardware brands, some reached through SDK vendors such as
[StreamUnlimited](https://www.streamunlimited.com/qobuz-connect-now-available-via-streamsdk/).

**Google Play policy points the same way.** The
[Device and Network Abuse](https://support.google.com/googleplay/android-developer/answer/16559646)
policy prohibits apps from unauthorized access to another party's API or service.
Borrowed credentials are unauthorized access by definition.

**This is not the AirPlay precedent.** AirPlay also rests on key material nobody
licensed (see [airplay.md](airplay.md), which keeps it out of the repository for
that reason). But the two are different in kind:

- *AirPlay:* the key lets a receiver *interoperate* with a sender. The audio comes
  from the guest's own phone, and no content service is involved or deceived.
- *Qobuz:* the credentials impersonate Qobuz's own client in order to *fetch
  licensed content* from a service whose terms the project would be breaking. It is
  the service's gate, not a device handshake.

**And the consequences are asymmetric.** v1.0 is live on Play as
`com.acelery.hifirend`, the repository is public, and both carry the author's name.
Qobuz can rotate the desktop secret or block the device fingerprint at any time
without notice. That would break a shipped feature for paying users and leave a
support problem nobody could fix, plus Play-policy exposure that affects the whole
app, not just this feature.

**A licensing problem sits on top.** StreamCore32 is **GPLv3**. qobuz-proxy is MIT,
but its `.proto` files are modified copies of StreamCore32's: same file names and
same comments, with 11 to 69 lines differing per file. This repository is Apache 2.0
with no GPL anywhere, so it must not take either set. An authorized implementation
would write its schema from the protocol facts, or better, from whatever Qobuz
provides.

---

## If it were authorized: how it maps onto this app

For the case where Qobuz says yes. Paths below are relative to
`android/app/src/main/kotlin/com/hifirend/`.

**The audio plane needs nothing new.** This is the pull shape from
protocols-beyond-dlna.md: the protocol yields a URL, and `usb/HttpStreamPlayback.kt`
plays it.

- Native FLAC decoding with 24-bit read as s32. 192 kHz FLAC is already proven
  against BubbleUPnP/Tidal.
- HTTPS and redirects are handled.
- FLAC seek works through Range requests, which Qobuz's CDN supports: qobuz-proxy's
  DLNA proxy forwards `Range` and nothing else (`backends/dlna/proxy_server.py:268-277`),
  so no custom request headers are needed. That matters, because `play()` cannot
  take any today.
- Gapless: when the source is exhausted, the front-end resolves the next track and
  calls `playGapless` (`usb/HttpStreamPlayback.kt:774`, `upnp/RendererAvTransport.kt:262`). The URL has to be resolved
  *at that moment*, not held ahead, because signed CDN URLs expire.

**Discovery and handshake.** Follow `airplay/RaopAdvertiser.kt`, which already
registers an NSD service with a TXT record. The handshake is three small HTTP
routes. A raw `ServerSocket` as in `airplay/RaopRtspServer.kt` would do, or the
Jetty that jUPnP already bundles.

**New dependencies.** A WebSocket client (OkHttp, or Jetty's `websocket-client`
module next to the Jetty already present) and protobuf, either `protobuf-javalite`
with the Gradle plugin or a hand-written codec in the spirit of `RtspMessage`.
There is none of either in `android/app/build.gradle.kts` today.

**Arbitration: a fourth source.** Add `SOURCE_QOBUZ` next to `SOURCE_PLAYLIST`,
`SOURCE_UPNP_AV` and `SOURCE_AIRPLAY` (`upnp/RendererUpnpService.kt:60-62`), and a
fourth entry in the OpenHome Product source list (`:1048-1060`). Extend
`onSourceSelected` (`:150-162`) and the engine-callback routing, which is two-way
today (`:970-979`). qobuz-proxy learned the key lesson the hard way, in
`docs/spotify-takeover-hotfix.md`: once another source takes the output, the
Connect session must be **released**, not just paused. Otherwise the hourly token
refresh re-joins as active and seeks whatever the other source is playing. Here
that means `onSourceSelected` leaving Qobuz tells the cloud the renderer is
inactive, and a new handshake is needed to come back.

**Volume.** Through `setDacVolume` (`upnp/RendererUpnpService.kt:930-941`), which
already saves the level with `VolumeMemory`. Changes are reported back as
`RndrSrvrVolumeChanged`. This would be the first non-UPnP protocol to apply remote
volume at all: AirPlay receives `SET_PARAMETER` volume and does not act on it.

**The screen.** A bit-perfect Qobuz stream would get the green tick and nothing to
say where it came from. The AirPlay label is derived from `senderAltered`, and
`RendererState` has no protocol field. It needs an `activeSource`, which would help
AirPlay too.

**Account.** The app has no concept of a user account anywhere. Handshake-only
operation (the phone's API JWT, if it works) keeps it that way. A qobuz-proxy-style
OAuth login, for sessions longer than the ~60-minute token, would be the first
credential this app ever stores. Start without it.

**The shell extraction comes due.** [airplay.md](airplay.md) deferred extracting the
appliance shell "until there is a real second-shape protocol to extract *against*".
Qobuz is a second non-UPnP lifecycle, and a new kind: a long-lived outbound cloud
connection with token refresh and reconnect backoff. Hanging a third protocol's
lifecycle off `RendererUpnpService` is the point where that deferral stops paying.

**Size.** qobuz-proxy's `connect/`, `auth/` and `playback/` come to about 6,500
lines of Python, and the player state machine alone is 1,938. hifirend's AirPlay is
about 1,400 lines of Kotlin. A realistic estimate for Connect is **2,500–4,000
lines of Kotlin**, most of it queue and state, not transport. That is larger than
AirPlay, with less risk in the audio path and more in the protocol.

**Durability risk.** StreamCore32 already models a second delivery format:
segmented FLAC-in-MP4 (`audio/mp4; codecs="flac"`) behind a `$SEGMENT$` URL
template with a key ID and key material (`include/QobuzTrack.h:91-136`). If Qobuz
moves Connect renderers onto it, the pull path gains an MP4 demuxer and a
decryption step. That is a different category of work, and a different legal
question, from fetching a FLAC file. *Whether Connect uses it today is not
verified.*

---

## Options, ranked

1. **Ask Qobuz.** Write to Qobuz's partner / API contact and ask whether a
   software renderer on Android can join Qobuz Connect, under what terms, and with
   what SDK. It costs an email and is the only step that can change the verdict.
   Expect the programme to be shaped around hardware brands. Asking is still free.
2. **Say what works, in the app and the README.** State which Qobuz paths work today
   (the table above) and that Qobuz Connect is not available. This is the same
   reasoning as saying that Bluetooth is unavailable: it stops both classes of user
   hunting for a setting that cannot exist.
3. **An unofficial build outside Play** is technically possible, and qobuz-proxy
   shows the shape. It is not recommended: it breaches the same terms, just more
   quietly, from a public repository under the author's name, and it would split
   the build in two for one feature. If it is ever done anyway, it must not live in
   this repository's main build, and it must not reuse StreamCore32-derived schema.
4. **Never in the Play build** without written authorization from Qobuz.

---

## Verification, if Qobuz says yes

- **Existing suites stay green**: `flutter test` and `./test/native/run.sh`.
- **Interop against both official apps**, Android and iOS, since the controller is
  now Qobuz's code and not ours.
- **A soak longer than 60 minutes** so it crosses a token expiry mid-album, with and
  without the phone still on the network.
- **Takeover, deliberately**: a DLNA controller and then an AirPlay guest arriving
  mid-Qobuz, each followed by reselecting the renderer in the Qobuz app. Check the
  other source is never seeked or stopped by a Qobuz refresh (the qobuz-proxy
  failure).
- **The bit-perfect claim**: the DAC's rate indication follows the source from 44.1
  to 192 across a queue, and `dumpsys media.audio_flinger` shows no active output
  stream for the app.
- **The screen says "Qobuz"**, alongside the bit-perfect state.
- **Plays are reported**: they appear in the account's listening history.

---

## Sources

- qobuz-proxy, MIT: <https://github.com/leolobato/qobuz-proxy> at `b1d2ca4`
- StreamCore32, GPLv3: <https://github.com/tobiasguyer/StreamCore32> at `62075a3`
- Qobuz API Terms of Use: <https://static.qobuz.com/apps/api/QobuzAPI-TermsofUse.pdf>
- Qobuz help centre, third-party control:
  <https://help.qobuz.com/en/articles/313603-can-qobuz-connect-be-used-via-a-third-party-app>
- Qobuz Connect partners:
  <https://community.qobuz.com/press-en/qobuz-connect-celebrates-over-100-partners>
- StreamUnlimited StreamSDK:
  <https://www.streamunlimited.com/qobuz-connect-now-available-via-streamsdk/>
- Google Play, Device and Network Abuse:
  <https://support.google.com/googleplay/android-developer/answer/16559646>
