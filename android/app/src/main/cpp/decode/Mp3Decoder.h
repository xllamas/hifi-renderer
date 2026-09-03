#pragma once

#include <array>
#include <vector>

#include "../third_party/minimp3/minimp3.h"
#include "Decoder.h"

/** MP3 via minimp3. Lossy, so "bit-perfect" means only that nothing resamples. */
class Mp3Decoder : public Decoder {
public:
    Mp3Decoder();
    ~Mp3Decoder() override;

    bool open(NetworkStream *stream, std::string *error) override;
    uint64_t read(int32_t *out, uint64_t frames) override;
    void close() override;

private:
    size_t refill();

    NetworkStream *stream_ = nullptr;
    mp3dec_t dec_{};
    std::vector<uint8_t> buffer_;
    size_t filled_ = 0;
    size_t consumed_ = 0;
    bool eof_ = false;

    std::array<mp3d_sample_t, MINIMP3_MAX_SAMPLES_PER_FRAME> pending_{};
    size_t pendingFrames_ = 0;
    size_t pendingOffset_ = 0;
};
