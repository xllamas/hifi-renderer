// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Italian (`it`).
class AppLocalizationsIt extends AppLocalizations {
  AppLocalizationsIt([String locale = 'it']) : super(locale);

  @override
  String get settingsTooltip => 'Impostazioni';

  @override
  String get idleReady => 'Pronto — in attesa di un controller';

  @override
  String get idleNoDac => 'Nessun DAC collegato';

  @override
  String get unknownTrack => 'Brano sconosciuto';

  @override
  String airPlayFromSender(String sender) {
    return 'AirPlay da $sender';
  }

  @override
  String get previousTrack => 'Brano precedente';

  @override
  String get nextTrack => 'Brano successivo';

  @override
  String get pause => 'Pausa';

  @override
  String get play => 'Riproduci';

  @override
  String get volumeWriteOnly =>
      'Questo DAC non comunica il proprio volume, quindi qui compare l’ultimo valore inviato dall’app.';

  @override
  String get systemAudioDetail =>
      'Altoparlante o cuffie del telefono — ricampionato da Android';

  @override
  String dacOneOf(int count) {
    return '(1 di $count)';
  }

  @override
  String get bitPerfect => 'bit-perfect';

  @override
  String get systemAudioBadge => 'audio di sistema';

  @override
  String get airPlaySenderResampled => 'AirPlay · ricampionato all’origine';

  @override
  String get settingsTitle => 'Impostazioni';

  @override
  String get settingsNetworkName => 'Nome in rete';

  @override
  String get settingsNetworkNameHelp =>
      'Come appare questo riproduttore nei controller DLNA.';

  @override
  String get settingsSave => 'Salva';

  @override
  String get settingsSaved => 'Salvato';

  @override
  String get settingsRenamed =>
      'Rinominato. Riavvia l’app perché i controller lo vedano.';

  @override
  String get settingsAudioDevice => 'Dispositivo audio';

  @override
  String settingsDacsMultiple(int count) {
    return 'Sono collegati $count dispositivi audio USB. Scegli quale usare; la scelta viene ricordata dopo i riavvii.';
  }

  @override
  String get settingsDacsSingle =>
      'È collegato un dispositivo audio USB. Toccalo per riprodurre attraverso di esso e per concedergli l’accesso se non lo ha ancora.';

  @override
  String get settingsUsbAudioDevice => 'Dispositivo audio USB';

  @override
  String get settingsPermissionNotGranted => ' — permesso non concesso';

  @override
  String get settingsReadingDevice => 'Lettura del dispositivo…';

  @override
  String get settingsProbing => 'Interrogazione del DAC su ciò che supporta';

  @override
  String settingsUacTap(String version) {
    return 'USB Audio Class $version — tocca per vedere cosa supporta';
  }

  @override
  String get settingsConnectToProbe =>
      'Collega un DAC USB e tocca per analizzarlo';

  @override
  String get settingsPcmOnly =>
      'Accettare solo flussi PCM e lasciare che sia il server a decodificare o convertire';

  @override
  String get settingsPcmOnlyOn =>
      'Il riproduttore annuncia soltanto LPCM, alle frequenze che questo DAC sa generare, quindi il server converte tutto perché rientri. Tutto suona e nulla è bit-perfect, compresi i brani che il DAC avrebbe potuto riprodurre intatti.';

  @override
  String get settingsPcmOnlyOff =>
      'Il riproduttore annuncia ogni formato che sa decodificare, quindi i file arrivano intatti. I brani a frequenze che questo DAC non sa generare vengono rifiutati, indicando il motivo.';

  @override
  String get settingsScreenOffAfter => 'Spegni lo schermo dopo';

  @override
  String get settingsScreenOffNever =>
      'Lo schermo resta acceso. Va bene su un telefono sempre alimentato, ma un pannello OLED che mostra la stessa schermata per mesi finisce per trattenerla in modo permanente.';

  @override
  String get settingsScreenOffTimed =>
      'Conteggiato da quando la musica si ferma: un brano lungo non spegne mai lo schermo a metà riproduzione. La riproduzione lo riaccende.';

  @override
  String get settingsTimeoutNever => 'Mai';

  @override
  String settingsTimeoutMinutes(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: '$minutes minuti',
      one: '1 minuto',
    );
    return '$_temp0';
  }

  @override
  String get settingsDacVerification => 'Verifica del DAC';

  @override
  String get settingsDacVerificationSubtitle =>
      'Prova tutte le frequenze dichiarate da questo DAC';

  @override
  String get settingsAlwaysOn => 'Sempre attivo';

  @override
  String get settingsAlwaysOnHelp =>
      'Un riproduttore dedicato deve continuare a funzionare a schermo spento e tornare dopo un riavvio. Android e la maggior parte dei produttori lo impediscono per impostazione predefinita.';

  @override
  String settingsDeaths(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Questo telefono ha fermato il riproduttore $count volte',
      one: 'Questo telefono ha fermato il riproduttore una volta',
    );
    return '$_temp0';
  }

  @override
  String get settingsDeathsDetail =>
      'Ognuna è un avvio successivo a un’esecuzione che non ha mai registrato un arresto pulito, quindi qualcosa lo ha ucciso in background. Concedere quanto segue di solito risolve.';

  @override
  String get settingsBattery => 'Esenzione dall’ottimizzazione della batteria';

  @override
  String get settingsBatteryGranted =>
      'Concessa — Android non sospenderà il riproduttore.';

  @override
  String get settingsBatteryNotGranted =>
      'Non concessa. Android può sospendere il riproduttore quando è inattivo.';

  @override
  String get settingsGrant => 'Concedi';

  @override
  String get settingsOpenSettings => 'Apri impostazioni';

  @override
  String get settingsCouldNotOpen =>
      'Impossibile aprire quella schermata su questo telefono.';

  @override
  String settingsAutostart(String vendor) {
    return 'Avvio automatico ($vendor)';
  }

  @override
  String get settingsAutostartVendorFallback => 'produttore';

  @override
  String get settingsAutostartDetail =>
      'I telefoni di questo produttore aggiungono di solito restrizioni proprie per le app in background, distinte da quelle di Android, e sono il motivo abituale per cui un riproduttore non parte dopo un riavvio. L’app non può rilevarle, sa soltanto che questo produttore ha una schermata del genere.';

  @override
  String get settingsWakeScreen => 'Accendi lo schermo quando parte la musica';

  @override
  String get settingsWakeScreenDetail =>
      'Qui è stata riprodotta musica mentre lo schermo restava spento. Android disattiva il blocco dello schermo richiesto da un’app senza finestre visibili, e questo telefono non ha permesso al riproduttore di mostrare la propria: il pannello si è acceso un istante ed è tornato a dormire. Il permesso si chiama di solito qualcosa come «Mostra finestre pop-up mentre è in esecuzione in background», ed è distinto dall’avvio automatico.';

  @override
  String get settingsRunSetup => 'Ripeti la configurazione';

  @override
  String get settingsRunSetupSubtitle => 'Rivedi i permessi nell’ordine';

  @override
  String get settingsLegal => 'Note legali';

  @override
  String get settingsLicenses => 'Licenze open source';

  @override
  String get settingsLicensesSubtitle => 'Su cosa si basa questa app';

  @override
  String get settingsLicensesLegalese =>
      'Licenza Apache 2.0. Basata su lavori rilasciati secondo i termini LGPL, Apache, CDDL, BSD, CC0 e di pubblico dominio elencati qui.';

  @override
  String get settingsLanguage => 'Lingua';

  @override
  String get settingsLanguageSystem => 'Come questo telefono';

  @override
  String get settingsLanguageHelp =>
      'Il riproduttore segue questo telefono se non scegli diversamente. Un apparecchio configurato su un telefono di scorta eredita spesso una lingua che nessuno voleva.';

  @override
  String get onboardingTitle => 'Configura HiFi Renderer';

  @override
  String get onboardingTitleRerun => 'Configurazione';

  @override
  String get onboardingIntro =>
      'Questo telefono resterà da qualche parte a fare da riproduttore di rete. Android e la maggior parte dei produttori danno per scontato che nessuna app voglia farlo, quindi qualche impostazione va attivata a mano.';

  @override
  String get onboardingOptional =>
      'Niente di tutto questo è necessario per provare l’app, e potrai cambiare ogni cosa più tardi nelle Impostazioni.';

  @override
  String get onboardingNotifications => 'Mostrare una notifica';

  @override
  String get onboardingNotificationsGranted =>
      'Concesso. Il riproduttore mostrerà la sua notifica mentre funziona.';

  @override
  String get onboardingNotificationsWhy =>
      'Android non lascia che il riproduttore resti in background senza di essa, ed è l’unico segno visibile che è vivo.';

  @override
  String get onboardingAllow => 'Consenti';

  @override
  String get onboardingNoNotificationScreen =>
      'Questo telefono non ha una schermata delle impostazioni di notifica da aprire.';

  @override
  String get onboardingNotificationsInSettings =>
      'Android ha smesso di chiedere — attivale lì.';

  @override
  String get onboardingBattery => 'Impedire ad Android di sospenderlo';

  @override
  String get onboardingBatteryGranted =>
      'Concesso. Android non sospenderà il riproduttore quando è inattivo.';

  @override
  String get onboardingBatteryWhy =>
      'Senza questo, Android sospende l’app quando lo schermo è spento da un po’ e la riproduzione si interrompe a metà brano.';

  @override
  String get onboardingUsbPrompt => 'Evitare che Android chieda del DAC';

  @override
  String get onboardingUsbPromptGranted =>
      'Concesso. La prossima volta che il DAC si collega, spunta «apri sempre» nella richiesta di Android e non chiederà più.';

  @override
  String get onboardingUsbPromptWhy =>
      'Senza il permesso del microfono, Android chiede se aprire l’app ogni volta che il DAC viene acceso, senza offrire l’opzione per smettere di chiedere. Concedilo, poi spunta «apri sempre» la prossima volta che il DAC si collega. L’app non registra mai nulla.';

  @override
  String get onboardingUsbPromptInSettings =>
      'Android ha smesso di chiedere — consenti il microfono in Autorizzazioni lì.';

  @override
  String onboardingVendorKnown(String vendor) {
    return 'Avvio automatico ($vendor)';
  }

  @override
  String get onboardingVendorKnownNoName => 'Avvio automatico';

  @override
  String get onboardingVendorUnknown =>
      'Le restrizioni proprie del produttore del tuo telefono';

  @override
  String get onboardingVendorKnownDetail =>
      'I telefoni di questo produttore aggiungono di solito restrizioni proprie per le app in background, distinte da quelle di Android, e sono il motivo abituale per cui un riproduttore non torna dopo un riavvio. L’app non può rilevarle — sa soltanto che questo produttore ha una schermata del genere — né può sapere se vi hai concesso qualcosa, quindi questo passaggio non viene mai spuntato.';

  @override
  String get onboardingVendorUnknownDetail =>
      'Non conosciamo alcuna schermata di impostazioni per questo telefono. Se il riproduttore si ferma quando è inattivo o non torna dopo un riavvio, cerca «avvio automatico», «app in background» o «app protette» nelle impostazioni della batteria del tuo telefono.';

  @override
  String get onboardingDac => 'Il tuo DAC';

  @override
  String get onboardingDacDetail =>
      'Collega il DAC USB quando vuoi. Android chiede il permesso al collegamento — spunta «apri sempre» in quella richiesta e smetterà di chiedere — e il riproduttore si adatta al DAC collegato invece di essere configurato per uno in particolare.';

  @override
  String get onboardingDone => 'Fatto';

  @override
  String get onboardingFinishAnyway => 'Termina comunque';

  @override
  String get onboardingAllGranted =>
      'È concesso tutto ciò che l’app può verificare.';

  @override
  String get onboardingSkippingIsFine =>
      'Saltare va benissimo. Il riproduttore funzionerà; potrebbe semplicemente non sopravvivere quando lo si lascia solo, e le Impostazioni ti diranno se qualcosa lo sta fermando.';

  @override
  String onboardingStep(int number, String title) {
    return '$number. $title';
  }

  @override
  String get dacCapsTitle => 'Capacità del DAC';

  @override
  String get dacCapsReprobe => 'Analizza di nuovo';

  @override
  String get dacCapsNotProbed => 'Non ancora analizzato';

  @override
  String get dacCapsNotProbedDetail => 'Collega un DAC USB e tocca aggiorna.';

  @override
  String get dacCapsUnknownError => 'Errore sconosciuto.';

  @override
  String get dacCapsNoDevice => 'Nessun DAC trovato';

  @override
  String get dacCapsPermissionNeeded => 'Serve il permesso';

  @override
  String get dacCapsOpenFailed => 'Impossibile aprire il DAC';

  @override
  String get dacCapsProbeFailed => 'Analisi non riuscita';

  @override
  String get dacCapsNotUsable =>
      'Non utilizzabile per una riproduzione bit-perfect';

  @override
  String get dacCapsWorthKnowing => 'Cose che vale la pena sapere';

  @override
  String get dacCapsWhatItSupports => 'Cosa supporta';

  @override
  String dacCapsIdentity(
    String version,
    String speed,
    String vendor,
    String product,
  ) {
    return 'USB Audio Class $version · velocità $speed · $vendor:$product';
  }

  @override
  String get dacCapsSampleRates => 'Frequenze di campionamento';

  @override
  String get dacCapsBitDepths => 'Profondità di bit';

  @override
  String get dacCapsChannels => 'Canali';

  @override
  String get dacCapsCurrentlyAt => 'Ora in funzione a';

  @override
  String get dacCapsUsbTiming => 'Sincronizzazione USB';

  @override
  String get dacCapsVolumeControl => 'Controllo del volume';

  @override
  String get dacCapsDsd => 'DSD';

  @override
  String get dacCapsUnknown => 'Sconosciuto';

  @override
  String dacCapsRateRange(String low, String high, int count) {
    return '$low – $high ($count frequenze)';
  }

  @override
  String dacCapsBitDepth(int bits) {
    return '$bits bit';
  }

  @override
  String get dacCapsAsync => 'Asincrono (clock del DAC)';

  @override
  String get dacCapsSync => 'Sincrono';

  @override
  String get dacCapsVolumeOverUsb => 'Supportato via USB';

  @override
  String get dacCapsVolumeDeviceOnly => 'Solo sull’apparecchio';

  @override
  String get dacCapsDsdSupported => 'Supportato dall’hardware';

  @override
  String get dacCapsTechnical => 'Dettagli tecnici';

  @override
  String get dacCapsTechnicalSubtitle => 'Per le segnalazioni di assistenza';

  @override
  String dacCapsKhz(String value) {
    return '$value kHz';
  }

  @override
  String get noteCannotPlayTitle =>
      'Questo dispositivo non può riprodurre audio';

  @override
  String get noteCannotPlayDetail =>
      'Si annuncia come classe audio USB ma non offre alcuna uscita PCM su un endpoint isocrono. I dispositivi di sola acquisizione hanno questo aspetto: un microfono USB, o la metà di registrazione di un adattatore per cuffie.';

  @override
  String get noteUac1Title => 'Questo dispositivo usa USB Audio Class 1.0';

  @override
  String get noteUac1Detail =>
      'Supportato, con i limiti imposti dalla classe stessa: l’USB full-speed limita la banda, quindi i dispositivi UAC1 si fermano ben al di sotto di quanto offre un DAC UAC2. La riproduzione resta bit-perfect alle frequenze che supporta: nulla viene ricampionato.';

  @override
  String get noteAdaptiveTitle =>
      'Questo dispositivo segue il clock del telefono';

  @override
  String get noteAdaptiveDetail =>
      'Il suo endpoint è adattivo anziché asincrono, quindi si allinea alla frequenza inviata dal telefono invece di imporre il proprio clock. Comune sull’hardware UAC1. I campioni arrivano comunque inalterati; cambia soltanto da che parte sta il riferimento temporale.';

  @override
  String get noteVolumeDeviceTitle =>
      'Il volume è gestito dal DAC, non da questa app';

  @override
  String get noteVolumeOneWayDetail =>
      'Questo dispositivo non espone alcun controllo di volume USB. Comunica al telefono la propria manopola o il telecomando, ma solo in una direzione: nulla inviato da qui può cambiarne il volume. Usa il comando fisico.';

  @override
  String get noteVolumeNoneDetail =>
      'Questo dispositivo non espone alcun controllo di volume USB, quindi i comandi di volume di un controller DLNA non possono raggiungerlo. Usa il comando fisico.';

  @override
  String get noteVolumeAppTitle =>
      'Il volume può essere regolato da questa app';

  @override
  String noteVolumeAppDetail(String detail) {
    return 'Il DAC espone un controllo di volume USB ($detail), quindi i comandi di volume DLNA arrivano direttamente all’hardware.';
  }

  @override
  String notePaddedTitle(int bits) {
    return 'I brani a 16 bit vengono estesi a $bits bit';
  }

  @override
  String notePaddedDetail(int bits) {
    return 'Questo DAC non offre una modalità a 16 bit, quindi i file in risoluzione CD vengono inseriti in un contenitore a $bits bit. I valori dei campioni non cambiano, quindi la riproduzione resta bit-perfect.';
  }

  @override
  String get noteAsyncGoodTitle => 'USB asincrono con clock proprio';

  @override
  String get noteAsyncGoodDetail =>
      'È il DAC a dettare il tempo anziché seguire il telefono, che è la disposizione migliore per la qualità del suono.';

  @override
  String get noteAsyncNoFeedbackTitle =>
      'Asincrono, ma nessun endpoint di feedback trovato';

  @override
  String get noteAsyncNoFeedbackDetail =>
      'La sincronizzazione non può essere seguita con precisione, quindi su riproduzioni lunghe sono possibili interruzioni occasionali.';

  @override
  String get noteDsdTitle => 'Compatibile DSD';

  @override
  String get noteDsdDetail =>
      'Questo DAC accetta DSD nativo. L’app non riproduce ancora il DSD.';

  @override
  String get noteAltConfigTitle => 'È disponibile un’altra modalità USB';

  @override
  String noteAltConfigDetail(int count) {
    return 'Il dispositivo offre $count configurazioni USB. Viene usata solo quella attiva; alcuni DAC tengono una modalità di compatibilità nell’altra.';
  }

  @override
  String get noteClockErrorTitle =>
      'Impossibile leggere le frequenze supportate';

  @override
  String get reportCopied => 'Rapporto copiato';

  @override
  String get copyReport => 'Copia rapporto';

  @override
  String get stop => 'Ferma';

  @override
  String get notReported => 'non comunicato';

  @override
  String get verifyTitle => 'Verifica del DAC';

  @override
  String get verifyResults => 'Risultati';

  @override
  String get verifyFollow => 'Segui';

  @override
  String get soakTitle => 'Prova di resistenza';

  @override
  String get soakRate => 'Frequenza';

  @override
  String get soakLength => 'Durata';

  @override
  String soakStart(String rate, String duration) {
    return 'Prova a $rate per $duration';
  }

  @override
  String soakProgress(String elapsed, String planned, String step) {
    return '$elapsed di $planned  ·  $step';
  }

  @override
  String get soakFaults => 'Guasti';

  @override
  String get soakRingFill => 'Riempimento del buffer';

  @override
  String get soakMeasuredRate => 'Frequenza misurata';

  @override
  String get soakUnderruns => 'Underrun';

  @override
  String get soakTransferErrors => 'Errori di trasferimento';

  @override
  String get soakPacketErrors => 'Errori di pacchetto';

  @override
  String get soakRebuffers => 'Riempimenti del buffer';

  @override
  String get soakWorstRingFill => 'Riempimento minimo del buffer';

  @override
  String get soakWorstDeviation => 'Scostamento massimo';

  @override
  String get soakDriftSpread => 'Ampiezza della deriva';

  @override
  String get soakMeetsBar =>
      'Supera l’asticella dei dieci minuti senza una sola interruzione.';

  @override
  String get soakShortOfBar =>
      'Sotto i dieci minuti, quindi non dice ancora nulla sui guasti che compaiono solo quando l’hardware si scalda.';

  @override
  String get playFileTitle => 'Riproduci un file';

  @override
  String get playFileIntro =>
      'Riproduce un tuo file attraverso il DAC e sorveglia il flusso, che è la domanda che le prove a tono non possono porre: se il materiale che possiedi davvero suona pulito. Vengono provate solo le frequenze presenti in quel materiale.';

  @override
  String get playFileChoose => 'Scegli un file';

  @override
  String get playFileFormats =>
      'FLAC, WAV, AIFF, MP3 e qualsiasi altro formato che il motore sappia decodificare.';

  @override
  String get playFileCache => 'Copiati nella cache dell’app';

  @override
  String get playFileCacheDetail =>
      'Il banco di prova M2. Solo WAV, ed è il modo più rapido di mettere un file noto su un telefono che stai analizzando via adb.';

  @override
  String get playFileStreamHealth => 'Stato del flusso';

  @override
  String get errServerUnreachable =>
      'Il riproduttore ha perso il contatto con il server multimediale.';

  @override
  String get errServerRefused =>
      'Il server multimediale ha rifiutato questo brano.';

  @override
  String get errDownloadFailed =>
      'Non è stato possibile scaricare questo brano dal server.';

  @override
  String get errUndecodableFormat =>
      'Questo brano è in un formato che il riproduttore non sa decodificare.';

  @override
  String get errDacRateUnsupported =>
      'Questo DAC non può essere impostato sulla frequenza o sulla profondità di bit di questo brano.';

  @override
  String get errDacConnectionLost =>
      'Il riproduttore ha perso la connessione con il DAC.';

  @override
  String get errTrackCouldNotBePlayed =>
      'Non è stato possibile riprodurre questo brano.';

  @override
  String errRateUnplayable(String rate, String ceiling) {
    return 'Questo DAC non può riprodurre a $rate; la sua frequenza massima è $ceiling.';
  }

  @override
  String errStoppedAfterFailures(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Fermato dopo che $count brani di fila non hanno potuto essere riprodotti.',
    );
    return '$_temp0';
  }

  @override
  String errRateNotOffered(String rate) {
    return 'Questo DAC non supporta $rate.';
  }

  @override
  String errTracksSkipped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count brani sono stati saltati perché non è stato possibile riprodurli.',
      one: 'Un brano è stato saltato perché non è stato possibile riprodurlo.',
    );
    return '$_temp0';
  }
}
