/// The result of walking every rate a DAC claims, and what it means.
///
/// The capabilities screen reports what the DAC **claims**; this reports what it
/// actually **does**. A device advertising a rate it cannot clock is exactly the
/// kind of undocumented gap the app exists to expose, and it is invisible to
/// anything that only reads descriptors.
library;

/// How far the measured rate may sit from the requested one and still pass.
///
/// Generous on purpose. A DAC tracking correctly holds to a few thousandths of
/// a percent -- 0.002% was measured on the reference hardware over 30 minutes --
/// so this is nowhere near a tight tolerance. It is sized to catch the failure
/// that actually happens: a device that accepts 96 kHz and quietly clocks 48.
const double kRateTolerancePercent = 0.5;

enum SweepVerdict {
  /// Configured, streamed clean, and the clock was measured where it was asked
  /// to be.
  pass,

  /// Something countable went wrong: it would not configure, it would not
  /// start, or the stream accrued errors.
  fail,

  /// Streamed clean, but nothing here could confirm the clock.
  ///
  /// Not a lesser pass and not a failure. A device with no feedback endpoint --
  /// every adaptive device, which is most cheap ones -- reports its rate to
  /// nobody, so the honest answer is that the digital path was faultless and
  /// the clock is unproven.
  unverified,
}

/// One rate, tested.
class RateResult {
  final int rate;

  /// The source depth asked for, which is what chose the alt-setting.
  final int requestedBits;

  /// False when configure or start refused; [failure] then says why.
  final bool configured;
  final String? failure;

  final int altSetting;
  final int deviceBits;
  final int subslot;

  /// From the feedback endpoint. Zero when the device has none to report with.
  final double measuredRateHz;
  final bool feedbackSeen;

  /// Accrued during the measurement window, after the stream had settled.
  final int underruns;
  final int transferErrors;
  final int packetErrors;
  final int packetsSubmitted;

  /// Counted before the measurement window opened.
  ///
  /// Kept separate rather than folded in: a glitch while an isochronous stream
  /// is still filling says something different from one in steady state, and
  /// counting the two together would fail every device for the cost of
  /// starting up.
  final int startupGlitches;

  const RateResult({
    required this.rate,
    required this.requestedBits,
    required this.configured,
    this.failure,
    this.altSetting = -1,
    this.deviceBits = 0,
    this.subslot = 0,
    this.measuredRateHz = 0,
    this.feedbackSeen = false,
    this.underruns = 0,
    this.transferErrors = 0,
    this.packetErrors = 0,
    this.packetsSubmitted = 0,
    this.startupGlitches = 0,
  });

  /// Signed distance of the measured rate from the requested one, or null when
  /// nothing measured it.
  double? get deviationPercent {
    if (!feedbackSeen || measuredRateHz <= 0 || rate <= 0) return null;
    return (measuredRateHz - rate) / rate * 100;
  }

  bool get isClean =>
      underruns == 0 && transferErrors == 0 && packetErrors == 0;

  SweepVerdict get verdict {
    if (!configured) return SweepVerdict.fail;
    if (!isClean) return SweepVerdict.fail;
    final dev = deviationPercent;
    if (dev == null) return SweepVerdict.unverified;
    return dev.abs() <= kRateTolerancePercent
        ? SweepVerdict.pass
        : SweepVerdict.fail;
  }

  /// One line of plain English saying what happened and, when it went wrong,
  /// what that means.
  String get summary {
    if (!configured) return failure ?? 'would not configure';
    if (!isClean) {
      final parts = <String>[
        if (underruns > 0) '$underruns underrun${underruns == 1 ? '' : 's'}',
        if (transferErrors > 0) '$transferErrors transfer errors',
        if (packetErrors > 0) '$packetErrors bad packets',
      ];
      return parts.join(', ');
    }
    final dev = deviationPercent;
    if (dev == null) return 'streamed clean; no feedback endpoint to confirm the clock';
    if (dev.abs() > kRateTolerancePercent) {
      return 'clocked ${measuredRateHz.toStringAsFixed(0)} Hz, not $rate Hz';
    }
    return 'clean, clock within ${dev.abs().toStringAsFixed(3)}%';
  }
}

/// Everything a sweep found, and the text a user can send us.
class SweepReport {
  final String deviceName;
  final String uacVersion;
  final DateTime when;
  final int seconds;
  final List<RateResult> results;

  const SweepReport({
    required this.deviceName,
    required this.uacVersion,
    required this.when,
    required this.seconds,
    required this.results,
  });

  int get passed => results.where((r) => r.verdict == SweepVerdict.pass).length;
  int get failed => results.where((r) => r.verdict == SweepVerdict.fail).length;
  int get unverified =>
      results.where((r) => r.verdict == SweepVerdict.unverified).length;

  /// True when nothing in the sweep could observe the clock at all.
  bool get nothingMeasured => results.every((r) => !r.feedbackSeen);

  /// A single sentence for the top of the screen.
  String get headline {
    if (results.isEmpty) return 'Nothing tested yet.';
    if (failed > 0) {
      return '$failed of ${results.length} rates failed.';
    }
    if (unverified == results.length) {
      return 'All ${results.length} rates streamed cleanly, but this DAC '
          'reports no clock.';
    }
    if (unverified > 0) {
      return 'All ${results.length} rates streamed cleanly; $unverified could '
          'not be clock-checked.';
    }
    return 'All ${results.length} rates passed.';
  }

  /// The report as text, for pasting into an email or an issue.
  ///
  /// This is the single most useful thing a user on hardware we do not own can
  /// send us, so it carries the device identity and the chosen alt-setting for
  /// every rate -- not just the verdicts.
  String asText() {
    final b = StringBuffer()
      ..writeln('HiFi Renderer -- DAC rate sweep')
      ..writeln(deviceName)
      ..writeln('USB Audio Class $uacVersion')
      ..writeln('${when.toIso8601String()}, ${seconds}s per rate')
      ..writeln()
      ..writeln('Rate        Result      Alt  Container  Measured      Notes')
      ..writeln('-' * 78);

    for (final r in results) {
      final rate = '${(r.rate / 1000).toStringAsFixed(1)} kHz'.padRight(11);
      final verdict = switch (r.verdict) {
        SweepVerdict.pass => 'PASS',
        SweepVerdict.fail => 'FAIL',
        SweepVerdict.unverified => 'UNVERIFIED',
      }
          .padRight(11);
      final alt = (r.configured ? '${r.altSetting}' : '-').padRight(4);
      final container = (r.configured
              ? '${r.requestedBits}-bit in ${r.subslot}B'
              : '-')
          .padRight(10);
      final measured = (r.feedbackSeen && r.measuredRateHz > 0
              ? '${r.measuredRateHz.toStringAsFixed(1)} Hz'
              : 'not reported')
          .padRight(13);
      b.writeln('$rate $verdict $alt $container $measured ${r.summary}');
      if (r.startupGlitches > 0) {
        b.writeln('${' ' * 12}(${r.startupGlitches} glitches while the stream '
            'was still filling, before measurement began)');
      }
    }

    b
      ..writeln()
      ..writeln(headline);

    if (nothingMeasured && results.isNotEmpty) {
      b
        ..writeln()
        ..writeln('This DAC has no feedback endpoint, so it never reports the '
            'rate it is actually')
        ..writeln('clocking. Every rate above was configured and streamed '
            'without a single error,')
        ..writeln('which is everything the digital path can be held to -- but '
            'no measurement here')
        ..writeln('can prove the DAC clocked what it was asked for.');
    }

    b
      ..writeln()
      ..writeln('This report covers the digital path only. If a rate passes '
          'here and still sounds')
      ..writeln('wrong, the data reached the DAC intact and the fault is '
          'after conversion --')
      ..writeln('cabling, grounding, or the amplifier. That was a real '
          'afternoon here once.');

    return b.toString();
  }
}
