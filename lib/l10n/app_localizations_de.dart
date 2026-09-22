// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get settingsTooltip => 'Einstellungen';

  @override
  String get idleReady => 'Bereit — wartet auf einen Controller';

  @override
  String get idleNoDac => 'Kein DAC angeschlossen';

  @override
  String get unknownTrack => 'Unbekannter Titel';

  @override
  String airPlayFromSender(String sender) {
    return 'AirPlay von $sender';
  }

  @override
  String get previousTrack => 'Vorheriger Titel';

  @override
  String get nextTrack => 'Nächster Titel';

  @override
  String get pause => 'Pause';

  @override
  String get play => 'Wiedergabe';

  @override
  String get volumeWriteOnly =>
      'Dieser DAC meldet seine Lautstärke nicht zurück, daher steht hier der zuletzt von der App gesendete Wert.';

  @override
  String get systemAudioDetail =>
      'Telefonlautsprecher oder Kopfhörer — von Android umgerechnet';

  @override
  String dacOneOf(int count) {
    return '(1 von $count)';
  }

  @override
  String get bitPerfect => 'bitgenau';

  @override
  String get systemAudioBadge => 'Systemaudio';

  @override
  String get airPlaySenderResampled => 'AirPlay · Quelle hat umgerechnet';

  @override
  String get settingsTitle => 'Einstellungen';

  @override
  String get settingsNetworkName => 'Name im Netzwerk';

  @override
  String get settingsNetworkNameHelp =>
      'Wie dieser Renderer in DLNA-Controllern erscheint.';

  @override
  String get settingsSave => 'Speichern';

  @override
  String get settingsSaved => 'Gespeichert';

  @override
  String get settingsRenamed =>
      'Umbenannt. Starte die App neu, damit Controller den Namen sehen.';

  @override
  String get settingsAudioDevice => 'Audiogerät';

  @override
  String settingsDacsMultiple(int count) {
    return 'Es sind $count USB-Audiogeräte angeschlossen. Wähle aus, über welches wiedergegeben wird; die Wahl bleibt über Neustarts erhalten.';
  }

  @override
  String get settingsDacsSingle =>
      'Ein USB-Audiogerät ist angeschlossen. Tippe darauf, um darüber wiederzugeben und ihm den Zugriff zu erteilen, falls das noch nicht geschehen ist.';

  @override
  String get settingsUsbAudioDevice => 'USB-Audiogerät';

  @override
  String get settingsPermissionNotGranted => ' — Zugriff nicht erteilt';

  @override
  String get settingsReadingDevice => 'Gerät wird ausgelesen…';

  @override
  String get settingsProbing => 'Der DAC wird gefragt, was er kann';

  @override
  String settingsUacTap(String version) {
    return 'USB Audio Class $version — tippen, um zu sehen, was er kann';
  }

  @override
  String get settingsConnectToProbe =>
      'Schließe einen USB-DAC an und tippe, um ihn auszulesen';

  @override
  String get settingsPcmOnly =>
      'Nur PCM-Streams annehmen und den Server dekodieren bzw. umwandeln lassen';

  @override
  String get settingsPcmOnlyOn =>
      'Der Renderer bietet ausschließlich LPCM an, in den Abtastraten, die dieser DAC takten kann, sodass der Server alles passend umwandelt. Alles spielt und nichts ist bitgenau — auch Titel nicht, die der DAC unangetastet hätte wiedergeben können.';

  @override
  String get settingsPcmOnlyOff =>
      'Der Renderer bietet jedes Format an, das er dekodieren kann, sodass Dateien unangetastet ankommen. Titel in Abtastraten, die dieser DAC nicht takten kann, werden abgelehnt, und der Grund wird angezeigt.';

  @override
  String get settingsScreenOffAfter => 'Bildschirm ausschalten nach';

  @override
  String get settingsScreenOffNever =>
      'Der Bildschirm bleibt an. Auf einem dauerhaft mit Strom versorgten Telefon unproblematisch, aber ein OLED-Panel, das monatelang dasselbe Bild zeigt, behält es irgendwann dauerhaft.';

  @override
  String get settingsScreenOffTimed =>
      'Gezählt ab dem Ende der Musik — ein langer Titel schaltet den Bildschirm nie mitten in der Wiedergabe aus. Die Wiedergabe schaltet ihn wieder ein.';

  @override
  String get settingsTimeoutNever => 'Nie';

  @override
  String settingsTimeoutMinutes(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: '$minutes Minuten',
      one: '1 Minute',
    );
    return '$_temp0';
  }

  @override
  String get settingsDacVerification => 'DAC-Überprüfung';

  @override
  String get settingsDacVerificationSubtitle =>
      'Jede Abtastrate testen, die dieser DAC angibt';

  @override
  String get settingsAlwaysOn => 'Dauerbetrieb';

  @override
  String get settingsAlwaysOnHelp =>
      'Ein fest installierter Renderer muss mit ausgeschaltetem Bildschirm weiterlaufen und nach einem Neustart zurückkommen. Android und die meisten Hersteller verhindern das standardmäßig.';

  @override
  String settingsDeaths(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Dieses Telefon hat den Renderer $count-mal beendet',
      one: 'Dieses Telefon hat den Renderer einmal beendet',
    );
    return '$_temp0';
  }

  @override
  String get settingsDeathsDetail =>
      'Jeder Fall ist ein Start nach einem Lauf, der nie ein sauberes Ende verzeichnet hat — irgendetwas hat ihn also im Hintergrund beendet. Die folgenden Berechtigungen zu erteilen behebt das meistens.';

  @override
  String get settingsBattery => 'Ausnahme von der Akku-Optimierung';

  @override
  String get settingsBatteryGranted =>
      'Erteilt — Android wird den Renderer nicht anhalten.';

  @override
  String get settingsBatteryNotGranted =>
      'Nicht erteilt. Android kann den Renderer im Leerlauf anhalten.';

  @override
  String get settingsGrant => 'Erteilen';

  @override
  String get settingsOpenSettings => 'Einstellungen öffnen';

  @override
  String get settingsCouldNotOpen =>
      'Dieser Bildschirm ließ sich auf diesem Telefon nicht öffnen.';

  @override
  String settingsAutostart(String vendor) {
    return 'Autostart ($vendor)';
  }

  @override
  String get settingsAutostartVendorFallback => 'Hersteller';

  @override
  String get settingsAutostartDetail =>
      'Telefone dieses Herstellers bringen meist eigene Einschränkungen für Hintergrund-Apps mit, getrennt von denen Androids, und sie sind der übliche Grund, warum ein Renderer nach einem Neustart nicht startet. Die App kann sie nicht erkennen, sie weiß nur, dass dieser Hersteller einen solchen Bildschirm hat.';

  @override
  String get settingsWakeScreen => 'Bildschirm einschalten, wenn Musik beginnt';

  @override
  String get settingsWakeScreenDetail =>
      'Hier lief Musik, während der Bildschirm dunkel blieb. Android hebt die Bildschirmsperre einer App ohne sichtbares Fenster auf, und dieses Telefon ließ den Renderer sein eigenes Fenster nicht öffnen — das Panel leuchtete kurz auf und schlief wieder ein. Die Berechtigung heißt meist ungefähr „Pop-up-Fenster anzeigen, während im Hintergrund ausgeführt“ und ist vom Autostart getrennt.';

  @override
  String get settingsRunSetup => 'Einrichtung erneut ausführen';

  @override
  String get settingsRunSetupSubtitle =>
      'Die Berechtigungen der Reihe nach durchgehen';

  @override
  String get settingsLegal => 'Rechtliches';

  @override
  String get settingsLicenses => 'Open-Source-Lizenzen';

  @override
  String get settingsLicensesSubtitle => 'Worauf diese App aufbaut';

  @override
  String get settingsLicensesLegalese =>
      'Apache-Lizenz 2.0. Aufgebaut auf Arbeiten unter den hier aufgeführten LGPL-, Apache-, CDDL-, BSD-, CC0- und Public-Domain-Bedingungen.';

  @override
  String get settingsLanguage => 'Sprache';

  @override
  String get settingsLanguageSystem => 'Wie dieses Telefon';

  @override
  String get settingsLanguageHelp =>
      'Der Renderer folgt diesem Telefon, sofern du nichts anderes wählst. Ein Gerät, das auf einem Zweittelefon eingerichtet wurde, erbt oft eine Sprache, die niemand wollte.';

  @override
  String get onboardingTitle => 'HiFi Renderer einrichten';

  @override
  String get onboardingTitleRerun => 'Einrichtung';

  @override
  String get onboardingIntro =>
      'Dieses Telefon wird irgendwo stehen und als Renderer arbeiten. Android und die meisten Hersteller gehen davon aus, dass keine App das will, also müssen ein paar Dinge von Hand eingeschaltet werden.';

  @override
  String get onboardingOptional =>
      'Nichts davon ist nötig, um die App auszuprobieren, und alles lässt sich später in den Einstellungen ändern.';

  @override
  String get onboardingNotifications => 'Eine Benachrichtigung anzeigen';

  @override
  String get onboardingNotificationsGranted =>
      'Erteilt. Der Renderer zeigt seine Benachrichtigung, solange er läuft.';

  @override
  String get onboardingNotificationsWhy =>
      'Ohne sie lässt Android den Renderer nicht im Hintergrund weiterlaufen, und sie ist das einzige sichtbare Zeichen dafür, dass er lebt.';

  @override
  String get onboardingAllow => 'Zulassen';

  @override
  String get onboardingNoNotificationScreen =>
      'Dieses Telefon hat keinen Bildschirm für Benachrichtigungseinstellungen, der sich öffnen ließe.';

  @override
  String get onboardingNotificationsInSettings =>
      'Android fragt nicht mehr — schalte sie dort ein.';

  @override
  String get onboardingBattery => 'Verhindern, dass Android ihn anhält';

  @override
  String get onboardingBatteryGranted =>
      'Erteilt. Android wird den Renderer im Leerlauf nicht anhalten.';

  @override
  String get onboardingBatteryWhy =>
      'Ohne dies hält Android die App an, wenn der Bildschirm eine Weile aus war, und die Wiedergabe bricht mitten im Titel ab.';

  @override
  String get onboardingUsbPrompt =>
      'Android nicht mehr nach dem DAC fragen lassen';

  @override
  String get onboardingUsbPromptGranted =>
      'Erteilt. Wenn der DAC das nächste Mal verbunden wird, setze in der Android-Abfrage den Haken bei „immer öffnen“, dann fragt Android nicht mehr.';

  @override
  String get onboardingUsbPromptWhy =>
      'Ohne Mikrofonberechtigung fragt Android bei jedem Einschalten des DACs, ob die App geöffnet werden soll, und bietet keine Möglichkeit, das abzustellen. Erlaube sie und setze beim nächsten Verbinden des DACs den Haken bei „immer öffnen“. Die App nimmt niemals etwas auf.';

  @override
  String get onboardingUsbPromptInSettings =>
      'Android fragt nicht mehr — erlaube dort unter Berechtigungen das Mikrofon.';

  @override
  String onboardingVendorKnown(String vendor) {
    return 'Autostart ($vendor)';
  }

  @override
  String get onboardingVendorKnownNoName => 'Autostart';

  @override
  String get onboardingVendorUnknown =>
      'Die eigenen Einschränkungen deines Telefonherstellers';

  @override
  String get onboardingVendorKnownDetail =>
      'Telefone dieses Herstellers bringen meist eigene Einschränkungen für Hintergrund-Apps mit, getrennt von denen Androids, und sie sind der übliche Grund, warum ein Renderer nach einem Neustart nicht zurückkommt. Die App kann sie nicht erkennen — sie weiß nur, dass dieser Hersteller einen solchen Bildschirm hat — und sie kann auch nicht feststellen, ob du dort etwas erteilt hast. Dieser Schritt wird deshalb nie abgehakt.';

  @override
  String get onboardingVendorUnknownDetail =>
      'Für dieses Telefon kennen wir keinen Einstellungsbildschirm. Wenn der Renderer im Leerlauf stehen bleibt oder nach einem Neustart nicht zurückkommt, suche in den Akku-Einstellungen deines Telefons nach „Autostart“, „Hintergrund-Apps“ oder „Geschützte Apps“.';

  @override
  String get onboardingDac => 'Dein DAC';

  @override
  String get onboardingDacDetail =>
      'Schließe den USB-DAC an, wann du möchtest. Android fragt beim ersten Anschließen nach der Berechtigung, hier ist also nichts zu tun — und der Renderer richtet sich nach dem DAC, der gerade angeschlossen ist, statt auf einen bestimmten eingestellt zu sein.';

  @override
  String get onboardingDone => 'Fertig';

  @override
  String get onboardingFinishAnyway => 'Trotzdem beenden';

  @override
  String get onboardingAllGranted =>
      'Alles, was die App prüfen kann, ist erteilt.';

  @override
  String get onboardingSkippingIsFine =>
      'Überspringen ist in Ordnung. Der Renderer läuft; er übersteht es womöglich nur nicht, allein gelassen zu werden, und die Einstellungen sagen dir, wenn ihn etwas stoppt.';

  @override
  String onboardingStep(int number, String title) {
    return '$number. $title';
  }

  @override
  String get dacCapsTitle => 'DAC-Fähigkeiten';

  @override
  String get dacCapsReprobe => 'Erneut auslesen';

  @override
  String get dacCapsNotProbed => 'Noch nicht ausgelesen';

  @override
  String get dacCapsNotProbedDetail =>
      'Schließe einen USB-DAC an und tippe auf Aktualisieren.';

  @override
  String get dacCapsUnknownError => 'Unbekannter Fehler.';

  @override
  String get dacCapsNoDevice => 'Kein DAC gefunden';

  @override
  String get dacCapsPermissionNeeded => 'Berechtigung erforderlich';

  @override
  String get dacCapsOpenFailed => 'DAC ließ sich nicht öffnen';

  @override
  String get dacCapsProbeFailed => 'Auslesen fehlgeschlagen';

  @override
  String get dacCapsNotUsable => 'Für bitgenaue Wiedergabe nicht nutzbar';

  @override
  String get dacCapsWorthKnowing => 'Wissenswertes';

  @override
  String get dacCapsWhatItSupports => 'Was er unterstützt';

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
  String get dacCapsSampleRates => 'Abtastraten';

  @override
  String get dacCapsBitDepths => 'Bittiefen';

  @override
  String get dacCapsChannels => 'Kanäle';

  @override
  String get dacCapsCurrentlyAt => 'Läuft derzeit mit';

  @override
  String get dacCapsUsbTiming => 'USB-Taktung';

  @override
  String get dacCapsVolumeControl => 'Lautstärkeregelung';

  @override
  String get dacCapsDsd => 'DSD';

  @override
  String get dacCapsUnknown => 'Unbekannt';

  @override
  String dacCapsRateRange(String low, String high, int count) {
    return '$low – $high ($count Abtastraten)';
  }

  @override
  String dacCapsBitDepth(int bits) {
    return '$bits Bit';
  }

  @override
  String get dacCapsAsync => 'Asynchron (Takt des DAC)';

  @override
  String get dacCapsSync => 'Synchron';

  @override
  String get dacCapsVolumeOverUsb => 'Über USB unterstützt';

  @override
  String get dacCapsVolumeDeviceOnly => 'Nur am Gerät selbst';

  @override
  String get dacCapsDsdSupported => 'Von der Hardware unterstützt';

  @override
  String get dacCapsTechnical => 'Technische Details';

  @override
  String get dacCapsTechnicalSubtitle => 'Für Support-Berichte';

  @override
  String dacCapsKhz(String value) {
    return '$value kHz';
  }

  @override
  String get noteCannotPlayTitle => 'Dieses Gerät kann kein Audio wiedergeben';

  @override
  String get noteCannotPlayDetail =>
      'Es meldet sich als USB-Audioklasse an, bietet aber keinen PCM-Ausgang über einen isochronen Endpunkt. Reine Aufnahmegeräte sehen so aus — ein USB-Mikrofon oder die Aufnahmehälfte eines Headset-Adapters.';

  @override
  String get noteUac1Title => 'Dieses Gerät nutzt USB Audio Class 1.0';

  @override
  String get noteUac1Detail =>
      'Unterstützt, mit den Grenzen, die die Klasse selbst setzt: Full-Speed-USB begrenzt die Bandbreite, daher bleiben UAC1-Geräte deutlich unter dem, was ein UAC2-DAC bietet. Die Wiedergabe ist bei den unterstützten Abtastraten weiterhin bitgenau — nichts wird umgerechnet.';

  @override
  String get noteAdaptiveTitle => 'Dieses Gerät folgt dem Takt des Telefons';

  @override
  String get noteAdaptiveDetail =>
      'Sein Endpunkt ist adaptiv statt asynchron: Es richtet sich nach der Rate, die das Telefon sendet, statt einen eigenen Takt vorzugeben. Bei UAC1-Hardware üblich. Die Abtastwerte kommen trotzdem unverändert an; lediglich die Zeitreferenz liegt beim Telefon.';

  @override
  String get noteVolumeDeviceTitle =>
      'Die Lautstärke regelt der DAC, nicht diese App';

  @override
  String get noteVolumeOneWayDetail =>
      'Dieses Gerät bietet keine Lautstärkeregelung über USB. Es meldet dem Telefon zwar seinen eigenen Regler oder seine Fernbedienung, aber nur in eine Richtung: Nichts von hier aus kann seine Lautstärke ändern. Nutze den Regler am Gerät.';

  @override
  String get noteVolumeNoneDetail =>
      'Dieses Gerät bietet keine Lautstärkeregelung über USB, daher können Lautstärkebefehle eines DLNA-Controllers es nicht erreichen. Nutze den Regler am Gerät.';

  @override
  String get noteVolumeAppTitle =>
      'Die Lautstärke lässt sich aus dieser App regeln';

  @override
  String noteVolumeAppDetail(String detail) {
    return 'Der DAC bietet eine Lautstärkeregelung über USB ($detail), daher werden DLNA-Lautstärkebefehle direkt an die Hardware weitergereicht.';
  }

  @override
  String notePaddedTitle(int bits) {
    return '16-Bit-Titel werden auf $bits Bit aufgefüllt';
  }

  @override
  String notePaddedDetail(int bits) {
    return 'Dieser DAC bietet keinen 16-Bit-Modus, daher werden Dateien in CD-Auflösung in einen $bits-Bit-Rahmen gelegt. Die Abtastwerte bleiben unverändert, die Wiedergabe ist also weiterhin bitgenau.';
  }

  @override
  String get noteAsyncGoodTitle => 'Asynchrones USB mit eigenem Takt';

  @override
  String get noteAsyncGoodDetail =>
      'Der DAC gibt den Takt vor, statt dem Telefon zu folgen — die bessere Anordnung für die Klangqualität.';

  @override
  String get noteAsyncNoFeedbackTitle =>
      'Asynchron, aber kein Feedback-Endpunkt gefunden';

  @override
  String get noteAsyncNoFeedbackDetail =>
      'Die Taktung lässt sich nicht genau verfolgen, daher sind bei langer Wiedergabe gelegentliche Aussetzer möglich.';

  @override
  String get noteDsdTitle => 'DSD-fähig';

  @override
  String get noteDsdDetail =>
      'Dieser DAC nimmt natives DSD an. Die App gibt DSD noch nicht wieder.';

  @override
  String get noteAltConfigTitle => 'Ein anderer USB-Modus ist verfügbar';

  @override
  String noteAltConfigDetail(int count) {
    return 'Das Gerät bietet $count USB-Konfigurationen. Nur die aktive wird genutzt; manche DACs halten in der anderen einen Kompatibilitätsmodus bereit.';
  }

  @override
  String get noteClockErrorTitle =>
      'Die unterstützten Abtastraten ließen sich nicht auslesen';

  @override
  String get reportCopied => 'Bericht kopiert';

  @override
  String get copyReport => 'Bericht kopieren';

  @override
  String get stop => 'Stopp';

  @override
  String get notReported => 'nicht gemeldet';

  @override
  String get verifyTitle => 'DAC-Überprüfung';

  @override
  String get verifyResults => 'Ergebnisse';

  @override
  String get verifyFollow => 'Folgen';

  @override
  String get soakTitle => 'Dauertest';

  @override
  String get soakRate => 'Abtastrate';

  @override
  String get soakLength => 'Dauer';

  @override
  String soakStart(String rate, String duration) {
    return '$duration lang mit $rate testen';
  }

  @override
  String soakProgress(String elapsed, String planned, String step) {
    return '$elapsed von $planned  ·  $step';
  }

  @override
  String get soakFaults => 'Fehler';

  @override
  String get soakRingFill => 'Pufferfüllstand';

  @override
  String get soakMeasuredRate => 'Gemessene Rate';

  @override
  String get soakUnderruns => 'Underruns';

  @override
  String get soakTransferErrors => 'Übertragungsfehler';

  @override
  String get soakPacketErrors => 'Paketfehler';

  @override
  String get soakRebuffers => 'Nachpufferungen';

  @override
  String get soakWorstRingFill => 'Niedrigster Pufferfüllstand';

  @override
  String get soakWorstDeviation => 'Größte Abweichung';

  @override
  String get soakDriftSpread => 'Driftbreite';

  @override
  String get soakMeetsBar =>
      'Schafft die Zehn-Minuten-Marke ohne einen einzigen Aussetzer.';

  @override
  String get soakShortOfBar =>
      'Unter zehn Minuten, sagt also noch nichts über die Fehler aus, die erst auftreten, wenn die Hardware warm ist.';

  @override
  String get playFileTitle => 'Eine Datei abspielen';

  @override
  String get playFileIntro =>
      'Spielt eine deiner eigenen Dateien über den DAC ab und beobachtet dabei den Stream — genau die Frage, die die Testtöne nicht stellen können: ob das Material, das dir tatsächlich gehört, sauber läuft. Getestet werden nur die Abtastraten, die in diesem Material vorkommen.';

  @override
  String get playFileChoose => 'Datei auswählen';

  @override
  String get playFileFormats =>
      'FLAC, WAV, AIFF, MP3 und alles andere, was die Engine dekodiert.';

  @override
  String get playFileCache => 'In den App-Cache kopiert';

  @override
  String get playFileCacheDetail =>
      'Der M2-Prüfstand. Nur WAV, und der schnellste Weg, eine bekannte Datei auf ein Telefon zu bringen, das du über adb untersuchst.';

  @override
  String get playFileStreamHealth => 'Zustand des Streams';

  @override
  String get errServerUnreachable =>
      'Der Renderer hat die Verbindung zum Medienserver verloren.';

  @override
  String get errServerRefused => 'Der Medienserver hat diesen Titel abgelehnt.';

  @override
  String get errDownloadFailed =>
      'Dieser Titel konnte nicht vom Server geladen werden.';

  @override
  String get errUndecodableFormat =>
      'Dieser Titel liegt in einem Format vor, das der Renderer nicht dekodieren kann.';

  @override
  String get errDacRateUnsupported =>
      'Dieser DAC lässt sich nicht auf die Abtastrate oder Bittiefe dieses Titels einstellen.';

  @override
  String get errDacConnectionLost =>
      'Der Renderer hat die Verbindung zum DAC verloren.';

  @override
  String get errTrackCouldNotBePlayed =>
      'Dieser Titel konnte nicht wiedergegeben werden.';

  @override
  String errRateUnplayable(String rate, String ceiling) {
    return 'Dieser DAC kann $rate nicht wiedergeben; seine höchste Abtastrate ist $ceiling.';
  }

  @override
  String errStoppedAfterFailures(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Angehalten, nachdem $count Titel nacheinander nicht wiedergegeben werden konnten.',
    );
    return '$_temp0';
  }
}
