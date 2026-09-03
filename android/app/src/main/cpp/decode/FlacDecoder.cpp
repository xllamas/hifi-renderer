#include "FlacDecoder.h"

#include <android/log.h>

#include "../NetworkStream.h"
#define DR_FLAC_IMPLEMENTATION
#define DR_FLAC_NO_STDIO
#include "../third_party/dr_libs/dr_flac.h"

#define LOG_TAG "hifirend"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)

namespace {

size_t onRead(void *user, void *out, size_t bytes) {
    return static_cast<NetworkStream *>(user)->read(static_cast<uint8_t *>(out), bytes);
}

// Live network bytes cannot be rewound; seeking re-requests with a byte range.
drflac_bool32 onSeek(void *, int, drflac_seek_origin) { return DRFLAC_FALSE; }

drflac_bool32 onTell(void *user, drflac_int64 *cursor) {
    *cursor = static_cast<drflac_int64>(static_cast<NetworkStream *>(user)->consumed());
    return DRFLAC_TRUE;
}

}  // namespace

FlacDecoder::~FlacDecoder() { close(); }

bool FlacDecoder::open(NetworkStream *stream, std::string *error) {
    stream_ = stream;
    drflac *f = relaxed_
        ? drflac_open_relaxed(onRead, onSeek, onTell, drflac_container_native, stream, nullptr)
        : drflac_open(onRead, onSeek, onTell, stream, nullptr);
    if (f == nullptr) {
        *error = "not a decodable FLAC stream";
        return false;
    }
    flac_ = f;
    rate_ = f->sampleRate;
    channels_ = f->channels;
    bits_ = f->bitsPerSample;
    LOGI("flac: %u Hz %d-bit %dch", rate_, bits_, channels_);
    return true;
}

uint64_t FlacDecoder::read(int32_t *out, uint64_t frames) {
    if (flac_ == nullptr) return 0;
    // dr_flac's s32 output is the sample left-justified in 32 bits, which is
    // exactly the convention this interface promises.
    return drflac_read_pcm_frames_s32(static_cast<drflac *>(flac_), frames, out);
}

void FlacDecoder::close() {
    if (flac_ != nullptr) {
        drflac_close(static_cast<drflac *>(flac_));
        flac_ = nullptr;
    }
    stream_ = nullptr;
}
