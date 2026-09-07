#include "AlacStream.h"

#include <android/log.h>
#include <cstring>

#include "third_party/alac/ALACDecoder.h"
#include "third_party/alac/ALACBitUtilities.h"

#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, "hifirend", __VA_ARGS__)
#define LOGW(...) __android_log_print(ANDROID_LOG_WARN, "hifirend", __VA_ARGS__)

namespace {

/** Big-endian writers: the magic cookie is a network-order structure. */
void put32(std::vector<uint8_t> &v, uint32_t x) {
    v.push_back((x >> 24) & 0xFF); v.push_back((x >> 16) & 0xFF);
    v.push_back((x >> 8) & 0xFF);  v.push_back(x & 0xFF);
}

void put16(std::vector<uint8_t> &v, uint16_t x) {
    v.push_back((x >> 8) & 0xFF); v.push_back(x & 0xFF);
}

}  // namespace

AlacStream::AlacStream() = default;
AlacStream::~AlacStream() = default;

bool AlacStream::configure(uint32_t frameLength, uint8_t compatibleVersion, uint8_t bitDepth,
                           uint8_t pb, uint8_t mb, uint8_t kb, uint8_t channels,
                           uint16_t maxRun, uint32_t maxFrameBytes, uint32_t avgBitRate,
                           uint32_t sampleRate) {
    // ALACSpecificConfig, in the exact order and width the reference decoder
    // reads it. This is a wire structure, not a struct copy: writing it by
    // hand avoids depending on the compiler's padding, which on a 64-bit
    // target does not match the file layout.
    cookie_.clear();
    cookie_.reserve(24);
    put32(cookie_, frameLength);
    cookie_.push_back(compatibleVersion);
    cookie_.push_back(bitDepth);
    cookie_.push_back(pb);
    cookie_.push_back(mb);
    cookie_.push_back(kb);
    cookie_.push_back(channels);
    put16(cookie_, maxRun);
    put32(cookie_, maxFrameBytes);
    put32(cookie_, avgBitRate);
    put32(cookie_, sampleRate);

    decoder_ = std::make_unique<ALACDecoder>();
    const int32_t status = decoder_->Init(cookie_.data(), static_cast<uint32_t>(cookie_.size()));
    if (status != 0) {
        LOGW("alac: decoder init failed (%d)", status);
        decoder_.reset();
        return false;
    }
    channels_ = channels;
    bitDepth_ = bitDepth;
    sampleRate_ = sampleRate;
    frameLength_ = frameLength;
    LOGI("alac: %u Hz %d-bit %dch, %u frames per packet",
         sampleRate_, bitDepth_, channels_, frameLength_);
    return true;
}

int AlacStream::decode(const uint8_t *frame, int length, uint8_t *out, int outCapacity) {
    if (!decoder_ || length <= 0) return 0;

    const int bytesPerSample = bitDepth_ / 8;
    const int needed = static_cast<int>(frameLength_) * channels_ * bytesPerSample;
    if (outCapacity < needed) {
        LOGW("alac: output buffer too small (%d < %d)", outCapacity, needed);
        return 0;
    }

    // BitBuffer wants a writable pointer, though decoding does not modify the
    // frame. Const-casting here rather than copying every packet: at ~117
    // packets a second a copy is not free, and the decoder genuinely only
    // reads.
    BitBuffer bits;
    BitBufferInit(&bits, const_cast<uint8_t *>(frame), static_cast<uint32_t>(length));

    uint32_t decoded = 0;
    const int32_t status = decoder_->Decode(&bits, out, frameLength_, channels_, &decoded);
    if (status != 0) {
        LOGW("alac: decode failed (%d) on a %d-byte frame", status, length);
        return 0;
    }
    return static_cast<int>(decoded) * channels_ * bytesPerSample;
}
