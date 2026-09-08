// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Korean (`ko`).
class AppLocalizationsKo extends AppLocalizations {
  AppLocalizationsKo([String locale = 'ko']) : super(locale);

  @override
  String get settingsTooltip => '설정';

  @override
  String get idleReady => '준비됨 — 컨트롤러를 기다리는 중';

  @override
  String get idleNoDac => '연결된 DAC 없음';

  @override
  String get unknownTrack => '알 수 없는 트랙';

  @override
  String airPlayFromSender(String sender) {
    return '$sender에서 보낸 AirPlay';
  }

  @override
  String get previousTrack => '이전 트랙';

  @override
  String get nextTrack => '다음 트랙';

  @override
  String get pause => '일시정지';

  @override
  String get play => '재생';

  @override
  String get volumeWriteOnly =>
      '이 DAC은 자신의 음량을 알려주지 않기 때문에, 여기에는 앱이 마지막으로 보낸 값이 표시됩니다.';

  @override
  String get systemAudioDetail => '휴대폰 스피커 또는 헤드폰 — Android가 리샘플링함';

  @override
  String dacOneOf(int count) {
    return '($count개 중 1번째)';
  }

  @override
  String get bitPerfect => '비트 퍼펙트';

  @override
  String get systemAudioBadge => '시스템 오디오';

  @override
  String get airPlaySenderResampled => 'AirPlay · 보내는 쪽에서 리샘플링됨';

  @override
  String get settingsTitle => '설정';

  @override
  String get settingsNetworkName => '네트워크 이름';

  @override
  String get settingsNetworkNameHelp => '이 렌더러가 DLNA 컨트롤러에 표시되는 이름입니다.';

  @override
  String get settingsSave => '저장';

  @override
  String get settingsSaved => '저장됨';

  @override
  String get settingsRenamed => '이름을 바꿨습니다. 컨트롤러에 반영하려면 앱을 다시 시작하세요.';

  @override
  String get settingsAudioDevice => '오디오 기기';

  @override
  String settingsDacsMultiple(int count) {
    return 'USB 오디오 기기가 $count개 연결되어 있습니다. 어느 기기로 재생할지 고르세요. 선택은 재시작 후에도 유지됩니다.';
  }

  @override
  String get settingsDacsSingle =>
      'USB 오디오 기기가 하나 연결되어 있습니다. 탭하면 그 기기로 재생하며, 아직 권한이 없다면 권한도 함께 요청합니다.';

  @override
  String get settingsUsbAudioDevice => 'USB 오디오 기기';

  @override
  String get settingsPermissionNotGranted => ' — 권한 없음';

  @override
  String get settingsReadingDevice => '기기를 읽는 중…';

  @override
  String get settingsProbing => 'DAC에 지원 형식을 묻는 중';

  @override
  String settingsUacTap(String version) {
    return 'USB Audio Class $version — 지원 내용을 보려면 탭하세요';
  }

  @override
  String get settingsConnectToProbe => 'USB DAC을 연결하고 탭하면 확인합니다';

  @override
  String get settingsPcmOnly => 'PCM 스트림만 받고 디코딩과 변환은 서버에 맡기기';

  @override
  String get settingsPcmOnlyOn =>
      '렌더러가 이 DAC이 다룰 수 있는 샘플레이트의 LPCM만 알리므로, 서버가 모든 것을 맞춰 변환합니다. 무엇이든 재생되지만 어느 것도 비트 퍼펙트가 아닙니다. DAC이 그대로 재생할 수 있었을 트랙까지 포함해서입니다.';

  @override
  String get settingsPcmOnlyOff =>
      '렌더러가 디코딩할 수 있는 모든 형식을 알리므로 파일이 손대지 않은 채로 도착합니다. 이 DAC이 다룰 수 없는 샘플레이트의 트랙은 이유를 밝히며 거부됩니다.';

  @override
  String get settingsScreenOffAfter => '화면을 끄기까지';

  @override
  String get settingsScreenOffNever =>
      '화면이 계속 켜져 있습니다. 항상 전원이 연결된 휴대폰이라면 문제없지만, OLED 패널에 같은 화면을 몇 달씩 띄워 두면 그 자국이 영구히 남습니다.';

  @override
  String get settingsScreenOffTimed =>
      '음악이 멈춘 시점부터 셉니다. 긴 트랙이 재생되는 도중에 화면이 꺼지는 일은 없습니다. 재생이 시작되면 다시 켜집니다.';

  @override
  String get settingsTimeoutNever => '안 함';

  @override
  String settingsTimeoutMinutes(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: '$minutes분',
    );
    return '$_temp0';
  }

  @override
  String get settingsDacVerification => 'DAC 검증';

  @override
  String get settingsDacVerificationSubtitle => '이 DAC이 지원한다고 밝힌 모든 샘플레이트를 시험';

  @override
  String get settingsAlwaysOn => '항상 켜짐';

  @override
  String get settingsAlwaysOnHelp =>
      '전용 렌더러는 화면이 꺼진 채로도 계속 돌아가야 하고 재부팅 후에도 돌아와야 합니다. Android와 대부분의 제조사는 기본적으로 이를 막습니다.';

  @override
  String settingsDeaths(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '이 휴대폰이 렌더러를 $count번 중단시켰습니다',
    );
    return '$_temp0';
  }

  @override
  String get settingsDeathsDetail =>
      '모두 정상 종료를 기록하지 못한 실행 바로 뒤에 시작된 경우입니다. 즉 백그라운드에서 무언가가 앱을 종료시켰다는 뜻입니다. 아래 권한을 주면 대개 해결됩니다.';

  @override
  String get settingsBattery => '배터리 최적화 제외';

  @override
  String get settingsBatteryGranted => '허용됨 — Android가 렌더러를 중단시키지 않습니다.';

  @override
  String get settingsBatteryNotGranted =>
      '허용되지 않음. 대기 중에 Android가 렌더러를 중단시킬 수 있습니다.';

  @override
  String get settingsGrant => '허용';

  @override
  String get settingsOpenSettings => '설정 열기';

  @override
  String get settingsCouldNotOpen => '이 휴대폰에서는 해당 설정 화면을 열 수 없었습니다.';

  @override
  String settingsAutostart(String vendor) {
    return '자동 실행 ($vendor)';
  }

  @override
  String get settingsAutostartVendorFallback => '제조사';

  @override
  String get settingsAutostartDetail =>
      '이 제조사의 휴대폰은 대개 Android와 별개로 자체 백그라운드 앱 제한을 두며, 재부팅 후 렌더러가 시작되지 않는 흔한 원인이 바로 그것입니다. 앱은 이를 감지할 수 없고, 이 제조사에 그런 화면이 있다는 것만 알 뿐입니다.';

  @override
  String get settingsWakeScreen => '음악이 시작되면 화면 켜기';

  @override
  String get settingsWakeScreenDetail =>
      '이 기기에서 화면이 꺼진 채 음악이 재생된 적이 있습니다. Android는 표시된 창이 없는 앱의 화면 유지 요청을 해제하는데, 이 휴대폰은 렌더러가 자기 창을 띄우는 것도 허락하지 않아 화면이 잠깐 켜졌다가 다시 꺼졌습니다. 이 권한은 보통 「백그라운드에서 팝업 창 표시」와 같은 이름이며, 자동 실행과는 별개입니다.';

  @override
  String get settingsRunSetup => '설정 다시 진행';

  @override
  String get settingsRunSetupSubtitle => '권한을 순서대로 살펴보기';

  @override
  String get settingsLanguage => '언어';

  @override
  String get settingsLanguageSystem => '이 휴대폰과 동일';

  @override
  String get settingsLanguageHelp =>
      '따로 고르지 않으면 렌더러는 이 휴대폰의 언어를 따릅니다. 여분의 휴대폰으로 설치한 기기는 아무도 원하지 않은 언어를 물려받기 쉽습니다.';

  @override
  String get onboardingTitle => 'HiFi Renderer 설정';

  @override
  String get onboardingTitleRerun => '설정';

  @override
  String get onboardingIntro =>
      '이 휴대폰은 어딘가에 놓인 채 렌더러 역할을 하게 됩니다. Android와 대부분의 제조사는 그런 앱이 있을 리 없다고 전제하므로, 몇 가지를 직접 켜 주어야 합니다.';

  @override
  String get onboardingOptional =>
      '앱을 써 보는 데 꼭 필요한 것은 없으며, 나중에 설정에서 모두 바꿀 수 있습니다.';

  @override
  String get onboardingNotifications => '알림 표시';

  @override
  String get onboardingNotificationsGranted => '허용됨. 렌더러가 동작하는 동안 알림을 표시합니다.';

  @override
  String get onboardingNotificationsWhy =>
      '알림이 없으면 Android는 렌더러가 백그라운드에서 계속 돌아가도록 두지 않으며, 알림은 렌더러가 살아 있다는 유일한 눈에 보이는 표시이기도 합니다.';

  @override
  String get onboardingAllow => '허용';

  @override
  String get onboardingNoNotificationScreen => '이 휴대폰에는 열 수 있는 알림 설정 화면이 없습니다.';

  @override
  String get onboardingNotificationsInSettings =>
      'Android가 더 이상 묻지 않습니다 — 그 화면에서 알림을 켜세요.';

  @override
  String get onboardingBattery => 'Android가 중단시키지 못하게 하기';

  @override
  String get onboardingBatteryGranted => '허용됨. 대기 중에 Android가 렌더러를 중단시키지 않습니다.';

  @override
  String get onboardingBatteryWhy =>
      '이것이 없으면 화면이 꺼진 뒤 얼마 지나 Android가 앱을 중단시키고, 재생이 트랙 도중에 멈춥니다.';

  @override
  String onboardingVendorKnown(String vendor) {
    return '자동 실행 ($vendor)';
  }

  @override
  String get onboardingVendorKnownNoName => '자동 실행';

  @override
  String get onboardingVendorUnknown => '휴대폰 제조사 자체의 제한';

  @override
  String get onboardingVendorKnownDetail =>
      '이 제조사의 휴대폰은 대개 Android와 별개로 자체 백그라운드 앱 제한을 두며, 재부팅 후 렌더러가 돌아오지 않는 흔한 원인이 바로 그것입니다. 앱은 이를 감지할 수 없고 — 이 제조사에 그런 화면이 있다는 것만 알 뿐이며 — 거기서 무엇을 허용했는지도 알 수 없기 때문에, 이 단계에는 절대 표시가 붙지 않습니다.';

  @override
  String get onboardingVendorUnknownDetail =>
      '이 휴대폰에 해당하는 설정 화면은 알지 못합니다. 렌더러가 대기 중에 멈추거나 재부팅 후 돌아오지 않는다면, 휴대폰의 배터리 설정에서 「자동 실행」, 「백그라운드 앱」, 「보호된 앱」 같은 항목을 찾아보세요.';

  @override
  String get onboardingDac => '사용하는 DAC';

  @override
  String get onboardingDacDetail =>
      'USB DAC은 원할 때 연결하면 됩니다. 처음 연결할 때 Android가 권한을 묻기 때문에 여기서 할 일은 없습니다. 렌더러는 특정 DAC에 맞춰 설정되는 것이 아니라, 그때 연결된 DAC을 따라갑니다.';

  @override
  String get onboardingDone => '완료';

  @override
  String get onboardingFinishAnyway => '그대로 마치기';

  @override
  String get onboardingAllGranted => '앱이 확인할 수 있는 항목은 모두 허용되었습니다.';

  @override
  String get onboardingSkippingIsFine =>
      '건너뛰어도 괜찮습니다. 렌더러는 동작합니다. 다만 혼자 두었을 때 버티지 못할 수 있으며, 무언가가 막고 있다면 설정 화면이 알려 줍니다.';

  @override
  String onboardingStep(int number, String title) {
    return '$number. $title';
  }

  @override
  String get dacCapsTitle => 'DAC 지원 사양';

  @override
  String get dacCapsReprobe => '다시 확인';

  @override
  String get dacCapsNotProbed => '아직 확인하지 않음';

  @override
  String get dacCapsNotProbedDetail => 'USB DAC을 연결하고 새로 고침을 탭하세요.';

  @override
  String get dacCapsUnknownError => '알 수 없는 오류입니다.';

  @override
  String get dacCapsNoDevice => 'DAC을 찾지 못했습니다';

  @override
  String get dacCapsPermissionNeeded => '권한이 필요합니다';

  @override
  String get dacCapsOpenFailed => 'DAC을 열 수 없었습니다';

  @override
  String get dacCapsProbeFailed => '확인에 실패했습니다';

  @override
  String get dacCapsNotUsable => '비트 퍼펙트 재생에는 쓸 수 없습니다';

  @override
  String get dacCapsWorthKnowing => '알아 둘 만한 점';

  @override
  String get dacCapsWhatItSupports => '지원 내용';

  @override
  String dacCapsIdentity(
    String version,
    String speed,
    String vendor,
    String product,
  ) {
    return 'USB Audio Class $version · $speed 속도 · $vendor:$product';
  }

  @override
  String get dacCapsSampleRates => '샘플레이트';

  @override
  String get dacCapsBitDepths => '비트 심도';

  @override
  String get dacCapsChannels => '채널 수';

  @override
  String get dacCapsCurrentlyAt => '현재 동작 중인 레이트';

  @override
  String get dacCapsUsbTiming => 'USB 동기 방식';

  @override
  String get dacCapsVolumeControl => '음량 조절';

  @override
  String get dacCapsDsd => 'DSD';

  @override
  String get dacCapsUnknown => '알 수 없음';

  @override
  String dacCapsRateRange(String low, String high, int count) {
    return '$low – $high ($count종)';
  }

  @override
  String dacCapsBitDepth(int bits) {
    return '$bits비트';
  }

  @override
  String get dacCapsAsync => '비동기 (DAC 클럭)';

  @override
  String get dacCapsSync => '동기';

  @override
  String get dacCapsVolumeOverUsb => 'USB로 지원';

  @override
  String get dacCapsVolumeDeviceOnly => '기기에서만 가능';

  @override
  String get dacCapsDsdSupported => '하드웨어가 지원';

  @override
  String get dacCapsTechnical => '기술 정보';

  @override
  String get dacCapsTechnicalSubtitle => '문의 시 첨부용';

  @override
  String dacCapsKhz(String value) {
    return '$value kHz';
  }

  @override
  String get noteCannotPlayTitle => '이 기기는 오디오를 재생할 수 없습니다';

  @override
  String get noteCannotPlayDetail =>
      'USB 오디오 클래스를 표방하지만 등시성 엔드포인트로 PCM을 출력하지 않습니다. 녹음 전용 기기가 이렇게 보입니다 — USB 마이크나 헤드셋 어댑터의 녹음 쪽이 그렇습니다.';

  @override
  String get noteUac1Title => '이 기기는 USB Audio Class 1.0을 사용합니다';

  @override
  String get noteUac1Detail =>
      '지원하지만 규격 자체의 한계가 따릅니다. 풀 스피드 USB가 대역폭을 제한하므로 UAC1 기기는 UAC2 DAC보다 훨씬 낮은 선에서 멈춥니다. 지원하는 샘플레이트에서는 재생이 여전히 비트 퍼펙트이며, 리샘플링은 전혀 일어나지 않습니다.';

  @override
  String get noteAdaptiveTitle => '이 기기는 휴대폰의 클럭을 따릅니다';

  @override
  String get noteAdaptiveDetail =>
      '엔드포인트가 비동기가 아니라 적응형이어서, 자체 클럭을 쓰고 휴대폰이 따라오게 하는 대신 휴대폰이 보내는 레이트에 스스로를 맞춥니다. UAC1 하드웨어에서 흔한 일입니다. 샘플은 여전히 그대로 도착하며, 시간 기준이 휴대폰 쪽에 있을 뿐입니다.';

  @override
  String get noteVolumeDeviceTitle => '음량은 이 앱이 아니라 DAC이 조절합니다';

  @override
  String get noteVolumeOneWayDetail =>
      '이 기기는 USB 음량 조절을 제공하지 않습니다. 자기 노브나 리모컨 상태를 휴대폰에 알리기는 하지만 그것은 한 방향이며, 여기서 보내는 어떤 것도 음량을 바꾸지 못합니다. 기기의 실제 조절기를 사용하세요.';

  @override
  String get noteVolumeNoneDetail =>
      '이 기기는 USB 음량 조절을 제공하지 않으므로 DLNA 컨트롤러의 음량 명령이 닿지 않습니다. 기기의 실제 조절기를 사용하세요.';

  @override
  String get noteVolumeAppTitle => '이 앱에서 음량을 조절할 수 있습니다';

  @override
  String noteVolumeAppDetail(String detail) {
    return '이 DAC은 USB 음량 조절($detail)을 제공하므로 DLNA 음량 명령이 하드웨어로 곧장 전달됩니다.';
  }

  @override
  String notePaddedTitle(int bits) {
    return '16비트 트랙은 $bits비트로 채워집니다';
  }

  @override
  String notePaddedDetail(int bits) {
    return '이 DAC에는 16비트 모드가 없어서 CD 해상도 파일이 $bits비트 그릇에 담깁니다. 샘플 값 자체는 바뀌지 않으므로 재생은 여전히 비트 퍼펙트입니다.';
  }

  @override
  String get noteAsyncGoodTitle => '자체 클럭을 갖춘 비동기 USB';

  @override
  String get noteAsyncGoodDetail =>
      '휴대폰을 따라가는 대신 DAC이 타이밍을 주도합니다. 음질 면에서 더 나은 구성입니다.';

  @override
  String get noteAsyncNoFeedbackTitle => '비동기이지만 피드백 엔드포인트를 찾지 못했습니다';

  @override
  String get noteAsyncNoFeedbackDetail =>
      '타이밍을 정확히 추적할 수 없어 오래 재생하면 이따금 끊김이 생길 수 있습니다.';

  @override
  String get noteDsdTitle => 'DSD 지원';

  @override
  String get noteDsdDetail => '이 DAC은 네이티브 DSD를 받아들입니다. 앱은 아직 DSD를 재생하지 않습니다.';

  @override
  String get noteAltConfigTitle => '다른 USB 모드가 있습니다';

  @override
  String noteAltConfigDetail(int count) {
    return '이 기기는 USB 구성을 $count가지 제공합니다. 활성화된 것만 사용되며, 일부 DAC은 나머지 하나에 호환 모드를 담아 둡니다.';
  }

  @override
  String get noteClockErrorTitle => '지원하는 샘플레이트를 읽지 못했습니다';

  @override
  String get reportCopied => '보고서를 복사했습니다';

  @override
  String get copyReport => '보고서 복사';

  @override
  String get stop => '정지';

  @override
  String get notReported => '보고되지 않음';

  @override
  String get verifyTitle => 'DAC 검증';

  @override
  String get verifyResults => '결과';

  @override
  String get verifyFollow => '따라가기';

  @override
  String get soakTitle => '안정성 장시간 시험';

  @override
  String get soakRate => '샘플레이트';

  @override
  String get soakLength => '길이';

  @override
  String soakStart(String rate, String duration) {
    return '$rate로 $duration 동안 시험';
  }

  @override
  String soakProgress(String elapsed, String planned, String step) {
    return '$planned 중 $elapsed  ·  $step';
  }

  @override
  String get soakFaults => '결함';

  @override
  String get soakRingFill => '버퍼 채움';

  @override
  String get soakMeasuredRate => '측정된 레이트';

  @override
  String get soakUnderruns => '언더런';

  @override
  String get soakTransferErrors => '전송 오류';

  @override
  String get soakPacketErrors => '패킷 오류';

  @override
  String get soakRebuffers => '재버퍼링';

  @override
  String get soakWorstRingFill => '버퍼 최저 채움';

  @override
  String get soakWorstDeviation => '최대 편차';

  @override
  String get soakDriftSpread => '드리프트 폭';

  @override
  String get soakMeetsBar => '10분 동안 끊김 없음 기준을 통과했습니다.';

  @override
  String get soakShortOfBar =>
      '10분에 못 미치므로, 하드웨어가 데워진 뒤에야 나타나는 결함에 대해서는 아직 아무것도 말해 주지 못합니다.';

  @override
  String get playFileTitle => '파일 재생';

  @override
  String get playFileIntro =>
      '직접 가진 파일을 DAC으로 재생하면서 스트림을 지켜봅니다. 테스트 톤으로는 물을 수 없는 질문, 곧 실제로 소장한 음원이 깨끗하게 재생되는가에 답하는 방식입니다. 시험되는 것은 그 음원에 실제로 들어 있는 샘플레이트뿐입니다.';

  @override
  String get playFileChoose => '파일 선택';

  @override
  String get playFileFormats =>
      'FLAC, WAV, AIFF, MP3, 그리고 엔진이 디코딩할 수 있는 그 밖의 형식.';

  @override
  String get playFileCache => '앱 캐시에 넣어 둔 파일';

  @override
  String get playFileCacheDetail =>
      'M2 시험 장치. WAV만 지원하며, adb로 디버깅 중인 휴대폰에 알려진 파일을 넣는 가장 빠른 방법입니다.';

  @override
  String get playFileStreamHealth => '스트림 상태';

  @override
  String get errServerUnreachable => '렌더러가 미디어 서버와의 연결을 잃었습니다.';

  @override
  String get errServerRefused => '미디어 서버가 이 트랙을 거부했습니다.';

  @override
  String get errDownloadFailed => '이 트랙을 서버에서 내려받지 못했습니다.';

  @override
  String get errUndecodableFormat => '이 트랙은 렌더러가 디코딩할 수 없는 형식입니다.';

  @override
  String get errDacRateUnsupported => '이 DAC은 이 트랙의 샘플레이트나 비트 심도로 설정할 수 없습니다.';

  @override
  String get errDacConnectionLost => '렌더러가 DAC과의 연결을 잃었습니다.';

  @override
  String get errTrackCouldNotBePlayed => '이 트랙을 재생할 수 없었습니다.';

  @override
  String errRateUnplayable(String rate, String ceiling) {
    return '이 DAC은 $rate를 재생할 수 없습니다. 지원하는 최고 레이트는 $ceiling입니다.';
  }

  @override
  String errStoppedAfterFailures(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count곡을 연달아 재생하지 못해 정지했습니다.',
    );
    return '$_temp0';
  }
}
