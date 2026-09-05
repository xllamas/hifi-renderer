#pragma once

#include <cstdint>
#include <vector>

/**
 * A looping test tone, for the DAC rate sweep.
 *
 * A file cannot serve the sweep: the point is to test every rate the DAC
 * advertises, including ones no music exists at -- 705.6 and 768 kHz on the
 * AL400 -- and making the user find material at each would fail exactly where
 * the feature is most needed.
 *
 * The one property that matters is that the buffer loops without a click. A
 * click is indistinguishable from the dropout the sweep exists to detect, so it
 * would not merely look untidy: it would make the test lie. That is why the
 * frequency follows from the rate rather than the other way round.
 */
class ToneSource {
public:
    /**
     * Builds a whole number of cycles of a sine near [approxHz].
     *
     * [approxHz] is a target, not a promise. The period is rounded to a whole
     * number of frames and the frequency recomputed from it, so the buffer ends
     * exactly where it began and wrapping is phase-continuous.
     *
     * Samples are left-justified in 32 bits, the convention everything on the
     * playback path shares.
     */
    void build(uint32_t rate, int approxHz, int channels, double amplitude);

    /** Fills [out] with [frames] interleaved frames, wrapping as needed. */
    void read(int32_t *out, size_t frames);

    void rewind() { pos_ = 0; }

    /** Frames in one cycle; the buffer is an exact multiple of this. */
    uint32_t framesPerCycle() const { return framesPerCycle_; }
    /** The frequency actually produced, which is rate / framesPerCycle. */
    double toneHz() const { return hz_; }
    size_t frames() const {
        return channels_ > 0 ? samples_.size() / static_cast<size_t>(channels_) : 0;
    }
    bool empty() const { return samples_.empty(); }

private:
    std::vector<int32_t> samples_;
    size_t pos_ = 0;
    int channels_ = 0;
    uint32_t framesPerCycle_ = 0;
    double hz_ = 0;
};
