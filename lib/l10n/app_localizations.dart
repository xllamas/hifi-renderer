import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_de.dart';
import 'app_localizations_en.dart';
import 'app_localizations_es.dart';
import 'app_localizations_fr.dart';
import 'app_localizations_it.dart';
import 'app_localizations_ja.dart';
import 'app_localizations_ko.dart';
import 'app_localizations_pt.dart';
import 'app_localizations_zh.dart';

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
  static const List<Locale> supportedLocales = <Locale>[
    Locale('de'),
    Locale('en'),
    Locale('es'),
    Locale('fr'),
    Locale('it'),
    Locale('ja'),
    Locale('ko'),
    Locale('pt'),
    Locale('pt', 'BR'),
    Locale('zh'),
  ];

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

  /// Title bar of the settings screen.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// Section heading for the name this renderer shows under on the network.
  ///
  /// In en, this message translates to:
  /// **'Network name'**
  String get settingsNetworkName;

  /// Explains the network name field. A 'controller' is the separate app or device that tells the renderer what to play. DLNA is a standard's name and is not translated.
  ///
  /// In en, this message translates to:
  /// **'How this renderer appears in DLNA controllers.'**
  String get settingsNetworkNameHelp;

  /// Button that stores the network name. Must be short: it sits in a narrow button beside a text field.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get settingsSave;

  /// Replaces the Save button briefly after saving. Same width constraint as Save.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get settingsSaved;

  /// Confirmation after the renderer is renamed. The new name only reaches controllers when the renderer re-announces itself on the network, which happens at startup.
  ///
  /// In en, this message translates to:
  /// **'Renamed. Restart the app for controllers to see it.'**
  String get settingsRenamed;

  /// Section heading for choosing which USB DAC to play through.
  ///
  /// In en, this message translates to:
  /// **'Audio device'**
  String get settingsAudioDevice;

  /// Explains the DAC chooser when more than one USB audio device is plugged in — often a hub with several things on it.
  ///
  /// In en, this message translates to:
  /// **'{count} USB audio devices are attached. Choose which one to play through; the choice is remembered across reboots.'**
  String settingsDacsMultiple(int count);

  /// Explains the DAC list when exactly one device is attached. Android requires the user to grant access to a USB device before an app may open it, and tapping the entry is what asks.
  ///
  /// In en, this message translates to:
  /// **'One USB audio device is attached. Tap it to play through it, and to grant access if it has not been granted yet.'**
  String get settingsDacsSingle;

  /// Fallback label for an attached device that did not report a name of its own.
  ///
  /// In en, this message translates to:
  /// **'USB audio device'**
  String get settingsUsbAudioDevice;

  /// Appended after a device's vendor and product id when Android has not yet granted this app access to it. Keep the leading space and dash: it continues a line like '1234:5678'.
  ///
  /// In en, this message translates to:
  /// **' — permission not granted'**
  String get settingsPermissionNotGranted;

  /// Shown while the app is interrogating a newly attached DAC.
  ///
  /// In en, this message translates to:
  /// **'Reading the device…'**
  String get settingsReadingDevice;

  /// Subtitle shown while the app reads a DAC's capabilities — which sample rates and bit depths it can accept.
  ///
  /// In en, this message translates to:
  /// **'Asking the DAC what it supports'**
  String get settingsProbing;

  /// Subtitle naming the USB Audio Class version a DAC implements (1 or 2), inviting a tap to see the full capability list. 'USB Audio Class' is the name of the specification and is normally left in English.
  ///
  /// In en, this message translates to:
  /// **'USB Audio Class {version} — tap for what it supports'**
  String settingsUacTap(String version);

  /// Subtitle shown when no DAC is attached, inviting the user to plug one in.
  ///
  /// In en, this message translates to:
  /// **'Connect a USB DAC and tap to probe'**
  String get settingsConnectToProbe;

  /// Label for a switch that makes the renderer advertise only uncompressed audio, so the media server converts everything before sending it. PCM and LPCM are format names and are not translated.
  ///
  /// In en, this message translates to:
  /// **'Accept only PCM streams and let the server do the decoding/transcoding'**
  String get settingsPcmOnly;

  /// Explains the consequence of the PCM-only switch being on. The trade is deliberate and the wording should keep its edge: it buys compatibility at the cost of the thing the app exists for.
  ///
  /// In en, this message translates to:
  /// **'The renderer advertises nothing but LPCM, at the rates this DAC can clock, so the server converts everything to fit. Everything plays and nothing is bit-perfect -- including tracks the DAC could have played untouched.'**
  String get settingsPcmOnlyOn;

  /// Explains the consequence of the PCM-only switch being off, which is the default and the bit-perfect behaviour.
  ///
  /// In en, this message translates to:
  /// **'The renderer advertises every format it can decode, so files arrive untouched. Tracks at rates this DAC cannot clock are refused, and the reason is shown.'**
  String get settingsPcmOnlyOff;

  /// Label for the screen blanking timeout chooser.
  ///
  /// In en, this message translates to:
  /// **'Turn the screen off after'**
  String get settingsScreenOffAfter;

  /// Warning shown when the screen timeout is set to Never. The last phrase means the image burns permanently into an OLED panel; keep the warning concrete rather than generic.
  ///
  /// In en, this message translates to:
  /// **'The screen stays on. Fine on a permanently powered phone, but an OLED panel showing the same screen for months is how it acquires a permanent one.'**
  String get settingsScreenOffNever;

  /// Explains that the screen timeout is measured from the end of playback rather than from the last touch.
  ///
  /// In en, this message translates to:
  /// **'Counted from when the music stops -- a long track never blanks the screen mid-play. Playback turns it back on.'**
  String get settingsScreenOffTimed;

  /// Screen timeout option meaning the display never blanks.
  ///
  /// In en, this message translates to:
  /// **'Never'**
  String get settingsTimeoutNever;

  /// A screen timeout in whole minutes.
  ///
  /// In en, this message translates to:
  /// **'{minutes, plural, =1{1 minute} other{{minutes} minutes}}'**
  String settingsTimeoutMinutes(int minutes);

  /// Opens a screen that plays test tones at every sample rate a DAC claims, to find out which it really handles.
  ///
  /// In en, this message translates to:
  /// **'DAC verification'**
  String get settingsDacVerification;

  /// Subtitle for DAC verification. 'Rate' here means sample rate, such as 44100 or 96000 Hz.
  ///
  /// In en, this message translates to:
  /// **'Test every rate this DAC claims'**
  String get settingsDacVerificationSubtitle;

  /// Section heading for the permissions that let the renderer keep running unattended.
  ///
  /// In en, this message translates to:
  /// **'Always on'**
  String get settingsAlwaysOn;

  /// Explains why the permissions below are needed at all.
  ///
  /// In en, this message translates to:
  /// **'A dedicated renderer has to keep running with the screen off and come back after a reboot. Android and most phone makers block that by default.'**
  String get settingsAlwaysOnHelp;

  /// Warning headline counting how many times the renderer was killed by the system rather than stopped normally.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{This phone has stopped the renderer once} other{This phone has stopped the renderer {count} times}}'**
  String settingsDeaths(int count);

  /// Explains how the app counts times it was killed: it notices at startup that the previous run never shut down tidily.
  ///
  /// In en, this message translates to:
  /// **'Each one is a start that followed a run which never recorded a clean stop, so something killed it in the background. Granting what is below usually fixes it.'**
  String get settingsDeathsDetail;

  /// Name of the Android permission that stops the system suspending a background app. Use the wording the target language's Android settings actually use, if it differs.
  ///
  /// In en, this message translates to:
  /// **'Battery optimisation exemption'**
  String get settingsBattery;

  /// Shown when the battery optimisation exemption has been granted.
  ///
  /// In en, this message translates to:
  /// **'Granted — Android will not suspend the renderer.'**
  String get settingsBatteryGranted;

  /// Shown when the battery optimisation exemption has not been granted.
  ///
  /// In en, this message translates to:
  /// **'Not granted. Android may suspend the renderer when idle.'**
  String get settingsBatteryNotGranted;

  /// Button that opens the Android screen where a permission can be granted. Short: it is a compact action button.
  ///
  /// In en, this message translates to:
  /// **'Grant'**
  String get settingsGrant;

  /// Button that opens a phone-maker settings screen. Short: a compact action button.
  ///
  /// In en, this message translates to:
  /// **'Open settings'**
  String get settingsOpenSettings;

  /// Shown when a phone-maker settings screen the app tried to open does not exist on this device.
  ///
  /// In en, this message translates to:
  /// **'Could not open that screen on this phone.'**
  String get settingsCouldNotOpen;

  /// Names the phone maker's own autostart permission, which is separate from Android's. The vendor is the manufacturer name, such as Xiaomi or Samsung.
  ///
  /// In en, this message translates to:
  /// **'Autostart ({vendor})'**
  String settingsAutostart(String vendor);

  /// Used in place of the manufacturer name when the phone did not report one, giving 'Autostart (vendor)'. Lower case, since it stands in for a brand name mid-sentence.
  ///
  /// In en, this message translates to:
  /// **'vendor'**
  String get settingsAutostartVendorFallback;

  /// Explains why the app asks about a vendor autostart setting it cannot check for itself.
  ///
  /// In en, this message translates to:
  /// **'Phones from this maker usually add background-app restrictions of their own, separate from Android\'s, and they are the usual reason a renderer does not start after a reboot. The app cannot detect them, only that this maker has such a screen.'**
  String get settingsAutostartDetail;

  /// Name of a permission that lets the renderer light the panel when playback begins.
  ///
  /// In en, this message translates to:
  /// **'Wake the screen when music starts'**
  String get settingsWakeScreen;

  /// Explains why waking the screen needs a vendor permission. The quoted phrase is the name of a setting on the phone; translate it to whatever that setting is actually called in the target language's Android, since the user has to find it.
  ///
  /// In en, this message translates to:
  /// **'Music has played here while the screen stayed dark. Android switches off a screen hold from an app with no window on display, and this phone refused to let the renderer bring its own window up, so the panel lit for a moment and went back to sleep. The permission is usually called something like \"Display pop-up windows while running in the background\", and it is separate from autostart.'**
  String get settingsWakeScreenDetail;

  /// Opens the first-run setup walkthrough again.
  ///
  /// In en, this message translates to:
  /// **'Run setup again'**
  String get settingsRunSetup;

  /// Subtitle for re-running setup.
  ///
  /// In en, this message translates to:
  /// **'Walk through the permissions in order'**
  String get settingsRunSetupSubtitle;

  /// Section heading on the settings screen, above the open-source licenses row.
  ///
  /// In en, this message translates to:
  /// **'Legal'**
  String get settingsLegal;

  /// Row that opens the license page listing this app's license and every component it is built on.
  ///
  /// In en, this message translates to:
  /// **'Open source licenses'**
  String get settingsLicenses;

  /// Subtitle under the open-source licenses row. Deliberately plain: it describes what the page shows, not a legal obligation.
  ///
  /// In en, this message translates to:
  /// **'What this app is built on'**
  String get settingsLicensesSubtitle;

  /// Shown at the foot of the license page, under the app name. Names this app's own license first, then the families of license its components use.
  ///
  /// In en, this message translates to:
  /// **'Apache License 2.0. Built on work released under the LGPL, Apache, CDDL, BSD, CC0 and public-domain terms listed here.'**
  String get settingsLicensesLegalese;

  /// Section heading for choosing the interface language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguage;

  /// The default language option: follow whatever language the phone is set to. Chosen so a guest picking the renderer up finds their own language without configuring anything.
  ///
  /// In en, this message translates to:
  /// **'Same as this phone'**
  String get settingsLanguageSystem;

  /// Explains the language setting and why an override exists.
  ///
  /// In en, this message translates to:
  /// **'The renderer follows this phone unless you choose otherwise. A box set up on a spare phone often inherits a language nobody wanted.'**
  String get settingsLanguageHelp;

  /// Title of the first-run setup walkthrough. 'HiFi Renderer' is the app's name and is not translated.
  ///
  /// In en, this message translates to:
  /// **'Set up HiFi Renderer'**
  String get onboardingTitle;

  /// Title when the walkthrough is opened again later from Settings, rather than on first run.
  ///
  /// In en, this message translates to:
  /// **'Setup'**
  String get onboardingTitleRerun;

  /// Opening paragraph of setup. A 'renderer' is a device that receives music over the network and plays it; here the phone becomes one and is expected to stay running unattended.
  ///
  /// In en, this message translates to:
  /// **'This phone is going to sit somewhere and be a renderer. Android and most phone makers assume no app wants to do that, so a few things have to be turned on by hand.'**
  String get onboardingIntro;

  /// Reassurance under the setup introduction, so nobody feels blocked by the permission list.
  ///
  /// In en, this message translates to:
  /// **'None of it is required to try the app, and you can change any of it later in Settings.'**
  String get onboardingOptional;

  /// Step title for the Android notification permission.
  ///
  /// In en, this message translates to:
  /// **'Show a notification'**
  String get onboardingNotifications;

  /// Shown once the notification permission has been given.
  ///
  /// In en, this message translates to:
  /// **'Granted. The renderer will show its notification while running.'**
  String get onboardingNotificationsGranted;

  /// Explains why the notification permission is needed: Android requires a visible notification for a long-running background service.
  ///
  /// In en, this message translates to:
  /// **'Android will not let the renderer keep running in the background without one, and it is the only visible sign the renderer is alive.'**
  String get onboardingNotificationsWhy;

  /// Button that asks Android for a permission. Short: a compact action button.
  ///
  /// In en, this message translates to:
  /// **'Allow'**
  String get onboardingAllow;

  /// Shown when the app cannot open the phone's notification settings because this phone has none to open.
  ///
  /// In en, this message translates to:
  /// **'This phone has no notification settings screen to open.'**
  String get onboardingNoNotificationScreen;

  /// Shown when Android will no longer show the permission prompt because it was refused before, so the user has to grant it in the settings screen that was just opened.
  ///
  /// In en, this message translates to:
  /// **'Android stopped asking — turn notifications on there.'**
  String get onboardingNotificationsInSettings;

  /// Step title for the battery optimisation exemption.
  ///
  /// In en, this message translates to:
  /// **'Stop Android suspending it'**
  String get onboardingBattery;

  /// Shown once the battery optimisation exemption has been given.
  ///
  /// In en, this message translates to:
  /// **'Granted. Android will not suspend the renderer when idle.'**
  String get onboardingBatteryGranted;

  /// Explains why the battery exemption matters: without it music stops partway through a track.
  ///
  /// In en, this message translates to:
  /// **'Without this, Android suspends the app when the screen has been off for a while, and playback stops mid-track.'**
  String get onboardingBatteryWhy;

  /// Step title for the optional microphone permission, whose only purpose is to stop Android's USB prompt appearing every time the DAC is switched on.
  ///
  /// In en, this message translates to:
  /// **'Stop Android asking about the DAC'**
  String get onboardingUsbPrompt;

  /// Shown once the microphone permission has been given. The quoted phrase refers to the checkbox in Android's own USB dialog, so use the wording Android uses in the target language.
  ///
  /// In en, this message translates to:
  /// **'Granted. The next time the DAC connects, tick \"always open\" in Android\'s prompt and it will not ask again.'**
  String get onboardingUsbPromptGranted;

  /// Explains why an audio player asks for the microphone: without it Android hides the 'always open' checkbox for DACs that describe an audio input. Must make clear the app never records. The quoted phrase refers to Android's own checkbox.
  ///
  /// In en, this message translates to:
  /// **'Without microphone permission, Android asks whether to open the app every time the DAC is switched on, and leaves out the option to stop asking. Allow it, then tick \"always open\" the next time the DAC connects. The app never records anything.'**
  String get onboardingUsbPromptWhy;

  /// Shown when Android will no longer show the microphone permission prompt, so the user must grant it in the app details screen that was just opened.
  ///
  /// In en, this message translates to:
  /// **'Android stopped asking — allow the microphone under Permissions there.'**
  String get onboardingUsbPromptInSettings;

  /// Step title naming the phone maker's own autostart setting.
  ///
  /// In en, this message translates to:
  /// **'Autostart ({vendor})'**
  String onboardingVendorKnown(String vendor);

  /// Step title for the phone maker's autostart setting when the phone did not report a manufacturer name.
  ///
  /// In en, this message translates to:
  /// **'Autostart'**
  String get onboardingVendorKnownNoName;

  /// Step title when the app has no known settings screen for this phone maker.
  ///
  /// In en, this message translates to:
  /// **'Your phone maker\'s own restrictions'**
  String get onboardingVendorUnknown;

  /// Explains the vendor autostart step and why it never shows as complete: the app can open the screen but cannot read what was granted there.
  ///
  /// In en, this message translates to:
  /// **'Phones from this maker usually add background-app restrictions of their own, separate from Android\'s, and they are the usual reason a renderer does not come back after a reboot. The app cannot detect them — it only knows this maker has such a screen — and it cannot tell whether you granted anything there, so this step never ticks.'**
  String get onboardingVendorKnownDetail;

  /// Advice when the app cannot open a vendor settings screen. The three quoted phrases are names of settings the user must hunt for, so translate them to whatever those settings are actually called on phones in the target language.
  ///
  /// In en, this message translates to:
  /// **'We have no known settings screen for this phone. If the renderer stops when idle or does not return after a reboot, look for \"autostart\", \"background apps\" or \"protected apps\" in your phone\'s own battery settings.'**
  String get onboardingVendorUnknownDetail;

  /// Step title for connecting the USB digital-to-analogue converter.
  ///
  /// In en, this message translates to:
  /// **'Your DAC'**
  String get onboardingDac;

  /// Explains that the DAC needs no setup: Android asks once on attach, its prompt can be told not to ask again, and the renderer adapts to whichever DAC is plugged in. The quoted phrase refers to the checkbox in Android's own USB dialog, so use the wording Android uses in the target language.
  ///
  /// In en, this message translates to:
  /// **'Plug the USB DAC in when you are ready. Android asks for permission when it is attached — tick \"always open\" in that prompt and it stops asking — and the renderer follows whatever DAC is connected rather than being configured for one.'**
  String get onboardingDacDetail;

  /// Button that closes setup when everything checkable has been granted.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get onboardingDone;

  /// Button that closes setup while some permissions are still ungranted. Should sound permitted rather than discouraging: skipping is a legitimate choice.
  ///
  /// In en, this message translates to:
  /// **'Finish anyway'**
  String get onboardingFinishAnyway;

  /// Shown at the end of setup when every permission the app is able to verify has been given. 'Can check' is deliberate — vendor settings cannot be verified.
  ///
  /// In en, this message translates to:
  /// **'Everything the app can check is granted.'**
  String get onboardingAllGranted;

  /// Shown at the end of setup when permissions are outstanding. Deliberately not a warning: the app works, it simply may be killed in the background.
  ///
  /// In en, this message translates to:
  /// **'Skipping is fine. The renderer will run; it may just not survive being left alone, and Settings will tell you if something is stopping it.'**
  String get onboardingSkippingIsFine;

  /// Numbers a setup step, as in '2. Show a notification'. Adjust the punctuation if a different form is conventional in the target language.
  ///
  /// In en, this message translates to:
  /// **'{number}. {title}'**
  String onboardingStep(int number, String title);

  /// Title of the screen listing what a connected DAC can do.
  ///
  /// In en, this message translates to:
  /// **'DAC capabilities'**
  String get dacCapsTitle;

  /// Tooltip on the refresh button that re-reads the DAC's capabilities.
  ///
  /// In en, this message translates to:
  /// **'Re-probe'**
  String get dacCapsReprobe;

  /// Shown when no DAC has been interrogated yet.
  ///
  /// In en, this message translates to:
  /// **'Not probed yet'**
  String get dacCapsNotProbed;

  /// Tells the user how to get capabilities: plug a DAC in and press the refresh button in the title bar.
  ///
  /// In en, this message translates to:
  /// **'Connect a USB DAC and tap refresh.'**
  String get dacCapsNotProbedDetail;

  /// Used when the probe failed but reported no reason.
  ///
  /// In en, this message translates to:
  /// **'Unknown error.'**
  String get dacCapsUnknownError;

  /// Probe failure: nothing is plugged in.
  ///
  /// In en, this message translates to:
  /// **'No DAC found'**
  String get dacCapsNoDevice;

  /// Probe failure: Android has not granted this app access to the USB device.
  ///
  /// In en, this message translates to:
  /// **'Permission needed'**
  String get dacCapsPermissionNeeded;

  /// Probe failure: the device is present and permitted but would not open.
  ///
  /// In en, this message translates to:
  /// **'Could not open the DAC'**
  String get dacCapsOpenFailed;

  /// Probe failure with no more specific cause.
  ///
  /// In en, this message translates to:
  /// **'Probe failed'**
  String get dacCapsProbeFailed;

  /// Warning banner shown for a device that cannot take audio unaltered — for example one that only records, or offers no usable output. Keep it blunt.
  ///
  /// In en, this message translates to:
  /// **'Not usable for bit-perfect playback'**
  String get dacCapsNotUsable;

  /// Heading above a list of caveats about this particular DAC.
  ///
  /// In en, this message translates to:
  /// **'Things worth knowing'**
  String get dacCapsWorthKnowing;

  /// Heading above the capability table.
  ///
  /// In en, this message translates to:
  /// **'What it supports'**
  String get dacCapsWhatItSupports;

  /// One-line identity of the device: which version of the USB Audio Class specification it implements, its USB speed (full, high), and its vendor and product identifiers in hex. These are technical terms; keep them recognisable.
  ///
  /// In en, this message translates to:
  /// **'USB Audio Class {version} · {speed}-speed · {vendor}:{product}'**
  String dacCapsIdentity(
    String version,
    String speed,
    String vendor,
    String product,
  );

  /// Table row label: the sample rates the DAC accepts, such as 44.1 or 96 kHz.
  ///
  /// In en, this message translates to:
  /// **'Sample rates'**
  String get dacCapsSampleRates;

  /// Table row label: the bit depths the DAC accepts, such as 16 or 24 bit.
  ///
  /// In en, this message translates to:
  /// **'Bit depths'**
  String get dacCapsBitDepths;

  /// Table row label: how many audio channels the DAC takes, normally two.
  ///
  /// In en, this message translates to:
  /// **'Channels'**
  String get dacCapsChannels;

  /// Table row label: the sample rate the DAC is clocking right now.
  ///
  /// In en, this message translates to:
  /// **'Currently running at'**
  String get dacCapsCurrentlyAt;

  /// Table row label for which side provides the audio clock.
  ///
  /// In en, this message translates to:
  /// **'USB timing'**
  String get dacCapsUsbTiming;

  /// Table row label for whether volume can be set over USB.
  ///
  /// In en, this message translates to:
  /// **'Volume control'**
  String get dacCapsVolumeControl;

  /// Table row label for Direct Stream Digital, a one-bit audio format. An abbreviation, normally left as DSD.
  ///
  /// In en, this message translates to:
  /// **'DSD'**
  String get dacCapsDsd;

  /// Table value when the DAC did not report something.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get dacCapsUnknown;

  /// Summarises a long list of sample rates as a range plus a count, used when listing them all would not fit.
  ///
  /// In en, this message translates to:
  /// **'{low} – {high} ({count} rates)'**
  String dacCapsRateRange(String low, String high, int count);

  /// A single bit depth, as in '24-bit'. Several are joined with commas.
  ///
  /// In en, this message translates to:
  /// **'{bits}-bit'**
  String dacCapsBitDepth(int bits);

  /// USB timing value: the DAC provides the clock and the phone follows it. This is the better arrangement for audio quality, which the parenthesis is there to convey.
  ///
  /// In en, this message translates to:
  /// **'Asynchronous (DAC clock)'**
  String get dacCapsAsync;

  /// USB timing value: the DAC follows the phone's clock rather than its own.
  ///
  /// In en, this message translates to:
  /// **'Synchronous'**
  String get dacCapsSync;

  /// Volume control value: the app can set the DAC's volume.
  ///
  /// In en, this message translates to:
  /// **'Supported over USB'**
  String get dacCapsVolumeOverUsb;

  /// Volume control value: volume can only be changed with the DAC's own knob — common on integrated amplifiers.
  ///
  /// In en, this message translates to:
  /// **'On the device only'**
  String get dacCapsVolumeDeviceOnly;

  /// DSD row value: the hardware can accept DSD, which is not the same as this app sending it.
  ///
  /// In en, this message translates to:
  /// **'Supported by the hardware'**
  String get dacCapsDsdSupported;

  /// Expandable section holding raw USB descriptor information.
  ///
  /// In en, this message translates to:
  /// **'Technical details'**
  String get dacCapsTechnical;

  /// Subtitle explaining that the technical section exists to be copied into a bug report. Its contents stay in English deliberately, being diagnostic output.
  ///
  /// In en, this message translates to:
  /// **'For support reports'**
  String get dacCapsTechnicalSubtitle;

  /// A sample rate in kilohertz, as in '96 kHz'. kHz is a unit symbol and is not translated, but the space before it follows local typographic convention.
  ///
  /// In en, this message translates to:
  /// **'{value} kHz'**
  String dacCapsKhz(String value);

  /// Capability note for a USB device that identifies as audio hardware but has no playback output at all.
  ///
  /// In en, this message translates to:
  /// **'This device cannot play audio'**
  String get noteCannotPlayTitle;

  /// Explains a device with no playback output: it is a recording device. 'Isochronous endpoint' is the USB term for the channel audio streams over; keep it recognisable to anyone who knows USB.
  ///
  /// In en, this message translates to:
  /// **'It advertises the USB audio class but offers no PCM output over an isochronous endpoint. Capture-only devices look like this — a USB microphone, or the recording half of a headset adapter.'**
  String get noteCannotPlayDetail;

  /// Capability note naming the older of the two USB audio specifications.
  ///
  /// In en, this message translates to:
  /// **'This device uses USB Audio Class 1.0'**
  String get noteUac1Title;

  /// Explains what USB Audio Class 1.0 costs and, importantly, what it does not: the ceiling is lower but the audio is still unaltered. 'Full-speed' is a USB speed grade, confusingly slower than 'high-speed'; keep the term.
  ///
  /// In en, this message translates to:
  /// **'Supported, with the limits the class itself imposes: full-speed USB caps the bandwidth, so UAC1 devices top out well below what a UAC2 DAC offers. Playback is still bit-perfect at the rates it does support — nothing is resampled.'**
  String get noteUac1Detail;

  /// Capability note for a DAC whose USB endpoint is adaptive rather than asynchronous, meaning the phone provides the timing reference.
  ///
  /// In en, this message translates to:
  /// **'This device follows the phone\'s clock'**
  String get noteAdaptiveTitle;

  /// Explains adaptive versus asynchronous USB timing, and reassures that the audio data itself is unchanged either way.
  ///
  /// In en, this message translates to:
  /// **'Its endpoint is adaptive rather than asynchronous, so it adapts to the rate the phone sends instead of running its own clock and asking the phone to follow. Common on UAC1 hardware. Samples still arrive unaltered; the timing reference is simply the phone\'s.'**
  String get noteAdaptiveDetail;

  /// Capability note for a DAC that exposes no volume control over USB.
  ///
  /// In en, this message translates to:
  /// **'Volume is controlled by the DAC, not this app'**
  String get noteVolumeDeviceTitle;

  /// For a DAC that tells the phone when its own knob moves but will not accept volume commands back. The asymmetry is the point.
  ///
  /// In en, this message translates to:
  /// **'This device exposes no USB volume control. It does report its own knob or remote to the phone, but that is one-way: nothing sent from here can change its volume. Use the physical control.'**
  String get noteVolumeOneWayDetail;

  /// For a DAC with no USB volume control of any kind. Common on integrated amplifiers with a physical knob.
  ///
  /// In en, this message translates to:
  /// **'This device exposes no USB volume control, so volume commands from a DLNA controller cannot reach it. Use the physical control.'**
  String get noteVolumeNoneDetail;

  /// Capability note for a DAC whose volume can be driven over USB.
  ///
  /// In en, this message translates to:
  /// **'Volume can be set from this app'**
  String get noteVolumeAppTitle;

  /// Explains that volume commands reach the hardware directly. The placeholder is a short technical description of the control, and stays in English.
  ///
  /// In en, this message translates to:
  /// **'The DAC exposes a USB volume control ({detail}), so DLNA volume commands are passed straight to the hardware.'**
  String noteVolumeAppDetail(String detail);

  /// Capability note for a DAC with no 16-bit mode, so CD-resolution audio is carried in a wider container.
  ///
  /// In en, this message translates to:
  /// **'16-bit tracks are padded to {bits}-bit'**
  String notePaddedTitle(int bits);

  /// Explains that padding a 16-bit sample into a wider container does not alter it — the reassurance is the point of the note.
  ///
  /// In en, this message translates to:
  /// **'This DAC offers no 16-bit mode, so CD-resolution files are placed in a {bits}-bit container. The sample values are unchanged, so playback is still bit-perfect.'**
  String notePaddedDetail(int bits);

  /// Capability note for the preferred timing arrangement, where the DAC drives the clock.
  ///
  /// In en, this message translates to:
  /// **'Asynchronous USB with its own clock'**
  String get noteAsyncGoodTitle;

  /// Explains why asynchronous USB is preferable: the DAC's own clock is steadier than one recovered from the phone.
  ///
  /// In en, this message translates to:
  /// **'The DAC drives timing rather than following the phone, which is the better arrangement for audio quality.'**
  String get noteAsyncGoodDetail;

  /// Capability note for a DAC that claims asynchronous timing but offers no channel to report its clock rate back.
  ///
  /// In en, this message translates to:
  /// **'Asynchronous, but no feedback endpoint found'**
  String get noteAsyncNoFeedbackTitle;

  /// Explains the practical consequence of a missing feedback endpoint: audio may break up over long sessions.
  ///
  /// In en, this message translates to:
  /// **'Timing cannot be tracked precisely, so occasional dropouts are possible on long playback.'**
  String get noteAsyncNoFeedbackDetail;

  /// Capability note for a DAC that accepts Direct Stream Digital.
  ///
  /// In en, this message translates to:
  /// **'DSD capable'**
  String get noteDsdTitle;

  /// States plainly that the hardware supports DSD but the app does not send it, so nobody expects it to work.
  ///
  /// In en, this message translates to:
  /// **'This DAC accepts native DSD. The app does not play DSD yet.'**
  String get noteDsdDetail;

  /// Capability note for a device offering more than one USB configuration.
  ///
  /// In en, this message translates to:
  /// **'Alternative USB mode available'**
  String get noteAltConfigTitle;

  /// Explains that a second USB configuration exists but is unused — often a legacy or compatibility mode.
  ///
  /// In en, this message translates to:
  /// **'The device offers {count} USB configurations. Only the active one is used; some DACs keep a compatibility mode in the other.'**
  String noteAltConfigDetail(int count);

  /// Capability note shown when interrogating the DAC's clock failed. The detail beneath it is the raw error and stays in English.
  ///
  /// In en, this message translates to:
  /// **'Could not read the supported sample rates'**
  String get noteClockErrorTitle;

  /// Confirmation after a diagnostic report is copied to the clipboard. The report itself stays in English, being diagnostic output.
  ///
  /// In en, this message translates to:
  /// **'Report copied'**
  String get reportCopied;

  /// Button that copies a diagnostic report to the clipboard. Short: a compact action button.
  ///
  /// In en, this message translates to:
  /// **'Copy report'**
  String get copyReport;

  /// Button that halts a running test. Short: a compact action button.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get stop;

  /// Value shown where a measurement was expected but the hardware gave none. Lower case: it stands in for a number in a results table.
  ///
  /// In en, this message translates to:
  /// **'not reported'**
  String get notReported;

  /// Title of the screen that plays a test tone at every sample rate a DAC claims, to find which it truly handles.
  ///
  /// In en, this message translates to:
  /// **'DAC verification'**
  String get verifyTitle;

  /// Heading above the per-rate verification results.
  ///
  /// In en, this message translates to:
  /// **'Results'**
  String get verifyResults;

  /// Button that keeps the results list scrolled to the test currently running. Short: a compact button.
  ///
  /// In en, this message translates to:
  /// **'Follow'**
  String get verifyFollow;

  /// Title of the screen that plays for a long stretch at one sample rate to find faults that only appear once the hardware is warm.
  ///
  /// In en, this message translates to:
  /// **'Stability soak'**
  String get soakTitle;

  /// Heading above the sample rate chooser. Short: it labels a row of chips.
  ///
  /// In en, this message translates to:
  /// **'Rate'**
  String get soakRate;

  /// Heading above the soak duration chooser. Short: it labels a row of chips.
  ///
  /// In en, this message translates to:
  /// **'Length'**
  String get soakLength;

  /// Button that begins the soak, naming the chosen sample rate and how long it will run.
  ///
  /// In en, this message translates to:
  /// **'Soak {rate} for {duration}'**
  String soakStart(String rate, String duration);

  /// Progress line during a soak: time so far, total planned, and what the test is doing. The step is a short status word from the engine and is not translated.
  ///
  /// In en, this message translates to:
  /// **'{elapsed} of {planned}  ·  {step}'**
  String soakProgress(String elapsed, String planned, String step);

  /// Results label: how many audible faults occurred. Any number above zero is a failure.
  ///
  /// In en, this message translates to:
  /// **'Faults'**
  String get soakFaults;

  /// Results label: how full the audio buffer stayed, as a percentage. A ring buffer feeds the DAC; if it empties, audio breaks up.
  ///
  /// In en, this message translates to:
  /// **'Ring fill'**
  String get soakRingFill;

  /// Results label: the sample rate the DAC's own clock actually ran at, as opposed to the rate it was asked for.
  ///
  /// In en, this message translates to:
  /// **'Measured rate'**
  String get soakMeasuredRate;

  /// Results label: times the buffer ran dry and the DAC had nothing to play. The standard audio term.
  ///
  /// In en, this message translates to:
  /// **'Underruns'**
  String get soakUnderruns;

  /// Results label: failed USB transfers.
  ///
  /// In en, this message translates to:
  /// **'Transfer errors'**
  String get soakTransferErrors;

  /// Results label: individual USB packets that failed within otherwise successful transfers.
  ///
  /// In en, this message translates to:
  /// **'Packet errors'**
  String get soakPacketErrors;

  /// Results label: times playback had to pause and refill the buffer.
  ///
  /// In en, this message translates to:
  /// **'Rebuffers'**
  String get soakRebuffers;

  /// Results label: the lowest the buffer ever got, as a percentage. The closer to zero, the closer it came to breaking up.
  ///
  /// In en, this message translates to:
  /// **'Worst ring fill'**
  String get soakWorstRingFill;

  /// Results label: the furthest the DAC's measured clock strayed from its nominal rate.
  ///
  /// In en, this message translates to:
  /// **'Worst deviation'**
  String get soakWorstDeviation;

  /// Results label: the range between the fastest and slowest measured clock readings across the soak.
  ///
  /// In en, this message translates to:
  /// **'Drift spread'**
  String get soakDriftSpread;

  /// Verdict when a soak ran at least ten minutes with no faults at all. Ten minutes with zero dropouts is the standard this app holds a DAC to.
  ///
  /// In en, this message translates to:
  /// **'Clears the ten-minute zero-dropout bar.'**
  String get soakMeetsBar;

  /// Verdict when a soak was clean but too short to count. The point is that a brief clean run proves nothing: some faults only appear after the hardware warms up.
  ///
  /// In en, this message translates to:
  /// **'Short of the ten-minute bar, so it says nothing yet about the faults that only appear once the hardware is warm.'**
  String get soakShortOfBar;

  /// Title of the screen that plays one of the user's own files through the DAC and watches the stream for faults.
  ///
  /// In en, this message translates to:
  /// **'Play a file'**
  String get playFileTitle;

  /// Explains what this test adds over the synthetic tone tests: real music, at whatever rates the user's own library happens to use.
  ///
  /// In en, this message translates to:
  /// **'Plays one of your own files through the DAC and watches the stream, which is the question the tone tests cannot ask: whether the material you actually own plays cleanly. Only the rates that material contains get tested.'**
  String get playFileIntro;

  /// Button that opens the file picker.
  ///
  /// In en, this message translates to:
  /// **'Choose a file'**
  String get playFileChoose;

  /// Lists accepted formats. The format names are not translated.
  ///
  /// In en, this message translates to:
  /// **'FLAC, WAV, AIFF, MP3 and anything else the engine decodes.'**
  String get playFileFormats;

  /// Heading above files copied onto the phone by a developer over a debugging cable, rather than chosen by the user.
  ///
  /// In en, this message translates to:
  /// **'Pushed to the app cache'**
  String get playFileCache;

  /// Explains the developer-pushed file list. 'M2 harness' is this project's own test rig and 'adb' is the Android debugging tool; neither is translated.
  ///
  /// In en, this message translates to:
  /// **'The M2 harness. WAV only, and the fastest way to put a known file on a phone you are debugging over adb.'**
  String get playFileCacheDetail;

  /// Heading above live statistics for the playing stream.
  ///
  /// In en, this message translates to:
  /// **'Stream health'**
  String get playFileStreamHealth;

  /// Failure headline: the machine holding the music stopped answering. Blames the network rather than the file, which matters — the decoder cannot tell a vanished server from a corrupt file, and saying the wrong one sends people hunting through their library.
  ///
  /// In en, this message translates to:
  /// **'The renderer lost contact with the media server.'**
  String get errServerUnreachable;

  /// Failure headline: the server answered, but with an error rather than the audio.
  ///
  /// In en, this message translates to:
  /// **'The media server refused this track.'**
  String get errServerRefused;

  /// Failure headline: the transfer started and did not finish.
  ///
  /// In en, this message translates to:
  /// **'This track could not be downloaded from the server.'**
  String get errDownloadFailed;

  /// Failure headline: the file arrived intact but is in a format the app has no decoder for.
  ///
  /// In en, this message translates to:
  /// **'This track is in a format the renderer cannot decode.'**
  String get errUndecodableFormat;

  /// Failure headline: nothing is broken — the file and the DAC simply do not meet. The wording deliberately blames neither.
  ///
  /// In en, this message translates to:
  /// **'This DAC cannot be set to this track\'s rate or bit depth.'**
  String get errDacRateUnsupported;

  /// Failure headline: the USB link to the converter failed — unplugged, or the hardware stopped responding.
  ///
  /// In en, this message translates to:
  /// **'The renderer lost its connection to the DAC.'**
  String get errDacConnectionLost;

  /// Failure headline used when nothing more specific could be determined.
  ///
  /// In en, this message translates to:
  /// **'This track could not be played.'**
  String get errTrackCouldNotBePlayed;

  /// Shown when a track is refused before being fetched because its sample rate is above anything the DAC can clock. Both values arrive already formatted, as in '192 kHz'.
  ///
  /// In en, this message translates to:
  /// **'This DAC cannot play {rate}; its highest rate is {ceiling}.'**
  String errRateUnplayable(String rate, String ceiling);

  /// Shown when a playlist gives up after several tracks failed consecutively. The count is the point: one bad file is bad luck, several in a row means the source is gone.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, other{Stopped after {count} tracks in a row could not be played.}}'**
  String errStoppedAfterFailures(int count);

  /// Shown when a track is refused before being fetched because its sample rate is within the DAC's range but not one of the rates it offers (for example 88.2 kHz on a DAC that lists 96 kHz). The value arrives already formatted, as in '88.2 kHz'.
  ///
  /// In en, this message translates to:
  /// **'This DAC does not support {rate}.'**
  String errRateNotOffered(String rate);

  /// Shown when a playlist reaches its end after stepping over tracks that could not be played. The reason for the last failure is shown on the line beneath it.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{One track was skipped because it could not be played.} other{{count} tracks were skipped because they could not be played.}}'**
  String errTracksSkipped(int count);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>[
    'de',
    'en',
    'es',
    'fr',
    'it',
    'ja',
    'ko',
    'pt',
    'zh',
  ].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when language+country codes are specified.
  switch (locale.languageCode) {
    case 'pt':
      {
        switch (locale.countryCode) {
          case 'BR':
            return AppLocalizationsPtBr();
        }
        break;
      }
  }

  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de':
      return AppLocalizationsDe();
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
    case 'fr':
      return AppLocalizationsFr();
    case 'it':
      return AppLocalizationsIt();
    case 'ja':
      return AppLocalizationsJa();
    case 'ko':
      return AppLocalizationsKo();
    case 'pt':
      return AppLocalizationsPt();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
