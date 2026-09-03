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
    // L16/L24 are raw PCM; wav is handled by the file player, not here.
    if (contains(mime, "l16") || contains(mime, "l24")) return SourceFormat::Pcm;
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
