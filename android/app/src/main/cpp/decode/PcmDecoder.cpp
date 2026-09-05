#include "PcmDecoder.h"

#include <android/log.h>

#include <algorithm>
#include <cctype>
#include <cstdlib>
#include <cstring>

#include "../NetworkStream.h"

#define LOG_TAG "hifirend"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)

namespace {

uint16_t le16(const uint8_t *p) {
    return static_cast<uint16_t>(p[0] | (p[1] << 8));
}

uint32_t le32(const uint8_t *p) {
    return static_cast<uint32_t>(p[0]) | (static_cast<uint32_t>(p[1]) << 8) |
           (static_cast<uint32_t>(p[2]) << 16) | (static_cast<uint32_t>(p[3]) << 24);
}

uint16_t be16(const uint8_t *p) {
    return static_cast<uint16_t>((p[0] << 8) | p[1]);
}

uint32_t be32(const uint8_t *p) {
    return (static_cast<uint32_t>(p[0]) << 24) | (static_cast<uint32_t>(p[1]) << 16) |
           (static_cast<uint32_t>(p[2]) << 8) | static_cast<uint32_t>(p[3]);
}

/**
 * AIFF states its sample rate as an 80-bit IEEE 754 extended float, which is
 * the only place in either container that is not a plain integer.
 *
 * Sign is ignored and the result truncated: a negative or fractional sample
 * rate is not a thing, and anything that does not land on a sane integer is
 * rejected by the caller as an unusable rate rather than guessed at.
 */
uint32_t extended80(const uint8_t *p) {
    const int exponent = ((p[0] & 0x7F) << 8) | p[1];
    uint64_t mantissa = 0;
    for (int i = 2; i < 10; i++) mantissa = (mantissa << 8) | p[i];
    if (exponent == 0 || mantissa == 0) return 0;
    // The mantissa carries an explicit integer bit, so the value is
    // mantissa * 2^(exponent - 16383 - 63).
    const int shift = exponent - 16383 - 63;
    if (shift >= 0) return 0;        // >= 2^63; not a sample rate
    if (shift < -63) return 0;       // rounds to nothing
    return static_cast<uint32_t>(mantissa >> -shift);
}

/**
 * A numeric MIME parameter, e.g. the 44100 in
 * "audio/L16;rate=44100;channels=2".
 *
 * Matched on the parameter name preceded by a delimiter, so "rate" does not
 * also match the "rate" inside "bitrate". Absent or unparseable falls back to
 * [fallback]: RFC 2586 makes both optional, and a server that omits them is
 * claiming the defaults.
 */
int mimeParam(const std::string &mime, const char *name, int fallback) {
    const size_t nameLen = strlen(name);
    for (size_t at = mime.find(name); at != std::string::npos;
         at = mime.find(name, at + 1)) {
        if (at > 0 && mime[at - 1] != ';' && mime[at - 1] != ' ') continue;
        size_t eq = at + nameLen;
        while (eq < mime.size() && mime[eq] == ' ') eq++;
        if (eq >= mime.size() || mime[eq] != '=') continue;
        const int value = atoi(mime.c_str() + eq + 1);
        if (value > 0) return value;
    }
    return fallback;
}

}  // namespace

PcmDecoder::PcmDecoder(std::string mime) : mime_(std::move(mime)) {}

size_t PcmDecoder::fill(uint8_t *dst, size_t n) {
    size_t got = 0;
    if (!carry_.empty()) {
        got = std::min(carry_.size(), n);
        memcpy(dst, carry_.data(), got);
        carry_.erase(carry_.begin(), carry_.begin() + static_cast<ptrdiff_t>(got));
    }
    if (got < n) got += stream_->read(dst + got, n - got);
    return got;
}

void PcmDecoder::pushBack(const uint8_t *data, size_t n) {
    carry_.insert(carry_.begin(), data, data + n);
}

bool PcmDecoder::skip(uint64_t n) {
    uint8_t scratch[4096];
    while (n > 0) {
        const size_t want = static_cast<size_t>(std::min<uint64_t>(n, sizeof(scratch)));
        if (fill(scratch, want) != want) return false;
        n -= want;
    }
    return true;
}

bool PcmDecoder::open(NetworkStream *stream, std::string *error) {
    stream_ = stream;

    // What the MIME type claims, which for L16 and L24 is the only statement
    // of the format that exists anywhere in the stream.
    std::string lower;
    for (char c : mime_) lower += static_cast<char>(tolower(c));
    bits_ = lower.find("l24") != std::string::npos ? 24 : 16;
    containerBytes_ = bits_ / 8;
    rate_ = static_cast<uint32_t>(mimeParam(mime_, "rate", 44100));
    channels_ = mimeParam(mime_, "channels", 2);
    bigEndian_ = true;

    // A WAV or AIFF body can arrive here either honestly labelled or under an
    // L16 content type, and its header would otherwise be played as audio.
    // Twelve bytes covers both signatures; when it is neither, those bytes are
    // audio and go back for the reader.
    uint8_t sig[12];
    const size_t got = fill(sig, sizeof(sig));
    const bool riff = got == sizeof(sig) && memcmp(sig, "RIFF", 4) == 0 &&
                      memcmp(sig + 8, "WAVE", 4) == 0;
    const bool form = got == sizeof(sig) && memcmp(sig, "FORM", 4) == 0 &&
                      (memcmp(sig + 8, "AIFF", 4) == 0 || memcmp(sig + 8, "AIFC", 4) == 0);
    if (riff) {
        containerName_ = "WAV";
        if (!readWavHeader(error)) return false;
    } else if (form) {
        const bool compressed = memcmp(sig + 8, "AIFC", 4) == 0;
        containerName_ = compressed ? "AIFC" : "AIFF";
        if (!readAiffHeader(compressed, error)) return false;
    } else {
        pushBack(sig, got);
    }

    if (rate_ == 0 || channels_ <= 0 || channels_ > 8) {
        *error = std::string(containerName_) +
                 " stream declares no usable rate or channel count (" + mime_ + ")";
        return false;
    }
    LOGI("pcm: %s %u Hz %d-bit %dch, %s", containerName_, rate_, bits_, channels_,
         bigEndian_ ? "big-endian" : "little-endian");
    return true;
}

bool PcmDecoder::setSampleSize(int sampleBits, bool unsigned8, std::string *error) {
    switch (sampleBits) {
        // No DAC has an 8-bit alt-setting, so 8-bit sources are widened to a
        // 16-bit container. That costs nothing: the samples are left-justified
        // in 32 bits either way, and narrowing drops only zero padding.
        case 8:  containerBytes_ = 1; bits_ = 16; unsignedSamples_ = unsigned8; break;
        case 16: containerBytes_ = 2; bits_ = 16; break;
        case 24: containerBytes_ = 3; bits_ = 24; break;
        case 32: containerBytes_ = 4; bits_ = 32; break;
        default:
            *error = std::string(containerName_) + " is " + std::to_string(sampleBits) +
                     "-bit, which no DAC can be configured for";
            return false;
    }
    return true;
}

bool PcmDecoder::readWavHeader(std::string *error) {
    bool haveFmt = false;
    // Bounded because a stream that is not really WAV can otherwise walk
    // nonsense chunk sizes forever.
    for (int chunk = 0; chunk < 64; chunk++) {
        uint8_t hdr[8];
        if (fill(hdr, sizeof(hdr)) != sizeof(hdr)) {
            *error = "WAV header ended before its audio";
            return false;
        }
        const uint32_t size = le32(hdr + 4);

        if (memcmp(hdr, "data", 4) == 0) {
            if (!haveFmt) {
                *error = "WAV audio begins before its format is declared";
                return false;
            }
            // The declared size is ignored: a streaming server cannot know it
            // in advance and writes a placeholder. End of stream is the end.
            return true;
        }

        if (memcmp(hdr, "fmt ", 4) == 0) {
            uint8_t fmt[40];
            const size_t want = std::min<size_t>(size, sizeof(fmt));
            if (want < 16 || fill(fmt, want) != want) {
                *error = "WAV format chunk is truncated";
                return false;
            }
            uint16_t tag = le16(fmt);
            channels_ = le16(fmt + 2);
            rate_ = le32(fmt + 4);
            const int sampleBits = le16(fmt + 14);
            // WAVE_FORMAT_EXTENSIBLE keeps the real format tag in the first
            // two bytes of its sub-format GUID.
            if (tag == 0xFFFE && want >= 26) tag = le16(fmt + 24);
            if (tag != 1) {
                *error = "WAV is not integer PCM (format tag " +
                         std::to_string(tag) + ")";
                return false;
            }
            // 8-bit WAV, alone among everything on this path, is unsigned.
            if (!setSampleSize(sampleBits, /*unsigned8=*/true, error)) return false;
            bigEndian_ = false;
            haveFmt = true;
            if (!skip(size - want + (size & 1))) {
                *error = "WAV header ended before its audio";
                return false;
            }
            continue;
        }

        // Anything else -- LIST, fact, embedded art -- is metadata. Chunks are
        // word-aligned, so an odd size is followed by a pad byte.
        if (!skip(static_cast<uint64_t>(size) + (size & 1))) {
            *error = "WAV header ended before its audio";
            return false;
        }
    }
    *error = "no audio found in the WAV header";
    return false;
}

bool PcmDecoder::readAiffHeader(bool compressed, std::string *error) {
    bool haveComm = false;
    // Bounded for the same reason the WAV walk is: a stream that is not really
    // AIFF can otherwise follow nonsense chunk sizes for ever.
    for (int chunk = 0; chunk < 64; chunk++) {
        uint8_t hdr[8];
        if (fill(hdr, sizeof(hdr)) != sizeof(hdr)) {
            *error = "AIFF header ended before its audio";
            return false;
        }
        const uint32_t size = be32(hdr + 4);

        if (memcmp(hdr, "SSND", 4) == 0) {
            if (!haveComm) {
                *error = "AIFF audio begins before its format is declared";
                return false;
            }
            uint8_t ssnd[8];
            if (fill(ssnd, sizeof(ssnd)) != sizeof(ssnd)) {
                *error = "AIFF sound chunk is truncated";
                return false;
            }
            // The offset is alignment padding between the chunk and the first
            // sample frame -- almost always zero, and never audio.
            if (!skip(be32(ssnd))) {
                *error = "AIFF header ended before its audio";
                return false;
            }
            return true;
        }

        if (memcmp(hdr, "COMM", 4) == 0) {
            uint8_t comm[24];
            const size_t want = std::min<size_t>(size, sizeof(comm));
            if (want < 18 || fill(comm, want) != want) {
                *error = "AIFF format chunk is truncated";
                return false;
            }
            channels_ = be16(comm);
            const int sampleBits = be16(comm + 6);
            rate_ = extended80(comm + 8);
            bigEndian_ = true;

            // AIFC names its encoding, and most of the names are codecs this
            // has no business trying to play. Two of the uncompressed ones are
            // big-endian like plain AIFF; 'sowt' is byte-swapped, which is
            // what Apple's tools write and the reason this cannot be assumed.
            if (compressed) {
                if (want < 22) {
                    *error = "AIFC declares no compression type";
                    return false;
                }
                const char *how = reinterpret_cast<const char *>(comm + 18);
                if (memcmp(how, "sowt", 4) == 0) {
                    bigEndian_ = false;
                } else if (memcmp(how, "NONE", 4) != 0 && memcmp(how, "twos", 4) != 0) {
                    *error = "AIFC is encoded as '" + std::string(how, 4) +
                             "', which is not PCM";
                    return false;
                }
            }

            // AIFF's 8-bit samples are signed, unlike WAV's.
            if (!setSampleSize(sampleBits, /*unsigned8=*/false, error)) return false;
            haveComm = true;
            if (!skip(size - want + (size & 1))) {
                *error = "AIFF header ended before its audio";
                return false;
            }
            continue;
        }

        // Anything else -- NAME, ANNO, embedded art -- is metadata. Chunks are
        // word-aligned, so an odd size is followed by a pad byte.
        if (!skip(static_cast<uint64_t>(size) + (size & 1))) {
            *error = "AIFF header ended before its audio";
            return false;
        }
    }
    *error = "no audio found in the AIFF header";
    return false;
}

uint64_t PcmDecoder::read(int32_t *out, uint64_t frames) {
    const size_t frameBytes = static_cast<size_t>(channels_) * containerBytes_;
    const size_t want = static_cast<size_t>(frames) * frameBytes;
    bytes_.resize(want);
    const size_t got = fill(bytes_.data(), want);

    // A short read at the end of a stream can leave a fraction of a frame.
    // It is kept rather than dropped, because a stall mid-track produces the
    // same short read and losing a byte there would shift every later sample
    // by one and swap the channels for the rest of the track.
    const size_t whole = got / frameBytes;
    if (const size_t remainder = got % frameBytes; remainder > 0) {
        pushBack(bytes_.data() + whole * frameBytes, remainder);
    }

    const uint8_t *p = bytes_.data();
    const size_t samples = whole * static_cast<size_t>(channels_);
    for (size_t i = 0; i < samples; i++, p += containerBytes_) {
        uint32_t v;
        if (unsignedSamples_) {
            v = (static_cast<uint32_t>(p[0]) - 128u) << 24;
        } else if (bigEndian_) {
            v = 0;
            for (int b = 0; b < containerBytes_; b++) v = (v << 8) | p[b];
            v <<= (32 - containerBytes_ * 8);
        } else {
            v = 0;
            for (int b = containerBytes_ - 1; b >= 0; b--) v = (v << 8) | p[b];
            v <<= (32 - containerBytes_ * 8);
        }
        // Left-justified in 32 bits, the convention every decoder here shares:
        // narrowing to the DAC's container then drops only zero padding.
        out[i] = static_cast<int32_t>(v);
    }
    return whole;
}

void PcmDecoder::close() {
    stream_ = nullptr;
    carry_.clear();
    bytes_.clear();
}
