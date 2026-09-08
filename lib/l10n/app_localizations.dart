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

  /// Explains that the DAC needs no setup: the renderer adapts to whichever one is plugged in.
  ///
  /// In en, this message translates to:
  /// **'Plug the USB DAC in when you are ready. Android asks for permission the first time it is attached, so there is nothing to do here — and the renderer follows whatever DAC is connected rather than being configured for one.'**
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
