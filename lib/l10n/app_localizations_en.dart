// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get settingsTooltip => 'Settings';

  @override
  String get idleReady => 'Ready — waiting for a controller';

  @override
  String get idleNoDac => 'No DAC connected';

  @override
  String get unknownTrack => 'Unknown track';

  @override
  String airPlayFromSender(String sender) {
    return 'AirPlay from $sender';
  }

  @override
  String get previousTrack => 'Previous track';

  @override
  String get nextTrack => 'Next track';

  @override
  String get pause => 'Pause';

  @override
  String get play => 'Play';

  @override
  String get volumeWriteOnly =>
      'This DAC does not report its volume back, so this shows the last value sent from here.';

  @override
  String get systemAudioDetail =>
      'Phone speaker or headphones — resampled by Android';

  @override
  String dacOneOf(int count) {
    return '(1 of $count)';
  }

  @override
  String get bitPerfect => 'bit-perfect';

  @override
  String get systemAudioBadge => 'system audio';

  @override
  String get airPlaySenderResampled => 'AirPlay · sender resampled';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsNetworkName => 'Network name';

  @override
  String get settingsNetworkNameHelp =>
      'How this renderer appears in DLNA controllers.';

  @override
  String get settingsSave => 'Save';

  @override
  String get settingsSaved => 'Saved';

  @override
  String get settingsRenamed =>
      'Renamed. Restart the app for controllers to see it.';

  @override
  String get settingsAudioDevice => 'Audio device';

  @override
  String settingsDacsMultiple(int count) {
    return '$count USB audio devices are attached. Choose which one to play through; the choice is remembered across reboots.';
  }

  @override
  String get settingsDacsSingle =>
      'One USB audio device is attached. Tap it to play through it, and to grant access if it has not been granted yet.';

  @override
  String get settingsUsbAudioDevice => 'USB audio device';

  @override
  String get settingsPermissionNotGranted => ' — permission not granted';

  @override
  String get settingsReadingDevice => 'Reading the device…';

  @override
  String get settingsProbing => 'Asking the DAC what it supports';

  @override
  String settingsUacTap(String version) {
    return 'USB Audio Class $version — tap for what it supports';
  }

  @override
  String get settingsConnectToProbe => 'Connect a USB DAC and tap to probe';

  @override
  String get settingsPcmOnly =>
      'Accept only PCM streams and let the server do the decoding/transcoding';

  @override
  String get settingsPcmOnlyOn =>
      'The renderer advertises nothing but LPCM, at the rates this DAC can clock, so the server converts everything to fit. Everything plays and nothing is bit-perfect -- including tracks the DAC could have played untouched.';

  @override
  String get settingsPcmOnlyOff =>
      'The renderer advertises every format it can decode, so files arrive untouched. Tracks at rates this DAC cannot clock are refused, and the reason is shown.';

  @override
  String get settingsScreenOffAfter => 'Turn the screen off after';

  @override
  String get settingsScreenOffNever =>
      'The screen stays on. Fine on a permanently powered phone, but an OLED panel showing the same screen for months is how it acquires a permanent one.';

  @override
  String get settingsScreenOffTimed =>
      'Counted from when the music stops -- a long track never blanks the screen mid-play. Playback turns it back on.';

  @override
  String get settingsTimeoutNever => 'Never';

  @override
  String settingsTimeoutMinutes(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: '$minutes minutes',
      one: '1 minute',
    );
    return '$_temp0';
  }

  @override
  String get settingsDacVerification => 'DAC verification';

  @override
  String get settingsDacVerificationSubtitle =>
      'Test every rate this DAC claims';

  @override
  String get settingsAlwaysOn => 'Always on';

  @override
  String get settingsAlwaysOnHelp =>
      'A dedicated renderer has to keep running with the screen off and come back after a reboot. Android and most phone makers block that by default.';

  @override
  String settingsDeaths(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'This phone has stopped the renderer $count times',
      one: 'This phone has stopped the renderer once',
    );
    return '$_temp0';
  }

  @override
  String get settingsDeathsDetail =>
      'Each one is a start that followed a run which never recorded a clean stop, so something killed it in the background. Granting what is below usually fixes it.';

  @override
  String get settingsBattery => 'Battery optimisation exemption';

  @override
  String get settingsBatteryGranted =>
      'Granted — Android will not suspend the renderer.';

  @override
  String get settingsBatteryNotGranted =>
      'Not granted. Android may suspend the renderer when idle.';

  @override
  String get settingsGrant => 'Grant';

  @override
  String get settingsOpenSettings => 'Open settings';

  @override
  String get settingsCouldNotOpen =>
      'Could not open that screen on this phone.';

  @override
  String settingsAutostart(String vendor) {
    return 'Autostart ($vendor)';
  }

  @override
  String get settingsAutostartVendorFallback => 'vendor';

  @override
  String get settingsAutostartDetail =>
      'Phones from this maker usually add background-app restrictions of their own, separate from Android\'s, and they are the usual reason a renderer does not start after a reboot. The app cannot detect them, only that this maker has such a screen.';

  @override
  String get settingsWakeScreen => 'Wake the screen when music starts';

  @override
  String get settingsWakeScreenDetail =>
      'Music has played here while the screen stayed dark. Android switches off a screen hold from an app with no window on display, and this phone refused to let the renderer bring its own window up, so the panel lit for a moment and went back to sleep. The permission is usually called something like \"Display pop-up windows while running in the background\", and it is separate from autostart.';

  @override
  String get settingsRunSetup => 'Run setup again';

  @override
  String get settingsRunSetupSubtitle =>
      'Walk through the permissions in order';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsLanguageSystem => 'Same as this phone';

  @override
  String get settingsLanguageHelp =>
      'The renderer follows this phone unless you choose otherwise. A box set up on a spare phone often inherits a language nobody wanted.';

  @override
  String get onboardingTitle => 'Set up HiFi Renderer';

  @override
  String get onboardingTitleRerun => 'Setup';

  @override
  String get onboardingIntro =>
      'This phone is going to sit somewhere and be a renderer. Android and most phone makers assume no app wants to do that, so a few things have to be turned on by hand.';

  @override
  String get onboardingOptional =>
      'None of it is required to try the app, and you can change any of it later in Settings.';

  @override
  String get onboardingNotifications => 'Show a notification';

  @override
  String get onboardingNotificationsGranted =>
      'Granted. The renderer will show its notification while running.';

  @override
  String get onboardingNotificationsWhy =>
      'Android will not let the renderer keep running in the background without one, and it is the only visible sign the renderer is alive.';

  @override
  String get onboardingAllow => 'Allow';

  @override
  String get onboardingNoNotificationScreen =>
      'This phone has no notification settings screen to open.';

  @override
  String get onboardingNotificationsInSettings =>
      'Android stopped asking — turn notifications on there.';

  @override
  String get onboardingBattery => 'Stop Android suspending it';

  @override
  String get onboardingBatteryGranted =>
      'Granted. Android will not suspend the renderer when idle.';

  @override
  String get onboardingBatteryWhy =>
      'Without this, Android suspends the app when the screen has been off for a while, and playback stops mid-track.';

  @override
  String onboardingVendorKnown(String vendor) {
    return 'Autostart ($vendor)';
  }

  @override
  String get onboardingVendorKnownNoName => 'Autostart';

  @override
  String get onboardingVendorUnknown => 'Your phone maker\'s own restrictions';

  @override
  String get onboardingVendorKnownDetail =>
      'Phones from this maker usually add background-app restrictions of their own, separate from Android\'s, and they are the usual reason a renderer does not come back after a reboot. The app cannot detect them — it only knows this maker has such a screen — and it cannot tell whether you granted anything there, so this step never ticks.';

  @override
  String get onboardingVendorUnknownDetail =>
      'We have no known settings screen for this phone. If the renderer stops when idle or does not return after a reboot, look for \"autostart\", \"background apps\" or \"protected apps\" in your phone\'s own battery settings.';

  @override
  String get onboardingDac => 'Your DAC';

  @override
  String get onboardingDacDetail =>
      'Plug the USB DAC in when you are ready. Android asks for permission the first time it is attached, so there is nothing to do here — and the renderer follows whatever DAC is connected rather than being configured for one.';

  @override
  String get onboardingDone => 'Done';

  @override
  String get onboardingFinishAnyway => 'Finish anyway';

  @override
  String get onboardingAllGranted => 'Everything the app can check is granted.';

  @override
  String get onboardingSkippingIsFine =>
      'Skipping is fine. The renderer will run; it may just not survive being left alone, and Settings will tell you if something is stopping it.';

  @override
  String onboardingStep(int number, String title) {
    return '$number. $title';
  }

  @override
  String get dacCapsTitle => 'DAC capabilities';

  @override
  String get dacCapsReprobe => 'Re-probe';

  @override
  String get dacCapsNotProbed => 'Not probed yet';

  @override
  String get dacCapsNotProbedDetail => 'Connect a USB DAC and tap refresh.';

  @override
  String get dacCapsUnknownError => 'Unknown error.';

  @override
  String get dacCapsNoDevice => 'No DAC found';

  @override
  String get dacCapsPermissionNeeded => 'Permission needed';

  @override
  String get dacCapsOpenFailed => 'Could not open the DAC';

  @override
  String get dacCapsProbeFailed => 'Probe failed';

  @override
  String get dacCapsNotUsable => 'Not usable for bit-perfect playback';

  @override
  String get dacCapsWorthKnowing => 'Things worth knowing';

  @override
  String get dacCapsWhatItSupports => 'What it supports';

  @override
  String dacCapsIdentity(
    String version,
    String speed,
    String vendor,
    String product,
  ) {
    return 'USB Audio Class $version · $speed-speed · $vendor:$product';
  }

  @override
  String get dacCapsSampleRates => 'Sample rates';

  @override
  String get dacCapsBitDepths => 'Bit depths';

  @override
  String get dacCapsChannels => 'Channels';

  @override
  String get dacCapsCurrentlyAt => 'Currently running at';

  @override
  String get dacCapsUsbTiming => 'USB timing';

  @override
  String get dacCapsVolumeControl => 'Volume control';

  @override
  String get dacCapsDsd => 'DSD';

  @override
  String get dacCapsUnknown => 'Unknown';

  @override
  String dacCapsRateRange(String low, String high, int count) {
    return '$low – $high ($count rates)';
  }

  @override
  String dacCapsBitDepth(int bits) {
    return '$bits-bit';
  }

  @override
  String get dacCapsAsync => 'Asynchronous (DAC clock)';

  @override
  String get dacCapsSync => 'Synchronous';

  @override
  String get dacCapsVolumeOverUsb => 'Supported over USB';

  @override
  String get dacCapsVolumeDeviceOnly => 'On the device only';

  @override
  String get dacCapsDsdSupported => 'Supported by the hardware';

  @override
  String get dacCapsTechnical => 'Technical details';

  @override
  String get dacCapsTechnicalSubtitle => 'For support reports';

  @override
  String dacCapsKhz(String value) {
    return '$value kHz';
  }

  @override
  String get noteCannotPlayTitle => 'This device cannot play audio';

  @override
  String get noteCannotPlayDetail =>
      'It advertises the USB audio class but offers no PCM output over an isochronous endpoint. Capture-only devices look like this — a USB microphone, or the recording half of a headset adapter.';

  @override
  String get noteUac1Title => 'This device uses USB Audio Class 1.0';

  @override
  String get noteUac1Detail =>
      'Supported, with the limits the class itself imposes: full-speed USB caps the bandwidth, so UAC1 devices top out well below what a UAC2 DAC offers. Playback is still bit-perfect at the rates it does support — nothing is resampled.';

  @override
  String get noteAdaptiveTitle => 'This device follows the phone\'s clock';

  @override
  String get noteAdaptiveDetail =>
      'Its endpoint is adaptive rather than asynchronous, so it adapts to the rate the phone sends instead of running its own clock and asking the phone to follow. Common on UAC1 hardware. Samples still arrive unaltered; the timing reference is simply the phone\'s.';

  @override
  String get noteVolumeDeviceTitle =>
      'Volume is controlled by the DAC, not this app';

  @override
  String get noteVolumeOneWayDetail =>
      'This device exposes no USB volume control. It does report its own knob or remote to the phone, but that is one-way: nothing sent from here can change its volume. Use the physical control.';

  @override
  String get noteVolumeNoneDetail =>
      'This device exposes no USB volume control, so volume commands from a DLNA controller cannot reach it. Use the physical control.';

  @override
  String get noteVolumeAppTitle => 'Volume can be set from this app';

  @override
  String noteVolumeAppDetail(String detail) {
    return 'The DAC exposes a USB volume control ($detail), so DLNA volume commands are passed straight to the hardware.';
  }

  @override
  String notePaddedTitle(int bits) {
    return '16-bit tracks are padded to $bits-bit';
  }

  @override
  String notePaddedDetail(int bits) {
    return 'This DAC offers no 16-bit mode, so CD-resolution files are placed in a $bits-bit container. The sample values are unchanged, so playback is still bit-perfect.';
  }

  @override
  String get noteAsyncGoodTitle => 'Asynchronous USB with its own clock';

  @override
  String get noteAsyncGoodDetail =>
      'The DAC drives timing rather than following the phone, which is the better arrangement for audio quality.';

  @override
  String get noteAsyncNoFeedbackTitle =>
      'Asynchronous, but no feedback endpoint found';

  @override
  String get noteAsyncNoFeedbackDetail =>
      'Timing cannot be tracked precisely, so occasional dropouts are possible on long playback.';

  @override
  String get noteDsdTitle => 'DSD capable';

  @override
  String get noteDsdDetail =>
      'This DAC accepts native DSD. The app does not play DSD yet.';

  @override
  String get noteAltConfigTitle => 'Alternative USB mode available';

  @override
  String noteAltConfigDetail(int count) {
    return 'The device offers $count USB configurations. Only the active one is used; some DACs keep a compatibility mode in the other.';
  }

  @override
  String get noteClockErrorTitle => 'Could not read the supported sample rates';

  @override
  String get reportCopied => 'Report copied';

  @override
  String get copyReport => 'Copy report';

  @override
  String get stop => 'Stop';

  @override
  String get notReported => 'not reported';

  @override
  String get verifyTitle => 'DAC verification';

  @override
  String get verifyResults => 'Results';

  @override
  String get verifyFollow => 'Follow';

  @override
  String get soakTitle => 'Stability soak';

  @override
  String get soakRate => 'Rate';

  @override
  String get soakLength => 'Length';

  @override
  String soakStart(String rate, String duration) {
    return 'Soak $rate for $duration';
  }

  @override
  String soakProgress(String elapsed, String planned, String step) {
    return '$elapsed of $planned  ·  $step';
  }

  @override
  String get soakFaults => 'Faults';

  @override
  String get soakRingFill => 'Ring fill';

  @override
  String get soakMeasuredRate => 'Measured rate';

  @override
  String get soakUnderruns => 'Underruns';

  @override
  String get soakTransferErrors => 'Transfer errors';

  @override
  String get soakPacketErrors => 'Packet errors';

  @override
  String get soakRebuffers => 'Rebuffers';

  @override
  String get soakWorstRingFill => 'Worst ring fill';

  @override
  String get soakWorstDeviation => 'Worst deviation';

  @override
  String get soakDriftSpread => 'Drift spread';

  @override
  String get soakMeetsBar => 'Clears the ten-minute zero-dropout bar.';

  @override
  String get soakShortOfBar =>
      'Short of the ten-minute bar, so it says nothing yet about the faults that only appear once the hardware is warm.';

  @override
  String get playFileTitle => 'Play a file';

  @override
  String get playFileIntro =>
      'Plays one of your own files through the DAC and watches the stream, which is the question the tone tests cannot ask: whether the material you actually own plays cleanly. Only the rates that material contains get tested.';

  @override
  String get playFileChoose => 'Choose a file';

  @override
  String get playFileFormats =>
      'FLAC, WAV, AIFF, MP3 and anything else the engine decodes.';

  @override
  String get playFileCache => 'Pushed to the app cache';

  @override
  String get playFileCacheDetail =>
      'The M2 harness. WAV only, and the fastest way to put a known file on a phone you are debugging over adb.';

  @override
  String get playFileStreamHealth => 'Stream health';
}
