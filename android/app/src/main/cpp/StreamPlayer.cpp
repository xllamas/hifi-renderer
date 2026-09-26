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
#include "AlacStream.h"

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
#include "decode/DsdDecoder.h"
#include "decode/FlacDecoder.h"
#include "decode/Mp3Decoder.h"
#include "decode/PcmDecoder.h"
#include "usb/UsbSink.h"
#include "sink/OboeSink.h"

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
    std::string start(int fd, int seekSeconds, bool relaxed, const std::string &mime,
                      bool gapless = false) {
        std::lock_guard<std::mutex> lock(mutex_);

        // A gapless start keeps the running stream and its ring: the previous
        // track's tail is still in there, and the new track's samples are
        // simply appended behind it. Whether that is actually possible is not
        // known until the header has been read, so the decision is deferred to
        // the decode loop -- here we only avoid destroying what it may reuse.
        const bool keepSink = gapless && sink_ && sinkStarted_;
        if (keepSink) {
            handover_.store(true);
            stopSourceLocked();
            handover_.store(false);
        } else {
            stopLocked();
        }

        positionBase_.store(seekSeconds);
        relaxed_ = relaxed;
        format_ = formatFromMime(mime);
        mime_ = mime;
        // Decoded here from the source's own bytes: nothing has been between
        // the file and this decoder.
        senderAltered_ = false;

        stream_ = std::make_unique<NetworkStream>();
        std::string err;
        if (!keepSink) {
            lastFd_ = fd;
            if (!openSink(fd, &err)) {
                sink_.reset();
                stream_.reset();
                return "{\"ok\":false,\"message\":\"" + esc(err) + "\"}";
            }
        }

        error_.clear();
        finished_.store(false);
        readyForNext_.store(false);
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
     *
     * [senderAltered] is the one thing this layer cannot work out for itself.
     * PCM from MediaCodec is the source's own audio and nothing has touched
     * it; PCM from an AirPlay sender has already been resampled to 44.1 kHz
     * and had the sender's volume applied before it left the other machine.
     * Both arrive through this same door, look identical once here, and only
     * the caller knows which is which.
     */
    std::string startPcm(int fd, uint32_t rate, int channels, int seekSeconds,
                         bool senderAltered) {
        std::lock_guard<std::mutex> lock(mutex_);
        stopLocked();

        std::string err;
        if (!openSink(fd, &err)) {
            sink_.reset();
            return "{\"ok\":false,\"message\":\"" + esc(err) + "\"}";
        }
        if (!sink_->configure(rate, 16, channels, &err)) {
            sink_.reset();
            return "{\"ok\":false,\"message\":\"" + esc(err) + "\"}";
        }

        pcmMode_ = true;
        senderAltered_ = senderAltered;
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
        LOGI("pcm: %u Hz %dch pushed in%s", rate, channels,
             senderAltered ? " (already resampled by the sender: NOT bit-perfect)" : "");
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

        // Announce it here, not after the drain. The ring still holds a second
        // or so of audio, and that is exactly the budget the next track has to
        // be fetched, opened and decoded into the same ring behind this one.
        // Waiting until the ring is empty -- which is what "finished" means --
        // spends that budget on silence before anyone is even told.
        readyForNext_.store(true, std::memory_order_release);

        while (running_.load() && !handover_.load() && sink_->ringAvailable() > 0) {
            usleep(5000);
        }
        if (handover_.load()) {
            LOGI("handing over to the next track with %zu bytes still to play",
                 sink_->ringAvailable());
            return;
        }
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

    bool getVolume(int *percent) {
        std::lock_guard<std::mutex> lock(mutex_);
        if (!sink_) return false;
        const bool ok = sink_->getVolumePercent(percent);
        volumeLearning_ = sink_->volumeLearning();
        return ok;
    }

    bool setVolume(int percent) {
        std::lock_guard<std::mutex> lock(mutex_);
        if (!sink_) return false;
        const bool ok = sink_->setVolumePercent(percent);
        volumeLearning_ = sink_->volumeLearning();
        return ok;
    }

    /**
     * Opens the USB sink when there is a device, and Android's own output when
     * there is not.
     *
     * A negative descriptor means the Kotlin layer found no DAC to use. That
     * is not an error: a phone with nothing plugged in should still play, and
     * everything above this point -- decoders, transport, playlist, widget --
     * is identical either way. What differs is that the fallback is not
     * bit-perfect, which it reports rather than conceals.
     */
    bool openSink(int fd, std::string *error) {
        if (fd >= 0) {
            auto usb = std::make_unique<UsbSink>();
            usb->adoptVolumeLearning(volumeLearning_);
            if (usb->open(fd, error)) {
                sink_ = std::move(usb);
                return true;
            }
            // A DAC that is present but unusable is a fault worth reporting,
            // not something to paper over by quietly playing through the
            // speaker at a quality the user did not ask for.
            LOGE("usb sink unavailable: %s", error->c_str());
            return false;
        }
        auto oboe = std::make_unique<OboeSink>();
        if (!oboe->open(fd, error)) return false;
        LOGI("no DAC attached; falling back to Android audio (NOT bit-perfect)");
        sink_ = std::move(oboe);
        return true;
    }

    /** The DAC changed, so nothing learned about the last one still applies. */
    void forgetVolumeLearning() {
        std::lock_guard<std::mutex> lock(mutex_);
        volumeLearning_ = AudioSink::VolumeLearning{};
    }

    void setPaused(bool paused) {
        std::lock_guard<std::mutex> lock(mutex_);
        if (sink_) sink_->setPaused(paused);
    }

    /** True once the track played to its natural end, as opposed to being stopped. */
    bool finished() const { return finished_.load(std::memory_order_acquire); }

    /** Source exhausted, tail still playing: the moment to start the next. */
    bool readyForNext() const { return readyForNext_.load(std::memory_order_acquire); }

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
        // The one claim this app may not get wrong, so it is composed in the
        // single place that can see both halves of it: a sink that alters
        // nothing, carrying samples that nobody altered on the way here.
        // Neither half is sufficient alone -- the USB sink is always honest
        // about itself, which is exactly why it must not be asked about the
        // stream.
        const bool exact = sink_->bitPerfect() && !senderAltered_;
        s += ",\"bitPerfect\":" + std::string(exact ? "true" : "false");
        s += ",\"senderAltered\":" + std::string(senderAltered_ ? "true" : "false");
        s += ",\"sourceBits\":" + std::to_string(sourceBits_);
        s += ",\"channels\":" + std::to_string(sourceChannels_);
        s += ",\"finished\":" + std::string(finished_.load() ? "true" : "false");
        // Whether the *decoder* is alive, which is not the same as whether the
        // sink is. Since a gapless change of track deliberately leaves the sink
        // running across tracks, the sink's own flag can no longer stand in for
        // "playback is progressing" -- a decoder that died leaves the stream
        // running and quietly empty.
        s += ",\"decoding\":" + std::string(running_.load() ? "true" : "false");
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
    /** Ends the current source and its decode thread, leaving the sink alone. */
    void stopSourceLocked() {
        running_.store(false);
        if (stream_) stream_->close();
        if (decoder_.joinable()) decoder_.join();
        stream_.reset();
    }

    void stopLocked() {
        stopSourceLocked();
        if (sink_) {
            sink_->stop();
            sink_->close();
            sink_.reset();
        }
        sinkStarted_ = false;
        cfgRate_ = 0;
        cfgBits_ = 0;
        cfgChannels_ = 0;
        cfgDsd_ = false;
        dopPhase_ = 0;
        pcmMode_ = false;
        pcmStarted_ = false;
    }

    void decodeLoop() {
        setpriority(PRIO_PROCESS, 0, -16);

        // Blocks until enough of the stream has arrived to read the headers.
        // Formats differ in how they announce themselves: FLAC has a global
        // header, MP3 carries one per frame, and raw PCM has none at all. The
        // decoder handles that; this only has to pick the right one. An unknown
        // or generic MIME type is tried as FLAC first, because that is what a
        // hi-fi source almost always is, then MP3.
        std::unique_ptr<Decoder> decoder;
        std::string err;
        DsdDecoder *dsd = nullptr;
        if (format_ == SourceFormat::Dsd) {
            // DSD is packed as DoP, whose marker has to alternate unbroken
            // into a track that follows without a gap; the phase is carried
            // from the last one. A stream that does not continue starts on
            // whichever marker it likes, so a stale phase costs nothing.
            auto d = std::make_unique<DsdDecoder>(dopPhase_);
            dsd = d.get();
            decoder = std::move(d);
            if (!decoder->open(stream_.get(), &err)) decoder.reset();
        } else if (format_ == SourceFormat::Pcm) {
            // Raw PCM announces nothing: for L16 and L24 the rate and channel
            // count are in the MIME type and nowhere else, which is why the
            // type is handed to the decoder rather than only classified by it.
            decoder = std::make_unique<PcmDecoder>(mime_);
            if (!decoder->open(stream_.get(), &err)) decoder.reset();
        } else if (format_ == SourceFormat::Mp3) {
            decoder = std::make_unique<Mp3Decoder>();
            if (!decoder->open(stream_.get(), &err)) decoder.reset();
        } else if (format_ == SourceFormat::Flac) {
            decoder = std::make_unique<FlacDecoder>(relaxed_);
            if (!decoder->open(stream_.get(), &err)) decoder.reset();
        } else {
            LOGI("stream: MIME '%s' not recognised, trying FLAC", mime_.c_str());
            decoder = std::make_unique<FlacDecoder>(relaxed_);
            if (decoder->open(stream_.get(), &err)) {
                // Report what actually decoded, not what the MIME type
                // guessed -- this label reaches the user as the format badge.
                format_ = SourceFormat::Flac;
            } else {
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

        // Can this track simply continue into the stream already running?
        //
        // Only when it is the same shape as the one before it. A change of
        // rate or depth has to be negotiated with the hardware, and the sink
        // cannot be reconfigured underneath a running stream -- which is why
        // gapless is possible within an album and not across a rate change.
        //
        // DSD and PCM of the same shape do not count as the same: the DAC is
        // in one mode or the other, and DoP data read as PCM is loud noise
        // until it has locked on -- or, the other way, PCM into a DAC that
        // is still listening for markers.
        const bool continuing = sinkStarted_ && cfgRate_ == rate &&
                                cfgBits_ == bits && cfgChannels_ == channels &&
                                cfgDsd_ == (dsd != nullptr);

        if (continuing) {
            // The tail of the previous track is still in the ring; these
            // samples go in behind it, and nothing is stopped or re-started.
            sink_->setSourceEnded(false);
            sink_->setPaused(false);
            LOGI("gapless: continuing into the running stream (%u Hz, %d-bit, %d ch)",
                 rate, bits, channels);
        } else {
            if (sinkStarted_) {
                // Same shape it is not, so the stream has to be rebuilt. The
                // tail is already gone by now: whoever asked for this accepted
                // the gap that a rate change costs.
                LOGI("format changed to %u Hz %d-bit %d ch; restarting the stream",
                     rate, bits, channels);
                sink_->stop();
                sink_->close();
                sink_.reset();
                sinkStarted_ = false;
                if (!openSink(lastFd_, &err)) {
                    error_ = err;
                    LOGE("decode: %s", err.c_str());
                    running_.store(false);
                    return;
                }
            }
            if (!sink_->configure(rate, bits, channels, &err)) {
                error_ = err;
                LOGE("decode: %s", err.c_str());
                running_.store(false);
                return;
            }
            cfgRate_ = rate;
            cfgBits_ = bits;
            cfgChannels_ = channels;
            cfgDsd_ = dsd != nullptr;
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
            if (dsd) dopPhase_ = dsd->markerPhase();
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
        if (!continuing) {
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
            sinkStarted_ = true;
        }

        // Rebuffer rather than dribble. If the source falls behind, hold output
        // silent until a healthy margin has rebuilt: one clean pause is better
        // than a minute of broken packets, and it keeps the underrun counter
        // meaningful.
        const size_t ringCapacity = sink_->ringSpace() + sink_->ringAvailable();
        const size_t lowWater = ringCapacity / 20;    // 5%
        const size_t highWater = ringCapacity / 2;    // 50%
        bool stalled = false;

        while (running_.load(std::memory_order_acquire)) {
            const size_t buffered = sink_->ringAvailable();
            if (!stalled && buffered < lowWater) {
                stalled = true;
                sink_->setStalled(true);
                sink_->noteRebuffer();
                LOGI("rebuffering: only %zu of %zu bytes buffered", buffered, ringCapacity);
            } else if (stalled && buffered >= highWater) {
                stalled = false;
                sink_->setStalled(false);
                LOGI("rebuffered: resuming with %zu bytes", buffered);
            }

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

        // Announce it here, not after the drain. The ring still holds a second
        // or so of audio, and that is exactly the budget the next track has to
        // be fetched, opened and decoded into the same ring behind this one.
        // Waiting until the ring is empty -- which is what "finished" means --
        // spends that budget on silence before anyone is even told.
        readyForNext_.store(true, std::memory_order_release);

        while (running_.load() && !handover_.load() && sink_->ringAvailable() > 0) {
            usleep(5000);
        }
        if (handover_.load()) {
            LOGI("handing over to the next track with %zu bytes still to play",
                 sink_->ringAvailable());
            decoder->close();
            return;
        }

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
    std::unique_ptr<AudioSink> sink_;
    std::thread decoder_;
    std::atomic<bool> running_{false};
    std::atomic<uint64_t> framesDecoded_{0};
    std::atomic<uint32_t> rate_{0};
    std::atomic<bool> finished_{false};
    /**
     * The decoder has run out of source, but the ring still holds the tail.
     *
     * This is the moment the next track has to start if there is to be no gap:
     * "finished" is only true once the ring has drained, by which point the
     * output has already been silent for as long as it takes to notice, fetch
     * and buffer the next one.
     */
    std::atomic<bool> readyForNext_{false};
    /** A replacement source is arriving; stop waiting for the tail to drain. */
    std::atomic<bool> handover_{false};

    // What the sink is currently configured for, and the descriptor it was
    // opened with, so a track that matches can be appended to the running
    // stream and one that does not can still reopen the device.
    uint32_t cfgRate_ = 0;
    int cfgBits_ = 0;
    int cfgChannels_ = 0;
    bool cfgDsd_ = false;
    /** Which DoP marker the next DSD frame carries; see decodeLoop. */
    int dopPhase_ = 0;
    bool sinkStarted_ = false;
    int lastFd_ = -1;
    std::atomic<uint32_t> positionBase_{0};
    bool relaxed_ = false;
    SourceFormat format_ = SourceFormat::Unknown;
    std::string mime_;
    bool pcmMode_ = false;
    bool pcmStarted_ = false;
    /**
     * Whether whoever handed us these samples had already changed them.
     *
     * Only the AirPlay path sets this. It is not a property of the sink and
     * not a property of the format -- lossless ALAC arrives here having been
     * resampled and attenuated by the sender, which is invisible from every
     * other vantage point in the engine.
     */
    bool senderAltered_ = false;
    int pcmChannels_ = 2;
    int sourceBits_ = 0;
    int sourceChannels_ = 0;
    std::vector<uint8_t> pcmScratch_;
    std::string error_;
    // Survives the sink, because it describes the DAC rather than the stream.
    AudioSink::VolumeLearning volumeLearning_;
};

}  // namespace

extern "C" {

JNIEXPORT jstring JNICALL
Java_com_hifirend_NativeBridge_nativeStartStream(JNIEnv *env, jobject, jint fd,
                                                 jint seekSeconds, jboolean relaxed,
                                                 jstring mime, jboolean gapless) {
    const char *m = mime ? env->GetStringUTFChars(mime, nullptr) : "";
    std::string result = StreamPlayer::instance().start(
        static_cast<int>(fd), static_cast<int>(seekSeconds), relaxed == JNI_TRUE, m,
        gapless == JNI_TRUE);
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
                                                    jint channels, jint seekSeconds,
                                                    jboolean senderAltered) {
    return env->NewStringUTF(
        StreamPlayer::instance()
            .startPcm(static_cast<int>(fd), static_cast<uint32_t>(rate),
                      static_cast<int>(channels), static_cast<int>(seekSeconds),
                      senderAltered == JNI_TRUE)
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

/**
 * ALAC for AirPlay: configure, then decode-and-push in one crossing.
 *
 * Decoding could have returned PCM to Kotlin for it to push back down, but
 * that is two JNI crossings and two copies of every packet, 117 times a
 * second, to no purpose -- nothing on the Java side wants to see the samples.
 * The decoder lives here and hands its output straight to the same push path
 * the AAC decoder already uses.
 */
static AlacStream g_alac;

JNIEXPORT jboolean JNICALL
Java_com_hifirend_NativeBridge_nativeAlacConfigure(JNIEnv *, jobject, jint frameLength,
                                                   jint compatibleVersion, jint bitDepth,
                                                   jint pb, jint mb, jint kb, jint channels,
                                                   jint maxRun, jint maxFrameBytes,
                                                   jint avgBitRate, jint sampleRate) {
    const bool ok = g_alac.configure(
        static_cast<uint32_t>(frameLength), static_cast<uint8_t>(compatibleVersion),
        static_cast<uint8_t>(bitDepth), static_cast<uint8_t>(pb), static_cast<uint8_t>(mb),
        static_cast<uint8_t>(kb), static_cast<uint8_t>(channels),
        static_cast<uint16_t>(maxRun), static_cast<uint32_t>(maxFrameBytes),
        static_cast<uint32_t>(avgBitRate), static_cast<uint32_t>(sampleRate));
    return ok ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jint JNICALL
Java_com_hifirend_NativeBridge_nativeAlacDecodePush(JNIEnv *env, jobject, jbyteArray frame,
                                                    jint len) {
    if (!g_alac.ready()) return -1;
    // Sized for the configured frame: the decoder refuses to write past it,
    // and a fixed buffer avoids an allocation per packet.
    static thread_local std::vector<uint8_t> pcm;
    const size_t needed = static_cast<size_t>(g_alac.frameLength()) * g_alac.channels() *
                          (g_alac.bitDepth() / 8);
    if (pcm.size() < needed) pcm.resize(needed);

    jbyte *p = env->GetByteArrayElements(frame, nullptr);
    const int bytes = g_alac.decode(reinterpret_cast<const uint8_t *>(p), static_cast<int>(len),
                                    pcm.data(), static_cast<int>(pcm.size()));
    env->ReleaseByteArrayElements(frame, p, JNI_ABORT);
    if (bytes <= 0) return 0;
    return StreamPlayer::instance().pushPcm(pcm.data(), static_cast<size_t>(bytes)) ? bytes : -2;
}

JNIEXPORT void JNICALL
Java_com_hifirend_NativeBridge_nativeSetStreamPaused(JNIEnv *, jobject, jboolean paused) {
    StreamPlayer::instance().setPaused(paused == JNI_TRUE);
}

JNIEXPORT jint JNICALL
Java_com_hifirend_NativeBridge_nativeGetDacVolume(JNIEnv *, jobject) {
    int pct = -1;
    return StreamPlayer::instance().getVolume(&pct) ? static_cast<jint>(pct) : -1;
}

JNIEXPORT jboolean JNICALL
Java_com_hifirend_NativeBridge_nativeSetDacVolume(JNIEnv *, jobject, jint percent) {
    return StreamPlayer::instance().setVolume(static_cast<int>(percent)) ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT void JNICALL
Java_com_hifirend_NativeBridge_nativeForgetVolumeLearning(JNIEnv *, jobject) {
    StreamPlayer::instance().forgetVolumeLearning();
}

JNIEXPORT jboolean JNICALL
Java_com_hifirend_NativeBridge_nativeStreamReadyForNext(JNIEnv *, jobject) {
    return StreamPlayer::instance().readyForNext() ? JNI_TRUE : JNI_FALSE;
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
