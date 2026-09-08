import 'dart:convert';
import '../l10n/app_localizations.dart';

/// One playable configuration on the DAC (a USB alt-setting).
class DacFormat {
  final int alt;
  final String format; // PCM, DSD, FLOAT, ...
  final int bits;
  final int channels;
  final String sync; // async, adaptive, sync, none
  final bool hasFeedback;
  final int maxPacket;

  /// UAC1 lists rates per alt-setting; UAC2 keeps them on the clock entity and
  /// leaves this empty.
  final List<int> rates;

  /// Whether this is an output. A capture alt-setting looks identical apart
  /// from endpoint direction, and a UAC1 headset adapter exposes both.
  final bool isOutput;

  const DacFormat({
    required this.alt,
    required this.format,
    required this.bits,
    required this.channels,
    required this.sync,
    required this.hasFeedback,
    required this.maxPacket,
    required this.rates,
    required this.isOutput,
  });

  factory DacFormat.fromJson(Map<String, dynamic> j) => DacFormat(
        alt: j['alt'] as int? ?? -1,
        format: j['format'] as String? ?? 'unknown',
        bits: j['bits'] as int? ?? -1,
        channels: j['channels'] as int? ?? -1,
        sync: (j['endpoint']?['sync'] as String?) ?? 'none',
        hasFeedback: j['feedbackEndpoint'] != null,
        maxPacket: (j['endpoint']?['maxPacket'] as int?) ?? 0,
        rates: ((j['rates'] as List?) ?? const []).cast<int>(),
        // The parser only fills the data endpoint for an isochronous OUT, so a
        // present iso endpoint is the same statement as "this can play".
        isOutput: (j['endpoint']?['iso'] as bool?) ?? false,
      );

  bool get isPcm => format == 'PCM';

  /// Usable for playback: PCM, out, over an isochronous endpoint.
  bool get isPlayable => isPcm && isOutput;
}

/// What the attached DAC can actually do, as measured rather than as documented.
///
/// Manufacturer documentation is frequently silent on the things that matter
/// most -- notably whether the host can control volume at all -- so this model
/// is built entirely from the device's own descriptors.
class DacCapabilities {
  final bool ok;
  final String? error;
  final String? errorMessage;

  final String manufacturer;
  final String product;
  final String vendorIdHex;
  final String productIdHex;
  final String uacVersion;
  final String speed;
  final int configurations;
  final bool claimedAudioControl;

  final List<int> rates;
  final int currentRate;
  final bool clockProgrammable;
  final String clockError;

  final bool volumeHostControllable;
  final String volumeDetail;
  final bool hidPresent;
  final bool hidHasOutputEndpoint;

  final List<DacFormat> formats;
  final String rawJson;

  const DacCapabilities._({
    required this.ok,
    this.error,
    this.errorMessage,
    this.manufacturer = '',
    this.product = '',
    this.vendorIdHex = '',
    this.productIdHex = '',
    this.uacVersion = 'unknown',
    this.speed = 'unknown',
    this.configurations = 1,
    this.claimedAudioControl = false,
    this.rates = const [],
    this.currentRate = 0,
    this.clockProgrammable = false,
    this.clockError = '',
    this.volumeHostControllable = false,
    this.volumeDetail = '',
    this.hidPresent = false,
    this.hidHasOutputEndpoint = false,
    this.formats = const [],
    this.rawJson = '',
  });

  static DacCapabilities parse(String source) {
    late final Map<String, dynamic> j;
    try {
      j = jsonDecode(source) as Map<String, dynamic>;
    } catch (_) {
      return DacCapabilities._(
        ok: false,
        error: 'bad_response',
        errorMessage: source,
        rawJson: source,
      );
    }

    if (j['ok'] != true) {
      return DacCapabilities._(
        ok: false,
        error: j['error'] as String?,
        errorMessage: j['message'] as String?,
        rawJson: source,
      );
    }

    final dac = (j['dac'] as Map<String, dynamic>?) ?? const {};
    if (dac['ok'] != true) {
      return DacCapabilities._(
        ok: false,
        error: dac['error'] as String? ?? 'probe_failed',
        errorMessage: dac['message'] as String?,
        rawJson: source,
      );
    }

    final clock = (dac['clock'] as Map<String, dynamic>?) ?? const {};
    final volume = (dac['volume'] as Map<String, dynamic>?) ?? const {};

    return DacCapabilities._(
      ok: true,
      manufacturer: dac['manufacturer'] as String? ?? '',
      product: dac['product'] as String? ?? '',
      vendorIdHex: dac['vendorIdHex'] as String? ?? '',
      productIdHex: dac['productIdHex'] as String? ?? '',
      uacVersion: dac['uacVersion'] as String? ?? 'unknown',
      speed: dac['speed'] as String? ?? 'unknown',
      configurations: dac['configurations'] as int? ?? 1,
      claimedAudioControl: j['claimedAudioControl'] as bool? ?? false,
      rates: ((clock['rates'] as List?) ?? const []).cast<int>(),
      currentRate: clock['currentRate'] as int? ?? 0,
      clockProgrammable: clock['programmable'] as bool? ?? false,
      clockError: clock['error'] as String? ?? '',
      volumeHostControllable: volume['hostControllable'] as bool? ?? false,
      volumeDetail: volume['detail'] as String? ?? '',
      hidPresent: volume['hidPresent'] as bool? ?? false,
      hidHasOutputEndpoint: volume['hidHasOutputEndpoint'] as bool? ?? false,
      formats: ((dac['formats'] as List?) ?? const [])
          .map((e) => DacFormat.fromJson(e as Map<String, dynamic>))
          .toList(),
      rawJson: source,
    );
  }

  String get displayName {
    final n = [manufacturer, product].where((s) => s.isNotEmpty).join(' ');
    return n.isEmpty ? 'USB audio device' : n;
  }

  List<int> get pcmBitDepths =>
      (formats.where((f) => f.isPlayable).map((f) => f.bits).toSet().toList()..sort());

  /// Every rate the device can actually clock.
  ///
  /// UAC2 answers this from the clock entity, so [rates] is authoritative.
  /// UAC1 has no clock entity and lists rates per alt-setting instead, so they
  /// have to be gathered from the playable formats.
  List<int> get playableRates {
    if (rates.isNotEmpty) return rates;
    final out = <int>{};
    for (final f in formats.where((f) => f.isPlayable)) {
      out.addAll(f.rates);
    }
    return out.toList()..sort();
  }

  /// Whether the app can play through this device.
  ///
  /// Deliberately not a class-version test. Both UAC1 and UAC2 are supported,
  /// and the thing that actually decides the question is whether the device
  /// offers PCM out over an isochronous endpoint -- which a USB microphone, or
  /// the capture half of a headset adapter, does not.
  bool get isSupported => formats.any((f) => f.isPlayable);

  bool get supportsDsd => formats.any((f) => f.format == 'DSD');
  bool get isAsync => formats.any((f) => f.sync == 'async');

  /// No asynchronous output at all: the device takes its timing from the host.
  bool get isAdaptiveOnly =>
      isSupported && !formats.any((f) => f.isPlayable && f.sync == 'async');
  bool get hasFeedback => formats.any((f) => f.hasFeedback);

  int? get maxRate => playableRates.isEmpty
      ? null
      : playableRates.reduce((a, b) => a > b ? a : b);
  int? get minRate => playableRates.isEmpty
      ? null
      : playableRates.reduce((a, b) => a < b ? a : b);

  /// True when 16-bit sources must be padded because the DAC offers no 16-bit
  /// alt-setting. Padding preserves sample values, so playback stays bit-perfect.
  bool get requiresPaddingFor16Bit =>
      pcmBitDepths.isNotEmpty && !pcmBitDepths.contains(16);

  /// Plain-language notes. These are the things a datasheet tends not to say.
  ///
  /// Takes the strings rather than reading a context: this is a model, built
  /// and tested without a widget tree, and the notes are prose a reader has to
  /// understand rather than data.
  List<CapabilityNote> notes(AppLocalizations t) {
    final out = <CapabilityNote>[];

    if (!isSupported) {
      out.add(CapabilityNote(
        severity: NoteSeverity.important,
        title: t.noteCannotPlayTitle,
        detail: t.noteCannotPlayDetail,
      ));
      return out;
    }

    if (uacVersion == '1.0') {
      out.add(CapabilityNote(
        severity: NoteSeverity.info,
        title: t.noteUac1Title,
        detail: t.noteUac1Detail,
      ));
    }

    if (isAdaptiveOnly) {
      out.add(CapabilityNote(
        severity: NoteSeverity.info,
        title: t.noteAdaptiveTitle,
        detail: t.noteAdaptiveDetail,
      ));
    }

    if (!volumeHostControllable) {
      out.add(CapabilityNote(
        severity: NoteSeverity.important,
        title: t.noteVolumeDeviceTitle,
        detail: hidPresent && !hidHasOutputEndpoint
            ? t.noteVolumeOneWayDetail
            : t.noteVolumeNoneDetail,
      ));
    } else {
      out.add(CapabilityNote(
        severity: NoteSeverity.good,
        title: t.noteVolumeAppTitle,
        detail: t.noteVolumeAppDetail(volumeDetail),
      ));
    }

    if (requiresPaddingFor16Bit) {
      final target = pcmBitDepths.first;
      out.add(CapabilityNote(
        severity: NoteSeverity.info,
        title: t.notePaddedTitle(target),
        detail: t.notePaddedDetail(target),
      ));
    }

    if (isAsync && hasFeedback) {
      out.add(CapabilityNote(
        severity: NoteSeverity.good,
        title: t.noteAsyncGoodTitle,
        detail: t.noteAsyncGoodDetail,
      ));
    } else if (isAsync && !hasFeedback) {
      out.add(CapabilityNote(
        severity: NoteSeverity.important,
        title: t.noteAsyncNoFeedbackTitle,
        detail: t.noteAsyncNoFeedbackDetail,
      ));
    }

    if (supportsDsd) {
      out.add(CapabilityNote(
        severity: NoteSeverity.info,
        title: t.noteDsdTitle,
        detail: t.noteDsdDetail,
      ));
    }

    if (configurations > 1) {
      out.add(CapabilityNote(
        severity: NoteSeverity.info,
        title: t.noteAltConfigTitle,
        detail: t.noteAltConfigDetail(configurations),
      ));
    }

    if (clockError.isNotEmpty) {
      out.add(CapabilityNote(
        severity: NoteSeverity.important,
        title: t.noteClockErrorTitle,
        // The engine's own words. Diagnostic, and left in English on purpose.
        detail: clockError,
      ));
    }

    return out;
  }
}

enum NoteSeverity { good, info, important }

class CapabilityNote {
  final NoteSeverity severity;
  final String title;
  final String detail;
  const CapabilityNote({
    required this.severity,
    required this.title,
    required this.detail,
  });
}

/// The result of probing whichever DAC is currently selected, plus whether a
/// probe is in flight.
///
/// This travels as one value because the two are only meaningful together: a
/// null [caps] means "no DAC" while idle but "still asking" while [probing],
/// and showing the first when the second is true is how a screen ends up
/// claiming there is no DAC attached to a phone that has two.
class DacProbeState {
  final DacCapabilities? caps;
  final bool probing;

  const DacProbeState({this.caps, this.probing = false});

  DacProbeState asProbing() => DacProbeState(caps: caps, probing: true);
}
