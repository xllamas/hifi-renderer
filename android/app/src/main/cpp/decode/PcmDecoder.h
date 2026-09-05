#pragma once

#include <cstdint>
#include <string>
#include <vector>

#include "Decoder.h"

/**
 * Raw PCM: the L16/L24 a transcoding server sends, and the two chunked
 * containers that hold nothing but PCM -- WAV and AIFF.
 *
 * None of them is something the other decoders would recognise. L16 and L24
 * have no header at all -- the sample rate and channel count live in the MIME
 * type and nowhere else -- and WAV and AIFF announce themselves with a chunk
 * list rather than a codec header, so all three arrive here.
 *
 * Byte order is the one thing that must not be guessed, and all three
 * disagree. DLNA's L16 and L24 are big-endian (RFC 2586), as is AIFF; WAV is
 * little-endian, and so is AIFC's 'sowt' encoding despite its big-endian
 * container. Reading any of them the wrong way round yields full-scale noise
 * rather than an obvious failure, which is the sort of mistake that reaches a
 * pair of speakers before it reaches a log.
 *
 * Sign is the other trap: 8-bit samples are unsigned in WAV and signed in
 * AIFF, and every other depth is signed in both.
 */
class PcmDecoder : public Decoder {
public:
    /** [mime] carries the rate and channel count for headerless L16/L24. */
    explicit PcmDecoder(std::string mime);

    bool open(NetworkStream *stream, std::string *error) override;
    uint64_t read(int32_t *out, uint64_t frames) override;
    void close() override;

private:
    /** Reads up to n bytes, drawing on [carry_] first. Short means EOF. */
    size_t fill(uint8_t *dst, size_t n);
    /** Returns bytes to the head of the stream, for the next read to see. */
    void pushBack(const uint8_t *data, size_t n);
    /** Discards n bytes. False if the stream ended first. */
    bool skip(uint64_t n);
    /** Walks the chunk list to "data", taking the format from "fmt ". */
    bool readWavHeader(std::string *error);
    /**
     * Walks the chunk list to "SSND", taking the format from "COMM".
     * [compressed] marks an AIFC container, whose COMM names an encoding.
     */
    bool readAiffHeader(bool compressed, std::string *error);
    /**
     * Maps a declared sample size onto the wire container and the depth the
     * sink is configured for. [unsigned8] is WAV's quirk alone.
     */
    bool setSampleSize(int sampleBits, bool unsigned8, std::string *error);

    const std::string mime_;
    NetworkStream *stream_ = nullptr;

    /**
     * Bytes read ahead of where the reader is: the signature sniffed by
     * [open], and any partial trailing frame left by a short read. Both have
     * to be seen before anything more is pulled from the stream.
     */
    std::vector<uint8_t> carry_;
    std::vector<uint8_t> bytes_;

    /** Bytes per sample on the wire, which is not always bitsPerSample()/8. */
    int containerBytes_ = 2;
    bool bigEndian_ = true;
    /** 8-bit WAV, and only 8-bit WAV, stores samples unsigned. */
    bool unsignedSamples_ = false;
    /** What the container is called, for the log line and for error text. */
    const char *containerName_ = "L16/L24";
};
