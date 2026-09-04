// USB Audio Class descriptor parsing.
//
// Two hard rules:
//  1. Never branch on VID/PID. Everything downstream derives from what was
//     parsed at runtime -- the reference DAC is one sample, not the spec.
//  2. Survive malformed input. This is the app's entire model of foreign
//     hardware, and Android's own parser crashes on at least one bus we have
//     tested. Every walk is bounded by bLength and rejects short descriptors.

#include "UacCapabilities.h"

#include <libusb.h>

#include <algorithm>
#include <cstdarg>
#include <cstdio>
#include <cstring>

namespace {

constexpr uint8_t kClassAudio = 0x01;
constexpr uint8_t kSubclassAudioControl = 0x01;
constexpr uint8_t kSubclassAudioStreaming = 0x02;

constexpr uint8_t kCsInterface = 0x24;
constexpr uint8_t kCsEndpoint = 0x25;

// UAC1 CS_ENDPOINT/EP_GENERAL: bmAttributes bit 0 is the sampling frequency
// control -- the only rate-setting mechanism UAC1 has.
constexpr uint8_t kEpGeneral = 0x01;
constexpr uint8_t kEpAttrSamplingFreq = 0x01;

constexpr uint8_t kAcHeader = 0x01;
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

const char *syncTypeName(uint8_t attr) {
    switch ((attr & kEpSyncMask) >> 2) {
        case 0: return "none";
        case 1: return "async";
        case 2: return "adaptive";
        case 3: return "sync";
        default: return "unknown";
    }
}

std::string formatName(uint32_t bmFormats, int uacVersion) {
    if (uacVersion < 0x0200) return "PCM";
    if (bmFormats & (1u << 31)) return "DSD";
    if (bmFormats & (1u << 0)) return "PCM";
    if (bmFormats & (1u << 2)) return "FLOAT";
    if (bmFormats & (1u << 1)) return "PCM8";
    if (bmFormats & (1u << 3)) return "ALAW";
    if (bmFormats & (1u << 4)) return "MULAW";
    if (bmFormats == 0) return "unknown";
    return fmt("other(0x%08x)", bmFormats);
}

// A zero or short bLength is exactly what makes a naive parser loop forever or
// read past the end of the buffer.
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

std::string joinInts(const std::vector<uint32_t> &v) {
    std::string s;
    for (size_t i = 0; i < v.size(); i++) {
        if (i) s += ",";
        s += fmt("%u", v[i]);
    }
    return s;
}

}  // namespace

bool UacCapabilities::supportsRate(uint32_t hz) const {
    if (!rates.empty()) {
        return std::find(rates.begin(), rates.end(), hz) != rates.end();
    }
    for (const auto &a : altSettings) {
        if (std::find(a.rates.begin(), a.rates.end(), hz) != a.rates.end()) return true;
    }
    return false;
}

bool UacCapabilities::hasPlayableAltSetting() const {
    for (const auto &a : altSettings) {
        if (a.playable()) return true;
    }
    return false;
}

const UacAltSetting *UacCapabilities::chooseAltSetting(int sourceBits, int ch,
                                                       uint32_t rate) const {
    const UacAltSetting *best = nullptr;
    for (const auto &a : altSettings) {
        if (!a.isPcm()) continue;              // DSD is out of scope
        if (a.channels != ch) continue;
        if (!a.data.present || !a.data.isIso) continue;
        // On UAC1 the alt-setting *is* the rate selection, so an alt that does
        // not list this rate cannot carry it however wide its container.
        if (!a.supportsRate(rate)) continue;
        // The container must hold every source bit. Widening is lossless
        // zero-padding; narrowing would discard real audio data.
        if (a.bits < sourceBits) continue;
        // Prefer the narrowest sufficient container: less bus bandwidth, and
        // no benefit to padding further than necessary.
        if (best == nullptr || a.bits < best->bits) best = &a;
    }
    return best;
}

UacCapabilities parseUacCapabilities(libusb_device_handle *h) {
    UacCapabilities caps;
    if (h == nullptr) {
        caps.error = "null handle";
        return caps;
    }

    libusb_device *dev = libusb_get_device(h);

    libusb_device_descriptor dd{};
    libusb_get_device_descriptor(dev, &dd);
    caps.vendorId = dd.idVendor;
    caps.productId = dd.idProduct;
    caps.configurations = dd.bNumConfigurations;
    caps.usbVersion = fmt("%x.%02x", dd.bcdUSB >> 8, dd.bcdUSB & 0xFF);

    unsigned char sbuf[256];
    if (dd.iManufacturer &&
        libusb_get_string_descriptor_ascii(h, dd.iManufacturer, sbuf, sizeof(sbuf)) > 0)
        caps.manufacturer = reinterpret_cast<char *>(sbuf);
    if (dd.iProduct &&
        libusb_get_string_descriptor_ascii(h, dd.iProduct, sbuf, sizeof(sbuf)) > 0)
        caps.product = reinterpret_cast<char *>(sbuf);

    int speed = libusb_get_device_speed(dev);
    caps.highSpeed = (speed == LIBUSB_SPEED_HIGH || speed == LIBUSB_SPEED_SUPER);
    caps.speed = speed == LIBUSB_SPEED_LOW ? "low"
               : speed == LIBUSB_SPEED_FULL ? "full"
               : speed == LIBUSB_SPEED_HIGH ? "high"
               : speed == LIBUSB_SPEED_SUPER ? "super" : "unknown";

    libusb_config_descriptor *cfg = nullptr;
    int r = libusb_get_active_config_descriptor(dev, &cfg);
    if (r != LIBUSB_SUCCESS || cfg == nullptr) {
        caps.error = fmt("config_descriptor: %s", libusb_error_name(r));
        return caps;
    }
    caps.activeConfiguration = cfg->bConfigurationValue;

    // Pass 1: all interfaces. Non-audio ones are evidence too -- a composite DAC
    // may put volume on HID rather than a UAC Feature Unit.
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
            caps.interfaceJson.push_back(
                fmt("{\"interface\":%u,\"alt\":%u,\"class\":%u,\"className\":\"%s\","
                    "\"subclass\":%u,\"protocol\":%u,\"endpoints\":%u}",
                    id.bInterfaceNumber, id.bAlternateSetting, id.bInterfaceClass, cls,
                    id.bInterfaceSubClass, id.bInterfaceProtocol, id.bNumEndpoints));

            if (id.bInterfaceClass == 0x03) {
                caps.hidPresent = true;
                for (int e = 0; e < id.bNumEndpoints; e++) {
                    if ((id.endpoint[e].bEndpointAddress & 0x80) == 0)
                        caps.hidHasOutputEndpoint = true;
                }
            }

            if (id.bInterfaceClass != kClassAudio) continue;
            caps.isAudioDevice = true;
            if (id.bInterfaceSubClass != kSubclassAudioControl) continue;

            caps.hasAudioControl = true;
            caps.audioControlInterface = id.bInterfaceNumber;
            for (int b = 0; b < id.extra_length && b < 256; b++)
                caps.audioControlRawHex += fmt("%02x", id.extra[b]);

            DescWalker w{id.extra, id.extra_length};
            const uint8_t *d;
            uint8_t len;
            while (w.next(&d, &len)) {
                if (d[1] != kCsInterface || len < 3) continue;
                switch (d[2]) {
                    case kAcHeader:
                        if (len >= 5) caps.uacVersion = d[3] | (d[4] << 8);
                        break;
                    case kAcClockSource:
                        if (len >= 6) {
                            caps.clockSourceId = d[3];
                            caps.clockProgrammable = (d[5] & 0x03) == 0x03;
                        }
                        break;
                    case kAcClockSelector:
                        if (len >= 4) caps.clockSelectorId = d[3];
                        break;
                    case kAcFeatureUnit: {
                        if (len < 6) break;
                        caps.featureUnitId = d[3];
                        if (caps.uacVersion >= 0x0200) {
                            if (len >= 9) {
                                uint32_t master = d[5] | (d[6] << 8) | (d[7] << 16) |
                                                  (static_cast<uint32_t>(d[8]) << 24);
                                uint8_t vol = (master >> 2) & 0x03;
                                if (vol) {
                                    caps.volumeHostControllable = (vol == 0x03);
                                    caps.volumeDetail =
                                        vol == 0x03 ? "host-programmable" : "read-only";
                                }
                            }
                        } else {
                            if (d[5] >= 1 && len >= 7 && (d[6] & 0x02)) {
                                caps.volumeHostControllable = true;
                                caps.volumeDetail = "UAC1 feature unit";
                            }
                        }
                        break;
                    }
                    default: break;
                }
            }
        }
    }

    // UAC2 reports real rates only from a live clock query.
    if (caps.uacVersion >= 0x0200 && caps.clockSourceId >= 0) {
        uint8_t buf[512];
        int n = libusb_control_transfer(
            h, LIBUSB_ENDPOINT_IN | LIBUSB_REQUEST_TYPE_CLASS | LIBUSB_RECIPIENT_INTERFACE,
            kReqCur, static_cast<uint16_t>(kCsSamFreqControl << 8),
            static_cast<uint16_t>((caps.clockSourceId << 8) | caps.audioControlInterface),
            buf, 4, 1000);
        if (n == 4) {
            caps.currentRate = buf[0] | (buf[1] << 8) | (buf[2] << 16) |
                               (static_cast<uint32_t>(buf[3]) << 24);
        }

        n = libusb_control_transfer(
            h, LIBUSB_ENDPOINT_IN | LIBUSB_REQUEST_TYPE_CLASS | LIBUSB_RECIPIENT_INTERFACE,
            kReqRange, static_cast<uint16_t>(kCsSamFreqControl << 8),
            static_cast<uint16_t>((caps.clockSourceId << 8) | caps.audioControlInterface),
            buf, sizeof(buf), 1000);
        if (n >= 2) {
            uint16_t count = static_cast<uint16_t>(buf[0] | (buf[1] << 8));
            for (uint16_t k = 0; k < count; k++) {
                size_t off = 2 + static_cast<size_t>(k) * 12;
                if (off + 12 > static_cast<size_t>(n)) break;
                uint32_t lo = buf[off] | (buf[off+1] << 8) | (buf[off+2] << 16) |
                              (static_cast<uint32_t>(buf[off+3]) << 24);
                uint32_t hi = buf[off+4] | (buf[off+5] << 8) | (buf[off+6] << 16) |
                              (static_cast<uint32_t>(buf[off+7]) << 24);
                caps.rates.push_back(lo);
                if (hi != lo) caps.rates.push_back(hi);
            }
        } else {
            caps.clockError = "clock query failed (AudioControl interface not claimed?)";
        }
    }

    // Pass 2: the playable formats.
    for (int i = 0; i < cfg->bNumInterfaces; i++) {
        const libusb_interface &itf = cfg->interface[i];
        for (int a = 0; a < itf.num_altsetting; a++) {
            const libusb_interface_descriptor &id = itf.altsetting[a];
            if (id.bInterfaceClass != kClassAudio ||
                id.bInterfaceSubClass != kSubclassAudioStreaming) continue;
            if (id.bNumEndpoints == 0) continue;  // zero-bandwidth alt 0

            UacAltSetting as;
            as.interfaceNum = id.bInterfaceNumber;
            as.alt = id.bAlternateSetting;
            uint32_t bmFormats = 0;

            DescWalker w{id.extra, id.extra_length};
            const uint8_t *d;
            uint8_t len;
            while (w.next(&d, &len)) {
                if (d[1] != kCsInterface || len < 3) continue;
                if (d[2] == kAsGeneral && caps.uacVersion >= 0x0200 && len >= 12) {
                    as.terminalLink = d[3];
                    bmFormats = d[6] | (d[7] << 8) | (d[8] << 16) |
                                (static_cast<uint32_t>(d[9]) << 24);
                    as.channels = d[10];
                } else if (d[2] == kAsGeneral && caps.uacVersion < 0x0200 && len >= 7) {
                    as.terminalLink = d[3];
                } else if (d[2] == kAsFormatType && len >= 4) {
                    if (caps.uacVersion >= 0x0200) {
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
            as.format = formatName(bmFormats, caps.uacVersion);

            for (int e = 0; e < id.bNumEndpoints; e++) {
                const libusb_endpoint_descriptor &ep = id.endpoint[e];
                UacEndpoint info;
                info.present = true;
                info.address = ep.bEndpointAddress;
                info.isIso = (ep.bmAttributes & kEpTypeMask) == kEpTypeIso;
                info.sync = syncTypeName(ep.bmAttributes);
                info.maxPacket = ep.wMaxPacketSize;
                info.interval = ep.bInterval;

                // The audio-class endpoint descriptor rides in the endpoint's
                // extra bytes. On UAC1 it carries the one bit that says whether
                // this endpoint accepts a sampling-frequency SET_CUR -- which
                // is the only way to change rate on a device with no clock
                // entity. A device without it is fixed-rate, and the engine has
                // to know that rather than discover it from a STALL.
                DescWalker ew{ep.extra, ep.extra_length};
                const uint8_t *ed;
                uint8_t elen;
                while (ew.next(&ed, &elen)) {
                    if (ed[1] != kCsEndpoint || elen < 4) continue;
                    if (ed[2] != kEpGeneral) continue;
                    if (caps.uacVersion < 0x0200) {
                        info.sampleRateControl = (ed[3] & kEpAttrSamplingFreq) != 0;
                    }
                }

                if ((ep.bmAttributes & kEpUsageMask) == kEpUsageFeedback ||
                    ((ep.bEndpointAddress & 0x80) && info.isIso && ep.wMaxPacketSize <= 4)) {
                    as.feedback = info;
                } else if ((ep.bEndpointAddress & 0x80) == 0) {
                    as.data = info;
                }
            }
            caps.altSettings.push_back(as);
        }
    }

    libusb_free_config_descriptor(cfg);
    caps.ok = true;
    return caps;
}

std::string uacCapabilitiesToJson(const UacCapabilities &c) {
    if (!c.ok) {
        return "{\"ok\":false,\"error\":" + jstr("parse_failed") +
               ",\"message\":" + jstr(c.error) + "}";
    }
    std::string j = "{\"ok\":true";
    j += ",\"vendorId\":" + fmt("%u", c.vendorId);
    j += ",\"productId\":" + fmt("%u", c.productId);
    j += ",\"vendorIdHex\":" + jstr(fmt("0x%04x", c.vendorId));
    j += ",\"productIdHex\":" + jstr(fmt("0x%04x", c.productId));
    j += ",\"manufacturer\":" + jstr(c.manufacturer);
    j += ",\"product\":" + jstr(c.product);
    j += ",\"usbVersion\":" + jstr(c.usbVersion);
    j += ",\"speed\":" + jstr(c.speed);
    j += ",\"configurations\":" + fmt("%u", c.configurations);
    j += ",\"activeConfiguration\":" + fmt("%u", c.activeConfiguration);
    j += ",\"isAudioDevice\":" + jbool(c.isAudioDevice);
    j += ",\"hasAudioControl\":" + jbool(c.hasAudioControl);
    j += ",\"uacVersion\":" + jstr(c.uacVersion == 0 ? "unknown"
                                   : c.uacVersion >= 0x0200 ? "2.0" : "1.0");
    j += ",\"clock\":{\"sourceId\":" + fmt("%d", c.clockSourceId);
    j += ",\"selectorId\":" + fmt("%d", c.clockSelectorId);
    j += ",\"programmable\":" + jbool(c.clockProgrammable);
    j += ",\"currentRate\":" + fmt("%u", c.currentRate);
    j += ",\"rates\":[" + joinInts(c.rates) + "]";
    j += ",\"error\":" + jstr(c.clockError) + "}";
    j += ",\"volume\":{\"hostControllable\":" + jbool(c.volumeHostControllable);
    j += ",\"featureUnitId\":" + fmt("%d", c.featureUnitId);
    j += ",\"detail\":" + jstr(c.volumeDetail);
    j += ",\"hidPresent\":" + jbool(c.hidPresent);
    j += ",\"hidHasOutputEndpoint\":" + jbool(c.hidHasOutputEndpoint) + "}";

    j += ",\"formats\":[";
    for (size_t i = 0; i < c.altSettings.size(); i++) {
        const UacAltSetting &a = c.altSettings[i];
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
        j += ",\"sampleRateControl\":" + jbool(a.data.sampleRateControl);
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
    for (size_t i = 0; i < c.interfaceJson.size(); i++) {
        if (i) j += ",";
        j += c.interfaceJson[i];
    }
    j += "]";
    j += ",\"audioControlRawHex\":" + jstr(c.audioControlRawHex);
    j += "}";
    return j;
}
