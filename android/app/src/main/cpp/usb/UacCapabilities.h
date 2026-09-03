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

    // Best alt-setting for the requested PCM stream, or nullptr if the device
    // cannot carry it. Prefers the narrowest container that holds the source
    // without truncation: a 16-bit source into a 24-bit slot is lossless
    // zero-padding, but a 24-bit source into a 16-bit slot would not be.
    const UacAltSetting *chooseAltSetting(int sourceBits, int channels) const;
};

// Parses the active configuration of an already-opened device. Never throws;
// failures land in UacCapabilities::error.
UacCapabilities parseUacCapabilities(libusb_device_handle *handle);

// Serialises to JSON for the UI and for logcat.
std::string uacCapabilitiesToJson(const UacCapabilities &caps);
