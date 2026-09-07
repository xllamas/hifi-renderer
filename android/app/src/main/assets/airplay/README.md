The RAOP private key belongs here, as `raop_key.pkcs8` (unencrypted PKCS#8
DER), and is deliberately not committed. See doc/airplay.md for what it is,
why it is kept out of the repository, and the one openssl command that converts
shairport-sync's PEM copy into this form.

Without it the renderer still advertises and still answers RTSP, and declines
every challenge -- which is the honest behaviour for a receiver that cannot
prove it is an AirPort Express, and enough to test discovery and framing.
