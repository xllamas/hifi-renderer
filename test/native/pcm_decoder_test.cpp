// Host tests for PcmDecoder: feeds crafted streams through it and checks the
// samples that come out. Built and run by ./run.sh, not by the app build.
//
// Worth having off-device because the failure this guards against is silent.
// L16, L24 and AIFF are big-endian, WAV and AIFC's 'sowt' are little-endian,
// and 8-bit is unsigned in WAV and signed in AIFF -- read any of those the
// wrong way round and the decoder happily produces full-scale noise, which is
// not something to discover through a pair of speakers.
#include "NetworkStream.h"
#include "decode/PcmDecoder.h"

#include <cstdio>
#include <cstring>
#include <string>
#include <thread>
#include <vector>

static int failures = 0;

static void check(bool ok, const std::string &what) {
    printf("%s  %s\n", ok ? "PASS" : "FAIL", what.c_str());
    if (!ok) failures++;
}

/** Runs bytes through the decoder and returns every frame it produced. */
static bool decodeAll(const std::vector<uint8_t> &in, std::vector<int32_t> *out,
                      PcmDecoder *dec, std::string *error) {
    NetworkStream stream;
    std::thread producer([&] {
        stream.write(in.data(), in.size());
        stream.setEof();
    });
    bool ok = dec->open(&stream, error);
    if (ok) {
        std::vector<int32_t> buf(4096 * 8);
        for (;;) {
            uint64_t got = dec->read(buf.data(), 128);
            if (got == 0) break;
            out->insert(out->end(), buf.begin(),
                        buf.begin() + got * dec->channels());
        }
    }
    stream.close();
    producer.join();
    return ok;
}

static void be16(std::vector<uint8_t> &v, int16_t s) {
    v.push_back(static_cast<uint8_t>((s >> 8) & 0xFF));
    v.push_back(static_cast<uint8_t>(s & 0xFF));
}
static void le16v(std::vector<uint8_t> &v, uint16_t s) {
    v.push_back(static_cast<uint8_t>(s & 0xFF));
    v.push_back(static_cast<uint8_t>((s >> 8) & 0xFF));
}
static void le32v(std::vector<uint8_t> &v, uint32_t s) {
    for (int i = 0; i < 4; i++) v.push_back(static_cast<uint8_t>((s >> (8 * i)) & 0xFF));
}
static void tag(std::vector<uint8_t> &v, const char *t) {
    v.insert(v.end(), t, t + 4);
}

static void be16v(std::vector<uint8_t> &v, uint16_t s) {
    v.push_back(static_cast<uint8_t>((s >> 8) & 0xFF));
    v.push_back(static_cast<uint8_t>(s & 0xFF));
}
static void be32v(std::vector<uint8_t> &v, uint32_t s) {
    for (int i = 3; i >= 0; i--) v.push_back(static_cast<uint8_t>((s >> (8 * i)) & 0xFF));
}
/** An 80-bit IEEE extended float holding an integral sample rate. */
static void extended(std::vector<uint8_t> &v, uint32_t rate) {
    int exponent = 16383 + 63;
    uint64_t mantissa = rate;
    while (mantissa != 0 && (mantissa & (1ULL << 63)) == 0) { mantissa <<= 1; exponent--; }
    be16v(v, static_cast<uint16_t>(exponent));
    for (int i = 7; i >= 0; i--) v.push_back(static_cast<uint8_t>((mantissa >> (8 * i)) & 0xFF));
}

int main() {
    // --- L16: big-endian, rate and channels from the MIME type only.
    {
        std::vector<uint8_t> in;
        const int16_t want[] = {0, 1, -1, 32767, -32768, 256};
        for (int16_t s : want) be16(in, s);
        PcmDecoder dec("audio/L16;rate=44100;channels=2");
        std::vector<int32_t> out; std::string err;
        bool ok = decodeAll(in, &out, &dec, &err);
        check(ok, "L16 opens: " + err);
        check(dec.sampleRate() == 44100, "L16 rate from MIME is 44100");
        check(dec.channels() == 2, "L16 channels from MIME is 2");
        check(dec.bitsPerSample() == 16, "L16 is 16-bit");
        check(out.size() == 6, "L16 produced 6 samples");
        bool values = out.size() == 6;
        for (size_t i = 0; values && i < 6; i++)
            values = out[i] == (static_cast<int32_t>(want[i]) << 16);
        check(values, "L16 samples are left-justified and correctly signed");
    }

    // The byte order that matters: 0x0100 read little-endian would be 0x0001.
    {
        std::vector<uint8_t> in = {0x01, 0x00, 0x01, 0x00};
        PcmDecoder dec("audio/L16;rate=48000;channels=2");
        std::vector<int32_t> out; std::string err;
        decodeAll(in, &out, &dec, &err);
        check(out.size() == 2 && out[0] == (256 << 16), "L16 is read big-endian");
        check(dec.sampleRate() == 48000, "L16 rate 48000 parsed");
    }

    // "rate" must not be matched inside "bitrate".
    {
        PcmDecoder dec("audio/L16;bitrate=176400;rate=88200;channels=2");
        std::vector<uint8_t> in = {0, 0, 0, 0};
        std::vector<int32_t> out; std::string err;
        decodeAll(in, &out, &dec, &err);
        check(dec.sampleRate() == 88200, "rate is not matched inside bitrate");
    }

    // --- L24: 24-bit big-endian.
    {
        std::vector<uint8_t> in = {0x12, 0x34, 0x56, 0xFF, 0xFF, 0xFF};
        PcmDecoder dec("audio/L24;rate=96000;channels=2");
        std::vector<int32_t> out; std::string err;
        decodeAll(in, &out, &dec, &err);
        check(dec.bitsPerSample() == 24 && dec.sampleRate() == 96000, "L24 is 24-bit at 96 kHz");
        check(out.size() == 2 && out[0] == 0x12345600 && out[1] == -256,
              "L24 samples are left-justified big-endian");
    }

    // --- WAV under an L16 content type: the header must not be played.
    {
        std::vector<uint8_t> in;
        tag(in, "RIFF"); le32v(in, 0xFFFFFFFF); tag(in, "WAVE");
        tag(in, "LIST"); le32v(in, 5); in.insert(in.end(), {'I','N','F','O','x'}); in.push_back(0);
        tag(in, "fmt "); le32v(in, 16);
        le16v(in, 1); le16v(in, 2); le32v(in, 44100); le32v(in, 176400);
        le16v(in, 4); le16v(in, 16);
        tag(in, "data"); le32v(in, 0xFFFFFFFF);
        const int16_t want[] = {0, 1, -1, 256};
        for (int16_t s : want) le16v(in, static_cast<uint16_t>(s));

        PcmDecoder dec("audio/L16;rate=8000;channels=1");
        std::vector<int32_t> out; std::string err;
        bool ok = decodeAll(in, &out, &dec, &err);
        check(ok, "WAV opens: " + err);
        check(dec.sampleRate() == 44100 && dec.channels() == 2,
              "WAV header overrides the MIME type");
        check(out.size() == 4, "WAV produced 4 samples, no header bytes");
        bool values = out.size() == 4;
        for (size_t i = 0; values && i < 4; i++)
            values = out[i] == (static_cast<int32_t>(want[i]) << 16);
        check(values, "WAV samples are read little-endian");
    }

    // --- 24-bit WAV.
    {
        std::vector<uint8_t> in;
        tag(in, "RIFF"); le32v(in, 0); tag(in, "WAVE");
        tag(in, "fmt "); le32v(in, 16);
        le16v(in, 1); le16v(in, 2); le32v(in, 192000); le32v(in, 0);
        le16v(in, 6); le16v(in, 24);
        tag(in, "data"); le32v(in, 6);
        in.insert(in.end(), {0x00, 0x56, 0x34, 0x00, 0x00, 0xFF});
        PcmDecoder dec("audio/wav");
        std::vector<int32_t> out; std::string err;
        decodeAll(in, &out, &dec, &err);
        check(dec.bitsPerSample() == 24 && dec.sampleRate() == 192000, "24-bit WAV at 192 kHz");
        check(out.size() == 2 && out[0] == 0x34560000 && out[1] == -16777216,
              "24-bit WAV samples are little-endian");
    }

    // --- 8-bit WAV is unsigned and widened to a 16-bit container.
    {
        std::vector<uint8_t> in;
        tag(in, "RIFF"); le32v(in, 0); tag(in, "WAVE");
        tag(in, "fmt "); le32v(in, 16);
        le16v(in, 1); le16v(in, 1); le32v(in, 22050); le32v(in, 0);
        le16v(in, 1); le16v(in, 8);
        tag(in, "data"); le32v(in, 3);
        in.insert(in.end(), {128, 0, 255});
        PcmDecoder dec("audio/wav");
        std::vector<int32_t> out; std::string err;
        decodeAll(in, &out, &dec, &err);
        check(dec.bitsPerSample() == 16, "8-bit WAV reports a 16-bit container");
        check(out.size() == 3 && out[0] == 0 && out[1] == static_cast<int32_t>(0x80000000) &&
              out[2] == 0x7F000000, "8-bit WAV is converted from unsigned");
    }

    // --- A stream that ends mid-frame must not shift the channels.
    {
        std::vector<uint8_t> in = {0x00, 0x10, 0x00, 0x20, 0x00};   // 2.5 frames of 16/1ch
        PcmDecoder dec("audio/L16;rate=44100;channels=1");
        std::vector<int32_t> out; std::string err;
        decodeAll(in, &out, &dec, &err);
        check(out.size() == 2 && out[0] == 0x00100000 && out[1] == 0x00200000,
              "a trailing partial frame is dropped, not misaligned");
    }

    // --- Float WAV is refused rather than played as noise.
    {
        std::vector<uint8_t> in;
        tag(in, "RIFF"); le32v(in, 0); tag(in, "WAVE");
        tag(in, "fmt "); le32v(in, 16);
        le16v(in, 3); le16v(in, 2); le32v(in, 44100); le32v(in, 0);
        le16v(in, 8); le16v(in, 32);
        tag(in, "data"); le32v(in, 0);
        PcmDecoder dec("audio/wav");
        std::vector<int32_t> out; std::string err;
        bool ok = decodeAll(in, &out, &dec, &err);
        check(!ok && err.find("not integer PCM") != std::string::npos,
              "float WAV is refused: " + err);
    }

    // --- AIFF: big-endian PCM behind a FORM chunk list.
    {
        std::vector<uint8_t> in;
        tag(in, "FORM"); be32v(in, 0); tag(in, "AIFF");
        tag(in, "NAME"); be32v(in, 5);
        in.insert(in.end(), {'H','e','l','l','o'}); in.push_back(0);   // odd size, pad byte
        tag(in, "COMM"); be32v(in, 18);
        be16v(in, 2); be32v(in, 3); be16v(in, 16); extended(in, 44100);
        tag(in, "SSND"); be32v(in, 0);
        be32v(in, 0); be32v(in, 0);   // offset, blockSize
        const int16_t want[] = {0, 1, -1, 256, 32767, -32768};
        for (int16_t x : want) be16v(in, static_cast<uint16_t>(x));

        PcmDecoder dec("audio/x-aiff");
        std::vector<int32_t> out; std::string err;
        bool ok = decodeAll(in, &out, &dec, &err);
        check(ok, "AIFF opens: " + err);
        check(dec.sampleRate() == 44100, "AIFF rate from the 80-bit extended float");
        check(dec.channels() == 2 && dec.bitsPerSample() == 16, "AIFF is 16-bit stereo");
        check(out.size() == 6, "AIFF produced 6 samples, no header or metadata bytes");
        bool values = out.size() == 6;
        for (size_t i = 0; values && i < 6; i++)
            values = out[i] == (static_cast<int32_t>(want[i]) << 16);
        check(values, "AIFF samples are read big-endian");
    }

    // The SSND offset is padding, not audio.
    {
        std::vector<uint8_t> in;
        tag(in, "FORM"); be32v(in, 0); tag(in, "AIFF");
        tag(in, "COMM"); be32v(in, 18);
        be16v(in, 1); be32v(in, 1); be16v(in, 16); extended(in, 96000);
        tag(in, "SSND"); be32v(in, 0);
        be32v(in, 4); be32v(in, 0);            // 4 bytes of alignment padding
        in.insert(in.end(), {0xDE, 0xAD, 0xBE, 0xEF});
        be16v(in, 0x1234);
        PcmDecoder dec("audio/aiff");
        std::vector<int32_t> out; std::string err;
        decodeAll(in, &out, &dec, &err);
        check(dec.sampleRate() == 96000, "AIFF at 96 kHz");
        check(out.size() == 1 && out[0] == 0x12340000, "the SSND offset is skipped, not played");
    }

    // --- 24-bit AIFF.
    {
        std::vector<uint8_t> in;
        tag(in, "FORM"); be32v(in, 0); tag(in, "AIFF");
        tag(in, "COMM"); be32v(in, 18);
        be16v(in, 2); be32v(in, 1); be16v(in, 24); extended(in, 192000);
        tag(in, "SSND"); be32v(in, 0); be32v(in, 0); be32v(in, 0);
        in.insert(in.end(), {0x12, 0x34, 0x56, 0xFF, 0xFF, 0xFF});
        PcmDecoder dec("audio/x-aiff");
        std::vector<int32_t> out; std::string err;
        decodeAll(in, &out, &dec, &err);
        check(dec.bitsPerSample() == 24 && dec.sampleRate() == 192000, "24-bit AIFF at 192 kHz");
        check(out.size() == 2 && out[0] == 0x12345600 && out[1] == -256,
              "24-bit AIFF samples are left-justified big-endian");
    }

    // --- 8-bit AIFF is signed, where 8-bit WAV is not.
    {
        std::vector<uint8_t> in;
        tag(in, "FORM"); be32v(in, 0); tag(in, "AIFF");
        tag(in, "COMM"); be32v(in, 18);
        be16v(in, 1); be32v(in, 3); be16v(in, 8); extended(in, 22050);
        tag(in, "SSND"); be32v(in, 0); be32v(in, 0); be32v(in, 0);
        in.insert(in.end(), {0x00, 0x80, 0x7F});
        PcmDecoder dec("audio/x-aiff");
        std::vector<int32_t> out; std::string err;
        decodeAll(in, &out, &dec, &err);
        check(dec.bitsPerSample() == 16, "8-bit AIFF reports a 16-bit container");
        check(out.size() == 3 && out[0] == 0 &&
              out[1] == static_cast<int32_t>(0x80000000) && out[2] == 0x7F000000,
              "8-bit AIFF is read as signed");
    }

    // --- AIFC 'sowt' is byte-swapped despite its big-endian container.
    {
        std::vector<uint8_t> in;
        tag(in, "FORM"); be32v(in, 0); tag(in, "AIFC");
        tag(in, "COMM"); be32v(in, 24);
        be16v(in, 1); be32v(in, 2); be16v(in, 16); extended(in, 48000);
        tag(in, "sowt"); be16v(in, 0);          // compression type + empty pstring
        tag(in, "SSND"); be32v(in, 0); be32v(in, 0); be32v(in, 0);
        in.insert(in.end(), {0x00, 0x01, 0x00, 0xFF});   // little-endian 256, -256
        PcmDecoder dec("audio/x-aiff");
        std::vector<int32_t> out; std::string err;
        bool ok = decodeAll(in, &out, &dec, &err);
        check(ok, "AIFC/sowt opens: " + err);
        check(out.size() == 2 && out[0] == (256 << 16) && out[1] == -(256 << 16),
              "AIFC 'sowt' is read little-endian");
    }

    // --- AIFC 'NONE' stays big-endian.
    {
        std::vector<uint8_t> in;
        tag(in, "FORM"); be32v(in, 0); tag(in, "AIFC");
        tag(in, "COMM"); be32v(in, 24);
        be16v(in, 1); be32v(in, 1); be16v(in, 16); extended(in, 44100);
        tag(in, "NONE"); be16v(in, 0);
        tag(in, "SSND"); be32v(in, 0); be32v(in, 0); be32v(in, 0);
        in.insert(in.end(), {0x01, 0x00});
        PcmDecoder dec("audio/x-aiff");
        std::vector<int32_t> out; std::string err;
        decodeAll(in, &out, &dec, &err);
        check(out.size() == 1 && out[0] == (256 << 16), "AIFC 'NONE' stays big-endian");
    }

    // --- A real codec in an AIFC is refused, not played as noise.
    {
        std::vector<uint8_t> in;
        tag(in, "FORM"); be32v(in, 0); tag(in, "AIFC");
        tag(in, "COMM"); be32v(in, 24);
        be16v(in, 2); be32v(in, 1); be16v(in, 16); extended(in, 44100);
        tag(in, "QDMC"); be16v(in, 0);
        tag(in, "SSND"); be32v(in, 0); be32v(in, 0); be32v(in, 0);
        PcmDecoder dec("audio/x-aiff");
        std::vector<int32_t> out; std::string err;
        bool ok = decodeAll(in, &out, &dec, &err);
        check(!ok && err.find("QDMC") != std::string::npos,
              "a compressed AIFC is refused: " + err);
    }

    // --- An AIFF with no COMM before its SSND is refused rather than guessed.
    {
        std::vector<uint8_t> in;
        tag(in, "FORM"); be32v(in, 0); tag(in, "AIFF");
        tag(in, "SSND"); be32v(in, 8); be32v(in, 0); be32v(in, 0);
        PcmDecoder dec("audio/x-aiff");
        std::vector<int32_t> out; std::string err;
        bool ok = decodeAll(in, &out, &dec, &err);
        check(!ok && err.find("before its format") != std::string::npos,
              "AIFF without a COMM is refused: " + err);
    }


    printf("\n%s\n", failures == 0 ? "all checks passed" : "FAILURES");
    return failures != 0;
}
