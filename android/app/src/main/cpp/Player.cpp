// M2: play a local WAV file bit-perfectly to a USB DAC.
//
// Bit-perfect here means: the DAC is switched to the source file's own sample
// rate, and every sample value reaches it unaltered. No resampling, no mixing,
// no volume scaling, no dither.
//
// The one transformation applied is container widening. The reference DAC
// offers no 16-bit alt-setting, so a 16-bit source must travel in a wider slot.
// Samples are left-justified (MSB-aligned) with zero LSBs, per the USB Audio
// format spec, which preserves their values exactly -- the DAC reads the top
// bits and the padding contributes nothing.

#include <android/log.h>
#include <jni.h>
#include <sys/resource.h>
#include <unistd.h>

#include <atomic>
#include <cstring>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#define DR_WAV_IMPLEMENTATION
#define DR_WAV_NO_STDIO_WCHAR
#include "third_party/dr_libs/dr_wav.h"

#include "usb/UsbSink.h"

#define LOG_TAG "hifirend"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

namespace {

std::string jsonEscape(const std::string &in) {
    std::string o;
    for (char c : in) {
        if (c == '"' || c == '\\') { o += '\\'; o += c; }
        else if (static_cast<unsigned char>(c) < 0x20) o += ' ';
        else o += c;
    }
    return o;
}

std::string errorJson(const std::string &msg) {
    return "{\"ok\":false,\"message\":\"" + jsonEscape(msg) + "\"}";
}

class Player {
public:
    static Player &instance() {
        static Player p;
        return p;
    }

    std::string play(int fd, const std::string &path, bool loop) {
        // play/stop arrive from Kotlin coroutine threads and can overlap when a
        // second file is tapped mid-playback. Without this the two paths race on
        // sink_ and feeder_, and the thread join aborts the process.
        std::lock_guard<std::mutex> lock(mutex_);
        stopLocked();

        drwav wav;
        if (!drwav_init_file(&wav, path.c_str(), nullptr)) {
            return errorJson("cannot open WAV: " + path);
        }
        const uint32_t rate = wav.sampleRate;
        const int channels = static_cast<int>(wav.channels);
        const int sourceBits = static_cast<int>(wav.bitsPerSample);
        const uint64_t totalFrames = wav.totalPCMFrameCount;

        auto sink = std::make_unique<UsbSink>();
        std::string err;
        if (!sink->open(fd, &err)) {
            drwav_uninit(&wav);
            return errorJson("open: " + err);
        }
        if (!sink->configure(rate, sourceBits, channels, &err)) {
            drwav_uninit(&wav);
            return errorJson("configure: " + err);
        }

        sink_ = std::move(sink);
        feeding_.store(true);
        loop_ = loop;
        sourceRate_ = rate;
        sourceBits_ = sourceBits;
        sourceChannels_ = channels;
        sourceFrames_ = totalFrames;
        memcpy(&wav_, &wav, sizeof(drwav));

        feeder_ = std::thread(&Player::feed, this);

        // Pre-roll before opening the stream. Isochronous transfers start
        // draining the instant they are submitted, so starting with an empty
        // ring guarantees a burst of silence -- roughly one underrun per packet
        // until the feeder catches up, and an audible glitch at every track
        // start. Wait for a real buffer first.
        const size_t target = sink_->ringSpace() / 2;
        for (int i = 0; i < 200 && sink_->ringAvailable() < target; i++) {
            usleep(5000);
        }
        LOGI("pre-roll: %zu bytes buffered before start", sink_->ringAvailable());

        if (!sink_->start(&err)) {
            feeding_.store(false);
            if (feeder_.joinable()) feeder_.join();
            sink_->close();
            sink_.reset();
            drwav_uninit(&wav_);
            return errorJson("start: " + err);
        }

        LOGI("play: %s -- %u Hz %d-bit %dch, %llu frames",
             path.c_str(), rate, sourceBits, channels,
             static_cast<unsigned long long>(totalFrames));

        return std::string("{\"ok\":true,\"sourceRate\":") + std::to_string(rate) +
               ",\"sourceBits\":" + std::to_string(sourceBits) +
               ",\"channels\":" + std::to_string(channels) +
               ",\"deviceBits\":" + std::to_string(sink_->deviceBits()) +
               ",\"altSetting\":" + std::to_string(sink_->altSetting()) + "}";
    }

    void stop() {
        std::lock_guard<std::mutex> lock(mutex_);
        stopLocked();
    }

    std::string statusJson() {
        std::lock_guard<std::mutex> lock(mutex_);
        return statusLocked();
    }

private:
    void stopLocked() {
        feeding_.store(false);
        if (feeder_.joinable()) feeder_.join();
        if (sink_) {
            sink_->stop();
            sink_->close();
            sink_.reset();
            drwav_uninit(&wav_);
        }
    }

    std::string statusLocked() {
        if (!sink_) return "{\"running\":false}";
        std::string s = sink_->statusJson();
        // Splice in what the sink does not know about the source.
        s.pop_back();
        s += ",\"sourceRate\":" + std::to_string(sourceRate_);
        s += ",\"sourceBits\":" + std::to_string(sourceBits_);
        s += ",\"sourceChannels\":" + std::to_string(sourceChannels_);
        s += ",\"sourceFrames\":" + std::to_string(sourceFrames_);
        s += ",\"framesRead\":" + std::to_string(framesRead_.load());
        s += "}";
        return s;
    }

    void feed() {
        // Decoding is not real-time critical, but if this thread stalls the
        // ring drains and the USB side starves.
        setpriority(PRIO_PROCESS, 0, -16);
        const int ch = sourceChannels_;
        const int srcBits = sourceBits_;
        const int subslot = sink_->deviceSubslot();
        constexpr int kChunkFrames = 4096;

        std::vector<int32_t> scratch(static_cast<size_t>(kChunkFrames) * ch);
        std::vector<uint8_t> wire(static_cast<size_t>(kChunkFrames) * ch * subslot);

        // dr_wav's s32 conversion is a pure left shift of the source sample, so
        // reading as s32 already yields the MSB-aligned form the USB subslot
        // wants. No scaling, no rounding, no loss.
        const int shiftDown = 32 - (subslot * 8);

        while (feeding_.load(std::memory_order_acquire)) {
            size_t space = sink_->ringSpace();
            size_t frameBytes = static_cast<size_t>(ch) * subslot;
            if (space < frameBytes * 256) {
                usleep(2000);
                continue;
            }
            size_t wantFrames = std::min<size_t>(kChunkFrames, space / frameBytes);

            drwav_uint64 got = drwav_read_pcm_frames_s32(&wav_, wantFrames, scratch.data());
            if (got == 0) {
                if (loop_) {
                    drwav_seek_to_pcm_frame(&wav_, 0);
                    continue;
                }
                // Let the tail drain before tearing the stream down.
                while (feeding_.load() && sink_->ringAvailable() > 0) usleep(5000);
                break;
            }
            framesRead_.fetch_add(got, std::memory_order_relaxed);

            const size_t samples = static_cast<size_t>(got) * ch;
            uint8_t *out = wire.data();
            for (size_t i = 0; i < samples; i++) {
                // Left-justified in 32 bits from dr_wav; narrow to the subslot
                // by dropping only the zero padding at the bottom.
                uint32_t v = static_cast<uint32_t>(scratch[i]) >> shiftDown;
                for (int b = 0; b < subslot; b++) {
                    *out++ = static_cast<uint8_t>((v >> (8 * b)) & 0xFF);
                }
            }

            size_t toWrite = samples * subslot;
            size_t written = 0;
            while (written < toWrite && feeding_.load(std::memory_order_acquire)) {
                written += sink_->write(wire.data() + written, toWrite - written);
                if (written < toWrite) usleep(1000);
            }
        }
        (void)srcBits;
        LOGI("feeder finished: %llu frames read",
             static_cast<unsigned long long>(framesRead_.load()));
    }

    std::mutex mutex_;
    std::unique_ptr<UsbSink> sink_;
    drwav wav_{};
    std::thread feeder_;
    std::atomic<bool> feeding_{false};
    std::atomic<uint64_t> framesRead_{0};
    bool loop_ = false;
    uint32_t sourceRate_ = 0;
    int sourceBits_ = 0, sourceChannels_ = 0;
    uint64_t sourceFrames_ = 0;
};

}  // namespace

extern "C" JNIEXPORT jstring JNICALL
Java_com_hifirend_NativeBridge_nativePlayWav(JNIEnv *env, jobject, jint fd,
                                             jstring path, jboolean loop) {
    const char *p = env->GetStringUTFChars(path, nullptr);
    std::string result = Player::instance().play(static_cast<int>(fd), p, loop == JNI_TRUE);
    env->ReleaseStringUTFChars(path, p);
    return env->NewStringUTF(result.c_str());
}

extern "C" JNIEXPORT void JNICALL
Java_com_hifirend_NativeBridge_nativeStopPlayback(JNIEnv *, jobject) {
    Player::instance().stop();
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_hifirend_NativeBridge_nativePlaybackStatus(JNIEnv *env, jobject) {
    return env->NewStringUTF(Player::instance().statusJson().c_str());
}
