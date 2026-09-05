#include "Decoder.h"

#include <algorithm>
#include <cctype>

namespace {
bool contains(const std::string &haystack, const char *needle) {
    return haystack.find(needle) != std::string::npos;
}
}  // namespace

SourceFormat formatFromMime(const std::string &mimeRaw) {
    std::string mime;
    mime.reserve(mimeRaw.size());
    for (char c : mimeRaw) mime += static_cast<char>(std::tolower(c));

    if (contains(mime, "flac")) return SourceFormat::Flac;
    if (contains(mime, "mpeg") || contains(mime, "mp3")) return SourceFormat::Mp3;
    // L16 and L24 are headerless PCM; WAV and AIFF are PCM behind a chunk
    // list. PcmDecoder takes all three: it sniffs for the RIFF and FORM
    // signatures and falls back to the MIME parameters, which is also what a
    // server labelling one of those bodies as L16 needs.
    if (contains(mime, "l16") || contains(mime, "l24") ||
        contains(mime, "wav") || contains(mime, "aif")) {
        return SourceFormat::Pcm;
    }
    return SourceFormat::Unknown;
}

const char *formatName(SourceFormat f) {
    switch (f) {
        case SourceFormat::Flac: return "FLAC";
        case SourceFormat::Mp3:  return "MP3";
        case SourceFormat::Pcm:  return "PCM";
        default:                 return "unknown";
    }
}
