import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('en')];

  /// Tooltip on the gear button in the corner of the now-playing screen.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTooltip;

  /// Shown on the idle screen when a DAC is attached and the renderer is waiting to be sent a track by a DLNA/OpenHome controller. 'Controller' is the phone or app that tells the renderer what to play; the renderer never chooses for itself.
  ///
  /// In en, this message translates to:
  /// **'Ready — waiting for a controller'**
  String get idleReady;

  /// Shown on the idle screen when no USB digital-to-analogue converter is plugged in. DAC is a standard audio abbreviation and is usually left untranslated.
  ///
  /// In en, this message translates to:
  /// **'No DAC connected'**
  String get idleNoDac;

  /// Shown in place of a track title when the sender gave us none. Must stay short: it is displayed at large size where a title would be.
  ///
  /// In en, this message translates to:
  /// **'Unknown track'**
  String get unknownTrack;

  /// Shown in place of a track title while a guest streams over AirPlay and sent no track name. Names the device streaming to us, so the owner can see who has taken the output. 'AirPlay' is an Apple product name and is never translated.
  ///
  /// In en, this message translates to:
  /// **'AirPlay from {sender}'**
  String airPlayFromSender(String sender);

  /// Tooltip on the skip-backwards button.
  ///
  /// In en, this message translates to:
  /// **'Previous track'**
  String get previousTrack;

  /// Tooltip on the skip-forwards button.
  ///
  /// In en, this message translates to:
  /// **'Next track'**
  String get nextTrack;

  /// Tooltip on the transport button while audio is playing.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get pause;

  /// Tooltip on the transport button while audio is stopped or paused.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get play;

  /// Explains a volume slider whose position cannot be trusted to match the hardware: the DAC accepts a volume but always reports its maximum back, so the number shown is what the app last sent rather than what the device is actually set to. Small print under the slider.
  ///
  /// In en, this message translates to:
  /// **'This DAC does not report its volume back, so this shows the last value sent from here.'**
  String get volumeWriteOnly;

  /// Shown when no DAC is attached and audio is going out through the phone itself. 'Resampled' means the sample rate was converted, which is the thing this app exists to avoid, so the wording should not soften it.
  ///
  /// In en, this message translates to:
  /// **'Phone speaker or headphones — resampled by Android'**
  String get systemAudioDetail;

  /// Appears after the name of the DAC in use when more than one USB audio device is attached, to say that others were found. Always the first of several.
  ///
  /// In en, this message translates to:
  /// **'(1 of {count})'**
  String dacOneOf(int count);

  /// The green badge shown when the audio reaches the DAC completely unaltered — not resampled, not volume-adjusted, bit for bit the source. This is the central promise of the whole app, so it should use whatever term audio enthusiasts in the target language actually use; keep it lower case and short enough to sit beside a format badge.
  ///
  /// In en, this message translates to:
  /// **'bit-perfect'**
  String get bitPerfect;

  /// Amber badge shown when audio is going through the phone's own output rather than a USB DAC, and so is not bit-perfect. Short: it sits beside a format badge like 'FLAC 16/44.1'.
  ///
  /// In en, this message translates to:
  /// **'system audio'**
  String get systemAudioBadge;

  /// Amber badge shown while a guest streams over AirPlay. The audio reaches the DAC untouched by us, but the sending device already converted its sample rate and applied its own volume, so the app must not claim bit-perfect. 'AirPlay' is never translated; the middle dot is a separator. Short: it sits beside a format badge.
  ///
  /// In en, this message translates to:
  /// **'AirPlay · sender resampled'**
  String get airPlaySenderResampled;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
