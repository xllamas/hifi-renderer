// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get settingsTooltip => '设置';

  @override
  String get idleReady => '就绪 — 正在等待控制端';

  @override
  String get idleNoDac => '未连接 DAC';

  @override
  String get unknownTrack => '未知曲目';

  @override
  String airPlayFromSender(String sender) {
    return '来自 $sender 的 AirPlay';
  }

  @override
  String get previousTrack => '上一曲';

  @override
  String get nextTrack => '下一曲';

  @override
  String get pause => '暂停';

  @override
  String get play => '播放';

  @override
  String get volumeWriteOnly => '此 DAC 不会回报自身音量，因此这里显示的是本应用最后发送的数值。';

  @override
  String get systemAudioDetail => '手机扬声器或耳机 — 已被 Android 重采样';

  @override
  String dacOneOf(int count) {
    return '（共 $count 个中的第 1 个）';
  }

  @override
  String get bitPerfect => '比特完美';

  @override
  String get systemAudioBadge => '系统音频';

  @override
  String get airPlaySenderResampled => 'AirPlay · 发送端已重采样';

  @override
  String get settingsTitle => '设置';

  @override
  String get settingsNetworkName => '网络名称';

  @override
  String get settingsNetworkNameHelp => '此渲染器在 DLNA 控制端中显示的名称。';

  @override
  String get settingsSave => '保存';

  @override
  String get settingsSaved => '已保存';

  @override
  String get settingsRenamed => '已重命名。重启应用后控制端才能看到新名称。';

  @override
  String get settingsAudioDevice => '音频设备';

  @override
  String settingsDacsMultiple(int count) {
    return '已连接 $count 个 USB 音频设备。请选择使用哪一个播放；该选择在重启后仍然保留。';
  }

  @override
  String get settingsDacsSingle => '已连接一个 USB 音频设备。轻点即可通过它播放，若尚未授权也会一并请求授权。';

  @override
  String get settingsUsbAudioDevice => 'USB 音频设备';

  @override
  String get settingsPermissionNotGranted => ' — 未授予权限';

  @override
  String get settingsReadingDevice => '正在读取设备…';

  @override
  String get settingsProbing => '正在询问 DAC 支持哪些格式';

  @override
  String settingsUacTap(String version) {
    return 'USB Audio Class $version — 轻点查看它支持什么';
  }

  @override
  String get settingsConnectToProbe => '接上 USB DAC 后轻点以检测';

  @override
  String get settingsPcmOnly => '只接受 PCM 流，由服务器负责解码或转码';

  @override
  String get settingsPcmOnlyOn =>
      '渲染器只声明支持 LPCM，且限于此 DAC 能够输出的采样率，因此服务器会把一切转换成合适的格式。所有曲目都能播放，但没有一首是比特完美的——包括那些 DAC 本可以原样播放的曲目。';

  @override
  String get settingsPcmOnlyOff =>
      '渲染器声明它能解码的所有格式，因此文件原样送达。采样率超出此 DAC 能力的曲目会被拒绝，并说明原因。';

  @override
  String get settingsScreenOffAfter => '多久后关闭屏幕';

  @override
  String get settingsScreenOffNever =>
      '屏幕保持常亮。对长期通电的手机没有问题，但 OLED 屏幕连续数月显示同一画面，正是烧屏的成因。';

  @override
  String get settingsScreenOffTimed => '从音乐停止时开始计时——长曲目不会在播放途中熄屏。播放会重新点亮屏幕。';

  @override
  String get settingsTimeoutNever => '从不';

  @override
  String settingsTimeoutMinutes(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: '$minutes 分钟',
    );
    return '$_temp0';
  }

  @override
  String get settingsDacVerification => 'DAC 验证';

  @override
  String get settingsDacVerificationSubtitle => '测试此 DAC 声称支持的每一个采样率';

  @override
  String get settingsAlwaysOn => '保持常驻';

  @override
  String get settingsAlwaysOnHelp =>
      '专用渲染器必须在息屏时继续运行，并在重启后自动恢复。Android 和多数手机厂商默认阻止这种行为。';

  @override
  String settingsDeaths(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '此手机已经终止渲染器 $count 次',
    );
    return '$_temp0';
  }

  @override
  String get settingsDeathsDetail =>
      '每一次都是紧接在一次没有记录到正常停止的运行之后启动的，说明它在后台被系统杀掉了。授予下面的权限通常可以解决。';

  @override
  String get settingsBattery => '电池优化豁免';

  @override
  String get settingsBatteryGranted => '已授予 — Android 不会挂起渲染器。';

  @override
  String get settingsBatteryNotGranted => '未授予。空闲时 Android 可能挂起渲染器。';

  @override
  String get settingsGrant => '授予';

  @override
  String get settingsOpenSettings => '打开设置';

  @override
  String get settingsCouldNotOpen => '无法在此手机上打开该设置界面。';

  @override
  String settingsAutostart(String vendor) {
    return '自启动（$vendor）';
  }

  @override
  String get settingsAutostartVendorFallback => '厂商';

  @override
  String get settingsAutostartDetail =>
      '此厂商的手机通常会在 Android 之外另加一套后台应用限制，这是渲染器重启后无法启动的常见原因。应用无法检测这些设置，只知道此厂商有这样一个界面。';

  @override
  String get settingsWakeScreen => '音乐开始时点亮屏幕';

  @override
  String get settingsWakeScreenDetail =>
      '这台设备上曾出现音乐在播放而屏幕始终不亮的情况。对于没有可见窗口的应用，Android 会取消其点亮屏幕的请求，而这台手机又不允许渲染器显示自己的窗口，于是屏幕亮了一下就重新熄灭。该权限通常叫作「后台弹出界面」之类的名称，与自启动是两回事。';

  @override
  String get settingsRunSetup => '重新运行设置向导';

  @override
  String get settingsRunSetupSubtitle => '按顺序逐项检查权限';

  @override
  String get settingsLegal => '法律信息';

  @override
  String get settingsLicenses => '开源许可证';

  @override
  String get settingsLicensesSubtitle => '这款应用建立在什么之上';

  @override
  String get settingsLicensesLegalese =>
      'Apache License 2.0。基于以此处列出的 LGPL、Apache、CDDL、BSD、CC0 及公共领域条款发布的作品构建。';

  @override
  String get settingsLanguage => '语言';

  @override
  String get settingsLanguageSystem => '与此手机相同';

  @override
  String get settingsLanguageHelp =>
      '除非另行选择，渲染器会跟随这台手机的语言。用备用手机配置的设备往往会继承一个谁也不想要的语言。';

  @override
  String get onboardingTitle => '设置 HiFi Renderer';

  @override
  String get onboardingTitleRerun => '设置';

  @override
  String get onboardingIntro =>
      '这台手机将固定放在某处充当渲染器。Android 和多数手机厂商都假定没有应用会这么做，因此有几项设置需要手动开启。';

  @override
  String get onboardingOptional => '这些都不是试用本应用的必要条件，之后都可以在设置中更改。';

  @override
  String get onboardingNotifications => '显示通知';

  @override
  String get onboardingNotificationsGranted => '已授予。渲染器运行期间会显示通知。';

  @override
  String get onboardingNotificationsWhy =>
      '没有通知，Android 不会允许渲染器在后台继续运行，而它也是渲染器仍在工作的唯一可见标志。';

  @override
  String get onboardingAllow => '允许';

  @override
  String get onboardingNoNotificationScreen => '此手机没有可供打开的通知设置界面。';

  @override
  String get onboardingNotificationsInSettings => 'Android 已不再询问 — 请在那里开启通知。';

  @override
  String get onboardingBattery => '阻止 Android 挂起它';

  @override
  String get onboardingBatteryGranted => '已授予。空闲时 Android 不会挂起渲染器。';

  @override
  String get onboardingBatteryWhy =>
      '没有这一项，屏幕熄灭一段时间后 Android 会挂起应用，播放会在曲目中途中断。';

  @override
  String onboardingVendorKnown(String vendor) {
    return '自启动（$vendor）';
  }

  @override
  String get onboardingVendorKnownNoName => '自启动';

  @override
  String get onboardingVendorUnknown => '你的手机厂商自己的限制';

  @override
  String get onboardingVendorKnownDetail =>
      '此厂商的手机通常会在 Android 之外另加一套后台应用限制，这是渲染器重启后无法恢复的常见原因。应用无法检测这些设置——只知道此厂商有这样一个界面——也无法判断你在那里授予了什么，因此这一步永远不会打勾。';

  @override
  String get onboardingVendorUnknownDetail =>
      '我们不知道这台手机对应的设置界面。如果渲染器在空闲时停止，或重启后没有恢复，请在手机自带的电池设置中查找「自启动」「后台应用」或「受保护的应用」。';

  @override
  String get onboardingDac => '你的 DAC';

  @override
  String get onboardingDacDetail =>
      '随时接上 USB DAC 即可。首次接入时 Android 会请求授权，所以这里无需操作——渲染器会跟随当前连接的 DAC，而不是为某一台专门配置。';

  @override
  String get onboardingDone => '完成';

  @override
  String get onboardingFinishAnyway => '仍然完成';

  @override
  String get onboardingAllGranted => '应用能够检查的项目都已授予。';

  @override
  String get onboardingSkippingIsFine =>
      '跳过也没关系。渲染器仍会运行，只是无人看管时可能撑不住；如果有什么在阻止它，设置界面会告诉你。';

  @override
  String onboardingStep(int number, String title) {
    return '$number. $title';
  }

  @override
  String get dacCapsTitle => 'DAC 能力';

  @override
  String get dacCapsReprobe => '重新检测';

  @override
  String get dacCapsNotProbed => '尚未检测';

  @override
  String get dacCapsNotProbedDetail => '接上 USB DAC 后轻点刷新。';

  @override
  String get dacCapsUnknownError => '未知错误。';

  @override
  String get dacCapsNoDevice => '未找到 DAC';

  @override
  String get dacCapsPermissionNeeded => '需要授权';

  @override
  String get dacCapsOpenFailed => '无法打开 DAC';

  @override
  String get dacCapsProbeFailed => '检测失败';

  @override
  String get dacCapsNotUsable => '无法用于比特完美播放';

  @override
  String get dacCapsWorthKnowing => '值得了解的事';

  @override
  String get dacCapsWhatItSupports => '它支持什么';

  @override
  String dacCapsIdentity(
    String version,
    String speed,
    String vendor,
    String product,
  ) {
    return 'USB Audio Class $version · $speed 速率 · $vendor:$product';
  }

  @override
  String get dacCapsSampleRates => '采样率';

  @override
  String get dacCapsBitDepths => '位深度';

  @override
  String get dacCapsChannels => '声道数';

  @override
  String get dacCapsCurrentlyAt => '当前运行于';

  @override
  String get dacCapsUsbTiming => 'USB 时钟方式';

  @override
  String get dacCapsVolumeControl => '音量控制';

  @override
  String get dacCapsDsd => 'DSD';

  @override
  String get dacCapsUnknown => '未知';

  @override
  String dacCapsRateRange(String low, String high, int count) {
    return '$low – $high（共 $count 种采样率）';
  }

  @override
  String dacCapsBitDepth(int bits) {
    return '$bits 位';
  }

  @override
  String get dacCapsAsync => '异步（以 DAC 时钟为准）';

  @override
  String get dacCapsSync => '同步';

  @override
  String get dacCapsVolumeOverUsb => '支持通过 USB 控制';

  @override
  String get dacCapsVolumeDeviceOnly => '仅限设备本身';

  @override
  String get dacCapsDsdSupported => '硬件支持';

  @override
  String get dacCapsTechnical => '技术细节';

  @override
  String get dacCapsTechnicalSubtitle => '供反馈问题时使用';

  @override
  String dacCapsKhz(String value) {
    return '$value kHz';
  }

  @override
  String get noteCannotPlayTitle => '此设备无法播放音频';

  @override
  String get noteCannotPlayDetail =>
      '它声明自己属于 USB 音频类，却没有提供任何等时端点上的 PCM 输出。只能录音的设备就是这个样子——比如 USB 麦克风，或者耳机适配器的录音部分。';

  @override
  String get noteUac1Title => '此设备使用 USB Audio Class 1.0';

  @override
  String get noteUac1Detail =>
      '支持，但受该规范本身的限制：全速 USB 限制了带宽，因此 UAC1 设备的上限远低于 UAC2 DAC。在它确实支持的采样率上，播放依然是比特完美的——不会有任何重采样。';

  @override
  String get noteAdaptiveTitle => '此设备跟随手机的时钟';

  @override
  String get noteAdaptiveDetail =>
      '它的端点是自适应而非异步的，因此会跟随手机送出的采样率，而不是用自己的时钟并要求手机跟随。这在 UAC1 硬件上很常见。采样数据依然原样送达，只是时间基准来自手机。';

  @override
  String get noteVolumeDeviceTitle => '音量由 DAC 控制，而非本应用';

  @override
  String get noteVolumeOneWayDetail =>
      '此设备没有提供 USB 音量控制。它确实会把自己的旋钮或遥控器状态告知手机，但这是单向的：从这里发出的任何指令都无法改变它的音量。请使用设备上的实体控制。';

  @override
  String get noteVolumeNoneDetail =>
      '此设备没有提供 USB 音量控制，因此 DLNA 控制端发出的音量指令无法送达。请使用设备上的实体控制。';

  @override
  String get noteVolumeAppTitle => '可以在本应用中调节音量';

  @override
  String noteVolumeAppDetail(String detail) {
    return '此 DAC 提供了 USB 音量控制（$detail），因此 DLNA 音量指令会直接传给硬件。';
  }

  @override
  String notePaddedTitle(int bits) {
    return '16 位曲目会被补齐为 $bits 位';
  }

  @override
  String notePaddedDetail(int bits) {
    return '此 DAC 没有 16 位模式，因此 CD 规格的文件会被放进 $bits 位的容器中。采样数值不变，所以播放依然是比特完美的。';
  }

  @override
  String get noteAsyncGoodTitle => '异步 USB，使用自身时钟';

  @override
  String get noteAsyncGoodDetail => '由 DAC 主导时钟而非跟随手机，这对音质来说是更好的安排。';

  @override
  String get noteAsyncNoFeedbackTitle => '异步，但未找到反馈端点';

  @override
  String get noteAsyncNoFeedbackDetail => '无法精确跟踪时钟，因此长时间播放时可能偶尔出现断音。';

  @override
  String get noteDsdTitle => '支持 DSD';

  @override
  String get noteDsdDetail => '此 DAC 可接受原生 DSD。本应用尚不支持播放 DSD。';

  @override
  String get noteAltConfigTitle => '存在另一种 USB 模式';

  @override
  String noteAltConfigDetail(int count) {
    return '此设备提供 $count 种 USB 配置。只会使用当前激活的一种；有些 DAC 会在另一种里保留兼容模式。';
  }

  @override
  String get noteClockErrorTitle => '无法读取支持的采样率';

  @override
  String get reportCopied => '报告已复制';

  @override
  String get copyReport => '复制报告';

  @override
  String get stop => '停止';

  @override
  String get notReported => '未提供';

  @override
  String get verifyTitle => 'DAC 验证';

  @override
  String get verifyResults => '结果';

  @override
  String get verifyFollow => '跟随';

  @override
  String get soakTitle => '稳定性长测';

  @override
  String get soakRate => '采样率';

  @override
  String get soakLength => '时长';

  @override
  String soakStart(String rate, String duration) {
    return '以 $rate 测试 $duration';
  }

  @override
  String soakProgress(String elapsed, String planned, String step) {
    return '$elapsed / $planned  ·  $step';
  }

  @override
  String get soakFaults => '故障';

  @override
  String get soakRingFill => '缓冲区填充';

  @override
  String get soakMeasuredRate => '实测采样率';

  @override
  String get soakUnderruns => '缓冲欠载';

  @override
  String get soakTransferErrors => '传输错误';

  @override
  String get soakPacketErrors => '数据包错误';

  @override
  String get soakRebuffers => '重新缓冲次数';

  @override
  String get soakWorstRingFill => '缓冲区最低填充';

  @override
  String get soakWorstDeviation => '最大偏差';

  @override
  String get soakDriftSpread => '漂移范围';

  @override
  String get soakMeetsBar => '达到了十分钟零断音的标准。';

  @override
  String get soakShortOfBar => '不足十分钟，因此还说明不了那些硬件热起来之后才会出现的故障。';

  @override
  String get playFileTitle => '播放文件';

  @override
  String get playFileIntro =>
      '通过 DAC 播放你自己的文件并监视数据流，这正是测试音回答不了的问题：你真正拥有的音乐能否干净地播放。只有该素材中实际包含的采样率才会被测试。';

  @override
  String get playFileChoose => '选择文件';

  @override
  String get playFileFormats => 'FLAC、WAV、AIFF、MP3，以及引擎能解码的其他格式。';

  @override
  String get playFileCache => '已推送到应用缓存';

  @override
  String get playFileCacheDetail => 'M2 测试装置。仅支持 WAV，是通过 adb 调试手机时放入已知文件最快的方式。';

  @override
  String get playFileStreamHealth => '数据流状态';

  @override
  String get errServerUnreachable => '渲染器与媒体服务器失去了联系。';

  @override
  String get errServerRefused => '媒体服务器拒绝了这首曲目。';

  @override
  String get errDownloadFailed => '无法从服务器下载这首曲目。';

  @override
  String get errUndecodableFormat => '这首曲目的格式渲染器无法解码。';

  @override
  String get errDacRateUnsupported => '此 DAC 无法设置为这首曲目的采样率或位深度。';

  @override
  String get errDacConnectionLost => '渲染器与 DAC 的连接已断开。';

  @override
  String get errTrackCouldNotBePlayed => '无法播放这首曲目。';

  @override
  String errRateUnplayable(String rate, String ceiling) {
    return '此 DAC 无法播放 $rate；它的最高采样率是 $ceiling。';
  }

  @override
  String errStoppedAfterFailures(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '连续 $count 首曲目无法播放，已停止。',
    );
    return '$_temp0';
  }
}
