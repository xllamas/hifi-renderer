#pragma once

#include <cstdint>
#include <string>
#include <vector>

#include "Decoder.h"

/**
 * DSD, carried to the DAC as DoP (DSD over PCM, open standard 1.1).
 *
 * DSD is one bit per sample at 2.8224 MHz and up, which no PCM alt-setting can
 * carry directly. DoP packs sixteen of those bits into the low 16 bits of an
 * ordinary 24-bit PCM frame and tags every frame with a marker byte that
 * alternates 0x05, 0xFA, so a DAC that understands DoP recognises the pattern
 * and reads the payload as DSD, while one that does not plays quiet noise.
 * Nothing about the stream is then special to the sink: it is 24-bit PCM at a
 * sixteenth of the DSD rate -- 176.4 kHz for DSD64.
 *
 * Two containers arrive here, and they share nothing but the payload:
 *
 *  - DSF (Sony): little-endian, and the audio is block-interleaved -- a whole
 *    4096-byte block of one channel, then the next channel's block. Bytes are
 *    usually LSB-first, so each is bit-reversed before packing.
 *  - DFF (Philips DSDIFF): big-endian, and the audio is byte-interleaved one
 *    byte per channel. Always MSB-first. Only the uncompressed form is
 *    accepted; DST is refused rather than decoded into noise.
 *
 * Both write their chunk sizes as 64-bit integers, which is where a copy of
 * the WAV/AIFF walk in PcmDecoder goes wrong.
 *
 * Bit order matters beyond tidiness: DoP wants the oldest sample in bit 7 of
 * each byte, and a stream packed the wrong way round is full-scale noise, not
 * an obvious failure.
 */
class DsdDecoder : public Decoder {
public:
    /**
     * [markerPhase] is which marker the first frame carries: 0 for 0x05, 1 for
     * 0xFA. A track that follows another without a gap has to carry on from
     * where the last one stopped, or the DAC drops out of DSD mode.
     */
    explicit DsdDecoder(int markerPhase = 0);

    bool open(NetworkStream *stream, std::string *error) override;
    uint64_t read(int32_t *out, uint64_t frames) override;
    void close() override;

    /** The marker the next frame will carry, for the track that follows. */
    int markerPhase() const { return phase_; }
    /** The DSD bit rate in Hz; sampleRate() is this divided by sixteen. */
    uint32_t dsdRate() const { return rate_ * 16; }

private:
    /** Reads up to n bytes, drawing on [carry_] first. Short means EOF. */
    size_t fill(uint8_t *dst, size_t n);
    /** Returns bytes to the head of the stream, for the next read to see. */
    void pushBack(const uint8_t *data, size_t n);
    /** Discards n bytes. False if the stream ended first. */
    bool skip(uint64_t n);

    bool readDsfHeader(std::string *error);
    bool readDffHeader(std::string *error);
    /** Checks the rate and channel count both headers must produce. */
    bool finishHeader(const char *container, uint64_t dsdRate, std::string *error);

    /** Loads the next run of audio into [planar_]. False at end of stream. */
    bool refill();
    bool refillDsf();
    bool refillDff();
    /** Left over bytes per channel that DoP has not consumed yet. */
    size_t buffered() const { return avail_ - pos_; }

    NetworkStream *stream_ = nullptr;
    std::vector<uint8_t> carry_;

    bool dsf_ = false;
    /** DSF's LSB-first files are bit-reversed on the way in; DFF never is. */
    bool reverseBits_ = false;

    /** DSF: bytes per channel in one block, and per channel still to come. */
    uint32_t blockSize_ = 0;
    uint64_t channelBytesLeft_ = 0;
    /** DFF: bytes of the data chunk still to come, all channels together. */
    uint64_t dataBytesLeft_ = 0;
    /** DFF streamed with a zero data size: the audio runs to end of stream. */
    bool dataToEof_ = false;

    /**
     * Audio waiting to be packed, one run of bytes per channel. Both
     * containers are turned into this shape on refill, so packing is the same
     * for either. [avail_] and [pos_] count bytes within each channel's run.
     */
    std::vector<uint8_t> planar_;
    std::vector<uint8_t> raw_;
    size_t capacity_ = 0;
    size_t avail_ = 0;
    size_t pos_ = 0;
    bool ended_ = false;

    /** 0 = the next frame's marker is 0x05, 1 = 0xFA. Survives across reads. */
    int phase_ = 0;
};
