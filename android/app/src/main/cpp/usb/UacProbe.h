#pragma once
#include <string>

// Adopts an already-open usbfs file descriptor (from Android's
// UsbDeviceConnection.getFileDescriptor()) and returns a human-readable USB
// Audio Class capability report. Never throws; failures are described in the
// returned text so they reach the diagnostics screen on hardware we do not own.
std::string probeUsbAudioDevice(int fd);
