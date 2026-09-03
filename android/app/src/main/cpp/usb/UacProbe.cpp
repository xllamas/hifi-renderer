// Thin wrapper: the parsing lives in UacCapabilities so the playback engine and
// the capabilities screen act on exactly the same model.

#include "UacProbe.h"

#include <android/log.h>
#include <libusb.h>

#include "UacCapabilities.h"

#define LOG_TAG "hifirend"

std::string probeUsbAudioDevice(int fd) {
    int r = libusb_set_option(nullptr, LIBUSB_OPTION_NO_DEVICE_DISCOVERY);
    if (r != LIBUSB_SUCCESS) {
        return "{\"ok\":false,\"error\":\"libusb_option\",\"message\":\"set_option failed\"}";
    }
    libusb_context *ctx = nullptr;
    if (libusb_init(&ctx) != LIBUSB_SUCCESS) {
        return "{\"ok\":false,\"error\":\"libusb_init\",\"message\":\"init failed\"}";
    }
    libusb_device_handle *h = nullptr;
    r = libusb_wrap_sys_device(ctx, static_cast<intptr_t>(fd), &h);
    if (r != LIBUSB_SUCCESS || h == nullptr) {
        libusb_exit(ctx);
        return "{\"ok\":false,\"error\":\"wrap_sys_device\",\"message\":\"could not adopt the USB file descriptor\"}";
    }

    UacCapabilities caps = parseUacCapabilities(h);
    std::string json = uacCapabilitiesToJson(caps);

    __android_log_print(ANDROID_LOG_INFO, LOG_TAG,
                        "probe: %s %s (%04x:%04x) UAC%s, %zu format(s), volume=%s",
                        caps.manufacturer.c_str(), caps.product.c_str(),
                        caps.vendorId, caps.productId,
                        caps.isUac2() ? "2.0" : caps.uacVersion ? "1.0" : "?",
                        caps.altSettings.size(),
                        caps.volumeHostControllable ? "host-controllable" : "device-only");

    libusb_close(h);
    libusb_exit(ctx);
    return json;
}
