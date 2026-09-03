#pragma once

#include <condition_variable>
#include <cstdint>
#include <cstring>
#include <deque>
#include <mutex>

/**
 * A blocking byte pipe between the Kotlin HTTP fetch and the native decoder.
 *
 * HTTP lives in Kotlin (OkHttp) rather than C: redirects, TLS, byte-range
 * requests and DLNA servers' assorted quirks are solved problems there, and
 * embedding an HTTP stack in the audio engine would be a large surface for
 * little gain.
 *
 * The decoder pulls through dr_flac's read callback, which is synchronous, so
 * reads block until data arrives or the stream ends. Writes block when the
 * buffer is full, which is what applies backpressure to the network thread --
 * without it a fast server would buffer an entire album into RAM.
 */
class NetworkStream {
public:
    /// 8 MB is roughly nine seconds of a 192 kHz/24-bit FLAC stream, which is
    /// the case that needs the slack; lower rates simply never fill it.
    explicit NetworkStream(size_t capacity = 8u * 1024 * 1024) : capacity_(capacity) {}

    /** Producer. Returns false once the stream is closed. */
    bool write(const uint8_t *data, size_t n) {
        std::unique_lock<std::mutex> lock(mutex_);
        size_t written = 0;
        while (written < n) {
            notFull_.wait(lock, [&] { return closed_ || buffer_.size() < capacity_; });
            if (closed_) return false;
            size_t room = capacity_ - buffer_.size();
            size_t take = std::min(room, n - written);
            buffer_.insert(buffer_.end(), data + written, data + written + take);
            written += take;
            notEmpty_.notify_all();
        }
        return true;
    }

    /**
     * Consumer. Blocks until n bytes are available, the producer signals end of
     * stream, or the stream is closed. Returns the count actually read; a short
     * read means the stream finished.
     */
    size_t read(uint8_t *dst, size_t n) {
        std::unique_lock<std::mutex> lock(mutex_);
        size_t got = 0;
        while (got < n) {
            notEmpty_.wait(lock, [&] { return closed_ || eof_ || !buffer_.empty(); });
            if (closed_) return got;
            if (buffer_.empty()) {
                if (eof_) return got;   // genuine end of stream
                continue;
            }
            size_t take = std::min(buffer_.size(), n - got);
            std::copy(buffer_.begin(), buffer_.begin() + take, dst + got);
            buffer_.erase(buffer_.begin(), buffer_.begin() + take);
            got += take;
            consumed_ += take;
            notFull_.notify_all();
        }
        return got;
    }

    /** Producer finished normally: readers drain what is left, then see EOF. */
    void setEof() {
        std::lock_guard<std::mutex> lock(mutex_);
        eof_ = true;
        notEmpty_.notify_all();
    }

    /** Abandon the stream; unblocks both sides immediately. */
    void close() {
        std::lock_guard<std::mutex> lock(mutex_);
        closed_ = true;
        notEmpty_.notify_all();
        notFull_.notify_all();
    }

    bool closed() const {
        std::lock_guard<std::mutex> lock(mutex_);
        return closed_;
    }

    size_t buffered() const {
        std::lock_guard<std::mutex> lock(mutex_);
        return buffer_.size();
    }

    uint64_t consumed() const {
        std::lock_guard<std::mutex> lock(mutex_);
        return consumed_;
    }

private:
    mutable std::mutex mutex_;
    std::condition_variable notEmpty_, notFull_;
    std::deque<uint8_t> buffer_;
    const size_t capacity_;
    bool eof_ = false;
    bool closed_ = false;
    uint64_t consumed_ = 0;
};
