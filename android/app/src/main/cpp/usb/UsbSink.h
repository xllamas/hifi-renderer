#pragma once

#include <atomic>
#include <memory>
#include <string>
#include <thread>
#include <vector>

#include "../RingBuffer.h"
#include "UacCapabilities.h"

struct libusb_context;
struct libusb_device_handle;
struct libusb_transfer;

struct SinkStats {
    std::atomic<uint64_t> framesSubmitted{0};
    std::atomic<uint64_t> underruns{0};
    std::atomic<uint64_t> transferErrors{0};
    // Per-PACKET failures. An isochronous transfer can report COMPLETED overall
    // while individual packets failed, so transfer-level status alone is blind
    // to most real dropouts.
    std::atomic<uint64_t> packetErrors{0};
    std::atomic<uint64_t> packetsSubmitted{0};
    std::atomic<uint32_t> feedbackRateMilliHz{0};
    std::atomic<uint32_t> lastFeedbackRaw{0};
};

// Streams PCM to a USB Audio Class 2.0 device over isochronous transfers.
//
// This is the whole reason the project has a native layer: Android's
// UsbDeviceConnection offers only control, bulk and interrupt transfers, and
// USB audio streaming is isochronous. libusb reaches it via usbfs ioctls on the
// file descriptor Android hands us.
//
// No sample is altered on the way through -- no resampling, no mixing, no
// volume. Where the DAC's container is wider than the source, samples are
// left-justified and zero-padded, which preserves their values exactly.
class UsbSink {
public:
    UsbSink();
    ~UsbSink();

    // fd is owned by the caller's UsbDeviceConnection and must outlive the sink.
    bool open(int fd, std::string *error);

    const UacCapabilities &capabilities() const { return caps_; }

    // Configures the stream. sourceBits selects the alt-setting; the DAC's
    // container may be wider.
    bool configure(uint32_t rate, int sourceBits, int channels, std::string *error);

    bool start(std::string *error);
    void stop();
    void close();

    // Producer side: returns bytes accepted, in the DAC's wire format.
    size_t write(const uint8_t *pcm, size_t bytes) { return ring_ ? ring_->write(pcm, bytes) : 0; }
    size_t ringSpace() const { return ring_ ? ring_->space() : 0; }
    size_t ringAvailable() const { return ring_ ? ring_->available() : 0; }

    /**
     * Pause emits silence without draining the ring, so everything upstream
     * stalls naturally: the decoder blocks on a full ring, the HTTP fetch
     * blocks on a full network buffer, and nothing loses its place. Keeping the
     * isochronous stream open also avoids re-negotiating the alt-setting on
     * resume, which the DAC would render as a click.
     */
    void setPaused(bool paused) { paused_.store(paused, std::memory_order_release); }
    bool paused() const { return paused_.load(std::memory_order_acquire); }

    /**
     * The decoder has reached the end of the source.
     *
     * Remaining audio still drains normally, but once the ring empties the
     * silence that follows is not an underrun -- there is nothing left to
     * starve on. Counting it would add hundreds of phantom faults per track and
     * make the one number that signals real dropouts useless.
     */
    void setSourceEnded(bool ended) { sourceEnded_.store(ended, std::memory_order_release); }

    /**
     * Volume via the UAC Feature Unit.
     *
     * Values travel as signed 16-bit hundredths-of-a-decibel (1/256 dB in the
     * spec's fixed-point), over a *control* transfer, so setting volume never
     * disturbs the isochronous stream. Many DACs -- integrated amps with a
     * physical knob especially -- expose no Feature Unit at all, which is a
     * normal outcome and not an error.
     */
    bool volumeSupported() const {
        return caps_.volumeHostControllable && caps_.featureUnitId >= 0;
    }
    bool readVolumeRange();
    bool getVolumePercent(int *percent);
    bool setVolumePercent(int percent);

    const SinkStats &stats() const { return stats_; }
    uint32_t rate() const { return rate_; }
    int deviceBits() const { return alt_ ? alt_->bits : 0; }
    int deviceSubslot() const { return alt_ ? alt_->subslot : 0; }
    int altSetting() const { return alt_ ? alt_->alt : -1; }
    bool running() const { return running_.load(); }

    std::string statusJson() const;

private:
    static void onDataComplete(libusb_transfer *t);
    static void onFeedbackComplete(libusb_transfer *t);
    void fillTransfer(libusb_transfer *t);
    void handleFeedback(libusb_transfer *t);
    bool setSampleRate(uint32_t hz, std::string *error);
    void eventLoop();
    void monitorLoop();

    libusb_context *ctx_ = nullptr;
    libusb_device_handle *handle_ = nullptr;
    UacCapabilities caps_;
    const UacAltSetting *alt_ = nullptr;

    uint32_t rate_ = 0;
    int channels_ = 2;
    int bytesPerFrame_ = 0;
    bool claimedStreaming_ = false;

    std::unique_ptr<RingBuffer> ring_;
    std::vector<libusb_transfer *> transfers_;
    libusb_transfer *feedbackTransfer_ = nullptr;
    std::vector<uint8_t> feedbackBuf_;

    // Samples per microframe in Q16.16, driven by the feedback endpoint. The
    // fractional part is carried across packets so the long-run average matches
    // the DAC's clock exactly rather than drifting.
    std::atomic<uint32_t> samplesPerFrameQ16_{0};
    // The rate implied by the configured sample rate. Feedback readings are
    // always validated against THIS, never against the running value -- doing
    // the latter lets each accepted reading become the new baseline, so small
    // errors ratchet the rate upward without bound.
    uint32_t nominalQ16_ = 0;
    std::atomic<uint32_t> feedbackAccepted_{0};
    std::atomic<uint32_t> feedbackRejected_{0};
    double packetAccum_ = 0.0;

    std::atomic<bool> running_{false};
    std::atomic<bool> paused_{false};
    std::atomic<bool> sourceEnded_{false};
    // Raw device units (1/256 dB). 0x8000 means "silence" in the spec.
    int16_t volMin_ = 0, volMax_ = 0, volRes_ = 1;
    bool volRangeKnown_ = false;
    std::atomic<int> inFlight_{0};
    std::thread eventThread_;
    // Logging happens here, never on the event thread: __android_log_print can
    // block for milliseconds, which is fatal on a thread with 125 us deadlines.
    std::thread monitorThread_;
    SinkStats stats_;
};
