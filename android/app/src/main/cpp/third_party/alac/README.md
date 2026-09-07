Apple's reference ALAC decoder, from https://github.com/macosforge/alac
(`codec/`), unmodified. Apache License 2.0 -- see LICENSE.

Only the decoder is vendored; the encoder is not needed. `shift.h` is in the
upstream tree but referenced by nothing here, so it is not carried.

Vendored rather than using MediaCodec because this hardware has no ALAC
decoder: nothing in /vendor/etc/media_codecs*.xml offers `audio/alac`, checked
2026-09-07. Vendored rather than written because a decoder bug produces noise
rather than an error, and this one is the reference.
