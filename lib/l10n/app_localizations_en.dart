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
}
