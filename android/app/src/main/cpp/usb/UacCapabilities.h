#pragma once

#include <cstdint>
#include <string>
#include <vector>

struct libusb_device_handle;

// A parsed USB Audio Class capability model.
//
// Shared deliberately: the probe renders this as JSON for the user, and the
// playback engine chooses an alt-setting from it. One parser, one model -- so
// what the capabilities screen promises is exactly what playback acts on.

struct UacEndpoint {
    bool present = false;
    uint8_t address = 0;
    bool isIso = false;
    std::string sync = "none";   // async | adaptive | sync | none
    uint16_t maxPacket = 0;
    uint8_t interval = 0;
    // UAC1 only: the endpoint's own CS_ENDPOINT descriptor says whether it
    // accepts a SET_CUR sampling-frequency request. UAC1 has no clock entity,
    // so this endpoint control is the *only* way to change rate -- and a device
    // without it is fixed-rate, which the engine has to know rather than
    // discover from a STALL.
    bool sampleRateControl = false;
};

struct UacAltSetting {
    uint8_t interfaceNum = 0;
    uint8_t alt = 0;
    int channels = -1;
    int bits = -1;        // bBitResolution: significant bits
    int subslot = -1;     // bSubslotSize: bytes per sample in the wire format
    int terminalLink = -1;
    std::string format = "unknown";  // PCM | DSD | FLOAT | ...
    std::vector<uint32_t> rates;     // UAC1 only; UAC2 rates live on the clock
    UacEndpoint data;
    UacEndpoint feedback;

    bool isPcm() const { return format == "PCM"; }
    int bytesPerFrame() const { return subslot * channels; }

    // Usable for playback: PCM, out over an isochronous endpoint. Capture-only
    // alt-settings look identical apart from endpoint direction, and a UAC1
    // headset adapter exposes both.
    bool playable() const { return isPcm() && data.present && data.isIso; }

    // UAC1 lists its rates per alt-setting; UAC2 keeps them on the clock
    // entity and leaves this empty, in which case any rate the clock supports
    // works with any alt-setting.
    bool supportsRate(uint32_t hz) const {
        if (rates.empty()) return true;
        for (uint32_t r : rates) if (r == hz) return true;
        return false;
    }
};

struct UacCapabilities {
    bool ok = false;
    std::string error;

    uint16_t vendorId = 0, productId = 0;
    std::string manufacturer, product;
    std::string usbVersion, speed;
    uint8_t configurations = 1, activeConfiguration = 1;
    bool highSpeed = false;

    bool isAudioDevice = false;
    bool hasAudioControl = false;
    int uacVersion = 0;              // 0x0200 = UAC2
    uint8_t audioControlInterface = 0;

    int clockSourceId = -1, clockSelectorId = -1;
    bool clockProgrammable = false;
    uint32_t currentRate = 0;
    std::vector<uint32_t> rates;
    std::string clockError;

    bool volumeHostControllable = false;
    int featureUnitId = -1;
    std::string volumeDetail;
    bool hidPresent = false, hidHasOutputEndpoint = false;

    std::vector<UacAltSetting> altSettings;
    std::vector<std::string> interfaceJson;
    std::string audioControlRawHex;

    bool isUac2() const { return uacVersion >= 0x0200; }
    bool supportsRate(uint32_t hz) const;

    // Whether anything here can carry audio out at all. A device can be a
    // perfectly valid audio device and still be no use to a renderer -- a USB
    // microphone, or the capture half of a headset adapter.
    bool hasPlayableAltSetting() const;

    // Best alt-setting for the requested PCM stream, or nullptr if the device
    // cannot carry it. Prefers the narrowest container that holds the source
    // without truncation: a 16-bit source into a 24-bit slot is lossless
    // zero-padding, but a 24-bit source into a 16-bit slot would not be.
    //
    // [rate] matters for UAC1, where each alt-setting carries its own rate
    // list and they need not agree; on UAC2 every alt-setting can clock any
    // rate the clock entity supports, so it is a no-op there.
    const UacAltSetting *chooseAltSetting(int sourceBits, int channels, uint32_t rate) const;
};

// Parses the active configuration of an already-opened device. Never throws;
// failures land in UacCapabilities::error.
UacCapabilities parseUacCapabilities(libusb_device_handle *handle);

// Serialises to JSON for the UI and for logcat.
std::string uacCapabilitiesToJson(const UacCapabilities &caps);
