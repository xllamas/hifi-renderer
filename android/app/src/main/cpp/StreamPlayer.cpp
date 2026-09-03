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
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#define DR_FLAC_IMPLEMENTATION
#define DR_FLAC_NO_STDIO
#include "third_party/dr_libs/dr_flac.h"

#include "NetworkStream.h"
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
    std::string start(int fd, int seekSeconds, bool relaxed) {
        std::lock_guard<std::mutex> lock(mutex_);
        stopLocked();
        positionBase_.store(seekSeconds);
        relaxed_ = relaxed;

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
    }

    static size_t onRead(void *user, void *out, size_t bytes) {
        return static_cast<NetworkStream *>(user)->read(static_cast<uint8_t *>(out), bytes);
    }

    // Live network bytes cannot be rewound. Seeking is handled by re-requesting
    // with an HTTP byte range on the Kotlin side, not here.
    static drflac_bool32 onSeek(void *, int, drflac_seek_origin) { return DRFLAC_FALSE; }

    static drflac_bool32 onTell(void *user, drflac_int64 *cursor) {
        *cursor = static_cast<drflac_int64>(static_cast<NetworkStream *>(user)->consumed());
        return DRFLAC_TRUE;
    }

    void decodeLoop() {
        setpriority(PRIO_PROCESS, 0, -16);

        // Blocks until enough of the stream has arrived to read the headers.
        // A stream that begins mid-file has no header, so the decoder has to
        // find the next frame boundary itself.
        drflac *flac = relaxed_
            ? drflac_open_relaxed(&StreamPlayer::onRead, &StreamPlayer::onSeek,
                                  &StreamPlayer::onTell, drflac_container_native,
                                  stream_.get(), nullptr)
            : drflac_open(&StreamPlayer::onRead, &StreamPlayer::onSeek,
                          &StreamPlayer::onTell, stream_.get(), nullptr);
        if (flac == nullptr) {
            error_ = "not a decodable FLAC stream";
            LOGE("decode: drflac_open failed");
            running_.store(false);
            return;
        }

        const uint32_t rate = flac->sampleRate;
        const int channels = flac->channels;
        const int bits = flac->bitsPerSample;
        rate_.store(rate);
        LOGI("stream: FLAC %u Hz %d-bit %dch", rate, bits, channels);

        std::string err;
        if (!sink_->configure(rate, bits, channels, &err)) {
            error_ = err;
            LOGE("decode: %s", err.c_str());
            drflac_close(flac);
            running_.store(false);
            return;
        }

        const int subslot = sink_->deviceSubslot();
        const int shiftDown = 32 - (subslot * 8);
        constexpr int kChunk = 4096;
        std::vector<drflac_int32> pcm(static_cast<size_t>(kChunk) * channels);
        std::vector<uint8_t> wire(static_cast<size_t>(kChunk) * channels * subslot);

        // Decode one chunk and hand it to the sink, shared by the pre-roll and
        // the main loop.
        auto decodeChunk = [&]() -> bool {
            drflac_uint64 got = drflac_read_pcm_frames_s32(flac, kChunk, pcm.data());
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
            drflac_close(flac);
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
        // the last fraction of a second is cut off.
        while (running_.load() && sink_->ringAvailable() > 0) usleep(5000);

        // Distinguish reaching the end from being stopped: the controller needs
        // to know the track finished so it can send the next one.
        if (running_.load()) finished_.store(true, std::memory_order_release);

        drflac_close(flac);
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
    std::string error_;
};

}  // namespace

extern "C" {

JNIEXPORT jstring JNICALL
Java_com_hifirend_NativeBridge_nativeStartStream(JNIEnv *env, jobject, jint fd,
                                                 jint seekSeconds, jboolean relaxed) {
    return env->NewStringUTF(
        StreamPlayer::instance()
            .start(static_cast<int>(fd), static_cast<int>(seekSeconds), relaxed == JNI_TRUE)
            .c_str());
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
