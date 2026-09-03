// M4: play a FLAC stream from the network, bit-perfectly, to the USB DAC.
//
// This is the path a DLNA controller actually drives. BubbleUPnP streaming
// Tidal hands us a proxied FLAC over plain HTTP, so that is the shape the
// engine is built around: bytes arrive from Kotlin, dr_flac decodes them, and
// the samples reach the DAC unaltered at the file's own sample rate.
//
// The stream is not seekable while it plays -- dr_flac's seek callback refuses
// -- because the bytes are arriving live. Seeking is a byte-range re-request on
// the Kotlin side, which restarts the stream at an offset.

#include <android/log.h>
#include <jni.h>
#include <sys/resource.h>
#include <unistd.h>

#include <atomic>
#include <algorithm>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#include "NetworkStream.h"
#include "decode/Decoder.h"
#include "decode/FlacDecoder.h"
#include "decode/Mp3Decoder.h"
#include "usb/UsbSink.h"

#define LOG_TAG "hifirend"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

namespace {

std::string esc(const std::string &in) {
    std::string o;
    for (char c : in) {
        if (c == '"' || c == '\\') { o += '\\'; o += c; }
        else if (static_cast<unsigned char>(c) < 0x20) o += ' ';
        else o += c;
    }
    return o;
}

class StreamPlayer {
public:
    static StreamPlayer &instance() {
        static StreamPlayer p;
        return p;
    }

    /**
     * @param seekSeconds where in the track this stream begins; the bytes are
     *        expected to have been requested with an HTTP Range starting there.
     * @param relaxed true when the stream starts mid-file and therefore has no
     *        FLAC header, so the decoder must scan for a frame boundary.
     */
    std::string start(int fd, int seekSeconds, bool relaxed, const std::string &mime) {
        std::lock_guard<std::mutex> lock(mutex_);
        stopLocked();
        positionBase_.store(seekSeconds);
        relaxed_ = relaxed;
        format_ = formatFromMime(mime);
        mime_ = mime;

        stream_ = std::make_unique<NetworkStream>();
        sink_ = std::make_unique<UsbSink>();
        std::string err;
        if (!sink_->open(fd, &err)) {
            sink_.reset();
            stream_.reset();
            return "{\"ok\":false,\"message\":\"" + esc(err) + "\"}";
        }

        error_.clear();
        finished_.store(false);
        running_.store(true);
        framesDecoded_.store(0);
        rate_.store(0);
        decoder_ = std::thread(&StreamPlayer::decodeLoop, this);
        return "{\"ok\":true}";
    }

    /**
     * Opens the DAC for PCM that is decoded elsewhere.
     *
     * AAC is decoded by Android's MediaCodec rather than natively: it avoids
     * bundling an AAC decoder, and MediaCodec is a *decoder*, not the system
     * mixer, so its PCM output still reaches the DAC untouched. The samples
     * arrive here as 16-bit little-endian and are widened the same way every
     * other source is.
     */
    std::string startPcm(int fd, uint32_t rate, int channels, int seekSeconds) {
        std::lock_guard<std::mutex> lock(mutex_);
        stopLocked();

        sink_ = std::make_unique<UsbSink>();
        std::string err;
        if (!sink_->open(fd, &err)) {
            sink_.reset();
            return "{\"ok\":false,\"message\":\"" + esc(err) + "\"}";
        }
        if (!sink_->configure(rate, 16, channels, &err)) {
            sink_.reset();
            return "{\"ok\":false,\"message\":\"" + esc(err) + "\"}";
        }

        pcmMode_ = true;
        pcmChannels_ = channels;
        sourceBits_ = 16;
        sourceChannels_ = channels;
        format_ = SourceFormat::Pcm;
        pcmStarted_ = false;
        positionBase_.store(seekSeconds);
        framesDecoded_.store(0);
        rate_.store(rate);
        finished_.store(false);
        error_.clear();
        running_.store(true);
        LOGI("pcm: %u Hz %dch from MediaCodec", rate, channels);
        return "{\"ok\":true}";
    }

    /** 16-bit little-endian interleaved PCM from the platform decoder. */
    bool pushPcm(const uint8_t *data, size_t n) {
        std::lock_guard<std::mutex> lock(mutex_);
        if (!sink_ || !running_.load()) return false;

        const int subslot = sink_->deviceSubslot();
        const int shiftDown = 32 - (subslot * 8);
        const size_t samples = n / 2;
        pcmScratch_.resize(samples * subslot);
        uint8_t *out = pcmScratch_.data();
        for (size_t i = 0; i < samples; i++) {
            const int16_t s16 = static_cast<int16_t>(data[i * 2] | (data[i * 2 + 1] << 8));
            const uint32_t v = (static_cast<uint32_t>(static_cast<int32_t>(s16) << 16)) >> shiftDown;
            for (int b = 0; b < subslot; b++) {
                *out++ = static_cast<uint8_t>((v >> (8 * b)) & 0xFF);
            }
        }
        framesDecoded_.fetch_add(samples / std::max(pcmChannels_, 1), std::memory_order_relaxed);

        size_t toWrite = pcmScratch_.size(), written = 0;
        while (written < toWrite && running_.load()) {
            written += sink_->write(pcmScratch_.data() + written, toWrite - written);
            if (written < toWrite) usleep(1000);
        }

        // Same pre-roll rule as every other path: fill before opening the
        // stream, or the track starts with a burst of silence.
        if (!pcmStarted_ && sink_->ringAvailable() >= sink_->ringSpace()) {
            std::string err;
            if (sink_->start(&err)) {
                pcmStarted_ = true;
                LOGI("pcm: stream started after %zu bytes pre-roll", sink_->ringAvailable());
            } else {
                error_ = err;
                LOGE("pcm start failed: %s", err.c_str());
                running_.store(false);
                return false;
            }
        }
        return true;
    }

    /** MediaCodec reached the end of the track. */
    void pcmEndOfStream() {
        std::lock_guard<std::mutex> lock(mutex_);
        if (!sink_) return;
        if (!pcmStarted_) {   // very short track: never hit the pre-roll mark
            std::string err;
            if (sink_->start(&err)) pcmStarted_ = true;
        }
        sink_->setSourceEnded(true);
        while (running_.load() && sink_->ringAvailable() > 0) usleep(5000);
        sink_->setPaused(true);
        finished_.store(true, std::memory_order_release);
    }

    bool push(const uint8_t *data, size_t n) {
        NetworkStream *s;
        {
            std::lock_guard<std::mutex> lock(mutex_);
            s = stream_.get();
            if (s == nullptr) return false;
        }
        return s->write(data, n);
    }

    void setPaused(bool paused) {
        std::lock_guard<std::mutex> lock(mutex_);
        if (sink_) sink_->setPaused(paused);
    }

    /** True once the track played to its natural end, as opposed to being stopped. */
    bool finished() const { return finished_.load(std::memory_order_acquire); }

    void endOfStream() {
        std::lock_guard<std::mutex> lock(mutex_);
        if (stream_) stream_->setEof();
    }

    void stop() {
        std::lock_guard<std::mutex> lock(mutex_);
        stopLocked();
    }

    std::string status() {
        std::lock_guard<std::mutex> lock(mutex_);
        if (!sink_) return "{\"running\":false}";
        std::string s = sink_->statusJson();
        s.pop_back();
        const uint32_t r = rate_.load();
        s += ",\"streamBuffered\":" + std::to_string(stream_ ? stream_->buffered() : 0);
        s += ",\"bytesConsumed\":" + std::to_string(stream_ ? stream_->consumed() : 0);
        s += ",\"framesDecoded\":" + std::to_string(framesDecoded_.load());
        s += ",\"positionSeconds\":" +
             std::to_string(positionBase_.load() + (r ? framesDecoded_.load() / r : 0));
        s += ",\"sourceFormat\":\"" + std::string(formatName(format_)) + "\"";
        s += ",\"sourceBits\":" + std::to_string(sourceBits_);
        s += ",\"channels\":" + std::to_string(sourceChannels_);
        s += ",\"finished\":" + std::string(finished_.load() ? "true" : "false");
        s += ",\"error\":\"" + esc(error_) + "\"";
        s += "}";
        return s;
    }

    /** Elapsed seconds, for AVTransport GetPositionInfo. */
    uint32_t positionSeconds() {
        const uint32_t r = rate_.load();
        const uint32_t decoded = r ? static_cast<uint32_t>(framesDecoded_.load() / r) : 0;
        return positionBase_.load() + decoded;
    }

private:
    void stopLocked() {
        running_.store(false);
        if (stream_) stream_->close();
        if (decoder_.joinable()) decoder_.join();
        if (sink_) {
            sink_->stop();
            sink_->close();
            sink_.reset();
        }
        stream_.reset();
        pcmMode_ = false;
        pcmStarted_ = false;
    }

    void decodeLoop() {
        setpriority(PRIO_PROCESS, 0, -16);

        // Blocks until enough of the stream has arrived to read the headers.
        // Formats differ in how they announce themselves: FLAC has a global
        // header, MP3 carries one per frame. The decoder handles that; this
        // only has to pick the right one. An unknown or generic MIME type is
        // tried as FLAC first, because that is what a hi-fi source almost
        // always is, then MP3.
        std::unique_ptr<Decoder> decoder;
        std::string err;
        if (format_ == SourceFormat::Mp3) {
            decoder = std::make_unique<Mp3Decoder>();
            if (!decoder->open(stream_.get(), &err)) decoder.reset();
        } else if (format_ == SourceFormat::Flac) {
            decoder = std::make_unique<FlacDecoder>(relaxed_);
            if (!decoder->open(stream_.get(), &err)) decoder.reset();
        } else {
            LOGI("stream: MIME '%s' not recognised, trying FLAC", mime_.c_str());
            decoder = std::make_unique<FlacDecoder>(relaxed_);
            if (!decoder->open(stream_.get(), &err)) {
                // The FLAC attempt consumed the head of the stream, so MP3
                // cannot be tried on the same bytes. Report clearly instead of
                // failing obscurely.
                decoder.reset();
                err = "unsupported or unrecognised audio format (" + mime_ + ")";
            }
        }

        if (!decoder) {
            error_ = err;
            LOGE("decode: %s", err.c_str());
            running_.store(false);
            return;
        }

        const uint32_t rate = decoder->sampleRate();
        const int channels = decoder->channels();
        const int bits = decoder->bitsPerSample();
        rate_.store(rate);
        sourceBits_ = bits;
        sourceChannels_ = channels;
        LOGI("stream: %s %u Hz %d-bit %dch", formatName(format_), rate, bits, channels);

        if (!sink_->configure(rate, bits, channels, &err)) {
            error_ = err;
            LOGE("decode: %s", err.c_str());
            running_.store(false);
            return;
        }

        const int subslot = sink_->deviceSubslot();
        const int shiftDown = 32 - (subslot * 8);
        constexpr int kChunk = 4096;
        std::vector<int32_t> pcm(static_cast<size_t>(kChunk) * channels);
        std::vector<uint8_t> wire(static_cast<size_t>(kChunk) * channels * subslot);

        // Decode one chunk and hand it to the sink, shared by the pre-roll and
        // the main loop.
        auto decodeChunk = [&]() -> bool {
            uint64_t got = decoder->read(pcm.data(), kChunk);
            if (got == 0) return false;
            framesDecoded_.fetch_add(got, std::memory_order_relaxed);
            const size_t samples = static_cast<size_t>(got) * channels;
            uint8_t *out = wire.data();
            for (size_t i = 0; i < samples; i++) {
                uint32_t v = static_cast<uint32_t>(pcm[i]) >> shiftDown;
                for (int b = 0; b < subslot; b++) {
                    *out++ = static_cast<uint8_t>((v >> (8 * b)) & 0xFF);
                }
            }
            size_t toWrite = samples * subslot, written = 0;
            while (written < toWrite && running_.load(std::memory_order_acquire)) {
                written += sink_->write(wire.data() + written, toWrite - written);
                if (written < toWrite) usleep(1000);
            }
            return true;
        };

        // Fill the ring BEFORE opening the stream. Isochronous transfers start
        // draining the instant they are submitted, so starting empty guarantees
        // a burst of silence and an audible glitch at the head of every track.
        const size_t preRoll = sink_->ringSpace() / 2;
        while (running_.load() && sink_->ringAvailable() < preRoll) {
            if (!decodeChunk()) break;
        }
        LOGI("pre-roll: %zu bytes buffered before start", sink_->ringAvailable());

        if (!sink_->start(&err)) {
            error_ = err;
            LOGE("decode: %s", err.c_str());
            running_.store(false);
            return;
        }

        while (running_.load(std::memory_order_acquire)) {
            const size_t frameBytes = static_cast<size_t>(channels) * subslot;
            if (sink_->ringSpace() < frameBytes * 256) {
                usleep(2000);
                continue;
            }
            // dr_flac's s32 output is the sample left-justified in 32 bits, so
            // narrowing to the subslot only drops zero padding. Nothing is
            // scaled, rounded or dithered -- that is what keeps it bit-perfect.
            if (!decodeChunk()) break;   // end of stream
        }

        // Let the tail reach the DAC before tearing the stream down, otherwise
        // the last fraction of a second is cut off. Telling the sink the source
        // has ended first means the silence after it is not counted as a fault.
        sink_->setSourceEnded(true);
        while (running_.load() && sink_->ringAvailable() > 0) usleep(5000);

        // Park the sink before announcing the end. Between here and the
        // controller acting there is a poll interval of silence, and without
        // this every packet of it counts as an underrun -- hundreds per track,
        // which makes the one number that signals real dropouts untrustworthy.
        if (running_.load()) {
            sink_->setPaused(true);
            finished_.store(true, std::memory_order_release);
        }

        decoder->close();
        LOGI("stream finished: %llu frames decoded",
             static_cast<unsigned long long>(framesDecoded_.load()));
    }

    std::mutex mutex_;
    std::unique_ptr<NetworkStream> stream_;
    std::unique_ptr<UsbSink> sink_;
    std::thread decoder_;
    std::atomic<bool> running_{false};
    std::atomic<uint64_t> framesDecoded_{0};
    std::atomic<uint32_t> rate_{0};
    std::atomic<bool> finished_{false};
    std::atomic<uint32_t> positionBase_{0};
    bool relaxed_ = false;
    SourceFormat format_ = SourceFormat::Unknown;
    std::string mime_;
    bool pcmMode_ = false;
    bool pcmStarted_ = false;
    int pcmChannels_ = 2;
    int sourceBits_ = 0;
    int sourceChannels_ = 0;
    std::vector<uint8_t> pcmScratch_;
    std::string error_;
};

}  // namespace

extern "C" {

JNIEXPORT jstring JNICALL
Java_com_hifirend_NativeBridge_nativeStartStream(JNIEnv *env, jobject, jint fd,
                                                 jint seekSeconds, jboolean relaxed,
                                                 jstring mime) {
    const char *m = mime ? env->GetStringUTFChars(mime, nullptr) : "";
    std::string result = StreamPlayer::instance().start(
        static_cast<int>(fd), static_cast<int>(seekSeconds), relaxed == JNI_TRUE, m);
    if (mime) env->ReleaseStringUTFChars(mime, m);
    return env->NewStringUTF(result.c_str());
}

JNIEXPORT jboolean JNICALL
Java_com_hifirend_NativeBridge_nativePushStreamData(JNIEnv *env, jobject,
                                                    jbyteArray data, jint len) {
    jbyte *p = env->GetByteArrayElements(data, nullptr);
    bool ok = StreamPlayer::instance().push(reinterpret_cast<uint8_t *>(p),
                                            static_cast<size_t>(len));
    env->ReleaseByteArrayElements(data, p, JNI_ABORT);
    return ok ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jstring JNICALL
Java_com_hifirend_NativeBridge_nativeStartPcmStream(JNIEnv *env, jobject, jint fd, jint rate,
                                                    jint channels, jint seekSeconds) {
    return env->NewStringUTF(
        StreamPlayer::instance()
            .startPcm(static_cast<int>(fd), static_cast<uint32_t>(rate),
                      static_cast<int>(channels), static_cast<int>(seekSeconds))
            .c_str());
}

JNIEXPORT jboolean JNICALL
Java_com_hifirend_NativeBridge_nativePushPcm(JNIEnv *env, jobject, jbyteArray data, jint len) {
    jbyte *p = env->GetByteArrayElements(data, nullptr);
    bool ok = StreamPlayer::instance().pushPcm(reinterpret_cast<uint8_t *>(p),
                                               static_cast<size_t>(len));
    env->ReleaseByteArrayElements(data, p, JNI_ABORT);
    return ok ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT void JNICALL
Java_com_hifirend_NativeBridge_nativePcmEndOfStream(JNIEnv *, jobject) {
    StreamPlayer::instance().pcmEndOfStream();
}

JNIEXPORT void JNICALL
Java_com_hifirend_NativeBridge_nativeSetStreamPaused(JNIEnv *, jobject, jboolean paused) {
    StreamPlayer::instance().setPaused(paused == JNI_TRUE);
}

JNIEXPORT jboolean JNICALL
Java_com_hifirend_NativeBridge_nativeStreamFinished(JNIEnv *, jobject) {
    return StreamPlayer::instance().finished() ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT void JNICALL
Java_com_hifirend_NativeBridge_nativeEndStream(JNIEnv *, jobject) {
    StreamPlayer::instance().endOfStream();
}

JNIEXPORT void JNICALL
Java_com_hifirend_NativeBridge_nativeStopStream(JNIEnv *, jobject) {
    StreamPlayer::instance().stop();
}

JNIEXPORT jstring JNICALL
Java_com_hifirend_NativeBridge_nativeStreamStatus(JNIEnv *env, jobject) {
    return env->NewStringUTF(StreamPlayer::instance().status().c_str());
}

JNIEXPORT jint JNICALL
Java_com_hifirend_NativeBridge_nativeStreamPositionSeconds(JNIEnv *, jobject) {
    return static_cast<jint>(StreamPlayer::instance().positionSeconds());
}

}  // extern "C"
