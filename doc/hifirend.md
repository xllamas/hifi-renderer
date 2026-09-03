
# HiFi Renderer

## App Objective

The app is a simple DLNA/UPnP (and possibly other protocols) audio renderer. The idea is to be able to convert an unused phone into a dedicated audio renderer with bit perfect USB audio output.

## Initial Functionality 

* DLNA Renderer

* Bit perfect audio output to USB bypassing the Android system so that the app works in Android versions previous to 14.

* The app should implement passing of volume change signals to the USB playback device (DAC) if accepted by the device.

* The main screen of the app should just show the current track album art, the track information (title, author etc), the format and resolution of the current track.

* The app should implement local playlists so that the app keeps playing the playlist even if the DLNA controller is no longer present.

* The app should include a 4x2 widget that shows the same information as the main screen but on a smaller format.

* The app should be always active, start on Android startup, turn the screen off after a few minutes of inactivity and turn the screen back on when audio playback starts, preventing all Android sleeps, and power saving shutdowns.

* On the main screen there should be a small button to enter a configuration screen.

* Initially the configuration should be the network name of the renderer. Other USB and DLNA tweaks and parameters could be implemented later.

* On first run the app should ask the user add the relevant permissions for the app to function properly.

## Implementation

* Flutter app

* Android version and (if at all possible) iOS version.

## Further Enhancements

* Other protocols: ChromeCast, AirPlay, Bluetooth, Tidal Connect?










 