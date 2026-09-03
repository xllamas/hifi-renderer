#pragma once

#include <atomic>
#include <cstddef>
#include <cstring>
#include <memory>

// Lock-free single-producer/single-consumer byte ring.
//
// The consumer is a USB isochronous completion callback: it runs on libusb's
// event thread and must never block, allocate, or take a lock, because missing
// a 125 us microframe deadline is an audible dropout. That constraint is what
// rules out a mutex-based queue here.
class RingBuffer {
public:
    explicit RingBuffer(size_t capacity)
        : capacity_(capacity + 1), buf_(new uint8_t[capacity + 1]) {}

    size_t capacity() const { return capacity_ - 1; }

    size_t available() const {
        size_t w = write_.load(std::memory_order_acquire);
        size_t r = read_.load(std::memory_order_relaxed);
        return w >= r ? w - r : capacity_ - r + w;
    }

    size_t space() const { return capacity() - available(); }

    // Producer side.
    size_t write(const uint8_t *src, size_t n) {
        size_t w = write_.load(std::memory_order_relaxed);
        size_t r = read_.load(std::memory_order_acquire);
        size_t free = (r > w ? r - w : capacity_ - w + r) - 1;
        if (n > free) n = free;
        size_t first = std::min(n, capacity_ - w);
        memcpy(buf_.get() + w, src, first);
        if (n > first) memcpy(buf_.get(), src + first, n - first);
        write_.store((w + n) % capacity_, std::memory_order_release);
        return n;
    }

    // Consumer side. Short reads are the caller's problem: an underrun must be
    // filled with silence rather than stalling the transfer.
    size_t read(uint8_t *dst, size_t n) {
        size_t r = read_.load(std::memory_order_relaxed);
        size_t w = write_.load(std::memory_order_acquire);
        size_t avail = w >= r ? w - r : capacity_ - r + w;
        if (n > avail) n = avail;
        size_t first = std::min(n, capacity_ - r);
        memcpy(dst, buf_.get() + r, first);
        if (n > first) memcpy(dst + first, buf_.get(), n - first);
        read_.store((r + n) % capacity_, std::memory_order_release);
        return n;
    }

    void clear() {
        read_.store(0, std::memory_order_relaxed);
        write_.store(0, std::memory_order_relaxed);
    }

private:
    const size_t capacity_;
    std::unique_ptr<uint8_t[]> buf_;
    std::atomic<size_t> read_{0};
    std::atomic<size_t> write_{0};
};
