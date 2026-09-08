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
}
