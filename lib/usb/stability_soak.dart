/// An extended run at one rate, and what it found.
///
/// The sweep answers bandwidth: can this DAC be driven at each rate it claims,
/// for a few seconds. It cannot answer endurance. Slow clock drift, thermal
/// throttling and rare scheduler stalls all take minutes to appear, and every
/// one of them is audible when it does.
///
/// This is also where the plan's own bar lives -- ten minutes of continuous
/// playback with zero dropouts -- surfaced as something a user can run rather
/// than a line in a document.
library;

import 'rate_sweep.dart' show SweepVerdict, kRateTolerancePercent;

export 'rate_sweep.dart' show SweepVerdict;

/// The plan's requirement, and the shortest run that proves anything about
/// endurance rather than start-up.
const Duration kSoakBar = Duration(minutes: 10);

/// One poll of the stream, with counters already relative to the baseline
/// taken after the stream settled.
class SoakSample {
  final Duration at;
  final double measuredRateHz;
  final int underruns;
  final int transferErrors;
  final int packetErrors;
  final int rebuffers;

  /// How full the ring was. A dip long before an underrun is the early
  /// warning; by the time the counter moves the audio has already gone.
  final int ringFillPercent;

  const SoakSample({
    required this.at,
    required this.measuredRateHz,
    this.underruns = 0,
    this.transferErrors = 0,
    this.packetErrors = 0,
    this.rebuffers = 0,
    this.ringFillPercent = 100,
  });

  int get faults => underruns + transferErrors + packetErrors;
}

class SoakResult {
  final String deviceName;
  final String uacVersion;
  final int rate;
  final int bits;
  final int altSetting;
  final Duration planned;
  final DateTime when;

  /// False when the run was stopped early, or the engine died under it.
  final bool completed;

  /// Why it ended early, when it did.
  final String? failure;

  final List<SoakSample> samples;

  const SoakResult({
    required this.deviceName,
    required this.uacVersion,
    required this.rate,
    required this.bits,
    required this.altSetting,
    required this.planned,
    required this.when,
    required this.completed,
    required this.samples,
    this.failure,
  });

  Duration get actual => samples.isEmpty ? Duration.zero : samples.last.at;

  SoakSample? get _last => samples.isEmpty ? null : samples.last;

  int get underruns => _last?.underruns ?? 0;
  int get transferErrors => _last?.transferErrors ?? 0;
  int get packetErrors => _last?.packetErrors ?? 0;
  int get rebuffers => _last?.rebuffers ?? 0;
  int get faults => _last?.faults ?? 0;

  bool get isClean => faults == 0 && failure == null;

  /// Whether anything ever reported the rate. Adaptive DACs never do.
  bool get feedbackSeen => samples.any((s) => s.measuredRateHz > 0);

  /// When the first fault appeared. The single most useful number in a soak:
  /// a fault at eight seconds and one at eight minutes have different causes.
  Duration? get firstFaultAt {
    for (final s in samples) {
      if (s.faults > 0) return s.at;
    }
    return null;
  }

  Iterable<double> get _rates =>
      samples.where((s) => s.measuredRateHz > 0).map((s) => s.measuredRateHz);

  double? get rateMin =>
      _rates.isEmpty ? null : _rates.reduce((a, b) => a < b ? a : b);
  double? get rateMax =>
      _rates.isEmpty ? null : _rates.reduce((a, b) => a > b ? a : b);

  /// The spread between the lowest and highest reading, as a percentage of
  /// nominal. This is the drift a short test cannot see.
  double? get rateSpreadPercent {
    final lo = rateMin, hi = rateMax;
    if (lo == null || hi == null || rate <= 0) return null;
    return (hi - lo) / rate * 100;
  }

  /// Worst deviation from nominal at any point, signed by magnitude.
  double? get worstDeviationPercent {
    if (!feedbackSeen || rate <= 0) return null;
    double worst = 0;
    for (final r in _rates) {
      final d = (r - rate) / rate * 100;
      if (d.abs() > worst.abs()) worst = d;
    }
    return worst;
  }

  int get worstRingFillPercent => samples.isEmpty
      ? 0
      : samples
          .map((s) => s.ringFillPercent)
          .reduce((a, b) => a < b ? a : b);

  /// Whether this run actually clears the plan's ten-minute zero-dropout bar.
  ///
  /// A clean two-minute run is not a shorter version of this: it says nothing
  /// about the failures that only appear once the hardware is warm.
  bool get meetsBar => isClean && actual >= kSoakBar && verdict != SweepVerdict.fail;

  SweepVerdict get verdict {
    if (!isClean) return SweepVerdict.fail;
    final worst = worstDeviationPercent;
    if (worst == null) return SweepVerdict.unverified;
    return worst.abs() <= kRateTolerancePercent
        ? SweepVerdict.pass
        : SweepVerdict.fail;
  }

  String get headline {
    if (samples.isEmpty) return 'Nothing measured.';
    final ran = _hms(actual);
    if (failure != null) return 'Stopped after $ran: $failure';
    if (faults > 0) {
      final at = firstFaultAt;
      return '$faults fault${faults == 1 ? '' : 's'} in $ran, '
          'first at ${_hms(at ?? Duration.zero)}.';
    }
    if (!completed) {
      return meetsBar
          ? 'Stopped at $ran, clean throughout — past the ten-minute bar.'
          : 'Stopped at $ran, clean so far — short of the ten-minute bar.';
    }
    if (!feedbackSeen) {
      return 'Clean for $ran, but this DAC reports no clock.';
    }
    return 'Clean for $ran at ${_khz(rate)}.';
  }

  String asText() {
    final b = StringBuffer()
      ..writeln('HiFi Renderer -- stability soak')
      ..writeln(deviceName)
      ..writeln('USB Audio Class $uacVersion')
      ..writeln(when.toIso8601String())
      ..writeln()
      ..writeln('Rate        ${_khz(rate)}')
      ..writeln('Container   $bits-bit, alt $altSetting')
      ..writeln('Planned     ${_hms(planned)}')
      ..writeln('Ran         ${_hms(actual)}'
          '${completed ? '' : '  (stopped early)'}')
      ..writeln();

    b
      ..writeln('Underruns        $underruns')
      ..writeln('Transfer errors  $transferErrors')
      ..writeln('Packet errors    $packetErrors')
      ..writeln('Rebuffers        $rebuffers')
      ..writeln('Worst ring fill  $worstRingFillPercent%');

    if (feedbackSeen) {
      b
        ..writeln('Measured rate    ${rateMin!.toStringAsFixed(1)} .. '
            '${rateMax!.toStringAsFixed(1)} Hz')
        ..writeln('Worst deviation  '
            '${worstDeviationPercent!.toStringAsFixed(4)}%')
        ..writeln('Drift spread     '
            '${rateSpreadPercent!.toStringAsFixed(4)}%');
    } else {
      b.writeln('Measured rate    not reported (no feedback endpoint)');
    }

    if (faults > 0) {
      b
        ..writeln()
        ..writeln('Faults appeared at:');
      var prev = 0;
      for (final s in samples) {
        if (s.faults > prev) {
          b.writeln('  ${_hms(s.at)}  '
              '${s.faults - prev} new '
              '(underruns ${s.underruns}, transfer ${s.transferErrors}, '
              'packets ${s.packetErrors})');
          prev = s.faults;
        }
      }
    }

    b
      ..writeln()
      ..writeln(headline);

    if (meetsBar) {
      b.writeln('Clears the ten-minute zero-dropout bar.');
    } else if (isClean && actual < kSoakBar) {
      b.writeln('Short of the ten-minute bar, so it says nothing yet about '
          'the faults that');
      b.writeln('only appear once the hardware is warm.');
    }

    if (!feedbackSeen && samples.isNotEmpty) {
      b
        ..writeln()
        ..writeln('This DAC has no feedback endpoint, so nothing here observed '
            'the rate it was')
        ..writeln('actually clocking. The stream was faultless for the whole '
            'run, which is all')
        ..writeln('the digital path can be held to.');
    }

    b
      ..writeln()
      ..writeln('A pass here describes this one device. The value of this test '
          'is what it')
      ..writeln('finds on hardware its authors do not own, so a failure is '
          'worth reporting')
      ..writeln('far more than a pass.');

    return b.toString();
  }
}

String _khz(int rate) {
  final k = rate / 1000.0;
  return k == k.truncateToDouble()
      ? '${k.toInt()} kHz'
      : '${k.toStringAsFixed(1)} kHz';
}

String _hms(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes % 60;
  final s = d.inSeconds % 60;
  final mm = m.toString().padLeft(2, '0');
  final ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
}
