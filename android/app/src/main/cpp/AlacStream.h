#pragma once

#include <cstdint>
#include <memory>
#include <vector>

class ALACDecoder;

/**
 * Decodes the ALAC frames an AirPlay sender pushes at us.
 *
 * Nothing else in this app decodes this way. Every other format is pulled
 * through [Decoder] from a NetworkStream, because the renderer fetches those
 * itself and can read ahead. AirPlay is the opposite shape: the sender decides
 * when bytes exist, they arrive one RTP packet at a time, and each packet is a
 * complete independently decodable frame. A pull decoder cannot express that
 * without a queue and a blocking read in front of it, which is machinery for
 * no gain.
 *
 * Configuration comes from the SDP rather than from the stream. RAOP sends
 * raw frames with no container and no magic cookie, and the parameters live in
 * the `fmtp` line of the ANNOUNCE:
 *
 *     a=fmtp:96 352 0 16 40 10 14 2 255 0 0 44100
 *              ^--frameLength                ^--sampleRate
 *
 * which maps one-for-one onto the ALACSpecificConfig the reference decoder
 * wants. Getting that mapping wrong does not fail -- it decodes noise -- so
 * the field order is spelled out at the call site.
 */
class AlacStream {
public:
    AlacStream();
    ~AlacStream();

    /** Builds the magic cookie from the fmtp fields and initialises. */
    bool configure(uint32_t frameLength, uint8_t compatibleVersion, uint8_t bitDepth,
                   uint8_t pb, uint8_t mb, uint8_t kb, uint8_t channels,
                   uint16_t maxRun, uint32_t maxFrameBytes, uint32_t avgBitRate,
                   uint32_t sampleRate);

    /**
     * Decodes one frame into interleaved little-endian PCM.
     *
     * Returns the number of bytes written to [out], or 0 if the frame could
     * not be decoded. [out] must have room for frameLength * channels *
     * (bitDepth/8) bytes.
     */
    int decode(const uint8_t *frame, int length, uint8_t *out, int outCapacity);

    bool ready() const { return decoder_ != nullptr; }
    int channels() const { return channels_; }
    int bitDepth() const { return bitDepth_; }
    uint32_t sampleRate() const { return sampleRate_; }
    uint32_t frameLength() const { return frameLength_; }

private:
    std::unique_ptr<ALACDecoder> decoder_;
    std::vector<uint8_t> cookie_;
    int channels_ = 2;
    int bitDepth_ = 16;
    uint32_t sampleRate_ = 44100;
    uint32_t frameLength_ = 352;
};
