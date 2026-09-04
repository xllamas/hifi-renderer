#pragma once

#include <atomic>
#include <memory>
#include <string>

#include <oboe/Oboe.h>

#include "../RingBuffer.h"
#include "AudioSink.h"

/**
 * The fallback output: Android's own audio stack, via Oboe.
 *
 * Used when there is no USB DAC to drive. Everything above it is identical to
 * the bit-perfect path -- same decoders, same ring buffer, same transport --
 * so the renderer, playlist, widget and UI all work on a phone with nothing
 * plugged into it.
 *
 * What is *not* identical is the audio. Android mixes this stream with every
 * other sound on the device and resamples it to whatever the output is running
 * at, so a 96 kHz source is not leaving the phone at 96 kHz. That is the
 * difference the app exists to make, so [bitPerfect] returns false and the
 * screen says so rather than letting the distinction quietly lapse.
 *
 * Samples arrive as 32-bit little-endian, the same wire format a 4-byte USB
 * subslot uses, and are converted to float in the callback. Float32 carries 24
 * bits of mantissa, so 24-bit sources survive exactly and only 32-bit ones lose
 * anything -- and this path has already given up more than that.
 */
class OboeSink : public AudioSink, public oboe::AudioStreamDataCallback {
public:
    ~OboeSink() override;

    bool open(int fd, std::string *error) override;
    bool configure(uint32_t rate, int sourceBits, int channels, std::string *error) override;
    bool start(std::string *error) override;
    void stop() override;
    void close() override;

    size_t write(const uint8_t *pcm, size_t bytes) override {
        return ring_ ? ring_->write(pcm, bytes) : 0;
    }
    size_t ringSpace() const override { return ring_ ? ring_->space() : 0; }
    size_t ringAvailable() const override { return ring_ ? ring_->available() : 0; }

    void setPaused(bool paused) override { paused_.store(paused, std::memory_order_release); }
    void setStalled(bool stalled) override { stalled_.store(stalled, std::memory_order_release); }
    void setSourceEnded(bool ended) override { sourceEnded_.store(ended, std::memory_order_release); }
    void noteRebuffer() override { rebuffers_.fetch_add(1, std::memory_order_relaxed); }

    /** 32-bit, so the decoder hands over int32 samples untruncated. */
    int deviceSubslot() const override { return 4; }

    /** Never. Android mixes and resamples this stream. */
    bool bitPerfect() const override { return false; }

    const char *outputName() const override { return "android"; }

    std::string statusJson() const override;

    oboe::DataCallbackResult onAudioReady(oboe::AudioStream *stream,
                                          void *audioData, int32_t numFrames) override;

private:
    std::shared_ptr<oboe::AudioStream> stream_;
    std::unique_ptr<RingBuffer> ring_;

    uint32_t rate_ = 0;
    int channels_ = 2;
    int bytesPerFrame_ = 0;
    /** What Android actually gave us, which need not be what was asked for. */
    std::atomic<uint32_t> actualRate_{0};

    std::atomic<bool> running_{false};
    std::atomic<bool> paused_{false};
    std::atomic<bool> stalled_{false};
    std::atomic<bool> sourceEnded_{false};

    std::atomic<uint64_t> framesSubmitted_{0};
    std::atomic<uint64_t> underruns_{0};
    std::atomic<uint64_t> rebuffers_{0};
};
