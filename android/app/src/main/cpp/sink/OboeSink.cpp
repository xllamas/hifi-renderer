#include "OboeSink.h"

#include <android/log.h>

#include <algorithm>
#include <cstdarg>
#include <cstdio>
#include <cstring>

#define LOG_TAG "hifirend"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

namespace {

std::string sfmt(const char *f, ...) {
    char buf[512];
    va_list ap;
    va_start(ap, f);
    vsnprintf(buf, sizeof(buf), f, ap);
    va_end(ap);
    return std::string(buf);
}

/** int32 full scale to float. */
constexpr float kToFloat = 1.0f / 2147483648.0f;

}  // namespace

OboeSink::~OboeSink() {
    stop();
    close();
}

bool OboeSink::open(int, std::string *) {
    // Nothing to open: the stream is built in start(), once configure() has
    // said what rate and channel count to ask Android for.
    return true;
}

bool OboeSink::configure(uint32_t rate, int sourceBits, int channels, std::string *error) {
    if (rate == 0 || channels <= 0) {
        *error = "invalid stream parameters";
        return false;
    }
    rate_ = rate;
    channels_ = channels;
    bytesPerFrame_ = 4 * channels;   // int32 per sample, see deviceSubslot()

    sourceEnded_.store(false);
    stalled_.store(false);
    paused_.store(false);
    framesSubmitted_.store(0);
    underruns_.store(0);

    // Two seconds, matching the USB path. Sized against the network rather
    // than the scheduler: a FLAC stream at a high rate needs real slack before
    // the decoder can keep ahead.
    const size_t twoSeconds = static_cast<size_t>(rate_) * bytesPerFrame_ * 2;
    const size_t ringBytes = std::clamp<size_t>(twoSeconds, 512u * 1024, 8u * 1024 * 1024);
    ring_ = std::make_unique<RingBuffer>(ringBytes);

    LOGI("oboe: configure %u Hz, source %d-bit, %d ch (fallback, NOT bit-perfect)",
         rate_, sourceBits, channels_);
    return true;
}

bool OboeSink::start(std::string *error) {
    if (running_.load()) return true;

    oboe::AudioStreamBuilder builder;
    builder.setDirection(oboe::Direction::Output)
        ->setPerformanceMode(oboe::PerformanceMode::None)
        ->setSharingMode(oboe::SharingMode::Shared)
        ->setFormat(oboe::AudioFormat::Float)
        ->setChannelCount(channels_)
        ->setSampleRate(static_cast<int32_t>(rate_))
        // Let Android convert rather than refuse. This path has already given
        // up bit-perfect output; failing to play at all would be worse.
        ->setSampleRateConversionQuality(oboe::SampleRateConversionQuality::Medium)
        ->setUsage(oboe::Usage::Media)
        ->setContentType(oboe::ContentType::Music)
        ->setDataCallback(this);

    oboe::Result r = builder.openStream(stream_);
    if (r != oboe::Result::OK || !stream_) {
        *error = sfmt("oboe openStream: %s", oboe::convertToText(r));
        return false;
    }

    actualRate_.store(static_cast<uint32_t>(stream_->getSampleRate()));
    running_.store(true, std::memory_order_release);

    r = stream_->requestStart();
    if (r != oboe::Result::OK) {
        *error = sfmt("oboe requestStart: %s", oboe::convertToText(r));
        running_.store(false);
        stream_->close();
        stream_.reset();
        return false;
    }

    LOGI("oboe: started, asked %u Hz got %d Hz, %d ch, burst %d frames%s",
         rate_, stream_->getSampleRate(), stream_->getChannelCount(),
         stream_->getFramesPerBurst(),
         actualRate_.load() == rate_ ? "" : " -- Android is resampling");
    return true;
}

void OboeSink::stop() {
    if (!running_.exchange(false)) return;
    if (stream_) {
        stream_->requestStop();
    }
}

void OboeSink::close() {
    if (stream_) {
        stream_->close();
        stream_.reset();
    }
    ring_.reset();
}

/**
 * Pulls one buffer from the ring.
 *
 * Runs on Android's audio callback thread, which has a hard deadline, so this
 * allocates nothing and takes no lock -- the same constraint the USB path has,
 * and the reason the ring buffer is lock-free.
 *
 * The int32 to float conversion happens in place: both are four bytes, and
 * each element is read before it is written.
 */
oboe::DataCallbackResult OboeSink::onAudioReady(oboe::AudioStream *,
                                                void *audioData, int32_t numFrames) {
    const size_t samples = static_cast<size_t>(numFrames) * channels_;
    const size_t wanted = samples * 4;
    auto *asInt = static_cast<int32_t *>(audioData);
    auto *out = static_cast<float *>(audioData);

    size_t got = 0;
    const bool holding = paused_.load(std::memory_order_acquire) ||
                         stalled_.load(std::memory_order_acquire);
    if (!holding && ring_) {
        got = ring_->read(static_cast<uint8_t *>(audioData), wanted);
    }

    if (got < wanted) {
        memset(static_cast<uint8_t *>(audioData) + got, 0, wanted - got);
        // Silence while paused, stalled, or after the source has ended is
        // expected rather than a fault; counting it would bury the real ones.
        if (!holding && !sourceEnded_.load(std::memory_order_acquire)) {
            underruns_.fetch_add(1, std::memory_order_relaxed);
        }
    }

    for (size_t i = 0; i < samples; i++) {
        out[i] = static_cast<float>(asInt[i]) * kToFloat;
    }
    framesSubmitted_.fetch_add(static_cast<uint64_t>(numFrames), std::memory_order_relaxed);
    return oboe::DataCallbackResult::Continue;
}

std::string OboeSink::statusJson() const {
    // Same shape as the USB sink's, so everything above reads one format. The
    // counters that only mean something for isochronous transfers are reported
    // as zero rather than omitted.
    return sfmt(
        "{\"running\":%s,\"paused\":%s,\"rate\":%u,\"altSetting\":%d,\"deviceBits\":%d,"
        "\"subslot\":%d,\"bytesPerFrame\":%d,\"framesSubmitted\":%llu,"
        "\"underruns\":%llu,\"transferErrors\":0,\"measuredRateHz\":%.1f,"
        "\"feedbackAccepted\":0,\"feedbackRejected\":0,"
        "\"packetErrors\":0,\"packetsSubmitted\":0,"
        "\"volumeSupported\":false,\"volumeReadback\":\"unproven\","
        "\"output\":\"android\","
        "\"rebuffers\":%llu,\"ringFillPercent\":%d}",
        running_.load() ? "true" : "false",
        paused_.load() ? "true" : "false",
        rate_, -1, 32, 4, bytesPerFrame_,
        static_cast<unsigned long long>(framesSubmitted_.load()),
        static_cast<unsigned long long>(underruns_.load()),
        static_cast<double>(actualRate_.load()),
        static_cast<unsigned long long>(rebuffers_.load()),
        ring_ ? static_cast<int>(ring_->available() * 100 /
                                 std::max<size_t>(ring_->capacity(), 1)) : 0);
}
