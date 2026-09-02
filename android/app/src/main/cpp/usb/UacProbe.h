#pragma once
#include <string>

// Adopts an already-open usbfs file descriptor (from Android's
// UsbDeviceConnection.getFileDescriptor()) and returns the device's USB Audio
// Class capabilities as a JSON object.
//
// Structured rather than pre-formatted text because there are three consumers
// with different needs: the audio engine picks an alt-setting from it, the
// settings screen renders it in plain language for the user, and logcat gets a
// human dump for support. Wording belongs in the UI layer, facts belong here.
//
// Never throws. Failures come back as {"ok":false,"error":...} so they still
// reach the user on hardware we do not own.
std::string probeUsbAudioDevice(int fd);
