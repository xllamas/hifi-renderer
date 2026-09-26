#pragma once

#include <cstdint>
#include <string>

class NetworkStream;

/**
 * A pull decoder reading from the network and producing PCM.
 *
 * Output is always **left-justified in 32 bits**, matching what the USB
 * subslot wants: narrowing to the DAC's container then drops only zero
 * padding, so nothing is scaled, rounded or dithered on the way out.
 */
class Decoder {
public:
    virtual ~Decoder() = default;

    /** Reads headers. Blocks until enough of the stream has arrived. */
    virtual bool open(NetworkStream *stream, std::string *error) = 0;

    /** Returns frames actually decoded; 0 means end of stream. */
    virtual uint64_t read(int32_t *out, uint64_t frames) = 0;

    virtual void close() = 0;

    uint32_t sampleRate() const { return rate_; }
    int channels() const { return channels_; }
    /** Significant bits in the source, which selects the DAC alt-setting. */
    int bitsPerSample() const { return bits_; }

protected:
    uint32_t rate_ = 0;
    int channels_ = 0;
    int bits_ = 0;
};

enum class SourceFormat { Flac, Mp3, Pcm, Dsd, Unknown };

/**
 * Chooses a decoder from the MIME type the controller or server reported.
 *
 * DLNA servers are inconsistent about these -- FLAC appears as audio/flac and
 * audio/x-flac, MP3 as audio/mpeg and audio/mp3 -- so matching is deliberately
 * loose. Content sniffing is the fallback when the type is absent or a
 * generic octet-stream.
 */
SourceFormat formatFromMime(const std::string &mime);
const char *formatName(SourceFormat f);
