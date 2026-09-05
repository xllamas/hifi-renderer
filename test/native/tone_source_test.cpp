// Host tests for ToneSource. Built and run by ./run.sh.
//
// The property under test is that the buffer loops without a discontinuity.
// A click at the loop point would be indistinguishable from the dropout the
// rate sweep exists to detect -- so getting this wrong would not make the test
// look untidy, it would make the test lie.
#include "ToneSource.h"

#include <cmath>
#include <cstdio>
#include <string>
#include <vector>

static int failures = 0;

static void check(bool ok, const std::string &what) {
    printf("%s  %s\n", ok ? "PASS" : "FAIL", what.c_str());
    if (!ok) failures++;
}

/** The largest jump between neighbouring frames anywhere in one wrap. */
static double largestStep(ToneSource &t, int channels) {
    const size_t frames = t.frames();
    std::vector<int32_t> buf((frames + 1) * channels);
    t.rewind();
    t.read(buf.data(), frames + 1);   // one extra frame, i.e. past the wrap
    double worst = 0;
    for (size_t f = 1; f <= frames; f++) {
        const double step =
            std::fabs(static_cast<double>(buf[f * channels]) -
                      static_cast<double>(buf[(f - 1) * channels]));
        if (step > worst) worst = step;
    }
    return worst;
}

int main() {
    constexpr double kAmp = 0.1 * 2147483647.0;

    // --- The period divides the rate exactly, at every rate a DAC may claim.
    for (uint32_t rate : {44100u, 48000u, 88200u, 96000u, 176400u, 192000u,
                          352800u, 384000u, 705600u, 768000u}) {
        ToneSource t;
        t.build(rate, 1000, 2, kAmp);
        const bool wholeCycles = t.frames() % t.framesPerCycle() == 0;
        const bool nearTarget = std::fabs(t.toneHz() - 1000.0) < 30.0;
        check(!t.empty() && wholeCycles && nearTarget,
              "at " + std::to_string(rate) + " Hz the buffer is whole cycles of " +
                  std::to_string(t.toneHz()) + " Hz");
    }

    // --- Wrapping is continuous: the step across the loop point is no larger
    // than the steps inside the waveform.
    {
        ToneSource t;
        t.build(44100, 1000, 2, kAmp);
        const double worst = largestStep(t, 2);
        // One frame of a 1 kHz sine at 44.1 kHz moves at most ~14% of peak.
        const double perFrame = kAmp * 2 * M_PI * t.toneHz() / 44100.0;
        check(worst <= perFrame * 1.2,
              "the loop point is phase-continuous (worst step " +
                  std::to_string(worst) + " vs " + std::to_string(perFrame) +
                  " per frame)");
    }

    // --- Reading far past the end keeps wrapping rather than running off it.
    {
        ToneSource t;
        t.build(48000, 1000, 2, kAmp);
        const size_t want = t.frames() * 3 + 7;
        std::vector<int32_t> buf(want * 2);
        t.read(buf.data(), want);
        bool nonZero = false, inRange = true;
        for (int32_t v : buf) {
            if (v != 0) nonZero = true;
            if (std::fabs(static_cast<double>(v)) > kAmp * 1.01) inRange = false;
        }
        check(nonZero && inRange, "reading three times round stays in range");
    }

    // --- Both channels carry the same sample, so a swapped pair is visible.
    {
        ToneSource t;
        t.build(96000, 1000, 2, kAmp);
        std::vector<int32_t> buf(64 * 2);
        t.read(buf.data(), 64);
        bool matched = true;
        for (int f = 0; f < 64; f++) matched &= buf[f * 2] == buf[f * 2 + 1];
        check(matched, "both channels carry the same sample");
    }

    // --- Amplitude is honoured, and never clips.
    {
        ToneSource t;
        t.build(44100, 1000, 2, kAmp);
        std::vector<int32_t> buf(t.frames() * 2);
        t.rewind();
        t.read(buf.data(), t.frames());
        double peak = 0;
        for (int32_t v : buf) peak = std::max(peak, std::fabs(static_cast<double>(v)));
        // A whole cycle at 44 frames does not land exactly on the peak, so
        // allow the sampling gap; what matters is that it is near and under.
        check(peak <= kAmp && peak > kAmp * 0.99,
              "peak sits just under the requested amplitude");
    }

    // --- Nonsense parameters produce nothing rather than a division by zero.
    {
        ToneSource a, b, c;
        a.build(0, 1000, 2, kAmp);
        b.build(44100, 0, 2, kAmp);
        c.build(44100, 1000, 0, kAmp);
        check(a.empty() && b.empty() && c.empty(),
              "a zero rate, frequency or channel count yields no tone");
    }

    // --- A frequency above Nyquist cannot make a cycle shorter than 2 frames.
    {
        ToneSource t;
        t.build(44100, 40000, 2, kAmp);
        check(t.framesPerCycle() >= 2, "the cycle never falls below two frames");
    }

    printf("\n%s\n", failures == 0 ? "all checks passed" : "FAILURES");
    return failures != 0;
}
