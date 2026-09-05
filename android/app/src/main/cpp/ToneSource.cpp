#include "ToneSource.h"

#include <algorithm>
#include <cmath>

void ToneSource::build(uint32_t rate, int approxHz, int channels, double amplitude) {
    samples_.clear();
    pos_ = 0;
    channels_ = channels;
    framesPerCycle_ = 0;
    hz_ = 0;
    if (rate == 0 || approxHz <= 0 || channels <= 0) return;

    // Frames per cycle first, rounded to an integer; the frequency is whatever
    // that turns out to mean. Two frames is the floor -- a cycle cannot be
    // shorter than its own Nyquist.
    framesPerCycle_ = std::max(2u, static_cast<uint32_t>(
        (rate + static_cast<uint32_t>(approxHz) / 2) / static_cast<uint32_t>(approxHz)));
    hz_ = static_cast<double>(rate) / framesPerCycle_;

    // Enough whole cycles to make the feeder's work per wrap negligible. Any
    // whole number would loop cleanly; this one just does it less often.
    uint32_t frames = framesPerCycle_;
    while (frames < 8192) frames += framesPerCycle_;

    samples_.resize(static_cast<size_t>(frames) * channels);
    for (uint32_t f = 0; f < frames; f++) {
        const double phase =
            2.0 * M_PI * static_cast<double>(f % framesPerCycle_) / framesPerCycle_;
        const auto v = static_cast<int32_t>(amplitude * std::sin(phase));
        for (int c = 0; c < channels; c++) {
            samples_[static_cast<size_t>(f) * channels + c] = v;
        }
    }
}

void ToneSource::read(int32_t *out, size_t frames) {
    const size_t total = this->frames();
    if (total == 0) return;
    for (size_t f = 0; f < frames; f++) {
        for (int c = 0; c < channels_; c++) {
            out[f * channels_ + c] = samples_[pos_ * channels_ + c];
        }
        if (++pos_ >= total) pos_ = 0;
    }
}
