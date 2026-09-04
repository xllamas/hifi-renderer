import 'dart:convert';

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
  List<CapabilityNote> get notes {
    final out = <CapabilityNote>[];

    if (!isSupported) {
      out.add(CapabilityNote(
        severity: NoteSeverity.important,
        title: 'This device cannot play audio',
        detail: 'It advertises the USB audio class but offers no PCM output '
            'over an isochronous endpoint. Capture-only devices look like this '
            '\u2014 a USB microphone, or the recording half of a headset adapter.',
      ));
      return out;
    }

    if (uacVersion == '1.0') {
      out.add(CapabilityNote(
        severity: NoteSeverity.info,
        title: 'This device uses USB Audio Class 1.0',
        detail: 'Supported, with the limits the class itself imposes: full-speed '
            'USB caps the bandwidth, so UAC1 devices top out well below what a '
            'UAC2 DAC offers. Playback is still bit-perfect at the rates it does '
            'support \u2014 nothing is resampled.',
      ));
    }

    if (isAdaptiveOnly) {
      out.add(CapabilityNote(
        severity: NoteSeverity.info,
        title: 'This device follows the phone\u0027s clock',
        detail: 'Its endpoint is adaptive rather than asynchronous, so it adapts '
            'to the rate the phone sends instead of running its own clock and '
            'asking the phone to follow. Common on UAC1 hardware. Samples still '
            'arrive unaltered; the timing reference is simply the phone\u0027s.',
      ));
    }

    if (!volumeHostControllable) {
      out.add(CapabilityNote(
        severity: NoteSeverity.important,
        title: 'Volume is controlled by the DAC, not this app',
        detail: hidPresent && !hidHasOutputEndpoint
            ? 'This device exposes no USB volume control. It does report its own '
                'knob or remote to the phone, but that is one-way: nothing sent '
                'from here can change its volume. Use the physical control.'
            : 'This device exposes no USB volume control, so volume commands from '
                'a DLNA controller cannot reach it. Use the physical control.',
      ));
    } else {
      out.add(CapabilityNote(
        severity: NoteSeverity.good,
        title: 'Volume can be set from this app',
        detail: 'The DAC exposes a USB volume control ($volumeDetail), so DLNA '
            'volume commands are passed straight to the hardware.',
      ));
    }

    if (requiresPaddingFor16Bit) {
      final target = pcmBitDepths.first;
      out.add(CapabilityNote(
        severity: NoteSeverity.info,
        title: '16-bit tracks are padded to $target-bit',
        detail: 'This DAC offers no 16-bit mode, so CD-resolution files are '
            'placed in a $target-bit container. The sample values are unchanged, '
            'so playback is still bit-perfect.',
      ));
    }

    if (isAsync && hasFeedback) {
      out.add(CapabilityNote(
        severity: NoteSeverity.good,
        title: 'Asynchronous USB with its own clock',
        detail: 'The DAC drives timing rather than following the phone, which is '
            'the better arrangement for audio quality.',
      ));
    } else if (isAsync && !hasFeedback) {
      out.add(CapabilityNote(
        severity: NoteSeverity.important,
        title: 'Asynchronous, but no feedback endpoint found',
        detail: 'Timing cannot be tracked precisely, so occasional dropouts are '
            'possible on long playback.',
      ));
    }

    if (supportsDsd) {
      out.add(CapabilityNote(
        severity: NoteSeverity.info,
        title: 'DSD capable',
        detail: 'This DAC accepts native DSD. The app does not play DSD yet.',
      ));
    }

    if (configurations > 1) {
      out.add(CapabilityNote(
        severity: NoteSeverity.info,
        title: 'Alternative USB mode available',
        detail: 'The device offers $configurations USB configurations. Only the '
            'active one is used; some DACs keep a compatibility mode in the other.',
      ));
    }

    if (clockError.isNotEmpty) {
      out.add(CapabilityNote(
        severity: NoteSeverity.important,
        title: 'Could not read the supported sample rates',
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
