#pragma once

#include "Decoder.h"

/**
 * FLAC via dr_flac.
 *
 * [relaxed] opens a stream that begins mid-file. It is only usable when the
 * frame headers happen to carry rate and depth explicitly, which is not
 * guaranteed -- FLAC allows them to say "refer to STREAMINFO". Seeking
 * therefore prepends the real header instead of relying on this.
 */
class FlacDecoder : public Decoder {
public:
    explicit FlacDecoder(bool relaxed = false) : relaxed_(relaxed) {}
    ~FlacDecoder() override;

    bool open(NetworkStream *stream, std::string *error) override;
    uint64_t read(int32_t *out, uint64_t frames) override;
    void close() override;

private:
    // Opaque: dr_flac declares `typedef struct {...} drflac;` with no tag, so
    // it cannot be forward-declared and the header would otherwise have to
    // drag in all 12k lines of the implementation.
    void *flac_ = nullptr;
    NetworkStream *stream_ = nullptr;
    bool relaxed_ = false;
};
