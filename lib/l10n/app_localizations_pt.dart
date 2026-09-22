// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Portuguese (`pt`).
class AppLocalizationsPt extends AppLocalizations {
  AppLocalizationsPt([String locale = 'pt']) : super(locale);

  @override
  String get settingsTooltip => 'Definições';

  @override
  String get idleReady => 'Pronto — à espera de um controlador';

  @override
  String get idleNoDac => 'Nenhum DAC ligado';

  @override
  String get unknownTrack => 'Faixa desconhecida';

  @override
  String airPlayFromSender(String sender) {
    return 'AirPlay de $sender';
  }

  @override
  String get previousTrack => 'Faixa anterior';

  @override
  String get nextTrack => 'Faixa seguinte';

  @override
  String get pause => 'Pausa';

  @override
  String get play => 'Reproduzir';

  @override
  String get volumeWriteOnly =>
      'Este DAC não comunica o seu próprio volume, pelo que aqui aparece o último valor enviado pela aplicação.';

  @override
  String get systemAudioDetail =>
      'Altifalante ou auscultadores do telemóvel — reamostrado pelo Android';

  @override
  String dacOneOf(int count) {
    return '(1 de $count)';
  }

  @override
  String get bitPerfect => 'bit-perfect';

  @override
  String get systemAudioBadge => 'áudio do sistema';

  @override
  String get airPlaySenderResampled => 'AirPlay · reamostrado na origem';

  @override
  String get settingsTitle => 'Definições';

  @override
  String get settingsNetworkName => 'Nome na rede';

  @override
  String get settingsNetworkNameHelp =>
      'Como este reprodutor aparece nos controladores DLNA.';

  @override
  String get settingsSave => 'Guardar';

  @override
  String get settingsSaved => 'Guardado';

  @override
  String get settingsRenamed =>
      'Renomeado. Reinicie a aplicação para que os controladores vejam o novo nome.';

  @override
  String get settingsAudioDevice => 'Dispositivo de áudio';

  @override
  String settingsDacsMultiple(int count) {
    return 'Estão ligados $count dispositivos de áudio USB. Escolha por qual reproduzir; a escolha é mantida entre reinícios.';
  }

  @override
  String get settingsDacsSingle =>
      'Está ligado um dispositivo de áudio USB. Toque nele para reproduzir através dele e para lhe conceder acesso, caso ainda não o tenha.';

  @override
  String get settingsUsbAudioDevice => 'Dispositivo de áudio USB';

  @override
  String get settingsPermissionNotGranted => ' — permissão não concedida';

  @override
  String get settingsReadingDevice => 'A ler o dispositivo…';

  @override
  String get settingsProbing => 'A perguntar ao DAC o que suporta';

  @override
  String settingsUacTap(String version) {
    return 'USB Audio Class $version — toque para ver o que suporta';
  }

  @override
  String get settingsConnectToProbe => 'Ligue um DAC USB e toque para analisar';

  @override
  String get settingsPcmOnly =>
      'Aceitar apenas fluxos PCM e deixar o servidor descodificar ou converter';

  @override
  String get settingsPcmOnlyOn =>
      'O reprodutor anuncia apenas LPCM, nas frequências que este DAC consegue gerar, pelo que o servidor converte tudo para caber. Tudo se ouve e nada é bit-perfect — incluindo faixas que o DAC poderia ter reproduzido intactas.';

  @override
  String get settingsPcmOnlyOff =>
      'O reprodutor anuncia todos os formatos que sabe descodificar, pelo que os ficheiros chegam intactos. As faixas em frequências que este DAC não consegue gerar são recusadas, indicando o motivo.';

  @override
  String get settingsScreenOffAfter => 'Desligar o ecrã após';

  @override
  String get settingsScreenOffNever =>
      'O ecrã fica sempre aceso. Não há problema num telemóvel permanentemente ligado à corrente, mas um painel OLED a mostrar o mesmo ecrã durante meses acaba por o reter de forma permanente.';

  @override
  String get settingsScreenOffTimed =>
      'Contado a partir do fim da música — uma faixa longa nunca apaga o ecrã a meio. A reprodução volta a acendê-lo.';

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
  String get settingsDacVerification => 'Verificação do DAC';

  @override
  String get settingsDacVerificationSubtitle =>
      'Testar todas as frequências que este DAC declara';

  @override
  String get settingsAlwaysOn => 'Sempre ativo';

  @override
  String get settingsAlwaysOnHelp =>
      'Um reprodutor dedicado tem de continuar a funcionar com o ecrã apagado e voltar depois de reiniciar. O Android e a maioria dos fabricantes bloqueiam isso por predefinição.';

  @override
  String settingsDeaths(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Este telemóvel já parou o reprodutor $count vezes',
      one: 'Este telemóvel já parou o reprodutor uma vez',
    );
    return '$_temp0';
  }

  @override
  String get settingsDeathsDetail =>
      'Cada uma é um arranque logo a seguir a uma execução que nunca registou uma paragem limpa, ou seja, algo o terminou em segundo plano. Conceder o que está abaixo costuma resolver.';

  @override
  String get settingsBattery => 'Isenção da otimização da bateria';

  @override
  String get settingsBatteryGranted =>
      'Concedida — o Android não vai suspender o reprodutor.';

  @override
  String get settingsBatteryNotGranted =>
      'Não concedida. O Android pode suspender o reprodutor quando estiver inativo.';

  @override
  String get settingsGrant => 'Conceder';

  @override
  String get settingsOpenSettings => 'Abrir definições';

  @override
  String get settingsCouldNotOpen =>
      'Não foi possível abrir esse ecrã neste telemóvel.';

  @override
  String settingsAutostart(String vendor) {
    return 'Arranque automático ($vendor)';
  }

  @override
  String get settingsAutostartVendorFallback => 'fabricante';

  @override
  String get settingsAutostartDetail =>
      'Os telemóveis deste fabricante costumam acrescentar restrições próprias para aplicações em segundo plano, distintas das do Android, e são o motivo habitual para um reprodutor não arrancar depois de reiniciar. A aplicação não as consegue detetar, sabe apenas que este fabricante tem um ecrã desse género.';

  @override
  String get settingsWakeScreen => 'Acender o ecrã quando a música começar';

  @override
  String get settingsWakeScreenDetail =>
      'Já se ouviu música aqui com o ecrã apagado. O Android desativa a retenção do ecrã pedida por uma aplicação sem janela visível, e este telemóvel não deixou o reprodutor mostrar a sua própria janela, pelo que o painel acendeu por instantes e voltou a adormecer. A permissão costuma chamar-se algo como «Mostrar janelas pop-up enquanto é executada em segundo plano», e é distinta do arranque automático.';

  @override
  String get settingsRunSetup => 'Repetir a configuração';

  @override
  String get settingsRunSetupSubtitle => 'Percorrer as permissões por ordem';

  @override
  String get settingsLegal => 'Informação legal';

  @override
  String get settingsLicenses => 'Licenças de código aberto';

  @override
  String get settingsLicensesSubtitle => 'Aquilo em que esta aplicação assenta';

  @override
  String get settingsLicensesLegalese =>
      'Licença Apache 2.0. Construída sobre trabalhos publicados ao abrigo dos termos LGPL, Apache, CDDL, BSD, CC0 e de domínio público aqui listados.';

  @override
  String get settingsLanguage => 'Idioma';

  @override
  String get settingsLanguageSystem => 'O mesmo deste telemóvel';

  @override
  String get settingsLanguageHelp =>
      'O reprodutor segue este telemóvel a não ser que escolha outro. Um aparelho configurado num telemóvel sobresselente herda muitas vezes um idioma que ninguém queria.';

  @override
  String get onboardingTitle => 'Configurar o HiFi Renderer';

  @override
  String get onboardingTitleRerun => 'Configuração';

  @override
  String get onboardingIntro =>
      'Este telemóvel vai ficar algures a servir de reprodutor de rede. O Android e a maioria dos fabricantes partem do princípio de que nenhuma aplicação quer isso, pelo que há algumas coisas a ativar à mão.';

  @override
  String get onboardingOptional =>
      'Nada disto é necessário para experimentar a aplicação, e pode alterar tudo mais tarde nas Definições.';

  @override
  String get onboardingNotifications => 'Mostrar uma notificação';

  @override
  String get onboardingNotificationsGranted =>
      'Concedido. O reprodutor mostrará a sua notificação enquanto estiver a funcionar.';

  @override
  String get onboardingNotificationsWhy =>
      'Sem ela o Android não deixa o reprodutor continuar em segundo plano, e é o único sinal visível de que está vivo.';

  @override
  String get onboardingAllow => 'Permitir';

  @override
  String get onboardingNoNotificationScreen =>
      'Este telemóvel não tem um ecrã de definições de notificações para abrir.';

  @override
  String get onboardingNotificationsInSettings =>
      'O Android deixou de perguntar — ative-as aí.';

  @override
  String get onboardingBattery => 'Impedir que o Android o suspenda';

  @override
  String get onboardingBatteryGranted =>
      'Concedido. O Android não vai suspender o reprodutor quando estiver inativo.';

  @override
  String get onboardingBatteryWhy =>
      'Sem isto, o Android suspende a aplicação quando o ecrã está apagado há algum tempo, e a reprodução para a meio da faixa.';

  @override
  String get onboardingUsbPrompt => 'Impedir que o Android pergunte pelo DAC';

  @override
  String get onboardingUsbPromptGranted =>
      'Concedido. Da próxima vez que o DAC se ligar, assinale «abrir sempre» no aviso do Android e ele deixa de perguntar.';

  @override
  String get onboardingUsbPromptWhy =>
      'Sem a permissão do microfone, o Android pergunta se deve abrir a app sempre que o DAC é ligado, e não oferece a opção de deixar de perguntar. Conceda-a e assinale «abrir sempre» da próxima vez que o DAC se ligar. A app nunca grava nada.';

  @override
  String get onboardingUsbPromptInSettings =>
      'O Android deixou de perguntar — permita o microfone em Autorizações aí.';

  @override
  String onboardingVendorKnown(String vendor) {
    return 'Arranque automático ($vendor)';
  }

  @override
  String get onboardingVendorKnownNoName => 'Arranque automático';

  @override
  String get onboardingVendorUnknown =>
      'As restrições próprias do fabricante do seu telemóvel';

  @override
  String get onboardingVendorKnownDetail =>
      'Os telemóveis deste fabricante costumam acrescentar restrições próprias para aplicações em segundo plano, distintas das do Android, e são o motivo habitual para um reprodutor não voltar depois de reiniciar. A aplicação não as consegue detetar — sabe apenas que este fabricante tem um ecrã desse género — nem consegue saber se concedeu ali alguma coisa, pelo que este passo nunca fica assinalado.';

  @override
  String get onboardingVendorUnknownDetail =>
      'Não conhecemos nenhum ecrã de definições para este telemóvel. Se o reprodutor parar quando está inativo ou não voltar depois de reiniciar, procure «arranque automático», «aplicações em segundo plano» ou «aplicações protegidas» nas definições de bateria do seu telemóvel.';

  @override
  String get onboardingDac => 'O seu DAC';

  @override
  String get onboardingDacDetail =>
      'Ligue o DAC USB quando quiser. O Android pede permissão ao ligá-lo — assinale «abrir sempre» nesse aviso e deixa de perguntar — e o reprodutor adapta-se ao DAC que estiver ligado, em vez de ser configurado para um em particular.';

  @override
  String get onboardingDone => 'Concluído';

  @override
  String get onboardingFinishAnyway => 'Concluir mesmo assim';

  @override
  String get onboardingAllGranted =>
      'Está concedido tudo o que a aplicação consegue verificar.';

  @override
  String get onboardingSkippingIsFine =>
      'Pode saltar sem problema. O reprodutor vai funcionar; pode apenas não sobreviver quando for deixado sozinho, e as Definições dir-lhe-ão se algo o estiver a parar.';

  @override
  String onboardingStep(int number, String title) {
    return '$number. $title';
  }

  @override
  String get dacCapsTitle => 'Capacidades do DAC';

  @override
  String get dacCapsReprobe => 'Analisar de novo';

  @override
  String get dacCapsNotProbed => 'Ainda não analisado';

  @override
  String get dacCapsNotProbedDetail => 'Ligue um DAC USB e toque em atualizar.';

  @override
  String get dacCapsUnknownError => 'Erro desconhecido.';

  @override
  String get dacCapsNoDevice => 'Nenhum DAC encontrado';

  @override
  String get dacCapsPermissionNeeded => 'É necessária permissão';

  @override
  String get dacCapsOpenFailed => 'Não foi possível abrir o DAC';

  @override
  String get dacCapsProbeFailed => 'A análise falhou';

  @override
  String get dacCapsNotUsable => 'Não serve para reprodução bit-perfect';

  @override
  String get dacCapsWorthKnowing => 'O que vale a pena saber';

  @override
  String get dacCapsWhatItSupports => 'O que suporta';

  @override
  String dacCapsIdentity(
    String version,
    String speed,
    String vendor,
    String product,
  ) {
    return 'USB Audio Class $version · velocidade $speed · $vendor:$product';
  }

  @override
  String get dacCapsSampleRates => 'Frequências de amostragem';

  @override
  String get dacCapsBitDepths => 'Profundidades de bits';

  @override
  String get dacCapsChannels => 'Canais';

  @override
  String get dacCapsCurrentlyAt => 'A funcionar agora a';

  @override
  String get dacCapsUsbTiming => 'Sincronismo USB';

  @override
  String get dacCapsVolumeControl => 'Controlo de volume';

  @override
  String get dacCapsDsd => 'DSD';

  @override
  String get dacCapsUnknown => 'Desconhecido';

  @override
  String dacCapsRateRange(String low, String high, int count) {
    return '$low – $high ($count frequências)';
  }

  @override
  String dacCapsBitDepth(int bits) {
    return '$bits bits';
  }

  @override
  String get dacCapsAsync => 'Assíncrono (relógio do DAC)';

  @override
  String get dacCapsSync => 'Síncrono';

  @override
  String get dacCapsVolumeOverUsb => 'Suportado por USB';

  @override
  String get dacCapsVolumeDeviceOnly => 'Apenas no próprio aparelho';

  @override
  String get dacCapsDsdSupported => 'Suportado pelo hardware';

  @override
  String get dacCapsTechnical => 'Detalhes técnicos';

  @override
  String get dacCapsTechnicalSubtitle => 'Para relatórios de apoio';

  @override
  String dacCapsKhz(String value) {
    return '$value kHz';
  }

  @override
  String get noteCannotPlayTitle =>
      'Este dispositivo não consegue reproduzir áudio';

  @override
  String get noteCannotPlayDetail =>
      'Anuncia-se como classe de áudio USB, mas não oferece qualquer saída PCM num endpoint isócrono. Os dispositivos só de captura têm este aspeto: um microfone USB, ou a metade de gravação de um adaptador de auscultadores.';

  @override
  String get noteUac1Title => 'Este dispositivo usa USB Audio Class 1.0';

  @override
  String get noteUac1Detail =>
      'Suportado, com os limites que a própria classe impõe: o USB full-speed limita a largura de banda, pelo que os dispositivos UAC1 ficam bastante abaixo do que um DAC UAC2 oferece. Nas frequências que suporta, a reprodução continua bit-perfect — nada é reamostrado.';

  @override
  String get noteAdaptiveTitle =>
      'Este dispositivo segue o relógio do telemóvel';

  @override
  String get noteAdaptiveDetail =>
      'O seu endpoint é adaptativo em vez de assíncrono, pelo que se ajusta à frequência que o telemóvel envia, em vez de usar o seu próprio relógio e pedir ao telemóvel que o siga. É comum em hardware UAC1. As amostras continuam a chegar intactas; muda apenas de que lado está a referência temporal.';

  @override
  String get noteVolumeDeviceTitle =>
      'O volume é controlado pelo DAC, não por esta aplicação';

  @override
  String get noteVolumeOneWayDetail =>
      'Este dispositivo não expõe qualquer controlo de volume por USB. Comunica ao telemóvel o seu próprio botão ou telecomando, mas isso é num só sentido: nada enviado daqui altera o seu volume. Use o controlo físico.';

  @override
  String get noteVolumeNoneDetail =>
      'Este dispositivo não expõe qualquer controlo de volume por USB, pelo que os comandos de volume de um controlador DLNA não lhe chegam. Use o controlo físico.';

  @override
  String get noteVolumeAppTitle =>
      'O volume pode ser ajustado a partir desta aplicação';

  @override
  String noteVolumeAppDetail(String detail) {
    return 'O DAC expõe um controlo de volume por USB ($detail), pelo que os comandos de volume DLNA são passados diretamente ao hardware.';
  }

  @override
  String notePaddedTitle(int bits) {
    return 'As faixas de 16 bits são preenchidas para $bits bits';
  }

  @override
  String notePaddedDetail(int bits) {
    return 'Este DAC não tem modo de 16 bits, pelo que os ficheiros em resolução de CD são colocados num contentor de $bits bits. Os valores das amostras não mudam, pelo que a reprodução continua bit-perfect.';
  }

  @override
  String get noteAsyncGoodTitle => 'USB assíncrono com relógio próprio';

  @override
  String get noteAsyncGoodDetail =>
      'É o DAC que dita o tempo, em vez de seguir o telemóvel, o que é a melhor disposição para a qualidade do som.';

  @override
  String get noteAsyncNoFeedbackTitle =>
      'Assíncrono, mas não foi encontrado endpoint de retorno';

  @override
  String get noteAsyncNoFeedbackDetail =>
      'O sincronismo não pode ser seguido com precisão, pelo que são possíveis cortes ocasionais em reproduções longas.';

  @override
  String get noteDsdTitle => 'Compatível com DSD';

  @override
  String get noteDsdDetail =>
      'Este DAC aceita DSD nativo. A aplicação ainda não reproduz DSD.';

  @override
  String get noteAltConfigTitle => 'Está disponível outro modo USB';

  @override
  String noteAltConfigDetail(int count) {
    return 'O dispositivo oferece $count configurações USB. Só a ativa é usada; alguns DAC guardam um modo de compatibilidade na outra.';
  }

  @override
  String get noteClockErrorTitle =>
      'Não foi possível ler as frequências suportadas';

  @override
  String get reportCopied => 'Relatório copiado';

  @override
  String get copyReport => 'Copiar relatório';

  @override
  String get stop => 'Parar';

  @override
  String get notReported => 'não comunicado';

  @override
  String get verifyTitle => 'Verificação do DAC';

  @override
  String get verifyResults => 'Resultados';

  @override
  String get verifyFollow => 'Acompanhar';

  @override
  String get soakTitle => 'Teste de resistência';

  @override
  String get soakRate => 'Frequência';

  @override
  String get soakLength => 'Duração';

  @override
  String soakStart(String rate, String duration) {
    return 'Testar a $rate durante $duration';
  }

  @override
  String soakProgress(String elapsed, String planned, String step) {
    return '$elapsed de $planned  ·  $step';
  }

  @override
  String get soakFaults => 'Falhas';

  @override
  String get soakRingFill => 'Ocupação do buffer';

  @override
  String get soakMeasuredRate => 'Frequência medida';

  @override
  String get soakUnderruns => 'Underruns';

  @override
  String get soakTransferErrors => 'Erros de transferência';

  @override
  String get soakPacketErrors => 'Erros de pacote';

  @override
  String get soakRebuffers => 'Novos enchimentos do buffer';

  @override
  String get soakWorstRingFill => 'Ocupação mínima do buffer';

  @override
  String get soakWorstDeviation => 'Maior desvio';

  @override
  String get soakDriftSpread => 'Amplitude da deriva';

  @override
  String get soakMeetsBar =>
      'Passa a fasquia dos dez minutos sem um único corte.';

  @override
  String get soakShortOfBar =>
      'Abaixo dos dez minutos, pelo que ainda nada diz sobre as falhas que só aparecem depois de o hardware aquecer.';

  @override
  String get playFileTitle => 'Reproduzir um ficheiro';

  @override
  String get playFileIntro =>
      'Reproduz um ficheiro seu através do DAC e vigia o fluxo, que é a pergunta que os testes de tom não conseguem fazer: se o material que realmente possui se ouve sem falhas. Só são testadas as frequências presentes nesse material.';

  @override
  String get playFileChoose => 'Escolher um ficheiro';

  @override
  String get playFileFormats =>
      'FLAC, WAV, AIFF, MP3 e qualquer outro formato que o motor saiba descodificar.';

  @override
  String get playFileCache => 'Copiados para a cache da aplicação';

  @override
  String get playFileCacheDetail =>
      'A bancada M2. Apenas WAV, e a forma mais rápida de pôr um ficheiro conhecido num telemóvel que está a depurar por adb.';

  @override
  String get playFileStreamHealth => 'Estado do fluxo';

  @override
  String get errServerUnreachable =>
      'O reprodutor perdeu o contacto com o servidor multimédia.';

  @override
  String get errServerRefused => 'O servidor multimédia recusou esta faixa.';

  @override
  String get errDownloadFailed =>
      'Não foi possível transferir esta faixa do servidor.';

  @override
  String get errUndecodableFormat =>
      'Esta faixa está num formato que o reprodutor não sabe descodificar.';

  @override
  String get errDacRateUnsupported =>
      'Este DAC não pode ser configurado para a frequência ou a profundidade de bits desta faixa.';

  @override
  String get errDacConnectionLost => 'O reprodutor perdeu a ligação ao DAC.';

  @override
  String get errTrackCouldNotBePlayed =>
      'Não foi possível reproduzir esta faixa.';

  @override
  String errRateUnplayable(String rate, String ceiling) {
    return 'Este DAC não consegue reproduzir a $rate; a sua frequência máxima é $ceiling.';
  }

  @override
  String errStoppedAfterFailures(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Parado depois de $count faixas seguidas não terem podido ser reproduzidas.',
    );
    return '$_temp0';
  }
}

/// The translations for Portuguese, as used in Brazil (`pt_BR`).
class AppLocalizationsPtBr extends AppLocalizationsPt {
  AppLocalizationsPtBr() : super('pt_BR');

  @override
  String get settingsTooltip => 'Configurações';

  @override
  String get idleReady => 'Pronto — aguardando um controlador';

  @override
  String get idleNoDac => 'Nenhum DAC conectado';

  @override
  String get unknownTrack => 'Faixa desconhecida';

  @override
  String airPlayFromSender(String sender) {
    return 'AirPlay de $sender';
  }

  @override
  String get previousTrack => 'Faixa anterior';

  @override
  String get nextTrack => 'Próxima faixa';

  @override
  String get pause => 'Pausar';

  @override
  String get play => 'Tocar';

  @override
  String get volumeWriteOnly =>
      'Este DAC não informa o próprio volume, então o que aparece aqui é o último valor enviado pelo app.';

  @override
  String get systemAudioDetail =>
      'Alto-falante ou fones do celular — reamostrado pelo Android';

  @override
  String dacOneOf(int count) {
    return '(1 de $count)';
  }

  @override
  String get bitPerfect => 'bit-perfect';

  @override
  String get systemAudioBadge => 'áudio do sistema';

  @override
  String get airPlaySenderResampled => 'AirPlay · reamostrado na origem';

  @override
  String get settingsTitle => 'Configurações';

  @override
  String get settingsNetworkName => 'Nome na rede';

  @override
  String get settingsNetworkNameHelp =>
      'Como este renderizador aparece nos controladores DLNA.';

  @override
  String get settingsSave => 'Salvar';

  @override
  String get settingsSaved => 'Salvo';

  @override
  String get settingsRenamed =>
      'Renomeado. Reinicie o app para os controladores verem o novo nome.';

  @override
  String get settingsAudioDevice => 'Dispositivo de áudio';

  @override
  String settingsDacsMultiple(int count) {
    return 'Há $count dispositivos de áudio USB conectados. Escolha por qual tocar; a escolha é lembrada entre reinicializações.';
  }

  @override
  String get settingsDacsSingle =>
      'Há um dispositivo de áudio USB conectado. Toque nele para tocar por ele e para conceder acesso, se ainda não tiver sido concedido.';

  @override
  String get settingsUsbAudioDevice => 'Dispositivo de áudio USB';

  @override
  String get settingsPermissionNotGranted => ' — permissão não concedida';

  @override
  String get settingsReadingDevice => 'Lendo o dispositivo…';

  @override
  String get settingsProbing => 'Perguntando ao DAC o que ele aceita';

  @override
  String settingsUacTap(String version) {
    return 'USB Audio Class $version — toque para ver o que ele aceita';
  }

  @override
  String get settingsConnectToProbe =>
      'Conecte um DAC USB e toque para analisar';

  @override
  String get settingsPcmOnly =>
      'Aceitar apenas fluxos PCM e deixar o servidor decodificar ou converter';

  @override
  String get settingsPcmOnlyOn =>
      'O renderizador anuncia somente LPCM, nas taxas que este DAC consegue gerar, então o servidor converte tudo para caber. Tudo toca e nada é bit-perfect — inclusive faixas que o DAC poderia ter tocado intactas.';

  @override
  String get settingsPcmOnlyOff =>
      'O renderizador anuncia todos os formatos que sabe decodificar, então os arquivos chegam intactos. Faixas em taxas que este DAC não consegue gerar são recusadas, com o motivo à vista.';

  @override
  String get settingsScreenOffAfter => 'Desligar a tela após';

  @override
  String get settingsScreenOffNever =>
      'A tela fica sempre acesa. Tudo bem num celular permanentemente na tomada, mas um painel OLED mostrando a mesma tela por meses acaba guardando essa imagem para sempre.';

  @override
  String get settingsScreenOffTimed =>
      'Contado a partir do fim da música — uma faixa longa nunca apaga a tela no meio. Ao voltar a tocar, ela acende de novo.';

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
  String get settingsDacVerification => 'Verificação do DAC';

  @override
  String get settingsDacVerificationSubtitle =>
      'Testar todas as taxas que este DAC declara';

  @override
  String get settingsAlwaysOn => 'Sempre ativo';

  @override
  String get settingsAlwaysOnHelp =>
      'Um renderizador dedicado precisa continuar rodando com a tela apagada e voltar depois de reiniciar. O Android e a maioria dos fabricantes bloqueiam isso por padrão.';

  @override
  String settingsDeaths(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Este celular já parou o renderizador $count vezes',
      one: 'Este celular já parou o renderizador uma vez',
    );
    return '$_temp0';
  }

  @override
  String get settingsDeathsDetail =>
      'Cada uma é uma inicialização logo depois de uma execução que nunca registrou uma parada limpa, ou seja, algo o encerrou em segundo plano. Conceder o que está abaixo costuma resolver.';

  @override
  String get settingsBattery => 'Isenção da otimização de bateria';

  @override
  String get settingsBatteryGranted =>
      'Concedida — o Android não vai suspender o renderizador.';

  @override
  String get settingsBatteryNotGranted =>
      'Não concedida. O Android pode suspender o renderizador quando estiver ocioso.';

  @override
  String get settingsGrant => 'Conceder';

  @override
  String get settingsOpenSettings => 'Abrir configurações';

  @override
  String get settingsCouldNotOpen =>
      'Não foi possível abrir essa tela neste celular.';

  @override
  String settingsAutostart(String vendor) {
    return 'Inicialização automática ($vendor)';
  }

  @override
  String get settingsAutostartVendorFallback => 'fabricante';

  @override
  String get settingsAutostartDetail =>
      'Celulares deste fabricante costumam adicionar restrições próprias para apps em segundo plano, separadas das do Android, e são o motivo mais comum de um renderizador não iniciar depois de reiniciar. O app não consegue detectá-las, sabe apenas que este fabricante tem uma tela desse tipo.';

  @override
  String get settingsWakeScreen => 'Acender a tela quando a música começar';

  @override
  String get settingsWakeScreenDetail =>
      'Já tocou música aqui com a tela apagada. O Android desliga a retenção de tela de um app sem janela visível, e este celular não deixou o renderizador abrir a própria janela, então o painel acendeu por um instante e voltou a dormir. A permissão costuma se chamar algo como «Mostrar janelas pop-up enquanto executa em segundo plano», e é diferente da inicialização automática.';

  @override
  String get settingsRunSetup => 'Refazer a configuração';

  @override
  String get settingsRunSetupSubtitle => 'Percorrer as permissões em ordem';

  @override
  String get settingsLegal => 'Informações legais';

  @override
  String get settingsLicenses => 'Licenças de código aberto';

  @override
  String get settingsLicensesSubtitle => 'Em que este app se baseia';

  @override
  String get settingsLicensesLegalese =>
      'Licença Apache 2.0. Construído sobre trabalhos publicados sob os termos LGPL, Apache, CDDL, BSD, CC0 e de domínio público listados aqui.';

  @override
  String get settingsLanguage => 'Idioma';

  @override
  String get settingsLanguageSystem => 'O mesmo deste celular';

  @override
  String get settingsLanguageHelp =>
      'O renderizador segue este celular, a menos que você escolha outro. Um aparelho configurado num celular reserva costuma herdar um idioma que ninguém queria.';

  @override
  String get onboardingTitle => 'Configurar o HiFi Renderer';

  @override
  String get onboardingTitleRerun => 'Configuração';

  @override
  String get onboardingIntro =>
      'Este celular vai ficar parado em algum lugar funcionando como renderizador. O Android e a maioria dos fabricantes partem do princípio de que nenhum app quer isso, então algumas coisas precisam ser ligadas na mão.';

  @override
  String get onboardingOptional =>
      'Nada disso é obrigatório para experimentar o app, e você pode mudar tudo depois nas Configurações.';

  @override
  String get onboardingNotifications => 'Mostrar uma notificação';

  @override
  String get onboardingNotificationsGranted =>
      'Concedido. O renderizador vai mostrar a notificação enquanto estiver rodando.';

  @override
  String get onboardingNotificationsWhy =>
      'O Android não deixa o renderizador continuar em segundo plano sem ela, e é o único sinal visível de que ele está vivo.';

  @override
  String get onboardingAllow => 'Permitir';

  @override
  String get onboardingNoNotificationScreen =>
      'Este celular não tem uma tela de configurações de notificação para abrir.';

  @override
  String get onboardingNotificationsInSettings =>
      'O Android parou de perguntar — ative as notificações por lá.';

  @override
  String get onboardingBattery => 'Impedir que o Android o suspenda';

  @override
  String get onboardingBatteryGranted =>
      'Concedido. O Android não vai suspender o renderizador quando estiver ocioso.';

  @override
  String get onboardingBatteryWhy =>
      'Sem isso, o Android suspende o app depois de um tempo com a tela apagada, e a reprodução para no meio da faixa.';

  @override
  String get onboardingUsbPrompt =>
      'Impedir que o Android pergunte sobre o DAC';

  @override
  String get onboardingUsbPromptGranted =>
      'Concedido. Na próxima vez que o DAC conectar, marque \"sempre abrir\" no aviso do Android e ele não vai perguntar de novo.';

  @override
  String get onboardingUsbPromptWhy =>
      'Sem a permissão do microfone, o Android pergunta se deve abrir o app toda vez que o DAC é ligado, e não oferece a opção de parar de perguntar. Conceda a permissão e marque \"sempre abrir\" na próxima vez que o DAC conectar. O app nunca grava nada.';

  @override
  String get onboardingUsbPromptInSettings =>
      'O Android parou de perguntar — permita o microfone em Permissões por lá.';

  @override
  String onboardingVendorKnown(String vendor) {
    return 'Inicialização automática ($vendor)';
  }

  @override
  String get onboardingVendorKnownNoName => 'Inicialização automática';

  @override
  String get onboardingVendorUnknown =>
      'As restrições próprias do fabricante do seu celular';

  @override
  String get onboardingVendorKnownDetail =>
      'Celulares deste fabricante costumam adicionar restrições próprias para apps em segundo plano, separadas das do Android, e são o motivo mais comum de um renderizador não voltar depois de reiniciar. O app não consegue detectá-las — sabe apenas que este fabricante tem uma tela desse tipo — nem consegue saber se você concedeu algo lá, então esta etapa nunca fica marcada.';

  @override
  String get onboardingVendorUnknownDetail =>
      'Não conhecemos nenhuma tela de configurações para este celular. Se o renderizador parar quando estiver ocioso ou não voltar depois de reiniciar, procure «inicialização automática», «apps em segundo plano» ou «apps protegidos» nas configurações de bateria do seu celular.';

  @override
  String get onboardingDac => 'Seu DAC';

  @override
  String get onboardingDacDetail =>
      'Conecte o DAC USB quando quiser. O Android pede permissão quando ele é conectado — marque \"sempre abrir\" nesse aviso e ele para de perguntar — e o renderizador se adapta ao DAC que estiver conectado, em vez de ser configurado para um específico.';

  @override
  String get onboardingDone => 'Concluído';

  @override
  String get onboardingFinishAnyway => 'Concluir mesmo assim';

  @override
  String get onboardingAllGranted =>
      'Tudo o que o app consegue verificar está concedido.';

  @override
  String get onboardingSkippingIsFine =>
      'Pular está tudo bem. O renderizador vai funcionar; ele só pode não sobreviver quando ficar sozinho, e as Configurações avisam se algo estiver parando ele.';

  @override
  String onboardingStep(int number, String title) {
    return '$number. $title';
  }

  @override
  String get dacCapsTitle => 'Recursos do DAC';

  @override
  String get dacCapsReprobe => 'Analisar de novo';

  @override
  String get dacCapsNotProbed => 'Ainda não analisado';

  @override
  String get dacCapsNotProbedDetail =>
      'Conecte um DAC USB e toque em atualizar.';

  @override
  String get dacCapsUnknownError => 'Erro desconhecido.';

  @override
  String get dacCapsNoDevice => 'Nenhum DAC encontrado';

  @override
  String get dacCapsPermissionNeeded => 'Precisa de permissão';

  @override
  String get dacCapsOpenFailed => 'Não foi possível abrir o DAC';

  @override
  String get dacCapsProbeFailed => 'A análise falhou';

  @override
  String get dacCapsNotUsable => 'Não serve para reprodução bit-perfect';

  @override
  String get dacCapsWorthKnowing => 'O que vale saber';

  @override
  String get dacCapsWhatItSupports => 'O que ele aceita';

  @override
  String dacCapsIdentity(
    String version,
    String speed,
    String vendor,
    String product,
  ) {
    return 'USB Audio Class $version · velocidade $speed · $vendor:$product';
  }

  @override
  String get dacCapsSampleRates => 'Taxas de amostragem';

  @override
  String get dacCapsBitDepths => 'Profundidades de bits';

  @override
  String get dacCapsChannels => 'Canais';

  @override
  String get dacCapsCurrentlyAt => 'Funcionando agora a';

  @override
  String get dacCapsUsbTiming => 'Sincronismo USB';

  @override
  String get dacCapsVolumeControl => 'Controle de volume';

  @override
  String get dacCapsDsd => 'DSD';

  @override
  String get dacCapsUnknown => 'Desconhecido';

  @override
  String dacCapsRateRange(String low, String high, int count) {
    return '$low – $high ($count taxas)';
  }

  @override
  String dacCapsBitDepth(int bits) {
    return '$bits bits';
  }

  @override
  String get dacCapsAsync => 'Assíncrono (relógio do DAC)';

  @override
  String get dacCapsSync => 'Síncrono';

  @override
  String get dacCapsVolumeOverUsb => 'Aceito por USB';

  @override
  String get dacCapsVolumeDeviceOnly => 'Só no próprio aparelho';

  @override
  String get dacCapsDsdSupported => 'Aceito pelo hardware';

  @override
  String get dacCapsTechnical => 'Detalhes técnicos';

  @override
  String get dacCapsTechnicalSubtitle => 'Para relatos de suporte';

  @override
  String dacCapsKhz(String value) {
    return '$value kHz';
  }

  @override
  String get noteCannotPlayTitle => 'Este dispositivo não consegue tocar áudio';

  @override
  String get noteCannotPlayDetail =>
      'Ele se anuncia como classe de áudio USB, mas não oferece saída PCM por um endpoint isócrono. Dispositivos só de captura são assim: um microfone USB, ou a metade de gravação de um adaptador de fone.';

  @override
  String get noteUac1Title => 'Este dispositivo usa USB Audio Class 1.0';

  @override
  String get noteUac1Detail =>
      'Aceito, com os limites que a própria classe impõe: o USB full-speed limita a banda, então dispositivos UAC1 param bem abaixo do que um DAC UAC2 oferece. Nas taxas que ele aceita, a reprodução continua bit-perfect — nada é reamostrado.';

  @override
  String get noteAdaptiveTitle => 'Este dispositivo segue o relógio do celular';

  @override
  String get noteAdaptiveDetail =>
      'O endpoint dele é adaptativo em vez de assíncrono, então ele se ajusta à taxa que o celular envia, em vez de usar o próprio relógio e pedir que o celular acompanhe. Comum em hardware UAC1. As amostras continuam chegando intactas; o que muda é só de que lado está a referência de tempo.';

  @override
  String get noteVolumeDeviceTitle =>
      'O volume é controlado pelo DAC, não por este app';

  @override
  String get noteVolumeOneWayDetail =>
      'Este dispositivo não expõe controle de volume por USB. Ele até informa ao celular o próprio botão ou controle remoto, mas isso é de mão única: nada enviado daqui muda o volume dele. Use o controle físico.';

  @override
  String get noteVolumeNoneDetail =>
      'Este dispositivo não expõe controle de volume por USB, então comandos de volume de um controlador DLNA não chegam até ele. Use o controle físico.';

  @override
  String get noteVolumeAppTitle => 'O volume pode ser ajustado por este app';

  @override
  String noteVolumeAppDetail(String detail) {
    return 'O DAC expõe um controle de volume por USB ($detail), então os comandos de volume DLNA vão direto para o hardware.';
  }

  @override
  String notePaddedTitle(int bits) {
    return 'Faixas de 16 bits são preenchidas para $bits bits';
  }

  @override
  String notePaddedDetail(int bits) {
    return 'Este DAC não tem modo de 16 bits, então arquivos em resolução de CD são colocados num contêiner de $bits bits. Os valores das amostras não mudam, então a reprodução continua bit-perfect.';
  }

  @override
  String get noteAsyncGoodTitle => 'USB assíncrono com relógio próprio';

  @override
  String get noteAsyncGoodDetail =>
      'É o DAC que dita o tempo, em vez de seguir o celular, o que é o melhor arranjo para a qualidade do som.';

  @override
  String get noteAsyncNoFeedbackTitle =>
      'Assíncrono, mas nenhum endpoint de retorno encontrado';

  @override
  String get noteAsyncNoFeedbackDetail =>
      'O sincronismo não pode ser acompanhado com precisão, então falhas ocasionais são possíveis em reproduções longas.';

  @override
  String get noteDsdTitle => 'Compatível com DSD';

  @override
  String get noteDsdDetail =>
      'Este DAC aceita DSD nativo. O app ainda não toca DSD.';

  @override
  String get noteAltConfigTitle => 'Há outro modo USB disponível';

  @override
  String noteAltConfigDetail(int count) {
    return 'O dispositivo oferece $count configurações USB. Só a ativa é usada; alguns DACs guardam um modo de compatibilidade na outra.';
  }

  @override
  String get noteClockErrorTitle => 'Não foi possível ler as taxas aceitas';

  @override
  String get reportCopied => 'Relatório copiado';

  @override
  String get copyReport => 'Copiar relatório';

  @override
  String get stop => 'Parar';

  @override
  String get notReported => 'não informado';

  @override
  String get verifyTitle => 'Verificação do DAC';

  @override
  String get verifyResults => 'Resultados';

  @override
  String get verifyFollow => 'Acompanhar';

  @override
  String get soakTitle => 'Teste de resistência';

  @override
  String get soakRate => 'Taxa';

  @override
  String get soakLength => 'Duração';

  @override
  String soakStart(String rate, String duration) {
    return 'Testar a $rate por $duration';
  }

  @override
  String soakProgress(String elapsed, String planned, String step) {
    return '$elapsed de $planned  ·  $step';
  }

  @override
  String get soakFaults => 'Falhas';

  @override
  String get soakRingFill => 'Ocupação do buffer';

  @override
  String get soakMeasuredRate => 'Taxa medida';

  @override
  String get soakUnderruns => 'Underruns';

  @override
  String get soakTransferErrors => 'Erros de transferência';

  @override
  String get soakPacketErrors => 'Erros de pacote';

  @override
  String get soakRebuffers => 'Rebufferizações';

  @override
  String get soakWorstRingFill => 'Ocupação mínima do buffer';

  @override
  String get soakWorstDeviation => 'Maior desvio';

  @override
  String get soakDriftSpread => 'Faixa de deriva';

  @override
  String get soakMeetsBar =>
      'Passa na marca de dez minutos sem uma única falha.';

  @override
  String get soakShortOfBar =>
      'Abaixo dos dez minutos, então ainda não diz nada sobre as falhas que só aparecem depois que o hardware esquenta.';

  @override
  String get playFileTitle => 'Tocar um arquivo';

  @override
  String get playFileIntro =>
      'Toca um arquivo seu pelo DAC e observa o fluxo, que é a pergunta que os testes de tom não conseguem fazer: se o material que você realmente tem toca sem falhas. Só as taxas presentes nesse material são testadas.';

  @override
  String get playFileChoose => 'Escolher um arquivo';

  @override
  String get playFileFormats =>
      'FLAC, WAV, AIFF, MP3 e qualquer outro formato que o motor saiba decodificar.';

  @override
  String get playFileCache => 'Copiados para o cache do app';

  @override
  String get playFileCacheDetail =>
      'A bancada M2. Só WAV, e o jeito mais rápido de colocar um arquivo conhecido num celular que você está depurando por adb.';

  @override
  String get playFileStreamHealth => 'Saúde do fluxo';

  @override
  String get errServerUnreachable =>
      'O renderizador perdeu contato com o servidor de mídia.';

  @override
  String get errServerRefused => 'O servidor de mídia recusou esta faixa.';

  @override
  String get errDownloadFailed =>
      'Não foi possível baixar esta faixa do servidor.';

  @override
  String get errUndecodableFormat =>
      'Esta faixa está num formato que o renderizador não sabe decodificar.';

  @override
  String get errDacRateUnsupported =>
      'Este DAC não pode ser ajustado para a taxa ou a profundidade de bits desta faixa.';

  @override
  String get errDacConnectionLost =>
      'O renderizador perdeu a conexão com o DAC.';

  @override
  String get errTrackCouldNotBePlayed => 'Não foi possível tocar esta faixa.';

  @override
  String errRateUnplayable(String rate, String ceiling) {
    return 'Este DAC não consegue tocar a $rate; a taxa máxima dele é $ceiling.';
  }

  @override
  String errStoppedAfterFailures(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Parado depois que $count faixas seguidas não puderam ser tocadas.',
    );
    return '$_temp0';
  }
}
