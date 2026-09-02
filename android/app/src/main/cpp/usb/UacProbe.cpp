// M1: build a USB Audio Class capability table from whatever DAC is attached.
//
// This runs over libusb rather than the Android Java USB API because the same
// libusb handle is what M2 needs for isochronous transfers, which the Java API
// cannot do at all. Proving libusb_wrap_sys_device() works on this phone is
// therefore as much the point of M1 as the descriptors themselves.
//
// The parser must survive malformed input: it is the app's entire model of
// hardware we do not own. Android's own descriptor parser crashes on at least
// one device we have tested against, so "the platform can parse it" is not a
// safe assumption. Every walk here is bounded by bLength and the buffer end.

#include "UacProbe.h"

#include <android/log.h>
#include <libusb.h>

#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

#define LOG_TAG "hifirend"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGW(...) __android_log_print(ANDROID_LOG_WARN, LOG_TAG, __VA_ARGS__)

namespace {

// USB Audio Class constants (usb.org Audio 1.0 / 2.0 specs).
constexpr uint8_t kClassAudio = 0x01;
constexpr uint8_t kSubclassAudioControl = 0x01;
constexpr uint8_t kSubclassAudioStreaming = 0x02;

constexpr uint8_t kCsInterface = 0x24;
constexpr uint8_t kCsEndpoint = 0x25;

// AC interface descriptor subtypes
constexpr uint8_t kAcHeader = 0x01;
constexpr uint8_t kAcInputTerminal = 0x02;
constexpr uint8_t kAcOutputTerminal = 0x03;
constexpr uint8_t kAcFeatureUnit = 0x06;
constexpr uint8_t kAcClockSource = 0x0A;  // UAC2 only

// AS interface descriptor subtypes
constexpr uint8_t kAsGeneral = 0x01;
constexpr uint8_t kAsFormatType = 0x02;

// Endpoint bmAttributes
constexpr uint8_t kEpTypeMask = 0x03;
constexpr uint8_t kEpTypeIso = 0x01;
constexpr uint8_t kEpSyncMask = 0x0C;
constexpr uint8_t kEpUsageMask = 0x30;
constexpr uint8_t kEpUsageFeedback = 0x10;

// UAC2 control-transfer requests
constexpr uint8_t kReqRange = 0x02;
constexpr uint8_t kCsSamFreqControl = 0x01;

std::string fmt(const char *f, ...) {
    char buf[512];
    va_list ap;
    va_start(ap, f);
    vsnprintf(buf, sizeof(buf), f, ap);
    va_end(ap);
    return std::string(buf);
}

const char *syncTypeName(uint8_t attr) {
    switch ((attr & kEpSyncMask) >> 2) {
        case 0: return "none";
        case 1: return "ASYNC";
        case 2: return "ADAPTIVE";
        case 3: return "SYNC";
        default: return "?";
    }
}

// A class-specific descriptor block, walked safely by bLength.
struct DescWalker {
    const uint8_t *p;
    int remaining;

    bool next(const uint8_t **out, uint8_t *len) {
        // A zero or short bLength would loop forever or read past the end --
        // this is precisely the shape of input that crashes naive parsers.
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

// UAC2 Format Type I bmFormats bits. Two alt-settings can share a bit depth and
// still be different formats (PCM vs DSD/raw), so this is what disambiguates them.
std::string formatNames(uint32_t bmFormats) {
    if (bmFormats == 0) return "(none)";
    std::string s;
    auto add = [&s](const char *n) { if (!s.empty()) s += "|"; s += n; };
    if (bmFormats & (1u << 0))  add("PCM");
    if (bmFormats & (1u << 1))  add("PCM8");
    if (bmFormats & (1u << 2))  add("FLOAT");
    if (bmFormats & (1u << 3))  add("ALAW");
    if (bmFormats & (1u << 4))  add("MULAW");
    if (bmFormats & (1u << 31)) add("RAW/DSD");
    if (s.empty()) s = fmt("0x%08x", bmFormats);
    return s;
}

struct ClockSource {
    uint8_t id = 0;
    std::vector<uint32_t> rates;
    bool ratesKnown = false;
};

// UAC2 reports sample rates at runtime via a GET_RANGE control transfer on the
// clock entity, not in the descriptors -- so a UAC2 device's real rate list is
// only discoverable from a live device.
// GET_CUR on the clock entity: the rate the DAC is running at right now.
bool queryUac2CurrentRate(libusb_device_handle *h, uint8_t acInterface, uint8_t clockId,
                          uint32_t *out) {
    uint8_t buf[4];
    int r = libusb_control_transfer(
        h,
        LIBUSB_ENDPOINT_IN | LIBUSB_REQUEST_TYPE_CLASS | LIBUSB_RECIPIENT_INTERFACE,
        0x01 /* CUR */,
        static_cast<uint16_t>(kCsSamFreqControl << 8),
        static_cast<uint16_t>((clockId << 8) | acInterface),
        buf, sizeof(buf), 1000);
    if (r != 4) return false;
    *out = buf[0] | (buf[1] << 8) | (buf[2] << 16) | (buf[3] << 24);
    return true;
}

bool queryUac2Rates(libusb_device_handle *h, uint8_t acInterface, uint8_t clockId,
                    std::vector<uint32_t> *out, std::string *err) {
    uint8_t buf[512];
    int r = libusb_control_transfer(
        h,
        LIBUSB_ENDPOINT_IN | LIBUSB_REQUEST_TYPE_CLASS | LIBUSB_RECIPIENT_INTERFACE,
        kReqRange,
        static_cast<uint16_t>(kCsSamFreqControl << 8),
        static_cast<uint16_t>((clockId << 8) | acInterface),
        buf, sizeof(buf), 1000);
    if (r < 2) {
        *err = fmt("GET_RANGE failed: %s", r < 0 ? libusb_error_name(r) : "short reply");
        return false;
    }
    uint16_t n = static_cast<uint16_t>(buf[0] | (buf[1] << 8));
    for (uint16_t i = 0; i < n; i++) {
        size_t off = 2 + static_cast<size_t>(i) * 12;
        if (off + 12 > static_cast<size_t>(r)) break;
        uint32_t lo = buf[off] | (buf[off+1] << 8) | (buf[off+2] << 16) | (buf[off+3] << 24);
        uint32_t hi = buf[off+4] | (buf[off+5] << 8) | (buf[off+6] << 16) | (buf[off+7] << 24);
        uint32_t res = buf[off+8] | (buf[off+9] << 8) | (buf[off+10] << 16) | (buf[off+11] << 24);
        if (lo == hi || res == 0) {
            out->push_back(lo);
        } else {
            // A continuous range. Report the bounds rather than enumerating.
            out->push_back(lo);
            out->push_back(hi);
        }
    }
    return true;
}

}  // namespace

std::string probeUsbAudioDevice(int fd) {
    std::string out;
    auto emit = [&out](const std::string &s) {
        LOGI("%s", s.c_str());
        out += s;
        out += "\n";
    };

    // Android apps cannot scan usbfs, so discovery must be disabled and the fd
    // adopted directly. This is the documented Android path for libusb.
    int r = libusb_set_option(nullptr, LIBUSB_OPTION_NO_DEVICE_DISCOVERY);
    if (r != LIBUSB_SUCCESS) {
        return fmt("libusb_set_option(NO_DEVICE_DISCOVERY) failed: %s", libusb_error_name(r));
    }

    libusb_context *ctx = nullptr;
    r = libusb_init(&ctx);
    if (r != LIBUSB_SUCCESS) return fmt("libusb_init failed: %s", libusb_error_name(r));

    libusb_device_handle *h = nullptr;
    r = libusb_wrap_sys_device(ctx, static_cast<intptr_t>(fd), &h);
    if (r != LIBUSB_SUCCESS || h == nullptr) {
        libusb_exit(ctx);
        return fmt("libusb_wrap_sys_device(fd=%d) failed: %s", fd, libusb_error_name(r));
    }
    emit(fmt("libusb_wrap_sys_device: OK (fd=%d)", fd));

    libusb_device *dev = libusb_get_device(h);

    libusb_device_descriptor dd{};
    if (libusb_get_device_descriptor(dev, &dd) == LIBUSB_SUCCESS) {
        emit(fmt("device %04x:%04x  usb=%x.%02x  class=%u  numCfg=%u",
                 dd.idVendor, dd.idProduct, dd.bcdUSB >> 8, dd.bcdUSB & 0xFF,
                 dd.bDeviceClass, dd.bNumConfigurations));
        unsigned char s[256];
        if (dd.iManufacturer &&
            libusb_get_string_descriptor_ascii(h, dd.iManufacturer, s, sizeof(s)) > 0)
            emit(fmt("  manufacturer: %s", s));
        if (dd.iProduct &&
            libusb_get_string_descriptor_ascii(h, dd.iProduct, s, sizeof(s)) > 0)
            emit(fmt("  product     : %s", s));
    }

    int speed = libusb_get_device_speed(dev);
    const char *speedName = speed == LIBUSB_SPEED_FULL ? "full (12 Mbps)"
                          : speed == LIBUSB_SPEED_HIGH ? "high (480 Mbps)"
                          : speed == LIBUSB_SPEED_SUPER ? "super (5 Gbps)"
                          : "unknown";
    emit(fmt("  speed       : %s", speedName));

    libusb_config_descriptor *cfg = nullptr;
    r = libusb_get_active_config_descriptor(dev, &cfg);
    if (r != LIBUSB_SUCCESS || cfg == nullptr) {
        libusb_close(h);
        libusb_exit(ctx);
        return out + fmt("get_active_config_descriptor failed: %s", libusb_error_name(r));
    }

    emit(fmt("config #%u: %u interface(s)", cfg->bConfigurationValue, cfg->bNumInterfaces));

    // Every interface, including non-audio ones. Composite DACs often put volume
    // on a HID interface instead of a UAC Feature Unit, so a HID interface here
    // is a lead worth following rather than noise.
    for (int i = 0; i < cfg->bNumInterfaces; i++) {
        const libusb_interface &itf = cfg->interface[i];
        for (int a = 0; a < itf.num_altsetting; a++) {
            const libusb_interface_descriptor &id = itf.altsetting[a];
            const char *cls =
                id.bInterfaceClass == 0x01 ? "AUDIO" :
                id.bInterfaceClass == 0x03 ? "HID" :
                id.bInterfaceClass == 0x08 ? "MASS-STORAGE" :
                id.bInterfaceClass == 0x0A ? "CDC-DATA" :
                id.bInterfaceClass == 0xFE ? "APP-SPECIFIC" :
                id.bInterfaceClass == 0xFF ? "VENDOR" : "other";
            emit(fmt("  if=%u alt=%u class=0x%02x(%s) sub=0x%02x proto=0x%02x eps=%u extra=%d",
                     id.bInterfaceNumber, id.bAlternateSetting, id.bInterfaceClass, cls,
                     id.bInterfaceSubClass, id.bInterfaceProtocol, id.bNumEndpoints,
                     id.extra_length));
            // Direction matters for the HID interface: an interrupt IN endpoint
            // means the DAC reports its own knob/remote to us, which is the
            // opposite of the host being able to set the DAC's volume.
            for (int e = 0; e < id.bNumEndpoints && id.bInterfaceClass != kClassAudio; e++) {
                const libusb_endpoint_descriptor &ep = id.endpoint[e];
                const char *type =
                    (ep.bmAttributes & 0x03) == 0 ? "control" :
                    (ep.bmAttributes & 0x03) == 1 ? "iso" :
                    (ep.bmAttributes & 0x03) == 2 ? "bulk" : "interrupt";
                emit(fmt("      ep 0x%02x %s %s maxPacket=%u interval=%u",
                         ep.bEndpointAddress,
                         (ep.bEndpointAddress & 0x80) ? "IN (device->host)" : "OUT (host->device)",
                         type, ep.wMaxPacketSize, ep.bInterval));
            }
        }
    }

    int uacVersion = 0;          // 0x0100 = UAC1, 0x0200 = UAC2
    uint8_t acInterfaceNum = 0;
    std::vector<ClockSource> clocks;
    bool sawAudio = false;
    bool volumeControl = false;
    std::string volumeDetail = "none found";

    // Pass 1: AudioControl interfaces -- UAC version, feature units, clocks.
    for (int i = 0; i < cfg->bNumInterfaces; i++) {
        const libusb_interface &itf = cfg->interface[i];
        for (int a = 0; a < itf.num_altsetting; a++) {
            const libusb_interface_descriptor &id = itf.altsetting[a];
            if (id.bInterfaceClass != kClassAudio) continue;
            sawAudio = true;
            if (id.bInterfaceSubClass != kSubclassAudioControl) continue;

            acInterfaceNum = id.bInterfaceNumber;

            // Dump the raw AC block. If a Feature Unit is reported as absent,
            // this is the evidence that it genuinely is not there rather than
            // the parser having skipped it.
            {
                std::string hex;
                for (int b = 0; b < id.extra_length && b < 128; b++) {
                    hex += fmt("%02x ", id.extra[b]);
                }
                emit(fmt("  AC raw (%d bytes): %s", id.extra_length, hex.c_str()));
            }

            DescWalker w{id.extra, id.extra_length};
            const uint8_t *d;
            uint8_t len;
            while (w.next(&d, &len)) {
                if (d[1] != kCsInterface || len < 3) continue;
                switch (d[2]) {
                    case kAcHeader:
                        if (len >= 5) {
                            uacVersion = d[3] | (d[4] << 8);
                            emit(fmt("AudioControl if=%u  UAC version %x.%02x",
                                     id.bInterfaceNumber, uacVersion >> 8, uacVersion & 0xFF));
                        }
                        break;
                    case kAcClockSource:
                        if (len >= 4) {
                            ClockSource cs;
                            cs.id = d[3];
                            clocks.push_back(cs);
                            emit(fmt("  clock source id=%u", cs.id));
                        }
                        break;
                    case kAcFeatureUnit: {
                        if (len < 6) break;
                        uint8_t unitId = d[3];
                        // UAC1 lays out bControlSize then bmaControls of that
                        // width; UAC2 uses fixed 4-byte entries. Volume lives in
                        // a different bit position in each.
                        if (uacVersion >= 0x0200) {
                            // d[5..] = bmaControls[0] (master), 4 bytes each
                            if (len >= 10) {
                                uint32_t master = d[5] | (d[6] << 8) | (d[7] << 16) | (d[8] << 24);
                                // bits 2-3 = Volume Control
                                uint8_t vol = (master >> 2) & 0x03;
                                if (vol) {
                                    volumeControl = true;
                                    volumeDetail = fmt("FeatureUnit id=%u, volume %s",
                                                       unitId,
                                                       vol == 3 ? "host-programmable" : "read-only");
                                }
                            }
                        } else {
                            uint8_t ctlSize = d[5];
                            if (ctlSize >= 1 && len >= 7) {
                                // bmaControls[0] bit 1 = Volume
                                if (d[6] & 0x02) {
                                    volumeControl = true;
                                    volumeDetail = fmt("FeatureUnit id=%u, volume (UAC1)", unitId);
                                }
                            }
                        }
                        emit(fmt("  feature unit id=%u", unitId));
                        break;
                    }
                    default:
                        break;
                }
            }
        }
    }

    // UAC2 rate discovery needs a live control transfer per clock entity.
    for (auto &cs : clocks) {
        uint32_t cur = 0;
        if (queryUac2CurrentRate(h, acInterfaceNum, cs.id, &cur)) {
            emit(fmt("  clock %u current rate: %u Hz", cs.id, cur));
        }
        std::string err;
        if (queryUac2Rates(h, acInterfaceNum, cs.id, &cs.rates, &err)) {
            cs.ratesKnown = true;
            std::string s = fmt("  clock %u rates:", cs.id);
            for (uint32_t hz : cs.rates) s += fmt(" %u", hz);
            emit(s);
        } else {
            emit(fmt("  clock %u rates: %s", cs.id, err.c_str()));
        }
    }

    // Pass 2: AudioStreaming alt-settings -- the actual playable formats.
    for (int i = 0; i < cfg->bNumInterfaces; i++) {
        const libusb_interface &itf = cfg->interface[i];
        for (int a = 0; a < itf.num_altsetting; a++) {
            const libusb_interface_descriptor &id = itf.altsetting[a];
            if (id.bInterfaceClass != kClassAudio ||
                id.bInterfaceSubClass != kSubclassAudioStreaming) continue;

            // alt 0 is the mandatory zero-bandwidth setting; nothing streams there.
            if (id.bNumEndpoints == 0) {
                emit(fmt("AS if=%u alt=%u  (zero-bandwidth)",
                         id.bInterfaceNumber, id.bAlternateSetting));
                continue;
            }

            int channels = -1, bits = -1, subslot = -1, termLink = -1;
            uint32_t bmFormats = 0;
            std::vector<uint32_t> rates;

            DescWalker w{id.extra, id.extra_length};
            const uint8_t *d;
            uint8_t len;
            while (w.next(&d, &len)) {
                if (d[1] != kCsInterface || len < 3) continue;
                if (d[2] == kAsGeneral && uacVersion >= 0x0200 && len >= 12) {
                    termLink = d[3];
                    bmFormats = d[6] | (d[7] << 8) | (d[8] << 16) |
                                (static_cast<uint32_t>(d[9]) << 24);
                    channels = d[10];
                } else if (d[2] == kAsFormatType && len >= 4) {
                    if (uacVersion >= 0x0200) {
                        if (len >= 6) { subslot = d[4]; bits = d[5]; }
                    } else if (len >= 8) {
                        channels = d[4];
                        subslot = d[5];
                        bits = d[6];
                        uint8_t nRates = d[7];
                        if (nRates == 0 && len >= 14) {
                            uint32_t lo = d[8] | (d[9] << 8) | (d[10] << 16);
                            uint32_t hi = d[11] | (d[12] << 8) | (d[13] << 16);
                            rates.push_back(lo);
                            rates.push_back(hi);
                        } else {
                            for (uint8_t k = 0; k < nRates; k++) {
                                size_t off = 8 + static_cast<size_t>(k) * 3;
                                if (off + 3 > len) break;
                                rates.push_back(d[off] | (d[off+1] << 8) | (d[off+2] << 16));
                            }
                        }
                    }
                }
            }

            std::string line = fmt("AS if=%u alt=%u  ch=%d bits=%d subslot=%d fmt=%s link=%d",
                                   id.bInterfaceNumber, id.bAlternateSetting,
                                   channels, bits, subslot,
                                   formatNames(bmFormats).c_str(), termLink);
            if (!rates.empty()) {
                line += "  rates:";
                for (uint32_t hz : rates) line += fmt(" %u", hz);
            } else if (uacVersion >= 0x0200) {
                line += "  rates: (from clock source)";
            }
            emit(line);

            for (int e = 0; e < id.bNumEndpoints; e++) {
                const libusb_endpoint_descriptor &ep = id.endpoint[e];
                bool isIso = (ep.bmAttributes & kEpTypeMask) == kEpTypeIso;
                bool isFeedback = (ep.bmAttributes & kEpUsageMask) == kEpUsageFeedback;
                emit(fmt("    ep 0x%02x %s %s%s maxPacket=%u interval=%u",
                         ep.bEndpointAddress,
                         (ep.bEndpointAddress & 0x80) ? "IN " : "OUT",
                         isIso ? "ISO " : "non-iso ",
                         isIso ? syncTypeName(ep.bmAttributes) : "",
                         ep.wMaxPacketSize, ep.bInterval));
                if (isFeedback) {
                    emit("      ^ feedback endpoint (async clock tracking)");
                }
            }
        }
    }

    if (dd.bNumConfigurations > 1) {
        emit(fmt("note: device has %u configurations; only the active one (#%u) was parsed. "
                 "XMOS-based DACs commonly expose a UAC1 fallback config here.",
                 dd.bNumConfigurations, cfg->bConfigurationValue));
    }

    emit("--------");
    emit(fmt("UAC version   : %s",
             uacVersion == 0 ? "not found"
             : uacVersion >= 0x0200 ? "2.0" : "1.0"));
    emit(fmt("audio class   : %s", sawAudio ? "yes" : "NO -- not a USB audio device"));
    emit(fmt("volume control: %s", volumeControl ? volumeDetail.c_str() : "none found"));

    libusb_free_config_descriptor(cfg);
    libusb_close(h);
    libusb_exit(ctx);
    return out;
}
