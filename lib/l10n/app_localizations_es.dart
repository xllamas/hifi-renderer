// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get settingsTooltip => 'Ajustes';

  @override
  String get idleReady => 'Listo — esperando a un controlador';

  @override
  String get idleNoDac => 'Ningún DAC conectado';

  @override
  String get unknownTrack => 'Pista desconocida';

  @override
  String airPlayFromSender(String sender) {
    return 'AirPlay desde $sender';
  }

  @override
  String get previousTrack => 'Pista anterior';

  @override
  String get nextTrack => 'Pista siguiente';

  @override
  String get pause => 'Pausar';

  @override
  String get play => 'Reproducir';

  @override
  String get volumeWriteOnly =>
      'Este DAC no informa de su volumen, así que aquí se muestra el último valor enviado desde la app.';

  @override
  String get systemAudioDetail =>
      'Altavoz o auriculares del teléfono — remuestreado por Android';

  @override
  String dacOneOf(int count) {
    return '(1 de $count)';
  }

  @override
  String get bitPerfect => 'bit perfect';

  @override
  String get systemAudioBadge => 'audio del sistema';

  @override
  String get airPlaySenderResampled => 'AirPlay · remuestreado en origen';

  @override
  String get settingsTitle => 'Ajustes';

  @override
  String get settingsNetworkName => 'Nombre en la red';

  @override
  String get settingsNetworkNameHelp =>
      'Cómo aparece este reproductor en los controladores DLNA.';

  @override
  String get settingsSave => 'Guardar';

  @override
  String get settingsSaved => 'Guardado';

  @override
  String get settingsRenamed =>
      'Renombrado. Reinicia la app para que los controladores lo vean.';

  @override
  String get settingsAudioDevice => 'Dispositivo de audio';

  @override
  String settingsDacsMultiple(int count) {
    return 'Hay $count dispositivos de audio USB conectados. Elige por cuál reproducir; la elección se recuerda entre reinicios.';
  }

  @override
  String get settingsDacsSingle =>
      'Hay un dispositivo de audio USB conectado. Tócalo para reproducir a través de él y para concederle acceso si aún no lo tiene.';

  @override
  String get settingsUsbAudioDevice => 'Dispositivo de audio USB';

  @override
  String get settingsPermissionNotGranted => ' — permiso no concedido';

  @override
  String get settingsReadingDevice => 'Leyendo el dispositivo…';

  @override
  String get settingsProbing => 'Preguntando al DAC qué admite';

  @override
  String settingsUacTap(String version) {
    return 'USB Audio Class $version — toca para ver qué admite';
  }

  @override
  String get settingsConnectToProbe =>
      'Conecta un DAC USB y toca para analizarlo';

  @override
  String get settingsPcmOnly =>
      'Aceptar solo flujos PCM y dejar que el servidor descodifique o convierta';

  @override
  String get settingsPcmOnlyOn =>
      'El reproductor anuncia únicamente LPCM, a las frecuencias que este DAC puede generar, así que el servidor lo convierte todo para que encaje. Todo suena y nada es bit perfect, incluidas las pistas que el DAC podría haber reproducido intactas.';

  @override
  String get settingsPcmOnlyOff =>
      'El reproductor anuncia todos los formatos que sabe descodificar, así que los archivos llegan intactos. Las pistas a frecuencias que este DAC no puede generar se rechazan, indicando el motivo.';

  @override
  String get settingsScreenOffAfter => 'Apagar la pantalla tras';

  @override
  String get settingsScreenOffNever =>
      'La pantalla permanece encendida. No hay problema en un teléfono siempre enchufado, pero un panel OLED mostrando la misma pantalla durante meses acaba con la imagen marcada de forma permanente.';

  @override
  String get settingsScreenOffTimed =>
      'Se cuenta desde que la música para, así que una pista larga nunca apaga la pantalla a mitad de reproducción. Al reanudar, vuelve a encenderse.';

  @override
  String get settingsTimeoutNever => 'Nunca';

  @override
  String settingsTimeoutMinutes(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: '$minutes minutos',
      one: '1 minuto',
    );
    return '$_temp0';
  }

  @override
  String get settingsDacVerification => 'Verificación del DAC';

  @override
  String get settingsDacVerificationSubtitle =>
      'Probar todas las frecuencias que declara este DAC';

  @override
  String get settingsAlwaysOn => 'Siempre activo';

  @override
  String get settingsAlwaysOnHelp =>
      'Un reproductor dedicado tiene que seguir funcionando con la pantalla apagada y volver tras reiniciar. Android y la mayoría de fabricantes lo impiden por defecto.';

  @override
  String settingsDeaths(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Este teléfono ha detenido el reproductor $count veces',
      one: 'Este teléfono ha detenido el reproductor una vez',
    );
    return '$_temp0';
  }

  @override
  String get settingsDeathsDetail =>
      'Cada una es un arranque posterior a una ejecución que nunca registró una parada limpia, así que algo lo mató en segundo plano. Conceder lo de abajo suele resolverlo.';

  @override
  String get settingsBattery => 'Exención de la optimización de batería';

  @override
  String get settingsBatteryGranted =>
      'Concedida — Android no suspenderá el reproductor.';

  @override
  String get settingsBatteryNotGranted =>
      'No concedida. Android puede suspender el reproductor cuando esté inactivo.';

  @override
  String get settingsGrant => 'Conceder';

  @override
  String get settingsOpenSettings => 'Abrir ajustes';

  @override
  String get settingsCouldNotOpen =>
      'No se pudo abrir esa pantalla en este teléfono.';

  @override
  String settingsAutostart(String vendor) {
    return 'Inicio automático ($vendor)';
  }

  @override
  String get settingsAutostartVendorFallback => 'fabricante';

  @override
  String get settingsAutostartDetail =>
      'Los teléfonos de este fabricante suelen añadir sus propias restricciones para apps en segundo plano, aparte de las de Android, y son el motivo habitual de que un reproductor no arranque tras reiniciar. La app no puede detectarlas, solo sabe que este fabricante tiene esa pantalla.';

  @override
  String get settingsWakeScreen => 'Encender la pantalla al empezar la música';

  @override
  String get settingsWakeScreenDetail =>
      'Aquí ha sonado música con la pantalla apagada. Android desactiva el bloqueo de pantalla de una app que no tiene ninguna ventana visible, y este teléfono no dejó que el reproductor mostrara la suya, así que el panel se encendió un instante y volvió a apagarse. El permiso suele llamarse algo así como «Mostrar ventanas emergentes mientras se ejecuta en segundo plano», y es distinto del inicio automático.';

  @override
  String get settingsRunSetup => 'Repetir la configuración';

  @override
  String get settingsRunSetupSubtitle => 'Recorrer los permisos en orden';

  @override
  String get settingsLegal => 'Aviso legal';

  @override
  String get settingsLicenses => 'Licencias de código abierto';

  @override
  String get settingsLicensesSubtitle => 'En qué se basa esta aplicación';

  @override
  String get settingsLicensesLegalese =>
      'Licencia Apache 2.0. Construida sobre trabajos publicados bajo las condiciones LGPL, Apache, CDDL, BSD, CC0 y de dominio público que se enumeran aquí.';

  @override
  String get settingsLanguage => 'Idioma';

  @override
  String get settingsLanguageSystem => 'El mismo que este teléfono';

  @override
  String get settingsLanguageHelp =>
      'El reproductor sigue el idioma de este teléfono salvo que elijas otro. Un equipo configurado en un teléfono de repuesto suele heredar un idioma que nadie quería.';

  @override
  String get onboardingTitle => 'Configurar HiFi Renderer';

  @override
  String get onboardingTitleRerun => 'Configuración';

  @override
  String get onboardingIntro =>
      'Este teléfono va a quedarse en algún sitio haciendo de reproductor. Android y la mayoría de fabricantes dan por hecho que ninguna app quiere eso, así que hay que activar unas cuantas cosas a mano.';

  @override
  String get onboardingOptional =>
      'Nada de esto hace falta para probar la app, y puedes cambiarlo todo después en Ajustes.';

  @override
  String get onboardingNotifications => 'Mostrar una notificación';

  @override
  String get onboardingNotificationsGranted =>
      'Concedido. El reproductor mostrará su notificación mientras funcione.';

  @override
  String get onboardingNotificationsWhy =>
      'Android no deja que el reproductor siga en segundo plano sin ella, y es la única señal visible de que está vivo.';

  @override
  String get onboardingAllow => 'Permitir';

  @override
  String get onboardingNoNotificationScreen =>
      'Este teléfono no tiene una pantalla de ajustes de notificaciones que abrir.';

  @override
  String get onboardingNotificationsInSettings =>
      'Android ha dejado de preguntar — actívalas ahí.';

  @override
  String get onboardingBattery => 'Evitar que Android lo suspenda';

  @override
  String get onboardingBatteryGranted =>
      'Concedido. Android no suspenderá el reproductor cuando esté inactivo.';

  @override
  String get onboardingBatteryWhy =>
      'Sin esto, Android suspende la app cuando la pantalla lleva un rato apagada y la reproducción se corta a mitad de pista.';

  @override
  String get onboardingUsbPrompt => 'Que Android deje de preguntar por el DAC';

  @override
  String get onboardingUsbPromptGranted =>
      'Concedido. La próxima vez que se conecte el DAC, marca «abrir siempre» en el aviso de Android y no volverá a preguntar.';

  @override
  String get onboardingUsbPromptWhy =>
      'Sin permiso de micrófono, Android pregunta si abrir la app cada vez que se enciende el DAC, y no ofrece la opción de dejar de preguntar. Concédelo y marca «abrir siempre» la próxima vez que se conecte el DAC. La app nunca graba nada.';

  @override
  String get onboardingUsbPromptInSettings =>
      'Android ha dejado de preguntar — permite el micrófono en Permisos ahí.';

  @override
  String onboardingVendorKnown(String vendor) {
    return 'Inicio automático ($vendor)';
  }

  @override
  String get onboardingVendorKnownNoName => 'Inicio automático';

  @override
  String get onboardingVendorUnknown =>
      'Las restricciones propias del fabricante de tu teléfono';

  @override
  String get onboardingVendorKnownDetail =>
      'Los teléfonos de este fabricante suelen añadir sus propias restricciones para apps en segundo plano, aparte de las de Android, y son el motivo habitual de que un reproductor no vuelva tras reiniciar. La app no puede detectarlas —solo sabe que este fabricante tiene esa pantalla— ni puede saber si has concedido algo allí, así que este paso nunca se marca.';

  @override
  String get onboardingVendorUnknownDetail =>
      'No conocemos ninguna pantalla de ajustes para este teléfono. Si el reproductor se detiene al quedarse inactivo o no vuelve tras reiniciar, busca «inicio automático», «apps en segundo plano» o «apps protegidas» en los ajustes de batería de tu teléfono.';

  @override
  String get onboardingDac => 'Tu DAC';

  @override
  String get onboardingDacDetail =>
      'Conecta el DAC USB cuando quieras. Android pide permiso la primera vez que se enchufa, así que aquí no hay nada que hacer, y el reproductor se adapta al DAC que esté conectado en lugar de configurarse para uno concreto.';

  @override
  String get onboardingDone => 'Hecho';

  @override
  String get onboardingFinishAnyway => 'Terminar igualmente';

  @override
  String get onboardingAllGranted =>
      'Está concedido todo lo que la app puede comprobar.';

  @override
  String get onboardingSkippingIsFine =>
      'Puedes saltártelo sin problema. El reproductor funcionará; puede que simplemente no sobreviva cuando lo dejes solo, y Ajustes te dirá si algo lo está deteniendo.';

  @override
  String onboardingStep(int number, String title) {
    return '$number. $title';
  }

  @override
  String get dacCapsTitle => 'Capacidades del DAC';

  @override
  String get dacCapsReprobe => 'Volver a analizar';

  @override
  String get dacCapsNotProbed => 'Aún sin analizar';

  @override
  String get dacCapsNotProbedDetail => 'Conecta un DAC USB y toca actualizar.';

  @override
  String get dacCapsUnknownError => 'Error desconocido.';

  @override
  String get dacCapsNoDevice => 'No se encontró ningún DAC';

  @override
  String get dacCapsPermissionNeeded => 'Hace falta permiso';

  @override
  String get dacCapsOpenFailed => 'No se pudo abrir el DAC';

  @override
  String get dacCapsProbeFailed => 'El análisis falló';

  @override
  String get dacCapsNotUsable => 'No sirve para reproducción bit perfect';

  @override
  String get dacCapsWorthKnowing => 'Cosas que conviene saber';

  @override
  String get dacCapsWhatItSupports => 'Qué admite';

  @override
  String dacCapsIdentity(
    String version,
    String speed,
    String vendor,
    String product,
  ) {
    return 'USB Audio Class $version · velocidad $speed · $vendor:$product';
  }

  @override
  String get dacCapsSampleRates => 'Frecuencias de muestreo';

  @override
  String get dacCapsBitDepths => 'Profundidades de bits';

  @override
  String get dacCapsChannels => 'Canales';

  @override
  String get dacCapsCurrentlyAt => 'Funcionando ahora a';

  @override
  String get dacCapsUsbTiming => 'Sincronización USB';

  @override
  String get dacCapsVolumeControl => 'Control de volumen';

  @override
  String get dacCapsDsd => 'DSD';

  @override
  String get dacCapsUnknown => 'Desconocido';

  @override
  String dacCapsRateRange(String low, String high, int count) {
    return '$low – $high ($count frecuencias)';
  }

  @override
  String dacCapsBitDepth(int bits) {
    return '$bits bits';
  }

  @override
  String get dacCapsAsync => 'Asíncrono (reloj del DAC)';

  @override
  String get dacCapsSync => 'Síncrono';

  @override
  String get dacCapsVolumeOverUsb => 'Admitido por USB';

  @override
  String get dacCapsVolumeDeviceOnly => 'Solo en el propio aparato';

  @override
  String get dacCapsDsdSupported => 'Admitido por el hardware';

  @override
  String get dacCapsTechnical => 'Detalles técnicos';

  @override
  String get dacCapsTechnicalSubtitle => 'Para informes de soporte';

  @override
  String dacCapsKhz(String value) {
    return '$value kHz';
  }

  @override
  String get noteCannotPlayTitle =>
      'Este dispositivo no puede reproducir audio';

  @override
  String get noteCannotPlayDetail =>
      'Se anuncia como clase de audio USB pero no ofrece salida PCM por un endpoint isócrono. Los dispositivos de solo captura tienen este aspecto: un micrófono USB, o la mitad de grabación de un adaptador de auriculares.';

  @override
  String get noteUac1Title => 'Este dispositivo usa USB Audio Class 1.0';

  @override
  String get noteUac1Detail =>
      'Compatible, con los límites que impone la propia clase: el USB full-speed limita el ancho de banda, así que los dispositivos UAC1 se quedan muy por debajo de lo que ofrece un DAC UAC2. La reproducción sigue siendo bit perfect a las frecuencias que sí admite; no se remuestrea nada.';

  @override
  String get noteAdaptiveTitle =>
      'Este dispositivo sigue el reloj del teléfono';

  @override
  String get noteAdaptiveDetail =>
      'Su endpoint es adaptativo en lugar de asíncrono, así que se adapta a la frecuencia que envía el teléfono en vez de usar su propio reloj y pedirle al teléfono que lo siga. Es habitual en hardware UAC1. Las muestras siguen llegando intactas; lo único que cambia es de quién es la referencia de tiempo.';

  @override
  String get noteVolumeDeviceTitle =>
      'El volumen lo controla el DAC, no esta app';

  @override
  String get noteVolumeOneWayDetail =>
      'Este dispositivo no expone ningún control de volumen por USB. Sí comunica al teléfono su propia rueda o su mando, pero eso va en un solo sentido: nada enviado desde aquí puede cambiar su volumen. Usa el control físico.';

  @override
  String get noteVolumeNoneDetail =>
      'Este dispositivo no expone ningún control de volumen por USB, así que las órdenes de volumen de un controlador DLNA no pueden llegarle. Usa el control físico.';

  @override
  String get noteVolumeAppTitle => 'El volumen se puede ajustar desde esta app';

  @override
  String noteVolumeAppDetail(String detail) {
    return 'El DAC expone un control de volumen por USB ($detail), así que las órdenes de volumen DLNA llegan directamente al hardware.';
  }

  @override
  String notePaddedTitle(int bits) {
    return 'Las pistas de 16 bits se rellenan a $bits bits';
  }

  @override
  String notePaddedDetail(int bits) {
    return 'Este DAC no ofrece modo de 16 bits, así que los archivos con resolución de CD se colocan en un contenedor de $bits bits. Los valores de las muestras no cambian, así que la reproducción sigue siendo bit perfect.';
  }

  @override
  String get noteAsyncGoodTitle => 'USB asíncrono con reloj propio';

  @override
  String get noteAsyncGoodDetail =>
      'El DAC marca el tiempo en lugar de seguir al teléfono, que es la mejor disposición para la calidad de sonido.';

  @override
  String get noteAsyncNoFeedbackTitle =>
      'Asíncrono, pero sin endpoint de realimentación';

  @override
  String get noteAsyncNoFeedbackDetail =>
      'El tiempo no se puede seguir con precisión, así que en reproducciones largas son posibles cortes ocasionales.';

  @override
  String get noteDsdTitle => 'Compatible con DSD';

  @override
  String get noteDsdDetail =>
      'Este DAC acepta DSD nativo. La app todavía no reproduce DSD.';

  @override
  String get noteAltConfigTitle => 'Hay otro modo USB disponible';

  @override
  String noteAltConfigDetail(int count) {
    return 'El dispositivo ofrece $count configuraciones USB. Solo se usa la activa; algunos DAC guardan un modo de compatibilidad en la otra.';
  }

  @override
  String get noteClockErrorTitle =>
      'No se pudieron leer las frecuencias admitidas';

  @override
  String get reportCopied => 'Informe copiado';

  @override
  String get copyReport => 'Copiar informe';

  @override
  String get stop => 'Parar';

  @override
  String get notReported => 'sin datos';

  @override
  String get verifyTitle => 'Verificación del DAC';

  @override
  String get verifyResults => 'Resultados';

  @override
  String get verifyFollow => 'Seguir';

  @override
  String get soakTitle => 'Prueba de resistencia';

  @override
  String get soakRate => 'Frecuencia';

  @override
  String get soakLength => 'Duración';

  @override
  String soakStart(String rate, String duration) {
    return 'Probar a $rate durante $duration';
  }

  @override
  String soakProgress(String elapsed, String planned, String step) {
    return '$elapsed de $planned  ·  $step';
  }

  @override
  String get soakFaults => 'Fallos';

  @override
  String get soakRingFill => 'Llenado del búfer';

  @override
  String get soakMeasuredRate => 'Frecuencia medida';

  @override
  String get soakUnderruns => 'Underruns';

  @override
  String get soakTransferErrors => 'Errores de transferencia';

  @override
  String get soakPacketErrors => 'Errores de paquete';

  @override
  String get soakRebuffers => 'Rellenados del búfer';

  @override
  String get soakWorstRingFill => 'Llenado mínimo del búfer';

  @override
  String get soakWorstDeviation => 'Desviación máxima';

  @override
  String get soakDriftSpread => 'Margen de deriva';

  @override
  String get soakMeetsBar =>
      'Supera el listón de diez minutos sin un solo corte.';

  @override
  String get soakShortOfBar =>
      'No llega a los diez minutos, así que todavía no dice nada sobre los fallos que solo aparecen cuando el equipo se calienta.';

  @override
  String get playFileTitle => 'Reproducir un archivo';

  @override
  String get playFileIntro =>
      'Reproduce uno de tus propios archivos a través del DAC y vigila el flujo, que es justo lo que las pruebas de tono no pueden preguntar: si el material que de verdad tienes suena sin problemas. Solo se prueban las frecuencias que ese material contiene.';

  @override
  String get playFileChoose => 'Elegir un archivo';

  @override
  String get playFileFormats =>
      'FLAC, WAV, AIFF, MP3 y cualquier otro formato que el motor sepa descodificar.';

  @override
  String get playFileCache => 'Copiados a la caché de la app';

  @override
  String get playFileCacheDetail =>
      'El banco de pruebas M2. Solo WAV, y la forma más rápida de poner un archivo conocido en un teléfono que estás depurando por adb.';

  @override
  String get playFileStreamHealth => 'Estado del flujo';

  @override
  String get errServerUnreachable =>
      'El reproductor perdió el contacto con el servidor multimedia.';

  @override
  String get errServerRefused => 'El servidor multimedia rechazó esta pista.';

  @override
  String get errDownloadFailed =>
      'No se pudo descargar esta pista del servidor.';

  @override
  String get errUndecodableFormat =>
      'Esta pista está en un formato que el reproductor no sabe descodificar.';

  @override
  String get errDacRateUnsupported =>
      'Este DAC no admite la frecuencia o la profundidad de bits de esta pista.';

  @override
  String get errDacConnectionLost =>
      'El reproductor perdió la conexión con el DAC.';

  @override
  String get errTrackCouldNotBePlayed => 'No se pudo reproducir esta pista.';

  @override
  String errRateUnplayable(String rate, String ceiling) {
    return 'Este DAC no puede reproducir a $rate; su frecuencia máxima es $ceiling.';
  }

  @override
  String errStoppedAfterFailures(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Parado tras no poder reproducir $count pistas seguidas.',
    );
    return '$_temp0';
  }
}
