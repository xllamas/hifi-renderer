#pragma once

#include <cstddef>
#include <cstdint>

/**
 * Owns the DoP marker sequence on the wire, so it stays unbroken whatever the
 * sink does between the decoder's frames.
 *
 * A DAC in DSD mode stays there only while the 0x05, 0xFA markers keep
 * alternating; one missed or doubled marker and it drops back to PCM, which
 * for a DSD stream is a burst of noise or, at best, a click. The decoder
 * stamps them correctly, but the sink interleaves its own frames -- silence on
 * pause, on a rebuffer and on an underrun -- and the ring resumes wherever it
 * left off, so the decoder's phase and the wire's drift apart by however many
 * idle frames went out in between. So the sink re-stamps the marker of every
 * frame it sends, decoded or idle, from one counter.
 *
 * Idle frames carry 0x69 in both DSD bytes, the DSD idle pattern, which a DAC
 * plays as silence without leaving DSD mode. PCM zeros -- what a paused PCM
 * stream sends -- are exactly what makes it leave.
 *
 * Frames are little-endian in [subslot] bytes per channel with the sample
 * left-justified, so the marker is each sample's last byte, the two DSD bytes
 * are the two before it, and any lower byte is zero padding.
 */
class DopFraming {
public:
    void configure(int channels, int subslot) {
        channels_ = channels;
        subslot_ = subslot;
        next_ = 0;
    }

    /** Re-stamps the marker of each whole frame in [buf], carrying on. */
    void restamp(uint8_t *buf, size_t bytes) {
        const size_t frame = frameBytes();
        if (frame == 0) return;
        for (size_t at = 0; at + frame <= bytes; at += frame) {
            const uint8_t marker = nextMarker();
            for (int ch = 0; ch < channels_; ch++) {
                buf[at + (ch + 1) * subslot_ - 1] = marker;
            }
        }
    }

    /** Fills [buf] with idle frames, carrying on. A stray partial frame is zeroed. */
    void idle(uint8_t *buf, size_t bytes) {
        const size_t frame = frameBytes();
        size_t at = 0;
        if (frame != 0 && subslot_ >= 3) {
            for (; at + frame <= bytes; at += frame) {
                const uint8_t marker = nextMarker();
                for (int ch = 0; ch < channels_; ch++) {
                    uint8_t *s = buf + at + ch * subslot_;
                    for (int i = 0; i < subslot_ - 3; i++) s[i] = 0;
                    s[subslot_ - 3] = kIdle;
                    s[subslot_ - 2] = kIdle;
                    s[subslot_ - 1] = marker;
                }
            }
        }
        for (; at < bytes; at++) buf[at] = 0;
    }

    static constexpr uint8_t kIdle = 0x69;

private:
    size_t frameBytes() const {
        return channels_ > 0 && subslot_ > 0 ? static_cast<size_t>(channels_ * subslot_) : 0;
    }
    uint8_t nextMarker() {
        const uint8_t m = next_ ? 0xFA : 0x05;
        next_ ^= 1;
        return m;
    }

    int channels_ = 0;
    int subslot_ = 0;
    int next_ = 0;
};
