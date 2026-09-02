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

  const DacFormat({
    required this.alt,
    required this.format,
    required this.bits,
    required this.channels,
    required this.sync,
    required this.hasFeedback,
    required this.maxPacket,
  });

  factory DacFormat.fromJson(Map<String, dynamic> j) => DacFormat(
        alt: j['alt'] as int? ?? -1,
        format: j['format'] as String? ?? 'unknown',
        bits: j['bits'] as int? ?? -1,
        channels: j['channels'] as int? ?? -1,
        sync: (j['endpoint']?['sync'] as String?) ?? 'none',
        hasFeedback: j['feedbackEndpoint'] != null,
        maxPacket: (j['endpoint']?['maxPacket'] as int?) ?? 0,
      );

  bool get isPcm => format == 'PCM';
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
      (formats.where((f) => f.isPcm).map((f) => f.bits).toSet().toList()..sort());

  /// The app targets USB Audio Class 2.0 only. UAC1 is a 1998-era spec, capped
  /// at 24/96 over full-speed USB, and essentially absent from DACs anyone would
  /// pair with a bit-perfect renderer. Supporting it would mean a second rate
  /// negotiation path (rates live in the descriptors rather than behind a clock
  /// entity) and a second endpoint model, for hardware that is not out there.
  /// UAC1 devices are still *identified* so the app can say so plainly.
  bool get isSupported => uacVersion == '2.0';

  bool get supportsDsd => formats.any((f) => f.format == 'DSD');
  bool get isAsync => formats.any((f) => f.sync == 'async');
  bool get hasFeedback => formats.any((f) => f.hasFeedback);

  int? get maxRate => rates.isEmpty ? null : rates.reduce((a, b) => a > b ? a : b);
  int? get minRate => rates.isEmpty ? null : rates.reduce((a, b) => a < b ? a : b);

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
        title: uacVersion == '1.0'
            ? 'This DAC uses USB Audio Class 1.0'
            : 'USB Audio Class version not recognised',
        detail: uacVersion == '1.0'
            ? 'This app supports USB Audio Class 2.0 only. UAC 1.0 is limited to '
                '24-bit/96 kHz and is not supported here, so this DAC cannot be '
                'used for bit-perfect playback.'
            : 'The device did not report a USB Audio Class version this app '
                'recognises, so it cannot be used for bit-perfect playback.',
      ));
      return out;
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
