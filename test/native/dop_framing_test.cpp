// Host tests for DopFraming: the marker sequence a DAC in DSD mode depends on,
// through the idle frames the sink sends on pause, rebuffer and underrun.
//
// The failure is silent in the same way as everything else DSD: a marker that
// repeats or is skipped just makes the DAC leave DSD mode, heard as a click.
#include "usb/DopFraming.h"

#include <cstdio>
#include <string>
#include <vector>

static int failures = 0;

static void check(bool ok, const std::string &what) {
    printf("%s  %s\n", ok ? "PASS" : "FAIL", what.c_str());
    if (!ok) failures++;
}

typedef std::vector<uint8_t> Bytes;

/** One frame of 24-bit-in-4-byte stereo DoP: pad, older, newer, marker. */
static void frame4(Bytes &v, uint8_t marker, uint8_t a, uint8_t b) {
    for (int ch = 0; ch < 2; ch++) { v.push_back(0); v.push_back(b); v.push_back(a); v.push_back(marker); }
}

int main() {
    // --- Idle frames, 4-byte subslot, stereo: alternating markers, 0x69 payload.
    {
        DopFraming d; d.configure(2, 4);
        Bytes buf(4 * 8 * 3, 0xEE);
        d.idle(buf.data(), buf.size());
        bool ok = true;
        for (int f = 0; f < 3; f++) {
            const uint8_t m = f % 2 ? 0xFA : 0x05;
            for (int ch = 0; ch < 2; ch++) {
                const uint8_t *s = &buf[f * 8 + ch * 4];
                ok = ok && s[0] == 0 && s[1] == 0x69 && s[2] == 0x69 && s[3] == m;
            }
        }
        check(ok, "idle frames, 4-byte subslot: zero pad, 0x69 0x69, alternating marker");
    }

    // --- 3-byte subslot has no pad byte.
    {
        DopFraming d; d.configure(2, 3);
        Bytes buf(3 * 2 * 2, 0xEE);
        d.idle(buf.data(), buf.size());
        check(buf[0] == 0x69 && buf[1] == 0x69 && buf[2] == 0x05 && buf[3] == 0x69 &&
              buf[5] == 0x05 && buf[8] == 0xFA && buf[11] == 0xFA,
              "idle frames, 3-byte subslot: 0x69 0x69 marker, both channels share it");
    }

    // --- Re-stamping repairs a broken phase and leaves the payload alone.
    {
        DopFraming d; d.configure(2, 4);
        Bytes buf;
        frame4(buf, 0x05, 0x11, 0x22);
        frame4(buf, 0x05, 0x33, 0x44);   // wrong: repeated
        frame4(buf, 0xFA, 0x55, 0x66);   // wrong: should be 0x05
        d.restamp(buf.data(), buf.size());
        check(buf[3] == 0x05 && buf[8 + 3] == 0xFA && buf[16 + 3] == 0x05 && buf[16 + 7] == 0x05,
              "restamp makes the marker alternate whatever the decoder wrote");
        check(buf[1] == 0x22 && buf[2] == 0x11 && buf[8 + 1] == 0x44 && buf[8 + 2] == 0x33 &&
              buf[16 + 1] == 0x66 && buf[16 + 2] == 0x55 && buf[0] == 0,
              "restamp leaves every DSD byte and the pad byte untouched");
    }

    // --- The point: music, then a pause, then music. No marker breaks, for
    // any number of idle frames, odd or even.
    for (int idleFrames = 0; idleFrames < 6; idleFrames++) {
        DopFraming d; d.configure(2, 4);
        Bytes wire;
        Bytes a; frame4(a, 0x05, 1, 2); frame4(a, 0xFA, 3, 4); frame4(a, 0x05, 5, 6);
        d.restamp(a.data(), a.size()); wire.insert(wire.end(), a.begin(), a.end());
        Bytes gap(idleFrames * 8, 0);
        d.idle(gap.data(), gap.size()); wire.insert(wire.end(), gap.begin(), gap.end());
        // The decoder's own phase knows nothing of the gap: it carries on 0xFA.
        Bytes b; frame4(b, 0xFA, 7, 8); frame4(b, 0x05, 9, 10);
        d.restamp(b.data(), b.size()); wire.insert(wire.end(), b.begin(), b.end());
        bool ok = true;
        const size_t frames = wire.size() / 8;
        for (size_t f = 0; f < frames; f++) {
            const uint8_t want = f % 2 ? 0xFA : 0x05;
            ok = ok && wire[f * 8 + 3] == want && wire[f * 8 + 7] == want;
        }
        check(ok, "unbroken alternation across " + std::to_string(idleFrames) + " idle frame(s)");
    }

    // --- A packet that is not a whole number of frames never overruns.
    {
        DopFraming d; d.configure(2, 4);
        Bytes buf(8 + 5, 0xEE);
        d.idle(buf.data(), buf.size());
        check(buf[8] == 0 && buf[12] == 0, "a stray partial frame is zeroed, not left as garbage");
    }

    printf("\n%s\n", failures ? "FAILED" : "all passed");
    return failures ? 1 : 0;
}
