// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get settingsTooltip => 'Réglages';

  @override
  String get idleReady => 'Prêt — en attente d’un contrôleur';

  @override
  String get idleNoDac => 'Aucun DAC connecté';

  @override
  String get unknownTrack => 'Piste inconnue';

  @override
  String airPlayFromSender(String sender) {
    return 'AirPlay depuis $sender';
  }

  @override
  String get previousTrack => 'Piste précédente';

  @override
  String get nextTrack => 'Piste suivante';

  @override
  String get pause => 'Pause';

  @override
  String get play => 'Lecture';

  @override
  String get volumeWriteOnly =>
      'Ce DAC ne renvoie pas son volume : la valeur affichée est donc la dernière envoyée depuis l’app.';

  @override
  String get systemAudioDetail =>
      'Haut-parleur ou casque du téléphone — rééchantillonné par Android';

  @override
  String dacOneOf(int count) {
    return '(1 sur $count)';
  }

  @override
  String get bitPerfect => 'bit-perfect';

  @override
  String get systemAudioBadge => 'audio du système';

  @override
  String get airPlaySenderResampled => 'AirPlay · rééchantillonné à la source';

  @override
  String get settingsTitle => 'Réglages';

  @override
  String get settingsNetworkName => 'Nom sur le réseau';

  @override
  String get settingsNetworkNameHelp =>
      'Le nom sous lequel ce lecteur apparaît dans les contrôleurs DLNA.';

  @override
  String get settingsSave => 'Enregistrer';

  @override
  String get settingsSaved => 'Enregistré';

  @override
  String get settingsRenamed =>
      'Renommé. Redémarrez l’app pour que les contrôleurs le voient.';

  @override
  String get settingsAudioDevice => 'Périphérique audio';

  @override
  String settingsDacsMultiple(int count) {
    return '$count périphériques audio USB sont connectés. Choisissez celui à utiliser ; le choix est conservé après un redémarrage.';
  }

  @override
  String get settingsDacsSingle =>
      'Un périphérique audio USB est connecté. Touchez-le pour l’utiliser, et pour lui accorder l’accès s’il ne l’a pas encore.';

  @override
  String get settingsUsbAudioDevice => 'Périphérique audio USB';

  @override
  String get settingsPermissionNotGranted => ' — autorisation non accordée';

  @override
  String get settingsReadingDevice => 'Lecture du périphérique…';

  @override
  String get settingsProbing => 'Interrogation du DAC sur ce qu’il accepte';

  @override
  String settingsUacTap(String version) {
    return 'USB Audio Class $version — touchez pour voir ce qu’il accepte';
  }

  @override
  String get settingsConnectToProbe =>
      'Branchez un DAC USB puis touchez pour l’analyser';

  @override
  String get settingsPcmOnly =>
      'N’accepter que les flux PCM et laisser le serveur décoder ou convertir';

  @override
  String get settingsPcmOnlyOn =>
      'Le lecteur n’annonce que du LPCM, aux fréquences que ce DAC sait cadencer : le serveur convertit donc tout pour que cela passe. Tout se lit et rien n’est bit-perfect, y compris les pistes que le DAC aurait pu lire intactes.';

  @override
  String get settingsPcmOnlyOff =>
      'Le lecteur annonce tous les formats qu’il sait décoder, donc les fichiers arrivent intacts. Les pistes aux fréquences que ce DAC ne sait pas cadencer sont refusées, avec la raison affichée.';

  @override
  String get settingsScreenOffAfter => 'Éteindre l’écran après';

  @override
  String get settingsScreenOffNever =>
      'L’écran reste allumé. Sans souci sur un téléphone branché en permanence, mais une dalle OLED qui affiche le même écran pendant des mois finit par le garder gravé.';

  @override
  String get settingsScreenOffTimed =>
      'Compté à partir de l’arrêt de la musique : une piste longue n’éteint jamais l’écran en pleine lecture. La lecture le rallume.';

  @override
  String get settingsTimeoutNever => 'Jamais';

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
  String get settingsDacVerification => 'Vérification du DAC';

  @override
  String get settingsDacVerificationSubtitle =>
      'Tester toutes les fréquences annoncées par ce DAC';

  @override
  String get settingsAlwaysOn => 'Toujours actif';

  @override
  String get settingsAlwaysOnHelp =>
      'Un lecteur dédié doit continuer à fonctionner écran éteint et revenir après un redémarrage. Android et la plupart des fabricants l’empêchent par défaut.';

  @override
  String settingsDeaths(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Ce téléphone a arrêté le lecteur $count fois',
      one: 'Ce téléphone a arrêté le lecteur une fois',
    );
    return '$_temp0';
  }

  @override
  String get settingsDeathsDetail =>
      'Chacune est un démarrage qui suivait une exécution sans arrêt propre : quelque chose l’a donc tué en arrière-plan. Accorder ce qui suit règle généralement le problème.';

  @override
  String get settingsBattery => 'Exemption d’optimisation de la batterie';

  @override
  String get settingsBatteryGranted =>
      'Accordée — Android ne suspendra pas le lecteur.';

  @override
  String get settingsBatteryNotGranted =>
      'Non accordée. Android peut suspendre le lecteur lorsqu’il est inactif.';

  @override
  String get settingsGrant => 'Accorder';

  @override
  String get settingsOpenSettings => 'Ouvrir les réglages';

  @override
  String get settingsCouldNotOpen =>
      'Impossible d’ouvrir cet écran sur ce téléphone.';

  @override
  String settingsAutostart(String vendor) {
    return 'Démarrage automatique ($vendor)';
  }

  @override
  String get settingsAutostartVendorFallback => 'fabricant';

  @override
  String get settingsAutostartDetail =>
      'Les téléphones de ce fabricant ajoutent en général leurs propres restrictions pour les apps en arrière-plan, distinctes de celles d’Android, et c’est la raison habituelle pour laquelle un lecteur ne démarre pas après un redémarrage. L’app ne peut pas les détecter, elle sait seulement que ce fabricant possède un tel écran.';

  @override
  String get settingsWakeScreen => 'Allumer l’écran au démarrage de la musique';

  @override
  String get settingsWakeScreenDetail =>
      'De la musique a été jouée ici alors que l’écran restait éteint. Android désactive le maintien de l’écran demandé par une app sans fenêtre visible, et ce téléphone a refusé que le lecteur affiche la sienne : la dalle s’est allumée un instant puis s’est rendormie. L’autorisation s’appelle en général quelque chose comme « Afficher des fenêtres contextuelles en arrière-plan », et elle est distincte du démarrage automatique.';

  @override
  String get settingsRunSetup => 'Refaire la configuration';

  @override
  String get settingsRunSetupSubtitle =>
      'Passer les autorisations en revue, dans l’ordre';

  @override
  String get settingsLanguage => 'Langue';

  @override
  String get settingsLanguageSystem => 'Comme ce téléphone';

  @override
  String get settingsLanguageHelp =>
      'Le lecteur suit ce téléphone sauf si vous en décidez autrement. Un appareil configuré sur un téléphone de rechange hérite souvent d’une langue que personne ne voulait.';

  @override
  String get onboardingTitle => 'Configurer HiFi Renderer';

  @override
  String get onboardingTitleRerun => 'Configuration';

  @override
  String get onboardingIntro =>
      'Ce téléphone va rester quelque part et servir de lecteur réseau. Android et la plupart des fabricants partent du principe qu’aucune app ne veut faire cela : il faut donc activer quelques réglages à la main.';

  @override
  String get onboardingOptional =>
      'Rien de tout cela n’est nécessaire pour essayer l’app, et vous pourrez tout modifier plus tard dans les Réglages.';

  @override
  String get onboardingNotifications => 'Afficher une notification';

  @override
  String get onboardingNotificationsGranted =>
      'Accordé. Le lecteur affichera sa notification pendant qu’il fonctionne.';

  @override
  String get onboardingNotificationsWhy =>
      'Android n’autorise pas le lecteur à rester en arrière-plan sans elle, et c’est le seul signe visible qu’il est en vie.';

  @override
  String get onboardingAllow => 'Autoriser';

  @override
  String get onboardingNoNotificationScreen =>
      'Ce téléphone n’a pas d’écran de réglages des notifications à ouvrir.';

  @override
  String get onboardingNotificationsInSettings =>
      'Android ne demande plus — activez-les là-bas.';

  @override
  String get onboardingBattery => 'Empêcher Android de le suspendre';

  @override
  String get onboardingBatteryGranted =>
      'Accordé. Android ne suspendra pas le lecteur lorsqu’il est inactif.';

  @override
  String get onboardingBatteryWhy =>
      'Sans cela, Android suspend l’app lorsque l’écran est éteint depuis un moment, et la lecture s’arrête en pleine piste.';

  @override
  String onboardingVendorKnown(String vendor) {
    return 'Démarrage automatique ($vendor)';
  }

  @override
  String get onboardingVendorKnownNoName => 'Démarrage automatique';

  @override
  String get onboardingVendorUnknown =>
      'Les restrictions propres au fabricant de votre téléphone';

  @override
  String get onboardingVendorKnownDetail =>
      'Les téléphones de ce fabricant ajoutent en général leurs propres restrictions pour les apps en arrière-plan, distinctes de celles d’Android, et c’est la raison habituelle pour laquelle un lecteur ne revient pas après un redémarrage. L’app ne peut pas les détecter — elle sait seulement que ce fabricant possède un tel écran — ni savoir si vous y avez accordé quoi que ce soit : cette étape ne se coche donc jamais.';

  @override
  String get onboardingVendorUnknownDetail =>
      'Nous ne connaissons aucun écran de réglages pour ce téléphone. Si le lecteur s’arrête au repos ou ne revient pas après un redémarrage, cherchez « démarrage automatique », « applications en arrière-plan » ou « applications protégées » dans les réglages de batterie de votre téléphone.';

  @override
  String get onboardingDac => 'Votre DAC';

  @override
  String get onboardingDacDetail =>
      'Branchez le DAC USB quand vous voulez. Android demande l’autorisation la première fois qu’il est connecté : il n’y a donc rien à faire ici, et le lecteur s’adapte au DAC branché plutôt que d’être configuré pour l’un d’eux.';

  @override
  String get onboardingDone => 'Terminé';

  @override
  String get onboardingFinishAnyway => 'Terminer quand même';

  @override
  String get onboardingAllGranted =>
      'Tout ce que l’app peut vérifier est accordé.';

  @override
  String get onboardingSkippingIsFine =>
      'Vous pouvez passer sans souci. Le lecteur fonctionnera ; il risque simplement de ne pas survivre lorsqu’on le laisse seul, et les Réglages vous diront si quelque chose l’arrête.';

  @override
  String onboardingStep(int number, String title) {
    return '$number. $title';
  }

  @override
  String get dacCapsTitle => 'Capacités du DAC';

  @override
  String get dacCapsReprobe => 'Analyser à nouveau';

  @override
  String get dacCapsNotProbed => 'Pas encore analysé';

  @override
  String get dacCapsNotProbedDetail =>
      'Branchez un DAC USB et touchez actualiser.';

  @override
  String get dacCapsUnknownError => 'Erreur inconnue.';

  @override
  String get dacCapsNoDevice => 'Aucun DAC trouvé';

  @override
  String get dacCapsPermissionNeeded => 'Autorisation nécessaire';

  @override
  String get dacCapsOpenFailed => 'Impossible d’ouvrir le DAC';

  @override
  String get dacCapsProbeFailed => 'Échec de l’analyse';

  @override
  String get dacCapsNotUsable => 'Inutilisable pour une lecture bit-perfect';

  @override
  String get dacCapsWorthKnowing => 'Ce qu’il faut savoir';

  @override
  String get dacCapsWhatItSupports => 'Ce qu’il accepte';

  @override
  String dacCapsIdentity(
    String version,
    String speed,
    String vendor,
    String product,
  ) {
    return 'USB Audio Class $version · vitesse $speed · $vendor:$product';
  }

  @override
  String get dacCapsSampleRates => 'Fréquences d’échantillonnage';

  @override
  String get dacCapsBitDepths => 'Profondeurs de bits';

  @override
  String get dacCapsChannels => 'Canaux';

  @override
  String get dacCapsCurrentlyAt => 'Fonctionne actuellement à';

  @override
  String get dacCapsUsbTiming => 'Cadencement USB';

  @override
  String get dacCapsVolumeControl => 'Contrôle du volume';

  @override
  String get dacCapsDsd => 'DSD';

  @override
  String get dacCapsUnknown => 'Inconnu';

  @override
  String dacCapsRateRange(String low, String high, int count) {
    return '$low – $high ($count fréquences)';
  }

  @override
  String dacCapsBitDepth(int bits) {
    return '$bits bits';
  }

  @override
  String get dacCapsAsync => 'Asynchrone (horloge du DAC)';

  @override
  String get dacCapsSync => 'Synchrone';

  @override
  String get dacCapsVolumeOverUsb => 'Pris en charge via USB';

  @override
  String get dacCapsVolumeDeviceOnly => 'Sur l’appareil uniquement';

  @override
  String get dacCapsDsdSupported => 'Pris en charge par le matériel';

  @override
  String get dacCapsTechnical => 'Détails techniques';

  @override
  String get dacCapsTechnicalSubtitle => 'Pour les rapports d’assistance';

  @override
  String dacCapsKhz(String value) {
    return '$value kHz';
  }

  @override
  String get noteCannotPlayTitle => 'Cet appareil ne peut pas lire d’audio';

  @override
  String get noteCannotPlayDetail =>
      'Il s’annonce comme classe audio USB mais n’offre aucune sortie PCM sur un endpoint isochrone. Les appareils de capture seule ressemblent à cela : un micro USB, ou la moitié enregistrement d’un adaptateur de casque.';

  @override
  String get noteUac1Title => 'Cet appareil utilise USB Audio Class 1.0';

  @override
  String get noteUac1Detail =>
      'Pris en charge, avec les limites qu’impose la classe elle-même : l’USB full-speed plafonne la bande passante, donc les appareils UAC1 s’arrêtent bien en dessous de ce qu’offre un DAC UAC2. La lecture reste bit-perfect aux fréquences qu’il accepte — rien n’est rééchantillonné.';

  @override
  String get noteAdaptiveTitle => 'Cet appareil suit l’horloge du téléphone';

  @override
  String get noteAdaptiveDetail =>
      'Son endpoint est adaptatif plutôt qu’asynchrone : il s’aligne sur la fréquence envoyée par le téléphone au lieu d’imposer sa propre horloge. Fréquent sur le matériel UAC1. Les échantillons arrivent toujours intacts ; seule la référence de temps change de camp.';

  @override
  String get noteVolumeDeviceTitle =>
      'Le volume est géré par le DAC, pas par cette app';

  @override
  String get noteVolumeOneWayDetail =>
      'Cet appareil n’expose aucun contrôle de volume USB. Il signale bien au téléphone son propre bouton ou sa télécommande, mais cela ne va que dans un sens : rien envoyé d’ici ne peut changer son volume. Utilisez la commande physique.';

  @override
  String get noteVolumeNoneDetail =>
      'Cet appareil n’expose aucun contrôle de volume USB : les commandes de volume d’un contrôleur DLNA ne peuvent donc pas l’atteindre. Utilisez la commande physique.';

  @override
  String get noteVolumeAppTitle => 'Le volume peut être réglé depuis cette app';

  @override
  String noteVolumeAppDetail(String detail) {
    return 'Le DAC expose un contrôle de volume USB ($detail) : les commandes de volume DLNA sont donc transmises directement au matériel.';
  }

  @override
  String notePaddedTitle(int bits) {
    return 'Les pistes 16 bits sont complétées en $bits bits';
  }

  @override
  String notePaddedDetail(int bits) {
    return 'Ce DAC n’offre pas de mode 16 bits : les fichiers en résolution CD sont donc placés dans un conteneur $bits bits. Les valeurs des échantillons ne changent pas, la lecture reste donc bit-perfect.';
  }

  @override
  String get noteAsyncGoodTitle => 'USB asynchrone avec horloge propre';

  @override
  String get noteAsyncGoodDetail =>
      'C’est le DAC qui impose le tempo plutôt que de suivre le téléphone, ce qui est la meilleure disposition pour la qualité sonore.';

  @override
  String get noteAsyncNoFeedbackTitle =>
      'Asynchrone, mais aucun endpoint de retour trouvé';

  @override
  String get noteAsyncNoFeedbackDetail =>
      'Le cadencement ne peut pas être suivi précisément : des coupures occasionnelles sont donc possibles sur une longue lecture.';

  @override
  String get noteDsdTitle => 'Compatible DSD';

  @override
  String get noteDsdDetail =>
      'Ce DAC accepte le DSD natif. L’app ne lit pas encore le DSD.';

  @override
  String get noteAltConfigTitle => 'Un autre mode USB est disponible';

  @override
  String noteAltConfigDetail(int count) {
    return 'L’appareil propose $count configurations USB. Seule celle qui est active est utilisée ; certains DAC gardent un mode de compatibilité dans l’autre.';
  }

  @override
  String get noteClockErrorTitle =>
      'Impossible de lire les fréquences prises en charge';

  @override
  String get reportCopied => 'Rapport copié';

  @override
  String get copyReport => 'Copier le rapport';

  @override
  String get stop => 'Arrêter';

  @override
  String get notReported => 'non communiqué';

  @override
  String get verifyTitle => 'Vérification du DAC';

  @override
  String get verifyResults => 'Résultats';

  @override
  String get verifyFollow => 'Suivre';

  @override
  String get soakTitle => 'Test d’endurance';

  @override
  String get soakRate => 'Fréquence';

  @override
  String get soakLength => 'Durée';

  @override
  String soakStart(String rate, String duration) {
    return 'Tester à $rate pendant $duration';
  }

  @override
  String soakProgress(String elapsed, String planned, String step) {
    return '$elapsed sur $planned  ·  $step';
  }

  @override
  String get soakFaults => 'Défauts';

  @override
  String get soakRingFill => 'Remplissage du tampon';

  @override
  String get soakMeasuredRate => 'Fréquence mesurée';

  @override
  String get soakUnderruns => 'Underruns';

  @override
  String get soakTransferErrors => 'Erreurs de transfert';

  @override
  String get soakPacketErrors => 'Erreurs de paquet';

  @override
  String get soakRebuffers => 'Remplissages du tampon';

  @override
  String get soakWorstRingFill => 'Remplissage minimal du tampon';

  @override
  String get soakWorstDeviation => 'Écart maximal';

  @override
  String get soakDriftSpread => 'Amplitude de dérive';

  @override
  String get soakMeetsBar =>
      'Franchit la barre des dix minutes sans la moindre coupure.';

  @override
  String get soakShortOfBar =>
      'En deçà des dix minutes : cela ne dit donc encore rien des défauts qui n’apparaissent qu’une fois le matériel chaud.';

  @override
  String get playFileTitle => 'Lire un fichier';

  @override
  String get playFileIntro =>
      'Lit l’un de vos propres fichiers via le DAC et surveille le flux, ce que les tests de tonalité ne peuvent pas demander : si ce que vous possédez réellement se lit proprement. Seules les fréquences présentes dans ce matériel sont testées.';

  @override
  String get playFileChoose => 'Choisir un fichier';

  @override
  String get playFileFormats =>
      'FLAC, WAV, AIFF, MP3 et tout autre format que le moteur sait décoder.';

  @override
  String get playFileCache => 'Copiés dans le cache de l’app';

  @override
  String get playFileCacheDetail =>
      'Le banc de test M2. WAV uniquement, et le moyen le plus rapide de mettre un fichier connu sur un téléphone que vous déboguez via adb.';

  @override
  String get playFileStreamHealth => 'État du flux';

  @override
  String get errServerUnreachable =>
      'Le lecteur a perdu le contact avec le serveur multimédia.';

  @override
  String get errServerRefused => 'Le serveur multimédia a refusé cette piste.';

  @override
  String get errDownloadFailed =>
      'Cette piste n’a pas pu être téléchargée depuis le serveur.';

  @override
  String get errUndecodableFormat =>
      'Cette piste est dans un format que le lecteur ne sait pas décoder.';

  @override
  String get errDacRateUnsupported =>
      'Ce DAC ne peut pas être réglé sur la fréquence ou la profondeur de bits de cette piste.';

  @override
  String get errDacConnectionLost =>
      'Le lecteur a perdu la connexion avec le DAC.';

  @override
  String get errTrackCouldNotBePlayed => 'Cette piste n’a pas pu être lue.';

  @override
  String errRateUnplayable(String rate, String ceiling) {
    return 'Ce DAC ne peut pas lire du $rate ; sa fréquence maximale est $ceiling.';
  }

  @override
  String errStoppedAfterFailures(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Arrêté après $count pistes d’affilée impossibles à lire.',
    );
    return '$_temp0';
  }
}
