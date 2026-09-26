#pragma once

#include <cstddef>
#include <cstdint>
#include <string>

// Where decoded audio goes.
//
// Two implementations, and the difference between them is the whole point of
// the app. UsbSink drives the DAC directly over isochronous USB and alters
// nothing on the way. OboeSink hands the samples to Android, which mixes and
// very likely resamples them -- so it is emphatically *not* bit-perfect, and
// says so, because a renderer that quietly stopped being bit-perfect would be
// worse than one that refused to play at all.
//
// The fallback exists so the renderer, the playlist, the widget and the whole
// UI can be exercised with no DAC attached, and so that a phone with nothing
// plugged in is a working speaker rather than a dead app.
class AudioSink {
public:
    /**
     * What has been learned about a device's volume control, carried between
     * sinks because it describes the hardware rather than one stream.
     *
     * Proven needs two *different* values to have read back correctly: a
     * device answering with a fixed number agrees with any write that lands
     * near it.
     */
    enum class Readback { Unknown, Probed, Proven, Untrusted };

    struct VolumeLearning {
        Readback readback = Readback::Unknown;
        int lastSetPercent = -1;
        int provenAtRaw = 0;
        bool haveProbe = false;
    };

    virtual ~AudioSink() = default;

    /** [fd] is a USB file descriptor; sinks that do not need one ignore it. */
    virtual bool open(int fd, std::string *error) = 0;
    virtual bool configure(uint32_t rate, int sourceBits, int channels, std::string *error) = 0;
    virtual bool start(std::string *error) = 0;
    virtual void stop() = 0;
    virtual void close() = 0;

    /** Producer side: bytes accepted, in this sink's wire format. */
    virtual size_t write(const uint8_t *pcm, size_t bytes) = 0;
    virtual size_t ringSpace() const = 0;
    virtual size_t ringAvailable() const = 0;

    /**
     * The stream carries DSD as DoP. Called after configure, before start. A
     * sink that can do something about it keeps the DoP markers unbroken
     * through its own silence; the rest need not care.
     */
    virtual void setDop(bool /*dop*/) {}

    /**
     * Drops audio buffered but not yet sent, with the stream left running.
     * For a track change on a stream that must not be torn down. The caller
     * has stopped writing. Sinks with nothing to preserve ignore it.
     */
    virtual void flush() {}

    virtual void setPaused(bool paused) = 0;
    virtual void setStalled(bool stalled) = 0;
    virtual void setSourceEnded(bool ended) = 0;
    virtual void noteRebuffer() = 0;

    /** Bytes per sample the decoder should pack into. */
    virtual int deviceSubslot() const = 0;

    /**
     * Whether *this sink* hands the hardware what it was given, unaltered.
     *
     * Scoped to the sink on purpose, and deliberately not published as the
     * whole answer. Bit-perfect is a property of the entire path, and a sink
     * cannot see past its own input: an AirPlay sender resamples and
     * attenuates everything before a single byte reaches us, so a USB sink
     * truthfully reporting that it changed nothing would still be describing
     * a stream that was already changed. Whoever knows where the samples came
     * from composes the two -- see StreamPlayer::status().
     */
    virtual bool bitPerfect() const = 0;

    /** Short name for the output path, for the UI and the logs. */
    virtual const char *outputName() const = 0;

    virtual std::string statusJson() const = 0;

    // Volume, where the device offers it. Defaults suit a sink that does not.
    virtual bool getVolumePercent(int *) { return false; }
    virtual bool setVolumePercent(int) { return false; }
    virtual VolumeLearning volumeLearning() const { return VolumeLearning{}; }
    virtual void adoptVolumeLearning(const VolumeLearning &) {}
};
