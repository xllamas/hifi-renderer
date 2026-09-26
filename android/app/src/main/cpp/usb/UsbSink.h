#pragma once

#include <atomic>
#include <memory>
#include <string>
#include <thread>
#include <vector>

#include "../RingBuffer.h"
#include "../sink/AudioSink.h"
#include "DopFraming.h"
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
    std::atomic<uint64_t> rebuffers{0};
    std::atomic<uint32_t> feedbackRateMilliHz{0};
    std::atomic<uint32_t> lastFeedbackRaw{0};
};

// Streams PCM to a USB Audio Class device over isochronous transfers.
//
// UAC2 and UAC1 differ in how the rate is negotiated and in how the device
// keeps time. UAC2 has a clock entity and, usually, an asynchronous endpoint
// with a feedback pipe the host tracks. UAC1 has neither: the rate belongs to
// the endpoint, the alt-setting *is* the rate selection, and endpoints are
// commonly adaptive, meaning the device follows the host instead. Both land in
// the same transfer loop -- with no feedback readings the nominal packet size
// simply stands, which is exactly right for an adaptive endpoint.
//
// This is the whole reason the project has a native layer: Android's
// UsbDeviceConnection offers only control, bulk and interrupt transfers, and
// USB audio streaming is isochronous. libusb reaches it via usbfs ioctls on the
// file descriptor Android hands us.
//
// No sample is altered on the way through -- no resampling, no mixing, no
// volume. Where the DAC's container is wider than the source, samples are
// left-justified and zero-padded, which preserves their values exactly.
class UsbSink : public AudioSink {
public:
    UsbSink();
    ~UsbSink();

    // fd is owned by the caller's UsbDeviceConnection and must outlive the sink.
    bool open(int fd, std::string *error) override;

    const UacCapabilities &capabilities() const { return caps_; }

    // Configures the stream. sourceBits selects the alt-setting; the DAC's
    // container may be wider.
    bool configure(uint32_t rate, int sourceBits, int channels, std::string *error) override;

    bool start(std::string *error) override;
    void stop() override;
    void close() override;

    // Producer side: returns bytes accepted, in the DAC's wire format.
    size_t write(const uint8_t *pcm, size_t bytes) override { return ring_ ? ring_->write(pcm, bytes) : 0; }
    size_t ringSpace() const override { return ring_ ? ring_->space() : 0; }
    size_t ringAvailable() const override { return ring_ ? ring_->available() : 0; }

    /**
     * Pause emits silence without draining the ring, so everything upstream
     * stalls naturally: the decoder blocks on a full ring, the HTTP fetch
     * blocks on a full network buffer, and nothing loses its place. Keeping the
     * isochronous stream open also avoids re-negotiating the alt-setting on
     * resume, which the DAC would render as a click.
     */
    void setDop(bool dop) override {
        dop_.configure(channels_, bytesPerFrame_ / (channels_ > 0 ? channels_ : 1));
        dopOn_.store(dop, std::memory_order_release);
    }
    void setPaused(bool paused) override { paused_.store(paused, std::memory_order_release); }
    bool paused() const { return paused_.load(std::memory_order_acquire); }

    /**
     * Rebuffering: the source could not keep up and we are deliberately
     * holding output silent until enough audio has accumulated again.
     *
     * Distinct from an underrun. An underrun is a fault -- audio should have
     * been there and was not. A stall is the engine choosing one clean pause
     * over thousands of individually broken packets, so it is counted as a
     * rebuffer event and not as a fault.
     */
    void setStalled(bool stalled) override { stalled_.store(stalled, std::memory_order_release); }
    bool stalled() const { return stalled_.load(std::memory_order_acquire); }
    void noteRebuffer() override { stats_.rebuffers.fetch_add(1, std::memory_order_relaxed); }

    /**
     * The decoder has reached the end of the source.
     *
     * Remaining audio still drains normally, but once the ring empties the
     * silence that follows is not an underrun -- there is nothing left to
     * starve on. Counting it would add hundreds of phantom faults per track and
     * make the one number that signals real dropouts useless.
     */
    void setSourceEnded(bool ended) override { sourceEnded_.store(ended, std::memory_order_release); }

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
    bool getVolumePercent(int *percent) override;
    bool setVolumePercent(int percent) override;

    const SinkStats &stats() const { return stats_; }
    uint32_t rate() const { return rate_; }
    int deviceBits() const { return alt_ ? alt_->bits : 0; }
    int deviceSubslot() const override { return alt_ ? alt_->subslot : 0; }
    int altSetting() const { return alt_ ? alt_->alt : -1; }
    bool running() const { return running_.load(); }

    std::string statusJson() const override;

    /**
     * Samples reach the DAC untouched; that is the point of this sink.
     *
     * True of everything this class does to them, and of nothing that happened
     * before they arrived -- a guest's AirPlay stream is resampled by the
     * sender and is not made bit-perfect by being carried faithfully from
     * here. Reporting the chain is StreamPlayer's job, not this one's.
     */
    bool bitPerfect() const override { return true; }
    const char *outputName() const override { return "usb"; }

private:
    static void onDataComplete(libusb_transfer *t);
    static void onFeedbackComplete(libusb_transfer *t);
    void fillTransfer(libusb_transfer *t);
    void handleFeedback(libusb_transfer *t);
    bool selectAltSetting(std::string *error);
    bool setSampleRate(uint32_t hz, std::string *error);
    void checkVolumeReadback(int16_t written);
    bool volumeValueSane(int16_t raw) const;
    bool setSampleRateUac1(uint32_t hz, std::string *error);
    void silence(uint8_t *dst, size_t bytes);
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
    // DSD as DoP: every frame sent, decoded or idle, gets its marker from
    // one counter here. See DopFraming.
    std::atomic<bool> dopOn_{false};
    DopFraming dop_;
    std::atomic<bool> sourceEnded_{false};
    std::atomic<bool> stalled_{false};
    // Raw device units (1/256 dB). 0x8000 means "silence" in the spec.
    int16_t volMin_ = 0, volMax_ = 0, volRes_ = 1;
    bool volRangeKnown_ = false;
    int lastVolumeLogged_ = -2;

    /**
     * Whether the device reports its own volume back honestly.
     *
     * Some devices accept SET_CUR and change the volume, but answer GET_CUR
     * with a fixed value -- the reference UAC1 dongle always says 0 dB, its
     * maximum. Polling such a device overwrites what the user just chose with a
     * lie, a second or two after they chose it.
     *
     * Detected by reading back once after a write rather than by recognising
     * the device: nothing here may branch on VID/PID, and a device that lies
     * about this is exactly the kind of thing the app exists to catch.
     */
public:
    VolumeLearning volumeLearning() const override {
        return VolumeLearning{volumeReadback_, lastSetPercent_, probeRaw_, haveProbe_};
    }
    void adoptVolumeLearning(const VolumeLearning &v) override {
        volumeReadback_ = v.readback;
        lastSetPercent_ = v.lastSetPercent;
        probeRaw_ = v.provenAtRaw;
        haveProbe_ = v.haveProbe;
    }

private:
    Readback volumeReadback_ = Readback::Unknown;
    int lastSetPercent_ = -1;
    int16_t probeRaw_ = 0;
    bool haveProbe_ = false;
    std::atomic<int> inFlight_{0};
    std::thread eventThread_;
    // Logging happens here, never on the event thread: __android_log_print can
    // block for milliseconds, which is fatal on a thread with 125 us deadlines.
    std::thread monitorThread_;
    SinkStats stats_;
};
