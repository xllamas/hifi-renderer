// minimp3 is header-only; this is the single translation unit that emits it.
#define MINIMP3_IMPLEMENTATION
#include "Mp3Decoder.h"

#include <android/log.h>

#include <algorithm>
#include <cstring>

#include "../NetworkStream.h"

#define LOG_TAG "hifirend"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)

namespace {
// Enough for a maximal frame plus slack, so a frame is never split across the
// end of the working buffer.
constexpr size_t kBufferSize = 64 * 1024;
constexpr size_t kRefillBelow = 32 * 1024;
}  // namespace

Mp3Decoder::Mp3Decoder() { buffer_.resize(kBufferSize); }

Mp3Decoder::~Mp3Decoder() { close(); }

size_t Mp3Decoder::refill() {
    if (eof_) return filled_;
    if (filled_ >= kRefillBelow) return filled_;
    // Move the unconsumed tail to the front, then top up.
    if (consumed_ > 0) {
        memmove(buffer_.data(), buffer_.data() + consumed_, filled_);
        consumed_ = 0;
    }
    size_t want = kBufferSize - filled_;
    size_t got = stream_->read(buffer_.data() + filled_, want);
    filled_ += got;
    if (got < want) eof_ = true;
    return filled_;
}

bool Mp3Decoder::open(NetworkStream *stream, std::string *error) {
    stream_ = stream;
    mp3dec_init(&dec_);

    // Decode the first frame to learn the format. MP3 has no global header --
    // every frame carries its own -- so this is also how the stream is
    // validated: if no frame is found in a reasonable amount of data, it is
    // not MP3.
    for (int attempt = 0; attempt < 64; attempt++) {
        refill();
        if (filled_ == 0) break;
        mp3dec_frame_info_t info{};
        int samples = mp3dec_decode_frame(
            &dec_, buffer_.data() + consumed_, static_cast<int>(filled_),
            pending_.data(), &info);
        if (info.frame_bytes > 0) {
            consumed_ += info.frame_bytes;
            filled_ -= info.frame_bytes;
        }
        if (samples > 0) {
            rate_ = static_cast<uint32_t>(info.hz);
            channels_ = info.channels;
            // minimp3 emits 16-bit samples; MP3 is lossy so there is no wider
            // source precision to preserve.
            bits_ = 16;
            pendingFrames_ = static_cast<size_t>(samples);
            pendingOffset_ = 0;
            LOGI("mp3: %u Hz %dch %d kbps layer %d",
                 rate_, channels_, info.bitrate_kbps, info.layer);
            return true;
        }
        if (info.frame_bytes == 0 && eof_ && filled_ == 0) break;
    }
    *error = "no MP3 frame found in stream";
    return false;
}

uint64_t Mp3Decoder::read(int32_t *out, uint64_t frames) {
    uint64_t written = 0;
    while (written < frames) {
        if (pendingFrames_ == 0) {
            refill();
            if (filled_ == 0) break;
            mp3dec_frame_info_t info{};
            int samples = mp3dec_decode_frame(
                &dec_, buffer_.data() + consumed_, static_cast<int>(filled_),
                pending_.data(), &info);
            if (info.frame_bytes > 0) {
                consumed_ += info.frame_bytes;
                filled_ -= info.frame_bytes;
            } else if (eof_) {
                break;   // no progress possible
            } else {
                continue;
            }
            if (samples <= 0) continue;   // skipped ID3 or garbage, keep going
            pendingFrames_ = static_cast<size_t>(samples);
            pendingOffset_ = 0;
        }

        const size_t take = std::min<size_t>(pendingFrames_, frames - written);
        for (size_t i = 0; i < take * static_cast<size_t>(channels_); i++) {
            // 16-bit sample left-justified into 32 bits, the same convention
            // every decoder here uses.
            out[written * channels_ + i] =
                static_cast<int32_t>(pending_[pendingOffset_ * channels_ + i]) << 16;
        }
        pendingOffset_ += take;
        pendingFrames_ -= take;
        written += take;
    }
    return written;
}

void Mp3Decoder::close() {
    stream_ = nullptr;
    filled_ = consumed_ = 0;
    pendingFrames_ = pendingOffset_ = 0;
    eof_ = false;
}
