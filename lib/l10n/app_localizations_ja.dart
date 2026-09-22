// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Japanese (`ja`).
class AppLocalizationsJa extends AppLocalizations {
  AppLocalizationsJa([String locale = 'ja']) : super(locale);

  @override
  String get settingsTooltip => '設定';

  @override
  String get idleReady => '待機中 — コントローラーからの指示を待っています';

  @override
  String get idleNoDac => 'DAC が接続されていません';

  @override
  String get unknownTrack => '不明なトラック';

  @override
  String airPlayFromSender(String sender) {
    return '$sender からの AirPlay';
  }

  @override
  String get previousTrack => '前のトラック';

  @override
  String get nextTrack => '次のトラック';

  @override
  String get pause => '一時停止';

  @override
  String get play => '再生';

  @override
  String get volumeWriteOnly => 'この DAC は音量を返さないため、ここにはアプリが最後に送った値が表示されます。';

  @override
  String get systemAudioDetail => '本体スピーカーまたはヘッドホン — Android によりリサンプリング';

  @override
  String dacOneOf(int count) {
    return '（$count 台中 1 台目）';
  }

  @override
  String get bitPerfect => 'ビットパーフェクト';

  @override
  String get systemAudioBadge => 'システム音声';

  @override
  String get airPlaySenderResampled => 'AirPlay · 送信側でリサンプリング済み';

  @override
  String get settingsTitle => '設定';

  @override
  String get settingsNetworkName => 'ネットワーク上の名前';

  @override
  String get settingsNetworkNameHelp => 'このレンダラーが DLNA コントローラーに表示される名前です。';

  @override
  String get settingsSave => '保存';

  @override
  String get settingsSaved => '保存しました';

  @override
  String get settingsRenamed => '名前を変更しました。コントローラーに反映するにはアプリを再起動してください。';

  @override
  String get settingsAudioDevice => 'オーディオ機器';

  @override
  String settingsDacsMultiple(int count) {
    return 'USB オーディオ機器が $count 台接続されています。どれで再生するか選んでください。選択は再起動後も保持されます。';
  }

  @override
  String get settingsDacsSingle =>
      'USB オーディオ機器が 1 台接続されています。タップするとその機器で再生し、まだ許可がなければ許可も求めます。';

  @override
  String get settingsUsbAudioDevice => 'USB オーディオ機器';

  @override
  String get settingsPermissionNotGranted => ' — 許可がありません';

  @override
  String get settingsReadingDevice => '機器を読み取っています…';

  @override
  String get settingsProbing => 'DAC に対応形式を問い合わせています';

  @override
  String settingsUacTap(String version) {
    return 'USB Audio Class $version — タップすると対応内容を表示';
  }

  @override
  String get settingsConnectToProbe => 'USB DAC を接続してタップすると調べます';

  @override
  String get settingsPcmOnly => 'PCM ストリームのみを受け付け、デコードや変換はサーバーに任せる';

  @override
  String get settingsPcmOnlyOn =>
      'レンダラーは、この DAC が扱えるサンプリング周波数の LPCM だけを提示するため、サーバーがすべてを合わせて変換します。何でも再生できますが、どれもビットパーフェクトではありません。DAC がそのまま再生できたはずのトラックも含めてです。';

  @override
  String get settingsPcmOnlyOff =>
      'レンダラーはデコードできるすべての形式を提示するため、ファイルは手を加えられずに届きます。この DAC が扱えないサンプリング周波数のトラックは、理由を示したうえで拒否されます。';

  @override
  String get settingsScreenOffAfter => '画面を消すまでの時間';

  @override
  String get settingsScreenOffNever =>
      '画面は点いたままになります。常時給電の端末なら問題ありませんが、OLED パネルに同じ画面を何か月も表示し続けると、そのまま焼き付きます。';

  @override
  String get settingsScreenOffTimed =>
      '音楽が止まった時点から数えます。長いトラックの途中で画面が消えることはありません。再生が始まれば再び点灯します。';

  @override
  String get settingsTimeoutNever => 'しない';

  @override
  String settingsTimeoutMinutes(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: '$minutes 分',
    );
    return '$_temp0';
  }

  @override
  String get settingsDacVerification => 'DAC の検証';

  @override
  String get settingsDacVerificationSubtitle => 'この DAC が公称するすべての周波数を試す';

  @override
  String get settingsAlwaysOn => '常時稼働';

  @override
  String get settingsAlwaysOnHelp =>
      '専用レンダラーは画面を消したまま動き続け、再起動後も復帰する必要があります。Android と多くのメーカーは既定でそれを妨げます。';

  @override
  String settingsDeaths(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'この端末はレンダラーを $count 回停止させています',
    );
    return '$_temp0';
  }

  @override
  String get settingsDeathsDetail =>
      'いずれも、正常な停止を記録しないまま終わった実行の直後に起動したものです。つまりバックグラウンドで何かに終了させられています。下記を許可すればたいてい解決します。';

  @override
  String get settingsBattery => '電池最適化の除外';

  @override
  String get settingsBatteryGranted => '許可済み — Android はレンダラーを停止させません。';

  @override
  String get settingsBatteryNotGranted =>
      '未許可です。待機中に Android がレンダラーを停止させることがあります。';

  @override
  String get settingsGrant => '許可する';

  @override
  String get settingsOpenSettings => '設定を開く';

  @override
  String get settingsCouldNotOpen => 'この端末ではその設定画面を開けませんでした。';

  @override
  String settingsAutostart(String vendor) {
    return '自動起動（$vendor）';
  }

  @override
  String get settingsAutostartVendorFallback => 'メーカー';

  @override
  String get settingsAutostartDetail =>
      'このメーカーの端末は、Android とは別に独自のバックグラウンド制限を加えているのが普通で、再起動後にレンダラーが起動しない原因はたいていそれです。アプリ側からは検出できず、このメーカーにそうした画面があることしか分かりません。';

  @override
  String get settingsWakeScreen => '音楽が始まったら画面を点ける';

  @override
  String get settingsWakeScreenDetail =>
      'この端末では、画面が暗いまま音楽が再生されたことがあります。表示中のウィンドウを持たないアプリからの画面点灯要求を Android は解除しますが、この端末はレンダラーが自分のウィンドウを表示することも許さなかったため、画面は一瞬点いてまた消えました。この権限は「バックグラウンドでポップアップ画面を表示」といった名前であることが多く、自動起動とは別物です。';

  @override
  String get settingsRunSetup => 'セットアップをやり直す';

  @override
  String get settingsRunSetupSubtitle => '権限を順番に確認する';

  @override
  String get settingsLegal => '法的情報';

  @override
  String get settingsLicenses => 'オープンソースライセンス';

  @override
  String get settingsLicensesSubtitle => 'このアプリを支えているもの';

  @override
  String get settingsLicensesLegalese =>
      'Apache License 2.0。ここに記載された LGPL、Apache、CDDL、BSD、CC0 およびパブリックドメインの条件で公開された成果物に基づいています。';

  @override
  String get settingsLanguage => '言語';

  @override
  String get settingsLanguageSystem => 'この端末に合わせる';

  @override
  String get settingsLanguageHelp =>
      '別途選ばないかぎり、レンダラーはこの端末の言語に従います。予備の端末で設定した機器は、誰も望まなかった言語を引き継いでしまいがちです。';

  @override
  String get onboardingTitle => 'HiFi Renderer をセットアップ';

  @override
  String get onboardingTitleRerun => 'セットアップ';

  @override
  String get onboardingIntro =>
      'この端末はどこかに据え置かれ、レンダラーとして働きます。Android と多くのメーカーは、そんなことを望むアプリはないという前提で作られているため、いくつかの設定を手動で有効にする必要があります。';

  @override
  String get onboardingOptional => 'どれもアプリを試すために必須ではありませんし、あとから設定でいつでも変更できます。';

  @override
  String get onboardingNotifications => '通知を表示する';

  @override
  String get onboardingNotificationsGranted => '許可済みです。動作中はレンダラーの通知が表示されます。';

  @override
  String get onboardingNotificationsWhy =>
      '通知がないと Android はレンダラーのバックグラウンド実行を許さず、また通知はレンダラーが生きている唯一の目に見える印でもあります。';

  @override
  String get onboardingAllow => '許可';

  @override
  String get onboardingNoNotificationScreen => 'この端末には開ける通知設定画面がありません。';

  @override
  String get onboardingNotificationsInSettings =>
      'Android は確認を求めなくなりました — その画面で通知を有効にしてください。';

  @override
  String get onboardingBattery => 'Android に停止させない';

  @override
  String get onboardingBatteryGranted =>
      '許可済みです。待機中に Android がレンダラーを停止させることはありません。';

  @override
  String get onboardingBatteryWhy =>
      'これがないと、画面が消えてしばらくすると Android がアプリを停止させ、再生がトラックの途中で止まります。';

  @override
  String get onboardingUsbPrompt => 'DAC について Android に尋ねさせない';

  @override
  String get onboardingUsbPromptGranted =>
      '許可済みです。次に DAC が接続されたとき、Android の確認で「常に開く」にチェックを入れると、以後は尋ねられません。';

  @override
  String get onboardingUsbPromptWhy =>
      'マイクの権限がないと、Android は DAC の電源を入れるたびにアプリを開くか尋ね、尋ねないようにする選択肢も表示しません。許可したうえで、次に DAC が接続されたときに「常に開く」にチェックを入れてください。アプリが録音することはありません。';

  @override
  String get onboardingUsbPromptInSettings =>
      'Android は確認を求めなくなりました — その画面の「権限」でマイクを許可してください。';

  @override
  String onboardingVendorKnown(String vendor) {
    return '自動起動（$vendor）';
  }

  @override
  String get onboardingVendorKnownNoName => '自動起動';

  @override
  String get onboardingVendorUnknown => 'お使いの端末メーカー独自の制限';

  @override
  String get onboardingVendorKnownDetail =>
      'このメーカーの端末は、Android とは別に独自のバックグラウンド制限を加えているのが普通で、再起動後にレンダラーが復帰しない原因はたいていそれです。アプリ側からは検出できず——このメーカーにそうした画面があることしか分かりません——そこで何を許可したかも分からないため、この項目にチェックが付くことはありません。';

  @override
  String get onboardingVendorUnknownDetail =>
      'この端末に対応する設定画面は分かりません。待機中にレンダラーが止まる、あるいは再起動後に復帰しない場合は、端末の電池設定で「自動起動」「バックグラウンドアプリ」「保護されたアプリ」といった項目を探してください。';

  @override
  String get onboardingDac => 'お使いの DAC';

  @override
  String get onboardingDacDetail =>
      'USB DAC はいつ接続してもかまいません。初めて接続したときに Android が許可を求めるので、ここで行うことはありません。レンダラーは特定の DAC 用に設定されるのではなく、そのとき接続されている DAC に合わせて動きます。';

  @override
  String get onboardingDone => '完了';

  @override
  String get onboardingFinishAnyway => 'このまま終了';

  @override
  String get onboardingAllGranted => 'アプリが確認できるものはすべて許可されています。';

  @override
  String get onboardingSkippingIsFine =>
      '飛ばしてもかまいません。レンダラーは動きます。ただ、放っておいたときに生き延びられないかもしれないだけで、何かに止められていれば設定画面が教えてくれます。';

  @override
  String onboardingStep(int number, String title) {
    return '$number. $title';
  }

  @override
  String get dacCapsTitle => 'DAC の対応内容';

  @override
  String get dacCapsReprobe => '再度調べる';

  @override
  String get dacCapsNotProbed => 'まだ調べていません';

  @override
  String get dacCapsNotProbedDetail => 'USB DAC を接続して更新をタップしてください。';

  @override
  String get dacCapsUnknownError => '不明なエラーです。';

  @override
  String get dacCapsNoDevice => 'DAC が見つかりません';

  @override
  String get dacCapsPermissionNeeded => '許可が必要です';

  @override
  String get dacCapsOpenFailed => 'DAC を開けませんでした';

  @override
  String get dacCapsProbeFailed => '調査に失敗しました';

  @override
  String get dacCapsNotUsable => 'ビットパーフェクト再生には使えません';

  @override
  String get dacCapsWorthKnowing => '知っておきたいこと';

  @override
  String get dacCapsWhatItSupports => '対応内容';

  @override
  String dacCapsIdentity(
    String version,
    String speed,
    String vendor,
    String product,
  ) {
    return 'USB Audio Class $version · $speed スピード · $vendor:$product';
  }

  @override
  String get dacCapsSampleRates => 'サンプリング周波数';

  @override
  String get dacCapsBitDepths => 'ビット深度';

  @override
  String get dacCapsChannels => 'チャンネル数';

  @override
  String get dacCapsCurrentlyAt => '現在の動作周波数';

  @override
  String get dacCapsUsbTiming => 'USB の同期方式';

  @override
  String get dacCapsVolumeControl => '音量制御';

  @override
  String get dacCapsDsd => 'DSD';

  @override
  String get dacCapsUnknown => '不明';

  @override
  String dacCapsRateRange(String low, String high, int count) {
    return '$low – $high（$count 種類）';
  }

  @override
  String dacCapsBitDepth(int bits) {
    return '$bits ビット';
  }

  @override
  String get dacCapsAsync => 'アシンクロナス（DAC のクロック）';

  @override
  String get dacCapsSync => 'シンクロナス';

  @override
  String get dacCapsVolumeOverUsb => 'USB 経由で対応';

  @override
  String get dacCapsVolumeDeviceOnly => '本体側のみ';

  @override
  String get dacCapsDsdSupported => 'ハードウェアが対応';

  @override
  String get dacCapsTechnical => '技術的な詳細';

  @override
  String get dacCapsTechnicalSubtitle => '問い合わせ用';

  @override
  String dacCapsKhz(String value) {
    return '$value kHz';
  }

  @override
  String get noteCannotPlayTitle => 'この機器は音声を再生できません';

  @override
  String get noteCannotPlayDetail =>
      'USB オーディオクラスを名乗っていますが、アイソクロナス転送での PCM 出力を持っていません。録音専用の機器はこう見えます——USB マイクや、ヘッドセットアダプターの録音側などです。';

  @override
  String get noteUac1Title => 'この機器は USB Audio Class 1.0 を使用します';

  @override
  String get noteUac1Detail =>
      '対応しています。ただし規格自体の制約は残ります。フルスピード USB が帯域を制限するため、UAC1 機器は UAC2 の DAC よりかなり低いところで頭打ちになります。対応する周波数においては、再生は変わらずビットパーフェクトです——リサンプリングは一切行われません。';

  @override
  String get noteAdaptiveTitle => 'この機器は端末のクロックに従います';

  @override
  String get noteAdaptiveDetail =>
      'エンドポイントがアシンクロナスではなくアダプティブなので、自分のクロックで動いて端末に合わせさせるのではなく、端末が送る周波数のほうに合わせます。UAC1 のハードウェアではよくあることです。サンプル自体は変わらず届き、時間の基準が端末側にあるというだけです。';

  @override
  String get noteVolumeDeviceTitle => '音量は本アプリではなく DAC が制御します';

  @override
  String get noteVolumeOneWayDetail =>
      'この機器は USB 経由の音量制御を持っていません。自分のつまみやリモコンの状態を端末に伝えてはきますが、それは一方通行で、こちらから送るものでは音量を変えられません。本体側の操作子をお使いください。';

  @override
  String get noteVolumeNoneDetail =>
      'この機器は USB 経由の音量制御を持たないため、DLNA コントローラーからの音量指示は届きません。本体側の操作子をお使いください。';

  @override
  String get noteVolumeAppTitle => '音量を本アプリから設定できます';

  @override
  String noteVolumeAppDetail(String detail) {
    return 'この DAC は USB 経由の音量制御（$detail）を備えているため、DLNA の音量指示はそのままハードウェアに渡されます。';
  }

  @override
  String notePaddedTitle(int bits) {
    return '16 ビットのトラックは $bits ビットに詰められます';
  }

  @override
  String notePaddedDetail(int bits) {
    return 'この DAC には 16 ビットのモードがないため、CD 品質のファイルは $bits ビットの器に収められます。サンプルの値は変わらないので、再生は変わらずビットパーフェクトです。';
  }

  @override
  String get noteAsyncGoodTitle => '自前のクロックを持つアシンクロナス USB';

  @override
  String get noteAsyncGoodDetail =>
      '端末に従うのではなく DAC がタイミングを主導します。音質の面ではこちらのほうが望ましい構成です。';

  @override
  String get noteAsyncNoFeedbackTitle => 'アシンクロナスですが、フィードバックエンドポイントが見つかりません';

  @override
  String get noteAsyncNoFeedbackDetail =>
      'タイミングを正確に追えないため、長時間の再生では時折音切れが起きることがあります。';

  @override
  String get noteDsdTitle => 'DSD に対応';

  @override
  String get noteDsdDetail => 'この DAC はネイティブ DSD を受け付けます。本アプリはまだ DSD を再生しません。';

  @override
  String get noteAltConfigTitle => '別の USB モードがあります';

  @override
  String noteAltConfigDetail(int count) {
    return 'この機器は USB 構成を $count 種類持っています。使われるのは有効なものだけです。DAC によっては、もう一方に互換モードを持たせていることがあります。';
  }

  @override
  String get noteClockErrorTitle => '対応するサンプリング周波数を読み取れませんでした';

  @override
  String get reportCopied => 'レポートをコピーしました';

  @override
  String get copyReport => 'レポートをコピー';

  @override
  String get stop => '停止';

  @override
  String get notReported => '報告なし';

  @override
  String get verifyTitle => 'DAC の検証';

  @override
  String get verifyResults => '結果';

  @override
  String get verifyFollow => '追従';

  @override
  String get soakTitle => '連続動作テスト';

  @override
  String get soakRate => '周波数';

  @override
  String get soakLength => '長さ';

  @override
  String soakStart(String rate, String duration) {
    return '$rate で $duration テストする';
  }

  @override
  String soakProgress(String elapsed, String planned, String step) {
    return '$planned 中 $elapsed  ·  $step';
  }

  @override
  String get soakFaults => '障害';

  @override
  String get soakRingFill => 'バッファ残量';

  @override
  String get soakMeasuredRate => '実測周波数';

  @override
  String get soakUnderruns => 'アンダーラン';

  @override
  String get soakTransferErrors => '転送エラー';

  @override
  String get soakPacketErrors => 'パケットエラー';

  @override
  String get soakRebuffers => '再バッファリング';

  @override
  String get soakWorstRingFill => 'バッファ残量の最小値';

  @override
  String get soakWorstDeviation => '最大偏差';

  @override
  String get soakDriftSpread => 'ドリフト幅';

  @override
  String get soakMeetsBar => '10 分間、音切れゼロの基準を満たしました。';

  @override
  String get soakShortOfBar =>
      '10 分に届いていないため、ハードウェアが温まってから現れる障害についてはまだ何も言えません。';

  @override
  String get playFileTitle => 'ファイルを再生';

  @override
  String get playFileIntro =>
      '手持ちのファイルを DAC で再生しながらストリームを監視します。これはテストトーンでは問えない問い——実際に所有している音源がきちんと鳴るかどうか——に答えるものです。テストされるのは、その音源に含まれる周波数だけです。';

  @override
  String get playFileChoose => 'ファイルを選ぶ';

  @override
  String get playFileFormats => 'FLAC、WAV、AIFF、MP3、そしてエンジンがデコードできるその他の形式。';

  @override
  String get playFileCache => 'アプリのキャッシュに転送済み';

  @override
  String get playFileCacheDetail =>
      'M2 テスト装置。WAV のみで、adb でデバッグ中の端末に既知のファイルを置くいちばん速い方法です。';

  @override
  String get playFileStreamHealth => 'ストリームの状態';

  @override
  String get errServerUnreachable => 'レンダラーがメディアサーバーとの連絡を失いました。';

  @override
  String get errServerRefused => 'メディアサーバーがこのトラックを拒否しました。';

  @override
  String get errDownloadFailed => 'このトラックをサーバーからダウンロードできませんでした。';

  @override
  String get errUndecodableFormat => 'このトラックはレンダラーがデコードできない形式です。';

  @override
  String get errDacRateUnsupported =>
      'この DAC は、このトラックのサンプリング周波数またはビット深度に設定できません。';

  @override
  String get errDacConnectionLost => 'レンダラーが DAC との接続を失いました。';

  @override
  String get errTrackCouldNotBePlayed => 'このトラックは再生できませんでした。';

  @override
  String errRateUnplayable(String rate, String ceiling) {
    return 'この DAC は $rate を再生できません。対応する最高周波数は $ceiling です。';
  }

  @override
  String errStoppedAfterFailures(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 曲続けて再生できなかったため停止しました。',
    );
    return '$_temp0';
  }
}
