#pragma once
// Stands in for the NDK's logging header so the decoders can be built and run
// on the host. Only what they use is here.
#include <cstdarg>
#include <cstdio>

enum { ANDROID_LOG_INFO, ANDROID_LOG_ERROR };

static inline int __android_log_print(int, const char *tag, const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    fprintf(stderr, "[%s] ", tag);
    vfprintf(stderr, fmt, ap);
    fprintf(stderr, "\n");
    va_end(ap);
    return 0;
}
