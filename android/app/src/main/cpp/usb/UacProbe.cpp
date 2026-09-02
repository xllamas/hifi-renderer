// Builds a USB Audio Class capability model from whatever DAC is attached.
//
// Two hard rules, both learned the hard way:
//
// 1. NOTHING here may be specialised to a particular device. The app targets
//    DACs we will never own, so every decision downstream must come from what
//    was parsed at runtime. No VID/PID branching.
//
// 2. The parser must survive malformed input. It is the app's entire model of
//    foreign hardware, and Android's own descriptor parser crashes on at least
//    one bus we have tested (`dumpsys usb` -> IllegalArgumentException in
//    UsbDescriptorParser). Every walk is bounded by bLength and rejects
//    zero/short descriptors.
//
// This runs over libusb rather than Android's Java USB API because the same
// handle is what the playback engine needs for isochronous transfers, which
// the Java API cannot do at all.

#include "UacProbe.h"

#include <android/log.h>
#include <libusb.h>

#include <cstdarg>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

#define LOG_TAG "hifirend"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)

namespace {

constexpr uint8_t kClassAudio = 0x01;
constexpr uint8_t kSubclassAudioControl = 0x01;
constexpr uint8_t kSubclassAudioStreaming = 0x02;

constexpr uint8_t kCsInterface = 0x24;

constexpr uint8_t kAcHeader = 0x01;
constexpr uint8_t kAcInputTerminal = 0x02;
constexpr uint8_t kAcOutputTerminal = 0x03;
constexpr uint8_t kAcFeatureUnit = 0x06;
constexpr uint8_t kAcClockSource = 0x0A;
constexpr uint8_t kAcClockSelector = 0x0B;

constexpr uint8_t kAsGeneral = 0x01;
constexpr uint8_t kAsFormatType = 0x02;

constexpr uint8_t kEpTypeMask = 0x03;
constexpr uint8_t kEpTypeIso = 0x01;
constexpr uint8_t kEpSyncMask = 0x0C;
constexpr uint8_t kEpUsageMask = 0x30;
constexpr uint8_t kEpUsageFeedback = 0x10;

constexpr uint8_t kReqCur = 0x01;
constexpr uint8_t kReqRange = 0x02;
constexpr uint8_t kCsSamFreqControl = 0x01;

std::string fmt(const char *f, ...) {
    char buf[1024];
    va_list ap;
    va_start(ap, f);
    vsnprintf(buf, sizeof(buf), f, ap);
    va_end(ap);
    return std::string(buf);
}

// Minimal JSON string escaping. Device strings come from foreign firmware and
// have no obligation to be well-behaved.
std::string jstr(const std::string &in) {
    std::string o = "\"";
    for (unsigned char c : in) {
        switch (c) {
            case '"':  o += "\\\""; break;
            case '\\': o += "\\\\"; break;
            case '\n': o += "\\n"; break;
            case '\r': o += "\\r"; break;
            case '\t': o += "\\t"; break;
            default:
                if (c < 0x20 || c == 0x7F) o += fmt("\\u%04x", c);
                else o += static_cast<char>(c);
        }
    }
    return o + "\"";
}

std::string jbool(bool b) { return b ? "true" : "false"; }

std::string errorJson(const std::string &code, const std::string &message) {
    return "{\"ok\":false,\"error\":" + jstr(code) + ",\"message\":" + jstr(message) + "}";
}

const char *syncTypeName(uint8_t attr) {
    switch ((attr & kEpSyncMask) >> 2) {
        case 0: return "none";
        case 1: return "async";
        case 2: return "adaptive";
        case 3: return "sync";
        default: return "unknown";
    }
}

// UAC2 Format Type I bmFormats. Two alt-settings can share a bit depth and
// still be different formats, so this is what tells PCM from DSD.
std::string formatName(uint32_t bmFormats, int uacVersion) {
    if (uacVersion < 0x0200) return "PCM";  // UAC1 uses wFormatTag; PCM dominates
    if (bmFormats & (1u << 31)) return "DSD";
    if (bmFormats & (1u << 0)) return "PCM";
    if (bmFormats & (1u << 2)) return "FLOAT";
    if (bmFormats & (1u << 1)) return "PCM8";
    if (bmFormats & (1u << 3)) return "ALAW";
    if (bmFormats & (1u << 4)) return "MULAW";
    if (bmFormats == 0) return "unknown";
    return fmt("other(0x%08x)", bmFormats);
}

// Walks a class-specific descriptor block safely. A zero or short bLength is
// the exact input that makes a naive parser loop forever or read past the end.
struct DescWalker {
    const uint8_t *p;
    int remaining;

    bool next(const uint8_t **out, uint8_t *len) {
        if (remaining < 2) return false;
        uint8_t l = p[0];
        if (l < 2 || l > remaining) return false;
        *out = p;
        *len = l;
        p += l;
        remaining -= l;
        return true;
    }
};

struct EndpointInfo {
    bool present = false;
    uint8_t address = 0;
    bool isIso = false;
    std::string sync = "none";
    uint16_t maxPacket = 0;
    uint8_t interval = 0;
};

struct AltSetting {
    uint8_t interfaceNum = 0;
    uint8_t alt = 0;
    int channels = -1;
    int bits = -1;
    int subslot = -1;
    int terminalLink = -1;
    std::string format = "unknown";
    std::vector<uint32_t> rates;   // UAC1 only; UAC2 gets them from the clock
    EndpointInfo data;
    EndpointInfo feedback;
};

std::string joinInts(const std::vector<uint32_t> &v) {
    std::string s;
    for (size_t i = 0; i < v.size(); i++) {
        if (i) s += ",";
        s += fmt("%u", v[i]);
    }
    return s;
}

bool queryRate(libusb_device_handle *h, uint8_t acInterface, uint8_t clockId,
               uint8_t request, uint8_t *buf, size_t bufLen, int *outLen) {
    int r = libusb_control_transfer(
        h,
        LIBUSB_ENDPOINT_IN | LIBUSB_REQUEST_TYPE_CLASS | LIBUSB_RECIPIENT_INTERFACE,
        request,
        static_cast<uint16_t>(kCsSamFreqControl << 8),
        static_cast<uint16_t>((clockId << 8) | acInterface),
        buf, static_cast<uint16_t>(bufLen), 1000);
    if (r < 0) return false;
    *outLen = r;
    return true;
}

}  // namespace

std::string probeUsbAudioDevice(int fd) {
    // Android apps cannot scan usbfs, so discovery must be off and the fd
    // adopted directly. This is the documented Android path for libusb.
    int r = libusb_set_option(nullptr, LIBUSB_OPTION_NO_DEVICE_DISCOVERY);
    if (r != LIBUSB_SUCCESS) {
        return errorJson("libusb_option", libusb_error_name(r));
    }

    libusb_context *ctx = nullptr;
    r = libusb_init(&ctx);
    if (r != LIBUSB_SUCCESS) return errorJson("libusb_init", libusb_error_name(r));

    libusb_device_handle *h = nullptr;
    r = libusb_wrap_sys_device(ctx, static_cast<intptr_t>(fd), &h);
    if (r != LIBUSB_SUCCESS || h == nullptr) {
        libusb_exit(ctx);
        return errorJson("wrap_sys_device",
                         fmt("fd=%d: %s", fd, libusb_error_name(r)));
    }

    libusb_device *dev = libusb_get_device(h);

    libusb_device_descriptor dd{};
    libusb_get_device_descriptor(dev, &dd);

    std::string manufacturer, product;
    unsigned char sbuf[256];
    if (dd.iManufacturer &&
        libusb_get_string_descriptor_ascii(h, dd.iManufacturer, sbuf, sizeof(sbuf)) > 0)
        manufacturer = reinterpret_cast<char *>(sbuf);
    if (dd.iProduct &&
        libusb_get_string_descriptor_ascii(h, dd.iProduct, sbuf, sizeof(sbuf)) > 0)
        product = reinterpret_cast<char *>(sbuf);

    int speed = libusb_get_device_speed(dev);
    const char *speedName = speed == LIBUSB_SPEED_LOW ? "low"
                          : speed == LIBUSB_SPEED_FULL ? "full"
                          : speed == LIBUSB_SPEED_HIGH ? "high"
                          : speed == LIBUSB_SPEED_SUPER ? "super"
                          : "unknown";

    libusb_config_descriptor *cfg = nullptr;
    r = libusb_get_active_config_descriptor(dev, &cfg);
    if (r != LIBUSB_SUCCESS || cfg == nullptr) {
        libusb_close(h);
        libusb_exit(ctx);
        return errorJson("config_descriptor", libusb_error_name(r));
    }

    int uacVersion = 0;
    uint8_t acInterfaceNum = 0;
    bool haveAudioControl = false;
    bool sawAudio = false;

    int clockSourceId = -1, clockSelectorId = -1;
    bool clockProgrammable = false;

    bool volumeSupported = false;
    std::string volumeDetail;
    int featureUnitId = -1;

    bool hidPresent = false, hidHasOutput = false;
    std::string acRawHex;
    std::vector<std::string> interfaceLines;

    // Pass 1: every interface, audio or not. A composite DAC may expose volume
    // over HID rather than a UAC Feature Unit, so non-audio interfaces are
    // evidence, not noise.
    for (int i = 0; i < cfg->bNumInterfaces; i++) {
        const libusb_interface &itf = cfg->interface[i];
        for (int a = 0; a < itf.num_altsetting; a++) {
            const libusb_interface_descriptor &id = itf.altsetting[a];
            const char *cls =
                id.bInterfaceClass == 0x01 ? "audio" :
                id.bInterfaceClass == 0x03 ? "hid" :
                id.bInterfaceClass == 0x08 ? "mass-storage" :
                id.bInterfaceClass == 0xFE ? "app-specific(DFU?)" :
                id.bInterfaceClass == 0xFF ? "vendor" : "other";
            interfaceLines.push_back(
                fmt("{\"interface\":%u,\"alt\":%u,\"class\":%u,\"className\":\"%s\","
                    "\"subclass\":%u,\"protocol\":%u,\"endpoints\":%u}",
                    id.bInterfaceNumber, id.bAlternateSetting, id.bInterfaceClass, cls,
                    id.bInterfaceSubClass, id.bInterfaceProtocol, id.bNumEndpoints));

            if (id.bInterfaceClass == 0x03) {
                hidPresent = true;
                for (int e = 0; e < id.bNumEndpoints; e++) {
                    // An OUT endpoint would mean the host can send reports, which
                    // is the only way HID could carry host->device volume.
                    if ((id.endpoint[e].bEndpointAddress & 0x80) == 0) hidHasOutput = true;
                }
            }

            if (id.bInterfaceClass != kClassAudio) continue;
            sawAudio = true;
            if (id.bInterfaceSubClass != kSubclassAudioControl) continue;

            haveAudioControl = true;
            acInterfaceNum = id.bInterfaceNumber;

            for (int b = 0; b < id.extra_length && b < 256; b++) {
                acRawHex += fmt("%02x", id.extra[b]);
            }

            DescWalker w{id.extra, id.extra_length};
            const uint8_t *d;
            uint8_t len;
            while (w.next(&d, &len)) {
                if (d[1] != kCsInterface || len < 3) continue;
                switch (d[2]) {
                    case kAcHeader:
                        if (len >= 5) uacVersion = d[3] | (d[4] << 8);
                        break;
                    case kAcClockSource:
                        if (len >= 6) {
                            clockSourceId = d[3];
                            // bmControls bits 0-1: 3 = frequency host-programmable
                            clockProgrammable = ((d[5] >> 0) & 0x03) == 0x03;
                        }
                        break;
                    case kAcClockSelector:
                        if (len >= 4) clockSelectorId = d[3];
                        break;
                    case kAcFeatureUnit: {
                        if (len < 6) break;
                        featureUnitId = d[3];
                        if (uacVersion >= 0x0200) {
                            if (len >= 9) {
                                uint32_t master = d[5] | (d[6] << 8) | (d[7] << 16) |
                                                  (static_cast<uint32_t>(d[8]) << 24);
                                uint8_t vol = (master >> 2) & 0x03;
                                if (vol) {
                                    volumeSupported = (vol == 0x03);
                                    volumeDetail = vol == 0x03 ? "host-programmable"
                                                               : "read-only";
                                }
                            }
                        } else {
                            uint8_t ctlSize = d[5];
                            if (ctlSize >= 1 && len >= 7 && (d[6] & 0x02)) {
                                volumeSupported = true;
                                volumeDetail = "UAC1 feature unit";
                            }
                        }
                        break;
                    }
                    default:
                        break;
                }
            }
        }
    }

    // UAC2 reports its real rates only from a live clock query.
    std::vector<uint32_t> clockRates;
    uint32_t currentRate = 0;
    std::string clockError;
    if (uacVersion >= 0x0200 && clockSourceId >= 0) {
        uint8_t buf[512];
        int n = 0;
        if (queryRate(h, acInterfaceNum, static_cast<uint8_t>(clockSourceId),
                      kReqCur, buf, 4, &n) && n == 4) {
            currentRate = buf[0] | (buf[1] << 8) | (buf[2] << 16) |
                          (static_cast<uint32_t>(buf[3]) << 24);
        }
        if (queryRate(h, acInterfaceNum, static_cast<uint8_t>(clockSourceId),
                      kReqRange, buf, sizeof(buf), &n) && n >= 2) {
            uint16_t count = static_cast<uint16_t>(buf[0] | (buf[1] << 8));
            for (uint16_t k = 0; k < count; k++) {
                size_t off = 2 + static_cast<size_t>(k) * 12;
                if (off + 12 > static_cast<size_t>(n)) break;
                uint32_t lo = buf[off] | (buf[off+1] << 8) | (buf[off+2] << 16) |
                              (static_cast<uint32_t>(buf[off+3]) << 24);
                uint32_t hi = buf[off+4] | (buf[off+5] << 8) | (buf[off+6] << 16) |
                              (static_cast<uint32_t>(buf[off+7]) << 24);
                clockRates.push_back(lo);
                if (hi != lo) clockRates.push_back(hi);
            }
        } else {
            // Almost always the kernel driver still holding the interface.
            clockError = "clock query failed (AudioControl interface not claimed?)";
        }
    }

    // Pass 2: the playable formats.
    std::vector<AltSetting> alts;
    for (int i = 0; i < cfg->bNumInterfaces; i++) {
        const libusb_interface &itf = cfg->interface[i];
        for (int a = 0; a < itf.num_altsetting; a++) {
            const libusb_interface_descriptor &id = itf.altsetting[a];
            if (id.bInterfaceClass != kClassAudio ||
                id.bInterfaceSubClass != kSubclassAudioStreaming) continue;
            if (id.bNumEndpoints == 0) continue;  // zero-bandwidth alt 0

            AltSetting as;
            as.interfaceNum = id.bInterfaceNumber;
            as.alt = id.bAlternateSetting;
            uint32_t bmFormats = 0;

            DescWalker w{id.extra, id.extra_length};
            const uint8_t *d;
            uint8_t len;
            while (w.next(&d, &len)) {
                if (d[1] != kCsInterface || len < 3) continue;
                if (d[2] == kAsGeneral && uacVersion >= 0x0200 && len >= 12) {
                    as.terminalLink = d[3];
                    bmFormats = d[6] | (d[7] << 8) | (d[8] << 16) |
                                (static_cast<uint32_t>(d[9]) << 24);
                    as.channels = d[10];
                } else if (d[2] == kAsGeneral && uacVersion < 0x0200 && len >= 7) {
                    as.terminalLink = d[3];
                } else if (d[2] == kAsFormatType && len >= 4) {
                    if (uacVersion >= 0x0200) {
                        if (len >= 6) { as.subslot = d[4]; as.bits = d[5]; }
                    } else if (len >= 8) {
                        as.channels = d[4];
                        as.subslot = d[5];
                        as.bits = d[6];
                        uint8_t nRates = d[7];
                        if (nRates == 0 && len >= 14) {
                            as.rates.push_back(d[8] | (d[9] << 8) | (d[10] << 16));
                            as.rates.push_back(d[11] | (d[12] << 8) | (d[13] << 16));
                        } else {
                            for (uint8_t k = 0; k < nRates; k++) {
                                size_t off = 8 + static_cast<size_t>(k) * 3;
                                if (off + 3 > len) break;
                                as.rates.push_back(d[off] | (d[off+1] << 8) | (d[off+2] << 16));
                            }
                        }
                    }
                }
            }
            as.format = formatName(bmFormats, uacVersion);

            for (int e = 0; e < id.bNumEndpoints; e++) {
                const libusb_endpoint_descriptor &ep = id.endpoint[e];
                EndpointInfo info;
                info.present = true;
                info.address = ep.bEndpointAddress;
                info.isIso = (ep.bmAttributes & kEpTypeMask) == kEpTypeIso;
                info.sync = syncTypeName(ep.bmAttributes);
                info.maxPacket = ep.wMaxPacketSize;
                info.interval = ep.bInterval;
                if ((ep.bmAttributes & kEpUsageMask) == kEpUsageFeedback ||
                    ((ep.bEndpointAddress & 0x80) && info.isIso && ep.wMaxPacketSize <= 4)) {
                    as.feedback = info;
                } else if ((ep.bEndpointAddress & 0x80) == 0) {
                    as.data = info;
                }
            }
            alts.push_back(as);
        }
    }

    // Serialise. Facts only -- the UI decides how to phrase them.
    std::string j = "{\"ok\":true";
    j += ",\"vendorId\":" + fmt("%u", dd.idVendor);
    j += ",\"productId\":" + fmt("%u", dd.idProduct);
    j += ",\"vendorIdHex\":" + jstr(fmt("0x%04x", dd.idVendor));
    j += ",\"productIdHex\":" + jstr(fmt("0x%04x", dd.idProduct));
    j += ",\"manufacturer\":" + jstr(manufacturer);
    j += ",\"product\":" + jstr(product);
    j += ",\"usbVersion\":" + jstr(fmt("%x.%02x", dd.bcdUSB >> 8, dd.bcdUSB & 0xFF));
    j += ",\"speed\":" + jstr(speedName);
    j += ",\"configurations\":" + fmt("%u", dd.bNumConfigurations);
    j += ",\"activeConfiguration\":" + fmt("%u", cfg->bConfigurationValue);
    j += ",\"isAudioDevice\":" + jbool(sawAudio);
    j += ",\"hasAudioControl\":" + jbool(haveAudioControl);
    j += ",\"uacVersion\":" + jstr(uacVersion == 0 ? "unknown"
                                   : uacVersion >= 0x0200 ? "2.0" : "1.0");

    j += ",\"clock\":{\"sourceId\":" + fmt("%d", clockSourceId);
    j += ",\"selectorId\":" + fmt("%d", clockSelectorId);
    j += ",\"programmable\":" + jbool(clockProgrammable);
    j += ",\"currentRate\":" + fmt("%u", currentRate);
    j += ",\"rates\":[" + joinInts(clockRates) + "]";
    j += ",\"error\":" + jstr(clockError) + "}";

    j += ",\"volume\":{\"hostControllable\":" + jbool(volumeSupported);
    j += ",\"featureUnitId\":" + fmt("%d", featureUnitId);
    j += ",\"detail\":" + jstr(volumeDetail);
    j += ",\"hidPresent\":" + jbool(hidPresent);
    j += ",\"hidHasOutputEndpoint\":" + jbool(hidHasOutput) + "}";

    j += ",\"formats\":[";
    for (size_t i = 0; i < alts.size(); i++) {
        const AltSetting &a = alts[i];
        if (i) j += ",";
        j += "{\"interface\":" + fmt("%u", a.interfaceNum);
        j += ",\"alt\":" + fmt("%u", a.alt);
        j += ",\"format\":" + jstr(a.format);
        j += ",\"bits\":" + fmt("%d", a.bits);
        j += ",\"subslot\":" + fmt("%d", a.subslot);
        j += ",\"channels\":" + fmt("%d", a.channels);
        j += ",\"terminalLink\":" + fmt("%d", a.terminalLink);
        j += ",\"rates\":[" + joinInts(a.rates) + "]";
        j += ",\"endpoint\":{\"address\":" + jstr(fmt("0x%02x", a.data.address));
        j += ",\"iso\":" + jbool(a.data.isIso);
        j += ",\"sync\":" + jstr(a.data.sync);
        j += ",\"maxPacket\":" + fmt("%u", a.data.maxPacket);
        j += ",\"interval\":" + fmt("%u", a.data.interval) + "}";
        j += ",\"feedbackEndpoint\":";
        if (a.feedback.present) {
            j += "{\"address\":" + jstr(fmt("0x%02x", a.feedback.address));
            j += ",\"maxPacket\":" + fmt("%u", a.feedback.maxPacket);
            j += ",\"interval\":" + fmt("%u", a.feedback.interval) + "}";
        } else {
            j += "null";
        }
        j += "}";
    }
    j += "]";

    j += ",\"interfaces\":[";
    for (size_t i = 0; i < interfaceLines.size(); i++) {
        if (i) j += ",";
        j += interfaceLines[i];
    }
    j += "]";
    j += ",\"audioControlRawHex\":" + jstr(acRawHex);
    j += "}";

    LOGI("probe: %s %s (%04x:%04x) UAC%s, %zu format(s), volume=%s",
         manufacturer.c_str(), product.c_str(), dd.idVendor, dd.idProduct,
         uacVersion >= 0x0200 ? "2.0" : uacVersion ? "1.0" : "?",
         alts.size(), volumeSupported ? "host-controllable" : "device-only");
    LOGI("probe json: %s", j.c_str());

    libusb_free_config_descriptor(cfg);
    libusb_close(h);
    libusb_exit(ctx);
    return j;
}
