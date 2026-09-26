// Host tests for DsdDecoder: feeds hand-built DSF and DFF streams through it
// and checks the DoP frames that come out, byte for byte.
//
// Worth having off-device because every mistake here is silent. A DSF read in
// the wrong bit order, a marker that restarts at a block boundary, or a chunk
// size read as 32 bits all yield a stream that decodes without complaint and
// plays as noise -- or, for the marker, drops the DAC out of DSD mode.
#include "NetworkStream.h"
#include "decode/DsdDecoder.h"

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

typedef std::vector<uint8_t> Bytes;

static bool decodeAll(const Bytes &in, std::vector<int32_t> *out, DsdDecoder *dec,
                      std::string *error, uint64_t chunk = 128) {
    NetworkStream stream;
    std::thread producer([&] {
        stream.write(in.data(), in.size());
        stream.setEof();
    });
    bool ok = dec->open(&stream, error);
    if (ok) {
        std::vector<int32_t> buf(chunk * 8);
        for (;;) {
            uint64_t got = dec->read(buf.data(), chunk);
            if (got == 0) break;
            out->insert(out->end(), buf.begin(), buf.begin() + got * dec->channels());
        }
    }
    stream.close();
    producer.join();
    return ok;
}

static void tag(Bytes &v, const char *t) { v.insert(v.end(), t, t + 4); }
static void le32(Bytes &v, uint32_t s) { for (int i = 0; i < 4; i++) v.push_back((s >> (8 * i)) & 0xFF); }
static void le64(Bytes &v, uint64_t s) { for (int i = 0; i < 8; i++) v.push_back((s >> (8 * i)) & 0xFF); }
static void be16(Bytes &v, uint16_t s) { v.push_back(s >> 8); v.push_back(s & 0xFF); }
static void be32(Bytes &v, uint32_t s) { for (int i = 3; i >= 0; i--) v.push_back((s >> (8 * i)) & 0xFF); }
static void be64(Bytes &v, uint64_t s) { for (int i = 7; i >= 0; i--) v.push_back((s >> (8 * i)) & 0xFF); }

static uint8_t rev(uint8_t b) {
    uint8_t r = 0;
    for (int i = 0; i < 8; i++) if (b & (1 << i)) r |= 1 << (7 - i);
    return r;
}

/** A DSF whose per-channel audio is [audio] (channel-major), block size [block]. */
static Bytes dsf(const std::vector<Bytes> &audio, uint32_t rate, uint32_t order,
                 uint32_t block, uint64_t sampleBits, bool padLast = true) {
    const size_t channels = audio.size();
    Bytes body;
    const size_t groups = (audio[0].size() + block - 1) / block;
    for (size_t g = 0; g < groups; g++) {
        for (size_t ch = 0; ch < channels; ch++) {
            for (size_t i = 0; i < block; i++) {
                const size_t at = g * block + i;
                body.push_back(at < audio[ch].size() ? audio[ch][at] : (padLast ? 0x69 : 0));
            }
        }
    }
    Bytes v;
    tag(v, "DSD "); le64(v, 28); le64(v, 0); le64(v, 0);
    tag(v, "fmt "); le64(v, 52);
    le32(v, 1); le32(v, 0); le32(v, 2); le32(v, static_cast<uint32_t>(channels));
    le32(v, rate); le32(v, order); le64(v, sampleBits); le32(v, block); le32(v, 0);
    tag(v, "data"); le64(v, 12 + body.size());
    v.insert(v.end(), body.begin(), body.end());
    return v;
}

static void sub(Bytes &v, const char *id, const Bytes &body) {
    tag(v, id); be64(v, body.size());
    v.insert(v.end(), body.begin(), body.end());
    if (body.size() & 1) v.push_back(0);
}

/** A DFF with audio interleaved one byte per channel. */
static Bytes dff(const std::vector<Bytes> &audio, uint32_t rate, const char *cmpr = "DSD ",
                 const char *dataId = "DSD ", bool sizeZero = false) {
    Bytes fs; be32(fs, rate);
    Bytes chnl; be16(chnl, static_cast<uint16_t>(audio.size()));
    for (size_t i = 0; i < audio.size(); i++) tag(chnl, i == 0 ? "SLFT" : "SRGT");
    Bytes cm; tag(cm, cmpr); cm.push_back(14); const char *nm = "not compressed";
    cm.insert(cm.end(), nm, nm + 14);
    Bytes prop; tag(prop, "SND ");
    sub(prop, "FS  ", fs); sub(prop, "CHNL", chnl); sub(prop, "CMPR", cm);
    Bytes data;
    for (size_t i = 0; i < audio[0].size(); i++)
        for (size_t ch = 0; ch < audio.size(); ch++) data.push_back(audio[ch][i]);

    Bytes ver; be32(ver, 0x01050000);
    Bytes body; tag(body, "DSD ");
    sub(body, "FVER", ver); sub(body, "PROP", prop);
    tag(body, dataId); be64(body, sizeZero ? 0 : data.size());
    body.insert(body.end(), data.begin(), data.end());
    Bytes v; tag(v, "FRM8"); be64(v, body.size());
    v.insert(v.end(), body.begin(), body.end());
    return v;
}

static int32_t dop(uint8_t marker, uint8_t a, uint8_t b) {
    return static_cast<int32_t>((uint32_t(marker) << 24) | (uint32_t(a) << 16) | (uint32_t(b) << 8));
}

int main() {
    const uint32_t DSD64 = 2822400;

    // --- DFF stereo: MSB-first already, byte-interleaved, marker alternates.
    {
        Bytes l = {0x11, 0x22, 0x33, 0x44}, r = {0xA1, 0xA2, 0xA3, 0xA4};
        DsdDecoder d; std::vector<int32_t> out; std::string err;
        bool ok = decodeAll(dff({l, r}, DSD64), &out, &d, &err);
        check(ok, "DFF opens: " + err);
        check(d.sampleRate() == 176400 && d.channels() == 2 && d.bitsPerSample() == 24,
              "DFF DSD64 reports 176400 Hz, 2 ch, 24-bit");
        check(out.size() == 4 && out[0] == dop(0x05, 0x11, 0x22) && out[1] == dop(0x05, 0xA1, 0xA2) &&
              out[2] == dop(0xFA, 0x33, 0x44) && out[3] == dop(0xFA, 0xA3, 0xA4),
              "DFF frames: older byte above newer, one marker per frame, channels share it");
    }

    // --- DSF: LSB-first is reversed, MSB-first is left alone.
    {
        Bytes l = {0x01, 0x80}, r = {0x0F, 0xF0};
        std::vector<int32_t> out; std::string err; DsdDecoder d;
        bool ok = decodeAll(dsf({l, r}, DSD64, 1, 4096, 16), &out, &d, &err);
        check(ok && out.size() == 2, "DSF LSB-first opens and stops at the sample count: " + err);
        check(out.size() == 2 && out[0] == dop(0x05, rev(0x01), rev(0x80)) &&
              out[1] == dop(0x05, rev(0x0F), rev(0xF0)),
              "DSF LSB-first bytes are bit-reversed");
        std::vector<int32_t> out2; DsdDecoder d2;
        decodeAll(dsf({l, r}, DSD64, 8, 4096, 16), &out2, &d2, &err);
        check(out2.size() == 2 && out2[0] == dop(0x05, 0x01, 0x80) && out2[1] == dop(0x05, 0x0F, 0xF0),
              "DSF MSB-first bytes pass through unchanged");
    }

    // --- DSF block interleave and marker phase across block boundaries.
    {
        const uint32_t block = 8;   // small, so several groups fit in a test
        Bytes l, r;
        for (int i = 0; i < 20; i++) { l.push_back(i); r.push_back(0x80 + i); }
        std::vector<int32_t> out; std::string err; DsdDecoder d;
        // Read one frame at a time to prove phase is state, not per-call.
        bool ok = decodeAll(dsf({l, r}, DSD64, 8, block, 20 * 8), &out, &d, &err, 1);
        bool good = ok && out.size() == 20;   // 10 frames x 2 ch
        for (int f = 0; good && f < 10; f++) {
            uint8_t m = (f % 2) ? 0xFA : 0x05;
            good = out[f * 2] == dop(m, l[f * 2], l[f * 2 + 1]) &&
                   out[f * 2 + 1] == dop(m, r[f * 2], r[f * 2 + 1]);
        }
        check(good, "DSF block-interleaved audio, marker unbroken across block groups and 1-frame reads");
    }

    // --- The padding after the sample count is never played; an odd byte count is paired with idle.
    {
        Bytes l = {1, 2, 3}, r = {4, 5, 6};   // 3 bytes each: 24 samples
        std::vector<int32_t> out; std::string err; DsdDecoder d;
        decodeAll(dsf({l, r}, DSD64, 8, 4096, 24), &out, &d, &err);
        check(out.size() == 4 && out[2] == dop(0xFA, 3, 0x69) && out[3] == dop(0xFA, 6, 0x69),
              "odd trailing byte is finished with DSD idle pattern, nothing after it plays");
    }

    // --- Marker phase carries into the next track.
    {
        Bytes a = {1, 2, 3, 4, 5, 6}, b = {1, 2, 3, 4, 5, 6};   // 3 frames
        std::vector<int32_t> out; std::string err; DsdDecoder d;
        decodeAll(dff({a, b}, DSD64), &out, &d, &err);
        check(d.markerPhase() == 1, "after an odd number of frames the next marker is 0xFA");
        std::vector<int32_t> out2; DsdDecoder d2(d.markerPhase());
        decodeAll(dff({a, b}, DSD64), &out2, &d2, &err);
        check(out2.size() == 6 && (out2[0] >> 24 & 0xFF) == 0xFA,
              "a following track starts on the marker the last one owed");
    }

    // --- Rates.
    {
        Bytes a = {1, 2}, b = {1, 2}; std::string err;
        DsdDecoder d128; std::vector<int32_t> o;
        decodeAll(dff({a, b}, DSD64 * 2), &o, &d128, &err);
        check(d128.sampleRate() == 352800, "DSD128 is 352800 Hz DoP");
        DsdDecoder d256; o.clear();
        decodeAll(dff({a, b}, DSD64 * 4), &o, &d256, &err);
        check(d256.sampleRate() == 705600, "DSD256 is 705600 Hz DoP");
    }

    // --- DFF: 64-bit sizes and zero-size streaming data.
    {
        Bytes a = {1, 2, 3, 4}, b = {5, 6, 7, 8};
        std::vector<int32_t> out; std::string err; DsdDecoder d;
        bool ok = decodeAll(dff({a, b}, DSD64, "DSD ", "DSD ", true), &out, &d, &err);
        check(ok && out.size() == 4, "DFF with a zero data size plays to end of stream: " + err);
    }

    // --- Refusals.
    {
        Bytes a = {1, 2}, b = {1, 2}; std::string err; std::vector<int32_t> o;
        DsdDecoder d1;
        check(!decodeAll(dff({a, b}, DSD64, "DST "), &o, &d1, &err) && err.find("DST") != std::string::npos,
              "DFF with CMPR 'DST ' is refused with a reason: " + err);
        DsdDecoder d2;
        check(!decodeAll(dff({a, b}, DSD64, "DSD ", "DST "), &o, &d2, &err) && err.find("DST") != std::string::npos,
              "DFF with a DST data chunk is refused: " + err);
        DsdDecoder d3;
        Bytes junk(64, 0x55);
        check(!decodeAll(junk, &o, &d3, &err), "a stream that is neither container is refused: " + err);
        DsdDecoder d4;
        check(!decodeAll(dsf({a, b}, DSD64, 4, 4096, 16), &o, &d4, &err),
              "DSF with a bit order that is neither 1 nor 8 is refused: " + err);
        DsdDecoder d5;
        check(!decodeAll(dsf({a, b}, 2822401, 8, 4096, 16), &o, &d5, &err),
              "a rate DoP cannot divide into is refused: " + err);
    }

    // --- Truncation fails cleanly rather than hanging or crashing.
    {
        Bytes a = {1, 2, 3, 4}, b = {1, 2, 3, 4};
        for (const Bytes &full : {dsf({a, b}, DSD64, 8, 4096, 32), dff({a, b}, DSD64)}) {
            for (size_t cut : {size_t(3), size_t(20), size_t(40), size_t(70)}) {
                Bytes t(full.begin(), full.begin() + std::min(cut, full.size() - 1));
                DsdDecoder d; std::vector<int32_t> o; std::string err;
                bool ok = decodeAll(t, &o, &d, &err);
                check(!ok || o.size() <= 4, "truncated at " + std::to_string(cut) + " bytes ends cleanly");
            }
        }
    }

    printf("\n%s\n", failures ? "FAILED" : "all passed");
    return failures ? 1 : 0;
}
