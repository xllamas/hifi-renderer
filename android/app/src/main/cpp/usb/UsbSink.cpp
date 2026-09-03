#include "UsbSink.h"

#include <android/log.h>
#include <libusb.h>
#include <unistd.h>

#include <sys/resource.h>
#include <sched.h>

#include <algorithm>
#include <chrono>
#include <cstdarg>
#include <cstdio>
#include <cstring>

#define LOG_TAG "hifirend"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

namespace {

// 16 transfers x 8 packets. At high speed one packet is a 125 us microframe, so
// each transfer is 1 ms of audio and 16 ms stays in flight. 8 ms proved too
// shallow: a single scheduler stall longer than the queue starves the DAC, and
// that shows up as an audible glitch with no ring underrun to explain it.
constexpr int kNumTransfers = 16;
constexpr int kPacketsPerTransfer = 8;
constexpr int kMicroframesPerSecond = 8000;   // high speed
constexpr int kFramesPerSecondFull = 1000;    // full speed

constexpr uint8_t kReqCur = 0x01;
constexpr uint8_t kCsSamFreqControl = 0x01;

std::string sfmt(const char *f, ...) {
    char buf[512];
    va_list ap;
    va_start(ap, f);
    vsnprintf(buf, sizeof(buf), f, ap);
    va_end(ap);
    return std::string(buf);
}

}  // namespace

UsbSink::UsbSink() = default;

UsbSink::~UsbSink() {
    stop();
    close();
}

bool UsbSink::open(int fd, std::string *error) {
    int r = libusb_set_option(nullptr, LIBUSB_OPTION_NO_DEVICE_DISCOVERY);
    if (r != LIBUSB_SUCCESS) {
        *error = sfmt("libusb_set_option: %s", libusb_error_name(r));
        return false;
    }
    r = libusb_init(&ctx_);
    if (r != LIBUSB_SUCCESS) {
        *error = sfmt("libusb_init: %s", libusb_error_name(r));
        return false;
    }
    r = libusb_wrap_sys_device(ctx_, static_cast<intptr_t>(fd), &handle_);
    if (r != LIBUSB_SUCCESS || handle_ == nullptr) {
        *error = sfmt("libusb_wrap_sys_device(fd=%d): %s", fd, libusb_error_name(r));
        libusb_exit(ctx_);
        ctx_ = nullptr;
        return false;
    }
    caps_ = parseUacCapabilities(handle_);
    if (!caps_.ok) {
        *error = caps_.error;
        return false;
    }
    if (!caps_.isUac2()) {
        *error = "device is not USB Audio Class 2.0";
        return false;
    }
    return true;
}

bool UsbSink::configure(uint32_t rate, int sourceBits, int channels, std::string *error) {
    if (handle_ == nullptr) { *error = "not open"; return false; }

    if (!caps_.supportsRate(rate)) {
        *error = sfmt("device does not support %u Hz", rate);
        return false;
    }
    alt_ = caps_.chooseAltSetting(sourceBits, channels);
    if (alt_ == nullptr) {
        *error = sfmt("no PCM alt-setting holds %d-bit %dch", sourceBits, channels);
        return false;
    }
    rate_ = rate;
    channels_ = channels;
    bytesPerFrame_ = alt_->bytesPerFrame();

    // Claim the streaming interface before touching its alt-setting. force=true
    // detaches the kernel's snd-usb-audio driver, without which this fails.
    int r = libusb_claim_interface(handle_, alt_->interfaceNum);
    if (r != LIBUSB_SUCCESS) {
        *error = sfmt("claim_interface(%u): %s", alt_->interfaceNum, libusb_error_name(r));
        return false;
    }
    claimedStreaming_ = true;

    r = libusb_set_interface_alt_setting(handle_, alt_->interfaceNum, alt_->alt);
    if (r != LIBUSB_SUCCESS) {
        *error = sfmt("set_alt_setting(if=%u alt=%u): %s",
                      alt_->interfaceNum, alt_->alt, libusb_error_name(r));
        return false;
    }

    if (!setSampleRate(rate, error)) return false;

    // Some DACs need a moment after SET_INTERFACE/rate change before their
    // endpoint will accept data.
    usleep(50 * 1000);

    double perFrame = static_cast<double>(rate_) /
                      (caps_.highSpeed ? kMicroframesPerSecond : kFramesPerSecondFull);
    nominalQ16_ = static_cast<uint32_t>(perFrame * 65536.0);
    samplesPerFrameQ16_.store(nominalQ16_);
    packetAccum_ = 0.0;
    feedbackAccepted_.store(0);
    feedbackRejected_.store(0);

    // ~200 ms of audio. Generous: the decoder feeds from a normal thread that
    // Android may deschedule at will, while the USB side cannot wait.
    ring_ = std::make_unique<RingBuffer>(
        static_cast<size_t>(rate_) * bytesPerFrame_ / 5);

    LOGI("configure: %u Hz, source %d-bit -> alt %u (%d-bit in %d-byte slot), "
         "%d ch, %d B/frame, %s%s",
         rate_, sourceBits, alt_->alt, alt_->bits, alt_->subslot, channels_,
         bytesPerFrame_, alt_->data.sync.c_str(),
         alt_->feedback.present ? " +feedback" : " (NO feedback endpoint)");
    return true;
}

bool UsbSink::setSampleRate(uint32_t hz, std::string *error) {
    if (caps_.clockSourceId < 0) {
        *error = "no clock source entity found";
        return false;
    }
    uint8_t data[4] = {
        static_cast<uint8_t>(hz & 0xFF),
        static_cast<uint8_t>((hz >> 8) & 0xFF),
        static_cast<uint8_t>((hz >> 16) & 0xFF),
        static_cast<uint8_t>((hz >> 24) & 0xFF)};
    int r = libusb_control_transfer(
        handle_,
        LIBUSB_ENDPOINT_OUT | LIBUSB_REQUEST_TYPE_CLASS | LIBUSB_RECIPIENT_INTERFACE,
        kReqCur,
        static_cast<uint16_t>(kCsSamFreqControl << 8),
        static_cast<uint16_t>((caps_.clockSourceId << 8) | caps_.audioControlInterface),
        data, 4, 1000);
    if (r != 4) {
        *error = sfmt("set sample rate %u Hz failed: %s", hz,
                      r < 0 ? libusb_error_name(r) : "short write");
        return false;
    }
    return true;
}

void UsbSink::fillTransfer(libusb_transfer *t) {
    const uint32_t q16 = samplesPerFrameQ16_.load(std::memory_order_relaxed);
    const double perPacket = q16 / 65536.0;
    const int maxPacket = alt_->data.maxPacket;

    uint8_t *buf = t->buffer;
    int offset = 0;

    for (int p = 0; p < kPacketsPerTransfer; p++) {
        // Carry the fractional sample count across packets. At 44.1 kHz this is
        // 5.5125 samples per microframe, so packets must alternate 5 and 6 --
        // rounding every packet the same way would drift audibly.
        packetAccum_ += perPacket;
        int frames = static_cast<int>(packetAccum_);
        packetAccum_ -= frames;

        int want = frames * bytesPerFrame_;
        if (want > maxPacket) want = (maxPacket / bytesPerFrame_) * bytesPerFrame_;

        // While paused, emit silence and leave the ring untouched. This is not
        // an underrun -- counting it as one would bury real faults in noise.
        if (paused_.load(std::memory_order_acquire)) {
            memset(buf + offset, 0, static_cast<size_t>(want));
            t->iso_packet_desc[p].length = static_cast<unsigned int>(want);
            offset += want;
            continue;
        }

        size_t got = ring_->read(buf + offset, static_cast<size_t>(want));
        if (got < static_cast<size_t>(want)) {
            // Underrun: emit silence rather than a short packet. A short packet
            // would slew the DAC's clock recovery; silence merely costs a gap.
            memset(buf + offset + got, 0, static_cast<size_t>(want) - got);
            stats_.underruns.fetch_add(1, std::memory_order_relaxed);
        }

        t->iso_packet_desc[p].length = static_cast<unsigned int>(want);
        offset += want;
    }
    t->length = offset;
    stats_.framesSubmitted.fetch_add(
        static_cast<uint64_t>(offset / bytesPerFrame_), std::memory_order_relaxed);
}

void UsbSink::onDataComplete(libusb_transfer *t) {
    auto *self = static_cast<UsbSink *>(t->user_data);

    // Per-packet status is where isochronous dropouts actually appear; the
    // transfer-level status can be COMPLETED while packets inside it failed.
    uint64_t bad = 0;
    for (int i = 0; i < t->num_iso_packets; i++) {
        if (t->iso_packet_desc[i].status != LIBUSB_TRANSFER_COMPLETED) bad++;
    }
    if (bad) self->stats_.packetErrors.fetch_add(bad, std::memory_order_relaxed);
    self->stats_.packetsSubmitted.fetch_add(
        static_cast<uint64_t>(t->num_iso_packets), std::memory_order_relaxed);

    if (t->status != LIBUSB_TRANSFER_COMPLETED &&
        t->status != LIBUSB_TRANSFER_TIMED_OUT) {
        if (t->status != LIBUSB_TRANSFER_CANCELLED) {
            self->stats_.transferErrors.fetch_add(1, std::memory_order_relaxed);
        }
        if (t->status == LIBUSB_TRANSFER_NO_DEVICE ||
            t->status == LIBUSB_TRANSFER_CANCELLED) {
            self->inFlight_.fetch_sub(1, std::memory_order_acq_rel);
            return;
        }
    }
    if (!self->running_.load(std::memory_order_acquire)) {
        self->inFlight_.fetch_sub(1, std::memory_order_acq_rel);
        return;
    }
    self->fillTransfer(t);
    if (libusb_submit_transfer(t) != LIBUSB_SUCCESS) {
        self->inFlight_.fetch_sub(1, std::memory_order_acq_rel);
    }
}

void UsbSink::handleFeedback(libusb_transfer *t) {
    if (t->status != LIBUSB_TRANSFER_COMPLETED) return;
    if (t->num_iso_packets < 1) return;
    const libusb_iso_packet_descriptor &d = t->iso_packet_desc[0];
    if (d.status != LIBUSB_TRANSFER_COMPLETED || d.actual_length < 3) return;

    const uint8_t *p = libusb_get_iso_packet_buffer_simple(t, 0);
    uint32_t q16;
    if (d.actual_length >= 4) {
        // High speed: 16.16 samples per microframe.
        uint32_t raw = p[0] | (p[1] << 8) | (p[2] << 16) |
                       (static_cast<uint32_t>(p[3]) << 24);
        q16 = raw;
    } else {
        // Full speed: 10.14 samples per frame, three bytes.
        uint32_t raw = p[0] | (p[1] << 8) | (static_cast<uint32_t>(p[2]) << 16);
        q16 = raw << 2;  // 10.14 -> 16.16
    }

    // Validate against the CONFIGURED nominal, never against the running value.
    // A real DAC's clock is within a fraction of a percent of nominal; anything
    // outside 2% is a misread, not a genuine deviation.
    if (nominalQ16_ != 0) {
        const uint32_t tolerance = nominalQ16_ / 50;  // 2%
        if (q16 < nominalQ16_ - tolerance || q16 > nominalQ16_ + tolerance) {
            feedbackRejected_.fetch_add(1, std::memory_order_relaxed);
            stats_.lastFeedbackRaw.store(q16, std::memory_order_relaxed);
            return;
        }
    }
    feedbackAccepted_.fetch_add(1, std::memory_order_relaxed);
    samplesPerFrameQ16_.store(q16, std::memory_order_relaxed);

    const double perMicroframe = q16 / 65536.0;
    stats_.feedbackRateMilliHz.store(
        static_cast<uint32_t>(perMicroframe *
            (caps_.highSpeed ? kMicroframesPerSecond : kFramesPerSecondFull) * 1000.0),
        std::memory_order_relaxed);
}

void UsbSink::onFeedbackComplete(libusb_transfer *t) {
    auto *self = static_cast<UsbSink *>(t->user_data);
    self->handleFeedback(t);
    if (!self->running_.load(std::memory_order_acquire)) {
        self->inFlight_.fetch_sub(1, std::memory_order_acq_rel);
        return;
    }
    if (libusb_submit_transfer(t) != LIBUSB_SUCCESS) {
        self->inFlight_.fetch_sub(1, std::memory_order_acq_rel);
    }
}

void UsbSink::eventLoop() {
    // Audio deadlines are hard: a stall longer than the in-flight queue starves
    // the DAC. Ask for real-time scheduling, and settle for the highest nice
    // value if the platform refuses (Android usually denies SCHED_FIFO to
    // ordinary apps).
    sched_param sp{};
    sp.sched_priority = 10;
    if (sched_setscheduler(0, SCHED_FIFO, &sp) != 0) {
        setpriority(PRIO_PROCESS, 0, -19);
    }

    // Nothing in this loop may log or allocate.
    while (running_.load(std::memory_order_acquire) ||
           inFlight_.load(std::memory_order_acquire) > 0) {
        timeval tv{0, 100 * 1000};
        libusb_handle_events_timeout_completed(ctx_, &tv, nullptr);
    }
}

void UsbSink::monitorLoop() {
    auto lastLog = std::chrono::steady_clock::now();
    while (running_.load(std::memory_order_acquire)) {
        // Short slices so stop() is not held up for a whole logging interval.
        std::this_thread::sleep_for(std::chrono::milliseconds(100));
        if (!running_.load(std::memory_order_acquire)) break;
        auto now = std::chrono::steady_clock::now();
        if (now - lastLog < std::chrono::seconds(2)) continue;
        lastLog = now;
        LOGI("stats: frames=%llu underruns=%llu xferErr=%llu pktErr=%llu/%llu "
             "fb(ok=%u rej=%u raw=0x%08x) rate=%.1f Hz ring=%zu%%",
             static_cast<unsigned long long>(stats_.framesSubmitted.load()),
             static_cast<unsigned long long>(stats_.underruns.load()),
             static_cast<unsigned long long>(stats_.transferErrors.load()),
             static_cast<unsigned long long>(stats_.packetErrors.load()),
             static_cast<unsigned long long>(stats_.packetsSubmitted.load()),
             feedbackAccepted_.load(), feedbackRejected_.load(),
             stats_.lastFeedbackRaw.load(),
             stats_.feedbackRateMilliHz.load() / 1000.0,
             ring_ ? ring_->available() * 100 / std::max<size_t>(ring_->capacity(), 1) : 0);
    }
}

bool UsbSink::start(std::string *error) {
    if (alt_ == nullptr) { *error = "not configured"; return false; }
    if (running_.load()) return true;

    const int maxPacket = alt_->data.maxPacket;
    running_.store(true, std::memory_order_release);

    for (int i = 0; i < kNumTransfers; i++) {
        libusb_transfer *t = libusb_alloc_transfer(kPacketsPerTransfer);
        if (t == nullptr) { *error = "alloc_transfer failed"; running_.store(false); return false; }
        auto *buf = static_cast<uint8_t *>(calloc(1, static_cast<size_t>(maxPacket) * kPacketsPerTransfer));
        libusb_fill_iso_transfer(t, handle_, alt_->data.address, buf,
                                 maxPacket * kPacketsPerTransfer, kPacketsPerTransfer,
                                 &UsbSink::onDataComplete, this, 1000);
        libusb_set_iso_packet_lengths(t, static_cast<unsigned int>(maxPacket));
        t->flags = LIBUSB_TRANSFER_FREE_BUFFER;
        fillTransfer(t);
        int r = libusb_submit_transfer(t);
        if (r != LIBUSB_SUCCESS) {
            *error = sfmt("submit iso transfer %d: %s", i, libusb_error_name(r));
            libusb_free_transfer(t);
            running_.store(false);
            return false;
        }
        inFlight_.fetch_add(1, std::memory_order_acq_rel);
        transfers_.push_back(t);
    }

    // The feedback endpoint is what keeps an asynchronous DAC from drifting.
    if (alt_->feedback.present) {
        const int fbLen = std::max<int>(alt_->feedback.maxPacket, 4);
        feedbackBuf_.assign(static_cast<size_t>(fbLen), 0);
        feedbackTransfer_ = libusb_alloc_transfer(1);
        libusb_fill_iso_transfer(feedbackTransfer_, handle_, alt_->feedback.address,
                                 feedbackBuf_.data(), fbLen, 1,
                                 &UsbSink::onFeedbackComplete, this, 1000);
        libusb_set_iso_packet_lengths(feedbackTransfer_, static_cast<unsigned int>(fbLen));
        int r = libusb_submit_transfer(feedbackTransfer_);
        if (r == LIBUSB_SUCCESS) {
            inFlight_.fetch_add(1, std::memory_order_acq_rel);
        } else {
            LOGE("feedback submit failed: %s -- clock will free-run", libusb_error_name(r));
            libusb_free_transfer(feedbackTransfer_);
            feedbackTransfer_ = nullptr;
        }
    }

    eventThread_ = std::thread(&UsbSink::eventLoop, this);
    monitorThread_ = std::thread(&UsbSink::monitorLoop, this);
    LOGI("start: %d transfers x %d packets, maxPacket=%d, feedback=%s",
         kNumTransfers, kPacketsPerTransfer, maxPacket,
         feedbackTransfer_ ? "yes" : "no");
    return true;
}

void UsbSink::stop() {
    // Single, idempotent teardown order. The previous version had two separate
    // join paths, so two threads calling stop() concurrently could both pass
    // joinable() and both join the same thread -- which throws system_error and
    // aborts the process.
    if (running_.exchange(false)) {
        for (auto *t : transfers_) libusb_cancel_transfer(t);
        if (feedbackTransfer_) libusb_cancel_transfer(feedbackTransfer_);
    }
    if (eventThread_.joinable()) eventThread_.join();
    if (monitorThread_.joinable()) monitorThread_.join();
    for (auto *t : transfers_) libusb_free_transfer(t);
    transfers_.clear();
    if (feedbackTransfer_) {
        libusb_free_transfer(feedbackTransfer_);
        feedbackTransfer_ = nullptr;
    }
}

void UsbSink::close() {
    if (handle_ != nullptr) {
        if (claimedStreaming_ && alt_ != nullptr) {
            // Back to the zero-bandwidth alt so the DAC stops clocking, then
            // release so the kernel driver can rebind and system audio returns.
            libusb_set_interface_alt_setting(handle_, alt_->interfaceNum, 0);
            libusb_release_interface(handle_, alt_->interfaceNum);
            claimedStreaming_ = false;
        }
        libusb_close(handle_);
        handle_ = nullptr;
    }
    if (ctx_ != nullptr) {
        libusb_exit(ctx_);
        ctx_ = nullptr;
    }
    ring_.reset();
    alt_ = nullptr;
}

std::string UsbSink::statusJson() const {
    const uint32_t fb = stats_.feedbackRateMilliHz.load();
    return sfmt(
        "{\"running\":%s,\"paused\":%s,\"rate\":%u,\"altSetting\":%d,\"deviceBits\":%d,"
        "\"subslot\":%d,\"bytesPerFrame\":%d,\"framesSubmitted\":%llu,"
        "\"underruns\":%llu,\"transferErrors\":%llu,\"measuredRateHz\":%.1f,"
        "\"feedbackAccepted\":%u,\"feedbackRejected\":%u,"
        "\"packetErrors\":%llu,\"packetsSubmitted\":%llu,\"ringFillPercent\":%d}",
        running_.load() ? "true" : "false",
        paused_.load() ? "true" : "false", rate_, altSetting(), deviceBits(),
        deviceSubslot(), bytesPerFrame_,
        static_cast<unsigned long long>(stats_.framesSubmitted.load()),
        static_cast<unsigned long long>(stats_.underruns.load()),
        static_cast<unsigned long long>(stats_.transferErrors.load()),
        fb / 1000.0, feedbackAccepted_.load(), feedbackRejected_.load(),
        static_cast<unsigned long long>(stats_.packetErrors.load()),
        static_cast<unsigned long long>(stats_.packetsSubmitted.load()),
        ring_ ? static_cast<int>(ring_->available() * 100 / std::max<size_t>(ring_->capacity(), 1)) : 0);
}
