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
#include <cstdlib>
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
constexpr uint8_t kReqRange = 0x02;   // UAC2: min/max/res in one reply

// UAC1 encodes direction in the request code itself: SET_x in the low nibble,
// GET_x with bit 7 set. UAC2 dropped that -- there the direction lives only in
// bmRequestType and CUR is 0x01 either way. Reusing the UAC2 codes for a UAC1
// read asks the device to SET what we meant to GET, and it stalls.
constexpr uint8_t kUac1GetCur = 0x81;
constexpr uint8_t kUac1GetMin = 0x82;
constexpr uint8_t kUac1GetMax = 0x83;
constexpr uint8_t kUac1GetRes = 0x84;
constexpr uint8_t kCsSamFreqControl = 0x01;
constexpr uint8_t kFuVolumeControl = 0x02;

/**
 * Routes libusb's own diagnostics into logcat.
 *
 * libusb collapses most ioctl failures into LIBUSB_ERROR_OTHER and puts the
 * real errno only in its internal log, which on Android goes to a native stderr
 * nothing reads. That is the difference between "set_alt_setting failed" and
 * knowing the kernel said EBUSY -- and on foreign hardware, that difference is
 * the whole diagnosis.
 */
void libusbLog(libusb_context *, enum libusb_log_level level, const char *str) {
    __android_log_print(level == LIBUSB_LOG_LEVEL_ERROR ? ANDROID_LOG_ERROR
                                                        : ANDROID_LOG_WARN,
                        LOG_TAG, "libusb: %s", str);
}

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
    libusb_set_log_cb(ctx_, libusbLog, LIBUSB_LOG_CB_CONTEXT);
    libusb_set_option(ctx_, LIBUSB_OPTION_LOG_LEVEL, LIBUSB_LOG_LEVEL_WARNING);
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
    if (caps_.uacVersion == 0) {
        *error = "device reports no USB Audio Class version";
        return false;
    }
    // A device can be a valid audio device and still be no use to a renderer:
    // a USB microphone, or the capture half of a headset adapter. Rejecting on
    // the absence of an output rather than on the class version is what lets
    // UAC1 devices through.
    if (!caps_.hasPlayableAltSetting()) {
        *error = "device has no PCM isochronous output endpoint";
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
    alt_ = caps_.chooseAltSetting(sourceBits, channels, rate);
    if (alt_ == nullptr) {
        *error = sfmt("no PCM alt-setting holds %d-bit %dch at %u Hz",
                      sourceBits, channels, rate);
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

    if (!selectAltSetting(error)) return false;

    if (!setSampleRate(rate, error)) return false;

    // Some DACs need a moment after SET_INTERFACE/rate change before their
    // endpoint will accept data.
    usleep(50 * 1000);

    double perFrame = static_cast<double>(rate_) /
                      (caps_.highSpeed ? kMicroframesPerSecond : kFramesPerSecondFull);
    sourceEnded_.store(false);
    stalled_.store(false);
    nominalQ16_ = static_cast<uint32_t>(perFrame * 65536.0);
    samplesPerFrameQ16_.store(nominalQ16_);
    packetAccum_ = 0.0;
    feedbackAccepted_.store(0);
    feedbackRejected_.store(0);

    // Two seconds of audio, bounded so very high rates cannot run away.
    //
    // This is sized against the *network*, not the scheduler. At 192 kHz/24-bit
    // the DAC drains 1.5 MB/s and a FLAC stream must sustain ~7.4 Mbps; the
    // previous 200 ms held only 300 ms of slack and starved for a full minute
    // before Wi-Fi caught up. Lower rates never showed it because their drain
    // rate is a quarter of this.
    const size_t twoSeconds = static_cast<size_t>(rate_) * bytesPerFrame_ * 2;
    const size_t ringBytes = std::clamp<size_t>(twoSeconds, 512u * 1024, 8u * 1024 * 1024);
    ring_ = std::make_unique<RingBuffer>(ringBytes);
    LOGI("ring: %zu bytes = %.0f ms at %u Hz", ringBytes,
         1000.0 * ringBytes / (static_cast<double>(rate_) * bytesPerFrame_), rate_);

    LOGI("configure: %u Hz, source %d-bit -> alt %u (%d-bit in %d-byte slot), "
         "%d ch, %d B/frame, %s%s",
         rate_, sourceBits, alt_->alt, alt_->bits, alt_->subslot, channels_,
         bytesPerFrame_, alt_->data.sync.c_str(),
         alt_->feedback.present ? " +feedback" : " (NO feedback endpoint)");
    return true;
}

/**
 * Selects the streaming alt-setting, from whatever state the device is in.
 *
 * A device is not reliably idle when we arrive. If a previous run was killed,
 * or the device stalled the teardown request, it is still sitting in a
 * streaming alt-setting -- and firmware that is asked to re-select the
 * alt-setting it already holds is entitled to stall, which is what the
 * reference UAC1 device does. The symptom is brutal to diagnose from the
 * outside: the first track after a fresh start plays, every later one is
 * silent, because the first is the only one that found the device at alt 0.
 *
 * So the interface is driven to alt 0 first and only then to the target. The
 * reset is best-effort: a device already at alt 0 may stall that too, and it
 * has still told us what we needed to know.
 */
bool UsbSink::selectAltSetting(std::string *error) {
    int r = libusb_set_interface_alt_setting(handle_, alt_->interfaceNum, 0);
    if (r != LIBUSB_SUCCESS) {
        LOGI("alt reset(if=%u -> 0): %s (continuing)", alt_->interfaceNum,
             libusb_error_name(r));
    }

    r = libusb_set_interface_alt_setting(handle_, alt_->interfaceNum, alt_->alt);
    if (r == LIBUSB_SUCCESS) return true;

    // One retry. A device that has just been dropped out of a streaming
    // alt-setting can need a moment before it will accept the next one.
    LOGI("set_alt_setting(if=%u alt=%u): %s -- retrying",
         alt_->interfaceNum, alt_->alt, libusb_error_name(r));
    usleep(50 * 1000);
    r = libusb_set_interface_alt_setting(handle_, alt_->interfaceNum, alt_->alt);
    if (r == LIBUSB_SUCCESS) return true;

    *error = sfmt("set_alt_setting(if=%u alt=%u): %s",
                  alt_->interfaceNum, alt_->alt, libusb_error_name(r));
    return false;
}

bool UsbSink::setSampleRate(uint32_t hz, std::string *error) {
    if (!caps_.isUac2()) return setSampleRateUac1(hz, error);

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

/**
 * UAC1 rate setting.
 *
 * UAC1 predates the clock-entity model entirely: there is no clock source to
 * address, and the rate is a property of the streaming *endpoint*, set with a
 * class request whose recipient is the endpoint rather than the interface. The
 * value is three bytes, not four.
 *
 * The request is only legal once the non-zero alt-setting is selected, because
 * before that the endpoint does not exist -- which is why configure() sets the
 * alt-setting first.
 *
 * A device whose endpoint descriptor does not advertise the control is
 * fixed-rate. That is not an error: the alt-setting was already chosen for a
 * rate it lists, so it is already clocking the rate we want, and issuing the
 * request anyway would earn a STALL from a device that is doing nothing wrong.
 */
bool UsbSink::setSampleRateUac1(uint32_t hz, std::string *error) {
    if (alt_ == nullptr) { *error = "not configured"; return false; }

    if (!alt_->data.sampleRateControl) {
        LOGI("UAC1: endpoint 0x%02x is fixed-rate; alt %u already carries %u Hz",
             alt_->data.address, alt_->alt, hz);
        return true;
    }

    uint8_t data[3] = {
        static_cast<uint8_t>(hz & 0xFF),
        static_cast<uint8_t>((hz >> 8) & 0xFF),
        static_cast<uint8_t>((hz >> 16) & 0xFF)};
    int r = libusb_control_transfer(
        handle_,
        LIBUSB_ENDPOINT_OUT | LIBUSB_REQUEST_TYPE_CLASS | LIBUSB_RECIPIENT_ENDPOINT,
        kReqCur,
        static_cast<uint16_t>(kCsSamFreqControl << 8),
        static_cast<uint16_t>(alt_->data.address),
        data, 3, 1000);
    if (r != 3) {
        *error = sfmt("UAC1 set sample rate %u Hz on endpoint 0x%02x failed: %s", hz,
                      alt_->data.address,
                      r < 0 ? libusb_error_name(r) : "short write");
        return false;
    }
    LOGI("UAC1: endpoint 0x%02x set to %u Hz", alt_->data.address, hz);
    return true;
}

void UsbSink::flush() {
    if (!ring_ || !running_.load(std::memory_order_acquire)) {
        if (ring_) ring_->clear();
        return;
    }
    flushPending_.store(true, std::memory_order_release);
    // Wait for the callback to do it, or new audio written next would be
    // discarded along with the old.
    for (int i = 0; i < 200 && flushPending_.load(std::memory_order_acquire); i++) usleep(1000);
}

void UsbSink::silence(uint8_t *dst, size_t bytes) {
    // PCM zeros would drop a DAC out of DSD mode, so DoP gets idle frames.
    if (dopOn_.load(std::memory_order_acquire)) dop_.idle(dst, bytes);
    else memset(dst, 0, bytes);
}

void UsbSink::fillTransfer(libusb_transfer *t) {
    const uint32_t q16 = samplesPerFrameQ16_.load(std::memory_order_relaxed);
    const double perPacket = q16 / 65536.0;
    const int maxPacket = alt_->data.maxPacket;

    uint8_t *buf = t->buffer;
    int offset = 0;

    if (flushPending_.exchange(false, std::memory_order_acq_rel)) ring_->discardAll();

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
        if (paused_.load(std::memory_order_acquire) ||
            stalled_.load(std::memory_order_acquire)) {
            silence(buf + offset, static_cast<size_t>(want));
            t->iso_packet_desc[p].length = static_cast<unsigned int>(want);
            offset += want;
            continue;
        }

        size_t got = ring_->read(buf + offset, static_cast<size_t>(want));
        if (dopOn_.load(std::memory_order_acquire)) dop_.restamp(buf + offset, got);
        if (got < static_cast<size_t>(want)) {
            // Underrun: emit silence rather than a short packet. A short packet
            // would slew the DAC's clock recovery; silence merely costs a gap.
            silence(buf + offset + got, static_cast<size_t>(want) - got);
            // Not a fault once the source has ended: there is nothing left to
            // starve on, and counting it would swamp real dropouts.
            if (!sourceEnded_.load(std::memory_order_acquire)) {
                stats_.underruns.fetch_add(1, std::memory_order_relaxed);
            }
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
            // Worth logging when it fails: the device is then left streaming,
            // which is exactly the state the next configure() has to recover
            // from.
            int r = libusb_set_interface_alt_setting(handle_, alt_->interfaceNum, 0);
            if (r != LIBUSB_SUCCESS) {
                LOGE("close: could not return if=%u to alt 0: %s",
                     alt_->interfaceNum, libusb_error_name(r));
            }
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

bool UsbSink::readVolumeRange() {
    if (!volumeSupported() || handle_ == nullptr) return false;
    if (volRangeKnown_) return true;

    const uint16_t wValue = static_cast<uint16_t>(kFuVolumeControl << 8);  // channel 0 = master
    const uint16_t wIndex =
        static_cast<uint16_t>((caps_.featureUnitId << 8) | caps_.audioControlInterface);
    const uint8_t in = LIBUSB_ENDPOINT_IN | LIBUSB_REQUEST_TYPE_CLASS | LIBUSB_RECIPIENT_INTERFACE;

    if (caps_.isUac2()) {
        // UAC2 returns a RANGE block: count, then (min,max,res) triples.
        uint8_t buf[64];
        int n = libusb_control_transfer(handle_, in, kReqRange, wValue, wIndex,
                                        buf, sizeof(buf), 1000);
        if (n < 8) return false;
        volMin_ = static_cast<int16_t>(buf[2] | (buf[3] << 8));
        volMax_ = static_cast<int16_t>(buf[4] | (buf[5] << 8));
        volRes_ = static_cast<int16_t>(buf[6] | (buf[7] << 8));
    } else {
        // UAC1 has no RANGE request: min, max and resolution are three
        // separate reads.
        uint8_t b[2];
        int n = libusb_control_transfer(handle_, in, kUac1GetMin, wValue, wIndex, b, 2, 1000);
        if (n != 2) {
            LOGE("volume: UAC1 GET_MIN failed (%d: %s)", n,
                 n < 0 ? libusb_error_name(n) : "short read");
            return false;
        }
        volMin_ = static_cast<int16_t>(b[0] | (b[1] << 8));
        n = libusb_control_transfer(handle_, in, kUac1GetMax, wValue, wIndex, b, 2, 1000);
        if (n != 2) {
            LOGE("volume: UAC1 GET_MAX failed (%d: %s)", n,
                 n < 0 ? libusb_error_name(n) : "short read");
            return false;
        }
        volMax_ = static_cast<int16_t>(b[0] | (b[1] << 8));
        // Resolution is optional; 1 is a safe assumption when it is absent.
        if (libusb_control_transfer(handle_, in, kUac1GetRes, wValue, wIndex, b, 2, 1000) == 2)
            volRes_ = static_cast<int16_t>(b[0] | (b[1] << 8));
    }
    if (volRes_ <= 0) volRes_ = 1;
    if (volMax_ <= volMin_) return false;
    volRangeKnown_ = true;
    LOGI("volume: range %.1f dB .. %.1f dB, step %.2f dB",
         volMin_ / 256.0, volMax_ / 256.0, volRes_ / 256.0);
    return true;
}

bool UsbSink::getVolumePercent(int *percent) {
    if (!readVolumeRange()) return false;

    // A device that does not report its own volume back has nothing useful to
    // say here, and asking it anyway would overwrite the value the user set
    // with whatever fixed number it returns.
    // Only a device that has proven it tracks writes is asked. Anything else
    // is answered from what this app last set, which is both the safe default
    // and the honest one: an unproven device may be reporting a fixed number.
    if (volumeReadback_ != Readback::Proven) {
        if (lastSetPercent_ < 0) return false;
        *percent = lastSetPercent_;
        return true;
    }

    uint8_t b[2];
    int n = libusb_control_transfer(
        handle_, LIBUSB_ENDPOINT_IN | LIBUSB_REQUEST_TYPE_CLASS | LIBUSB_RECIPIENT_INTERFACE,
        caps_.isUac2() ? kReqCur : kUac1GetCur,
        static_cast<uint16_t>(kFuVolumeControl << 8),
        static_cast<uint16_t>((caps_.featureUnitId << 8) | caps_.audioControlInterface),
        b, 2, 1000);
    if (n != 2) return false;
    const int16_t cur = static_cast<int16_t>(b[0] | (b[1] << 8));

    // A device that answers outside the range it declared itself is not
    // reporting a volume, whatever it is reporting. 0x8000 is the spec's
    // "silence" sentinel rather than a level, and values far below the
    // declared minimum are simply junk. Either way, believing it would
    // overwrite what the user set with nonsense.
    if (!volumeValueSane(cur)) {
        if (volumeReadback_ != Readback::Untrusted) {
            volumeReadback_ = Readback::Untrusted;
            LOGI("volume: device answered %.1f dB, outside its own range "
                 "[%.1f, %.1f] -- readback not trustworthy, using the last "
                 "value set", cur / 256.0, volMin_ / 256.0, volMax_ / 256.0);
        }
        if (lastSetPercent_ < 0) return false;
        *percent = lastSetPercent_;
        return true;
    }

    int pct = static_cast<int>(
        (static_cast<double>(cur - volMin_) / (volMax_ - volMin_)) * 100.0 + 0.5);
    if (pct < 0) pct = 0;
    if (pct > 100) pct = 100;
    // Logged only on change: this is polled several times a second while
    // playing, and the raw device value is the only way to tell a genuine
    // volume change from a device that reports a different scale than it
    // accepts.
    if (pct != lastVolumeLogged_) {
        LOGI("volume: GET_CUR raw=%d (%.1f dB) in [%d, %d] -> %d%%",
             cur, cur / 256.0, volMin_, volMax_, pct);
        lastVolumeLogged_ = pct;
    }
    *percent = pct;
    return true;
}

bool UsbSink::setVolumePercent(int percent) {
    if (!readVolumeRange()) return false;
    if (percent < 0) percent = 0;
    if (percent > 100) percent = 100;

    // Interpolate in the device's own dB range and snap to its step, rather
    // than assuming a linear 0-100 scale the hardware never agreed to.
    double raw = volMin_ + (volMax_ - volMin_) * (percent / 100.0);
    int16_t value = static_cast<int16_t>(raw);
    if (volRes_ > 1) {
        const int steps = static_cast<int>((value - volMin_) / volRes_);
        value = static_cast<int16_t>(volMin_ + steps * volRes_);
    }

    uint8_t b[2] = {static_cast<uint8_t>(value & 0xFF),
                    static_cast<uint8_t>((value >> 8) & 0xFF)};
    int n = libusb_control_transfer(
        handle_, LIBUSB_ENDPOINT_OUT | LIBUSB_REQUEST_TYPE_CLASS | LIBUSB_RECIPIENT_INTERFACE,
        kReqCur, static_cast<uint16_t>(kFuVolumeControl << 8),
        static_cast<uint16_t>((caps_.featureUnitId << 8) | caps_.audioControlInterface),
        b, 2, 1000);
    if (n != 2) {
        LOGE("volume: SET_CUR failed (%d)", n);
        return false;
    }
    LOGI("volume: set %d%% (%.1f dB)", percent, value / 256.0);
    lastSetPercent_ = percent;
    if (volumeReadback_ != Readback::Untrusted &&
        volumeReadback_ != Readback::Proven) {
        checkVolumeReadback(value);
    }
    return true;
}

/**
 * Decides once whether GET_CUR can be believed, by reading back a value we
 * just wrote.
 *
 * Anything within one step of what was written counts as honest -- devices are
 * entitled to snap to their own resolution, and some report the snapped value
 * rather than the requested one.
 */
bool UsbSink::volumeValueSane(int16_t raw) const {
    // 0x8000 means "silence", not a level, per the class spec.
    if (raw == static_cast<int16_t>(0x8000)) return false;
    const int slack = volRes_ > 0 ? volRes_ : 256;
    return raw >= volMin_ - slack && raw <= volMax_ + slack;
}

void UsbSink::checkVolumeReadback(int16_t written) {
    const uint8_t in =
        LIBUSB_ENDPOINT_IN | LIBUSB_REQUEST_TYPE_CLASS | LIBUSB_RECIPIENT_INTERFACE;
    const int tolerance = volRes_ > 0 ? volRes_ : 1;

    // Read several times rather than once. The reference UAC1 dongle echoes
    // the written value correctly on the read immediately following a write
    // and only then starts alternating between junk and its maximum -- so a
    // single probe samples exactly the one answer it gets right, and concludes
    // the device is honest.
    for (int attempt = 0; attempt < 3; attempt++) {
        if (attempt > 0) usleep(25 * 1000);
        uint8_t b[2];
        int n = libusb_control_transfer(
            handle_, in, caps_.isUac2() ? kReqCur : kUac1GetCur,
            static_cast<uint16_t>(kFuVolumeControl << 8),
            static_cast<uint16_t>((caps_.featureUnitId << 8) | caps_.audioControlInterface),
            b, 2, 1000);
        if (n != 2) {
            volumeReadback_ = Readback::Untrusted;
            LOGI("volume: device does not answer GET_CUR; using the last value set");
            return;
        }
        const int16_t got = static_cast<int16_t>(b[0] | (b[1] << 8));
        if (!volumeValueSane(got) ||
            std::abs(static_cast<int>(got) - static_cast<int>(written)) > tolerance) {
            volumeReadback_ = Readback::Untrusted;
            LOGI("volume: wrote %.1f dB, device answered %.1f dB on read %d -- "
                 "readback not trustworthy, using the last value set",
                 written / 256.0, got / 256.0, attempt + 1);
            return;
        }
    }

    // Agreed -- but agreeing once proves nothing. A device answering with a
    // fixed value agrees with any write that lands near it, which is exactly
    // how this check was passed at 99% on a device whose answer is always its
    // 0 dB maximum. Proof needs a second, clearly different value.
    if (!haveProbe_) {
        haveProbe_ = true;
        probeRaw_ = written;
        volumeReadback_ = Readback::Probed;
        LOGI("volume: device echoed %.1f dB; needs a second, different value "
             "before its readback is believed", written / 256.0);
        return;
    }
    const int spread = std::abs(static_cast<int>(written) - static_cast<int>(probeRaw_));
    if (spread <= tolerance * 4) {
        LOGI("volume: %.1f dB is too close to %.1f dB to prove anything; "
             "still using the last value set", written / 256.0, probeRaw_ / 256.0);
        return;
    }
    volumeReadback_ = Readback::Proven;
    LOGI("volume: device tracked two values %.1f dB apart; its readback is "
         "believable, polling it", spread / 256.0);
}

std::string UsbSink::statusJson() const {
    const uint32_t fb = stats_.feedbackRateMilliHz.load();
    return sfmt(
        "{\"running\":%s,\"paused\":%s,\"rate\":%u,\"altSetting\":%d,\"deviceBits\":%d,"
        "\"subslot\":%d,\"bytesPerFrame\":%d,\"framesSubmitted\":%llu,"
        "\"underruns\":%llu,\"transferErrors\":%llu,\"measuredRateHz\":%.1f,"
        "\"feedbackAccepted\":%u,\"feedbackRejected\":%u,"
        "\"packetErrors\":%llu,\"packetsSubmitted\":%llu,"
        "\"volumeSupported\":%s,\"volumeReadback\":\"%s\","
        "\"output\":\"usb\","
        "\"rebuffers\":%llu,\"ringFillPercent\":%d}",
        running_.load() ? "true" : "false",
        paused_.load() ? "true" : "false", rate_, altSetting(), deviceBits(),
        deviceSubslot(), bytesPerFrame_,
        static_cast<unsigned long long>(stats_.framesSubmitted.load()),
        static_cast<unsigned long long>(stats_.underruns.load()),
        static_cast<unsigned long long>(stats_.transferErrors.load()),
        fb / 1000.0, feedbackAccepted_.load(), feedbackRejected_.load(),
        static_cast<unsigned long long>(stats_.packetErrors.load()),
        static_cast<unsigned long long>(stats_.packetsSubmitted.load()),
        volumeSupported() ? "true" : "false",
        volumeReadback_ == Readback::Proven ? "trusted"
            : volumeReadback_ == Readback::Untrusted ? "untrusted" : "unproven",
        static_cast<unsigned long long>(stats_.rebuffers.load()),
        ring_ ? static_cast<int>(ring_->available() * 100 / std::max<size_t>(ring_->capacity(), 1)) : 0);
}
