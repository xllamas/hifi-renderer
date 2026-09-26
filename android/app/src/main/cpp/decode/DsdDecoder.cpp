#include "DsdDecoder.h"

#include <android/log.h>

#include <algorithm>
#include <cstdio>
#include <cstring>

#include "../NetworkStream.h"

#define LOG_TAG "hifirend"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)

namespace {

uint32_t le32(const uint8_t *p) {
    return static_cast<uint32_t>(p[0]) | (static_cast<uint32_t>(p[1]) << 8) |
           (static_cast<uint32_t>(p[2]) << 16) | (static_cast<uint32_t>(p[3]) << 24);
}

uint64_t le64(const uint8_t *p) {
    return static_cast<uint64_t>(le32(p)) | (static_cast<uint64_t>(le32(p + 4)) << 32);
}

uint16_t be16(const uint8_t *p) {
    return static_cast<uint16_t>((p[0] << 8) | p[1]);
}

uint32_t be32(const uint8_t *p) {
    return (static_cast<uint32_t>(p[0]) << 24) | (static_cast<uint32_t>(p[1]) << 16) |
           (static_cast<uint32_t>(p[2]) << 8) | static_cast<uint32_t>(p[3]);
}

uint64_t be64(const uint8_t *p) {
    return (static_cast<uint64_t>(be32(p)) << 32) | static_cast<uint64_t>(be32(p + 4));
}

uint8_t reverseByte(uint8_t b) {
    b = static_cast<uint8_t>(((b & 0xF0) >> 4) | ((b & 0x0F) << 4));
    b = static_cast<uint8_t>(((b & 0xCC) >> 2) | ((b & 0x33) << 2));
    b = static_cast<uint8_t>(((b & 0xAA) >> 1) | ((b & 0x55) << 1));
    return b;
}

/**
 * The DSD idle pattern. It pads the end of a run that has an odd number of
 * bytes, because DoP takes them two at a time; it decodes as silence.
 */
constexpr uint8_t kDsdSilence = 0x69;

constexpr uint8_t kMarker[2] = {0x05, 0xFA};

/** How much of a DFF is read per refill, per channel. */
constexpr size_t kDffRun = 4096;

}  // namespace

DsdDecoder::DsdDecoder(int markerPhase) : phase_(markerPhase & 1) {}

size_t DsdDecoder::fill(uint8_t *dst, size_t n) {
    size_t got = 0;
    if (!carry_.empty()) {
        got = std::min(carry_.size(), n);
        memcpy(dst, carry_.data(), got);
        carry_.erase(carry_.begin(), carry_.begin() + static_cast<ptrdiff_t>(got));
    }
    if (got < n) got += stream_->read(dst + got, n - got);
    return got;
}

void DsdDecoder::pushBack(const uint8_t *data, size_t n) {
    carry_.insert(carry_.begin(), data, data + n);
}

bool DsdDecoder::skip(uint64_t n) {
    uint8_t scratch[4096];
    while (n > 0) {
        const size_t want = static_cast<size_t>(std::min<uint64_t>(n, sizeof(scratch)));
        if (fill(scratch, want) != want) return false;
        n -= want;
    }
    return true;
}

bool DsdDecoder::open(NetworkStream *stream, std::string *error) {
    stream_ = stream;

    // Sixteen bytes tells the containers apart: DSF starts "DSD " and DFF
    // starts "FRM8", with its form type "DSD " twelve bytes in. Both headers
    // are then parsed from the top, so the bytes go back.
    uint8_t sig[16];
    const size_t got = fill(sig, sizeof(sig));
    pushBack(sig, got);
    if (got == sizeof(sig) && memcmp(sig, "DSD ", 4) == 0) {
        dsf_ = true;
        return readDsfHeader(error);
    }
    if (got == sizeof(sig) && memcmp(sig, "FRM8", 4) == 0 &&
        memcmp(sig + 12, "DSD ", 4) == 0) {
        dsf_ = false;
        return readDffHeader(error);
    }
    // Says what was seen, because the usual cause is not a bad DSD file but
    // something that only has a .dsf name -- macOS's 4096-byte "._name"
    // resource forks on a network share, or a seek that restarted the file
    // without its header.
    char seen[3 * sizeof(sig) + 1] = "";
    for (size_t i = 0; i < std::min<size_t>(got, 8); i++) {
        snprintf(seen + strlen(seen), sizeof(seen) - strlen(seen), "%02X ", sig[i]);
    }
    *error = "not a DSF or DFF stream (" + std::to_string(got) + " bytes read, starting " +
             (got ? std::string(seen) : std::string("with nothing")) +
             "); check for macOS '._' files and for a seek into the middle of a file";
    return false;
}

bool DsdDecoder::finishHeader(const char *container, uint64_t dsdRate, std::string *error) {
    if (channels_ <= 0 || channels_ > 8) {
        *error = std::string(container) + " declares " + std::to_string(channels_) +
                 " channels, which is not a usable count";
        return false;
    }
    // DoP takes sixteen DSD bits per frame, so the rate has to divide, and
    // anything that does not is not a DSD rate at all. The upper bound only
    // stops a corrupt header from wrapping the 32-bit rate.
    if (dsdRate == 0 || dsdRate % 16 != 0 || dsdRate / 16 > 0xFFFFFFu) {
        *error = std::string(container) + " declares a DSD rate of " +
                 std::to_string(dsdRate) + " Hz, which is not usable";
        return false;
    }
    rate_ = static_cast<uint32_t>(dsdRate / 16);
    // The marker and two DSD bytes are the significant 24 bits; the low byte
    // is padding, like a 16-bit source in a wider slot.
    bits_ = 24;
    capacity_ = dsf_ ? blockSize_ : kDffRun + 1;
    planar_.assign(capacity_ * static_cast<size_t>(channels_), 0);
    LOGI("dsd: %s DSD%u (%llu Hz) as DoP %u Hz %dch, %s", container,
         static_cast<unsigned>(dsdRate / 44100), static_cast<unsigned long long>(dsdRate),
         rate_, channels_, reverseBits_ ? "LSB-first, reversed" : "MSB-first");
    return true;
}

bool DsdDecoder::readDsfHeader(std::string *error) {
    // "DSD " chunk: id, size (8, and 28 in every file seen), total file size,
    // and the offset of the ID3 tag that follows the audio.
    uint8_t top[28];
    if (fill(top, sizeof(top)) != sizeof(top)) {
        *error = "DSF header is truncated";
        return false;
    }
    const uint64_t topSize = le64(top + 4);
    if (topSize < sizeof(top) || !skip(topSize - sizeof(top))) {
        *error = "DSF header is truncated";
        return false;
    }

    // "fmt ": id, size (8), then version, format ID, channel type, channel
    // count, sampling frequency, bits per sample, sample count (8), block size
    // per channel and a reserved word.
    uint8_t hdr[12];
    uint8_t fmt[40];
    if (fill(hdr, sizeof(hdr)) != sizeof(hdr) || memcmp(hdr, "fmt ", 4) != 0) {
        *error = "DSF has no format chunk where it belongs";
        return false;
    }
    const uint64_t fmtSize = le64(hdr + 4);
    if (fmtSize < sizeof(hdr) + sizeof(fmt) || fill(fmt, sizeof(fmt)) != sizeof(fmt) ||
        !skip(fmtSize - sizeof(hdr) - sizeof(fmt))) {
        *error = "DSF format chunk is truncated";
        return false;
    }
    if (le32(fmt + 4) != 0) {
        *error = "DSF format ID " + std::to_string(le32(fmt + 4)) + " is not raw DSD";
        return false;
    }
    channels_ = static_cast<int>(le32(fmt + 12));
    const uint32_t dsdRate = le32(fmt + 16);
    // 1 = the least significant bit is the earliest sample, 8 = the most. DoP
    // wants the earliest in bit 7, so LSB-first bytes are reversed on the way
    // in. Any other value is not a bit order this can trust.
    const uint32_t order = le32(fmt + 20);
    if (order != 1 && order != 8) {
        *error = "DSF declares bit order " + std::to_string(order) + ", which is not 1 or 8";
        return false;
    }
    reverseBits_ = order == 1;
    const uint64_t samples = le64(fmt + 24);
    blockSize_ = le32(fmt + 32);
    // Even, because DoP pairs bytes and a block that ended on an odd one would
    // split a pair across two block groups.
    if (blockSize_ == 0 || blockSize_ % 2 != 0 || blockSize_ > 65536) {
        *error = "DSF block size " + std::to_string(blockSize_) + " is not usable";
        return false;
    }
    // The sample count is where the audio ends: the last block is padded out
    // with idle pattern, and playing it would be a fraction of a second of
    // something that is not the recording.
    channelBytesLeft_ = (samples + 7) / 8;

    for (int chunk = 0; chunk < 64; chunk++) {
        if (fill(hdr, sizeof(hdr)) != sizeof(hdr)) break;
        const uint64_t size = le64(hdr + 4);
        if (memcmp(hdr, "data", 4) == 0) return finishHeader("DSF", dsdRate, error);
        if (size < sizeof(hdr) || !skip(size - sizeof(hdr))) break;
    }
    *error = "no audio found in the DSF header";
    return false;
}

bool DsdDecoder::readDffHeader(std::string *error) {
    // "FRM8": id, size (8, big-endian), form type "DSD ".
    uint8_t frm[16];
    if (fill(frm, sizeof(frm)) != sizeof(frm)) {
        *error = "DFF header is truncated";
        return false;
    }

    uint64_t dsdRate = 0;
    bool haveRate = false, haveChannels = false;
    reverseBits_ = false;   // DFF has one bit order and it is the right one.

    for (int chunk = 0; chunk < 64; chunk++) {
        uint8_t hdr[12];
        if (fill(hdr, sizeof(hdr)) != sizeof(hdr)) {
            *error = "DFF header ended before its audio";
            return false;
        }
        const uint64_t size = be64(hdr + 4);

        if (memcmp(hdr, "DSD ", 4) == 0) {
            if (!haveRate || !haveChannels) {
                *error = "DFF audio begins before its format is declared";
                return false;
            }
            // Zero is what a streaming writer leaves when it could not know
            // the length; the audio then runs to the end of the stream.
            dataToEof_ = size == 0;
            dataBytesLeft_ = size;
            return finishHeader("DFF", dsdRate, error);
        }

        if (memcmp(hdr, "DST ", 4) == 0) {
            *error = "DFF is DST-compressed, which is not supported";
            return false;
        }

        if (memcmp(hdr, "PROP", 4) == 0) {
            uint8_t type[4];
            if (size < sizeof(type) || fill(type, sizeof(type)) != sizeof(type)) {
                *error = "DFF property chunk is truncated";
                return false;
            }
            uint64_t left = size - sizeof(type);
            if (memcmp(type, "SND ", 4) != 0) {
                if (!skip(left + (size & 1))) {
                    *error = "DFF header ended before its audio";
                    return false;
                }
                continue;
            }
            // The sound properties are a chunk list of their own, with the
            // same 12-byte headers, inside the one chunk.
            while (left >= sizeof(hdr)) {
                uint8_t sub[12];
                if (fill(sub, sizeof(sub)) != sizeof(sub)) {
                    *error = "DFF property chunk is truncated";
                    return false;
                }
                left -= sizeof(sub);
                const uint64_t subSize = be64(sub + 4);
                if (subSize > left) {
                    *error = "DFF property chunk overruns its parent";
                    return false;
                }
                uint8_t body[8];
                const size_t want = static_cast<size_t>(std::min<uint64_t>(subSize, sizeof(body)));
                if (fill(body, want) != want) {
                    *error = "DFF property chunk is truncated";
                    return false;
                }
                if (memcmp(sub, "FS  ", 4) == 0 && want >= 4) {
                    dsdRate = be32(body);
                    haveRate = true;
                } else if (memcmp(sub, "CHNL", 4) == 0 && want >= 2) {
                    channels_ = be16(body);
                    haveChannels = true;
                } else if (memcmp(sub, "CMPR", 4) == 0 && want >= 4) {
                    if (memcmp(body, "DSD ", 4) != 0) {
                        *error = "DFF is compressed as '" + std::string(reinterpret_cast<char *>(body), 4) +
                                 "', which is not supported";
                        return false;
                    }
                }
                // Sub-chunks are padded to an even size like their parents,
                // unless the parent ends first.
                const uint64_t pad = (subSize & 1) && left > subSize ? 1 : 0;
                const uint64_t rest = subSize - want + pad;
                if (!skip(rest)) {
                    *error = "DFF property chunk is truncated";
                    return false;
                }
                left -= want + rest;
            }
            if (!skip(left + (size & 1))) {
                *error = "DFF header ended before its audio";
                return false;
            }
            continue;
        }

        // FVER, comments, markers, embedded art: none of it is audio.
        if (!skip(size + (size & 1))) {
            *error = "DFF header ended before its audio";
            return false;
        }
    }
    *error = "no audio found in the DFF header";
    return false;
}

bool DsdDecoder::refillDsf() {
    if (channelBytesLeft_ == 0) return false;
    const size_t group = static_cast<size_t>(blockSize_) * static_cast<size_t>(channels_);
    raw_.resize(group);
    // Every group is full, the last one included -- it is padded, not short --
    // so a short read is a truncated file, not a final partial block.
    if (fill(raw_.data(), group) != group) return false;

    const size_t valid = static_cast<size_t>(std::min<uint64_t>(channelBytesLeft_, blockSize_));
    channelBytesLeft_ -= valid;
    for (int ch = 0; ch < channels_; ch++) {
        const uint8_t *src = raw_.data() + static_cast<size_t>(ch) * blockSize_;
        uint8_t *dst = planar_.data() + static_cast<size_t>(ch) * capacity_;
        if (reverseBits_) {
            for (size_t i = 0; i < valid; i++) dst[i] = reverseByte(src[i]);
        } else {
            memcpy(dst, src, valid);
        }
    }
    avail_ = valid;
    pos_ = 0;
    return true;
}

bool DsdDecoder::refillDff() {
    size_t want = static_cast<size_t>(channels_) * kDffRun;
    if (!dataToEof_) {
        if (dataBytesLeft_ == 0) return false;
        want = static_cast<size_t>(std::min<uint64_t>(want, dataBytesLeft_));
    }
    raw_.resize(want);
    const size_t got = fill(raw_.data(), want);
    if (!dataToEof_) dataBytesLeft_ -= got;

    // A short read is the end of the stream; a byte or two that does not fill
    // a frame across every channel has nothing to pair with and is dropped.
    const size_t frames = got / static_cast<size_t>(channels_);
    if (frames == 0) return false;
    for (int ch = 0; ch < channels_; ch++) {
        uint8_t *dst = planar_.data() + static_cast<size_t>(ch) * capacity_;
        for (size_t i = 0; i < frames; i++) dst[i] = raw_[i * channels_ + ch];
    }
    avail_ = frames;
    pos_ = 0;
    if (got < want) dataBytesLeft_ = 0;
    return true;
}

bool DsdDecoder::refill() {
    if (ended_) return false;
    const bool ok = dsf_ ? refillDsf() : refillDff();
    if (!ok) {
        ended_ = true;
        return false;
    }
    // DoP takes two bytes per frame, so an odd run -- only ever the last --
    // gets one byte of idle pattern to finish the pair.
    if (avail_ % 2 != 0) {
        for (int ch = 0; ch < channels_; ch++) {
            planar_[static_cast<size_t>(ch) * capacity_ + avail_] = kDsdSilence;
        }
        avail_++;
    }
    return true;
}

uint64_t DsdDecoder::read(int32_t *out, uint64_t frames) {
    uint64_t done = 0;
    while (done < frames) {
        if (buffered() < 2 && !refill()) break;

        const uint64_t n = std::min<uint64_t>(frames - done, buffered() / 2);
        for (uint64_t f = 0; f < n; f++) {
            // Every channel of a frame shares one marker, and the marker
            // alternates frame to frame across reads, refills and tracks.
            const uint32_t marker = static_cast<uint32_t>(kMarker[phase_]) << 24;
            phase_ ^= 1;
            for (int ch = 0; ch < channels_; ch++) {
                const uint8_t *p = planar_.data() + static_cast<size_t>(ch) * capacity_ + pos_;
                // The older byte sits above the newer, then a zero pad byte.
                out[(done + f) * channels_ + ch] = static_cast<int32_t>(
                    marker | (static_cast<uint32_t>(p[0]) << 16) |
                    (static_cast<uint32_t>(p[1]) << 8));
            }
            pos_ += 2;
        }
        done += n;
    }
    return done;
}

void DsdDecoder::close() {
    stream_ = nullptr;
    carry_.clear();
    raw_.clear();
    planar_.clear();
}
