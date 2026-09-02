// M0 skeleton: proves the whole native chain is wired up before any real work
// depends on it -- JNI reaches C++, libusb links and reports its version, and
// Oboe links. Everything here is replaced in M1/M2.

#include <jni.h>
#include <android/log.h>
#include <string>

#include <libusb.h>
#include <oboe/Oboe.h>

#define LOG_TAG "hifirend"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)

namespace {

// Reported to the UI so an M0 install on unknown hardware says something useful.
std::string selfTest() {
    const libusb_version *v = libusb_get_version();

    // Not just a version macro: calling a real Oboe symbol is what proves the
    // prefab AAR actually linked rather than merely being on the include path.
    const char *oboeOk = oboe::convertToText(oboe::Result::OK);

    std::string abi =
#if defined(__aarch64__)
        "arm64-v8a";
#elif defined(__arm__)
        "armeabi-v7a";
#elif defined(__x86_64__)
        "x86_64";
#else
        "unknown";
#endif

    std::string out = "abi=" + abi +
                      " libusb=" + std::to_string(v->major) + "." +
                      std::to_string(v->minor) + "." + std::to_string(v->micro) +
                      " oboe=" + oboeOk +
                      " bits=" + std::to_string(sizeof(void *) * 8);

    LOGI("selfTest: %s", out.c_str());
    return out;
}

}  // namespace

extern "C" JNIEXPORT jstring JNICALL
Java_com_hifirend_NativeBridge_nativeSelfTest(JNIEnv *env, jobject /* this */) {
    return env->NewStringUTF(selfTest().c_str());
}
