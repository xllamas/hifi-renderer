import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../usb/dac_capabilities.dart';
import '../usb/stability_soak.dart';

/// M8's stability soak: one rate, held for a long time, watched closely.
///
/// The sweep answers bandwidth; this answers endurance. Slow clock drift,
/// thermal throttling and rare scheduler stalls take minutes to appear and are
/// all audible when they do, so a few seconds per rate cannot see any of them.
class StabilitySoakScreen extends StatefulWidget {
  final DacCapabilities caps;

  const StabilitySoakScreen({super.key, required this.caps});

  @override
  State<StabilitySoakScreen> createState() => _StabilitySoakScreenState();
}

class _StabilitySoakScreenState extends State<StabilitySoakScreen> {
  static const _channel = MethodChannel('com.hifirend/renderer');

  /// Same reasoning as the sweep: the stream is still filling at first, and
  /// glitches from that say nothing about the hardware.
  static const _settle = Duration(seconds: 2);

  /// Fine enough to place a fault to within a few seconds without keeping an
  /// unreasonable number of samples for a long run.
  static const _interval = Duration(seconds: 5);

  static const _durations = [
    Duration(minutes: 10),
    Duration(minutes: 30),
    Duration(hours: 1),
  ];

  late int _rate;
  Duration _planned = kSoakBar;

  bool _running = false;
  bool _cancelled = false;
  Duration _elapsed = Duration.zero;
  final List<SoakSample> _samples = [];
  SoakResult? _result;
  String _step = '';

  @override
  void initState() {
    super.initState();
    // The top rate by default: it is the most demanding, and the one the sweep
    // proved only for a few seconds.
    _rate = widget.caps.maxRate ?? 44100;
  }

  @override
  void dispose() {
    _cancelled = true;
    _channel.invokeMethod('stopPlayback');
    super.dispose();
  }

  void _set(VoidCallback fn) {
    if (mounted) setState(fn);
  }

  Map<String, dynamic> _decode(String s) {
    try {
      return Map<String, dynamic>.from(jsonDecode(s) as Map);
    } catch (_) {
      return const {};
    }
  }

  int _int(Map<String, dynamic> m, String k) => (m[k] as num?)?.toInt() ?? 0;

  Future<Map<String, dynamic>> _status() async =>
      _decode(await _channel.invokeMethod<String>('playbackStatus') ?? '{}');

  Future<void> _run() async {
    final bits = widget.caps.pcmBitDepths.isEmpty
        ? 16
        : widget.caps.pcmBitDepths.last;

    _set(() {
      _running = true;
      _cancelled = false;
      _elapsed = Duration.zero;
      _samples.clear();
      _result = null;
      _step = 'starting';
    });

    final started = _decode(await _channel.invokeMethod<String>('playTone', {
          'rate': _rate,
          'bits': bits,
          'channels': 2,
          'hz': 1000,
        }) ??
        '{}');

    if (started['ok'] != true) {
      _finish(bits, 0, (started['message'] as String?) ?? 'would not start');
      return;
    }

    _set(() => _step = 'settling');
    await Future<void>.delayed(_settle);
    final baseline = await _status();
    final alt = _int(baseline, 'altSetting');

    _set(() => _step = 'running');
    var elapsed = Duration.zero;
    String? failure;

    while (!_cancelled && elapsed < _planned) {
      await Future<void>.delayed(_interval);
      if (_cancelled) break;
      elapsed += _interval;

      final s = await _status();

      // A stream that stopped on its own is a fault, not an end: the tone
      // loops for ever, so nothing should ever finish it.
      if (s['running'] != true) {
        failure = 'the stream stopped on its own';
        _set(() => _elapsed = elapsed);
        break;
      }

      _samples.add(SoakSample(
        at: elapsed,
        measuredRateHz: (s['measuredRateHz'] as num?)?.toDouble() ?? 0,
        underruns: _int(s, 'underruns') - _int(baseline, 'underruns'),
        transferErrors:
            _int(s, 'transferErrors') - _int(baseline, 'transferErrors'),
        packetErrors: _int(s, 'packetErrors') - _int(baseline, 'packetErrors'),
        rebuffers: _int(s, 'rebuffers') - _int(baseline, 'rebuffers'),
        ringFillPercent: _int(s, 'ringFillPercent'),
      ));
      _set(() => _elapsed = elapsed);
    }

    _finish(bits, alt, failure);
  }

  Future<void> _finish(int bits, int alt, String? failure) async {
    await _channel.invokeMethod('stopPlayback');
    _set(() {
      _running = false;
      _step = '';
      _result = SoakResult(
        deviceName: widget.caps.displayName,
        uacVersion: widget.caps.uacVersion,
        rate: _rate,
        bits: bits,
        altSetting: alt,
        planned: _planned,
        when: DateTime.now(),
        completed: !_cancelled && failure == null,
        failure: failure,
        samples: List.of(_samples),
      );
    });
  }

  Future<void> _copy() async {
    final text = _result?.asText();
    if (text == null) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Report copied')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final caps = widget.caps;
    return Scaffold(
      appBar: AppBar(title: const Text('Stability soak')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Holds one rate for a long time and watches for what a few seconds '
            'cannot show: slow clock drift, thermal throttling, and the rare '
            'scheduler stall. Ten minutes clean is the bar this project set '
            'itself.',
            style: const TextStyle(color: Colors.white54, fontSize: 12.5,
                height: 1.35),
          ),
          const SizedBox(height: 18),
          _rates(caps),
          const SizedBox(height: 16),
          _lengths(),
          const SizedBox(height: 20),
          if (_running) _progress() else _startButton(),
          if (_result != null) ...[
            const SizedBox(height: 24),
            _report(_result!),
          ],
        ],
      ),
    );
  }

  Widget _rates(DacCapabilities caps) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Rate', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final r in caps.playableRates)
                ChoiceChip(
                  label: Text(_khz(r)),
                  selected: _rate == r,
                  onSelected:
                      _running ? null : (_) => setState(() => _rate = r),
                ),
            ],
          ),
        ],
      );

  Widget _lengths() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Length', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final d in _durations)
                ChoiceChip(
                  label: Text(_hms(d)),
                  selected: _planned == d,
                  onSelected:
                      _running ? null : (_) => setState(() => _planned = d),
                ),
            ],
          ),
        ],
      );

  Widget _startButton() => FilledButton.icon(
        onPressed: _run,
        icon: const Icon(Icons.play_arrow),
        label: Text('Soak ${_khz(_rate)} for ${_hms(_planned)}'),
      );

  Widget _progress() {
    final fraction = _planned.inSeconds == 0
        ? 0.0
        : (_elapsed.inSeconds / _planned.inSeconds).clamp(0.0, 1.0);
    final last = _samples.isEmpty ? null : _samples.last;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LinearProgressIndicator(value: _step == 'running' ? fraction : null),
        const SizedBox(height: 12),
        Text('${_hms(_elapsed)} of ${_hms(_planned)}  ·  $_step',
            style: const TextStyle(fontFamily: 'monospace')),
        if (last != null) ...[
          const SizedBox(height: 12),
          _stat('Faults', '${last.faults}', bad: last.faults > 0),
          _stat('Ring fill', '${last.ringFillPercent}%'),
          _stat(
            'Measured rate',
            last.measuredRateHz > 0
                ? '${last.measuredRateHz.toStringAsFixed(1)} Hz'
                : 'not reported',
          ),
        ],
        const SizedBox(height: 16),
        TextButton.icon(
          onPressed: () => setState(() => _cancelled = true),
          icon: const Icon(Icons.stop),
          label: const Text('Stop'),
        ),
        const SizedBox(height: 8),
        const Text(
          'The screen may sleep; the run continues. Playback holds a wake lock '
          'so the CPU cannot suspend under the stream.',
          style: TextStyle(color: Colors.white38, fontSize: 11.5),
        ),
      ],
    );
  }

  Widget _stat(String k, String v, {bool bad = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          SizedBox(
              width: 120,
              child: Text(k,
                  style: const TextStyle(color: Colors.white60, fontSize: 13))),
          Text(v,
              style: TextStyle(
                  fontFamily: 'monospace',
                  color: bad ? Colors.redAccent : null)),
        ]),
      );

  Widget _report(SoakResult r) {
    final (icon, colour) = switch (r.verdict) {
      SweepVerdict.pass => (Icons.check_circle, Colors.greenAccent),
      SweepVerdict.fail => (Icons.error, Colors.redAccent),
      SweepVerdict.unverified => (Icons.help_outline, Colors.amberAccent),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(icon, color: colour),
          const SizedBox(width: 10),
          Expanded(
            child: Text(r.headline,
                style: TextStyle(color: colour, fontSize: 15)),
          ),
        ]),
        const SizedBox(height: 14),
        _stat('Underruns', '${r.underruns}', bad: r.underruns > 0),
        _stat('Transfer errors', '${r.transferErrors}',
            bad: r.transferErrors > 0),
        _stat('Packet errors', '${r.packetErrors}', bad: r.packetErrors > 0),
        _stat('Rebuffers', '${r.rebuffers}', bad: r.rebuffers > 0),
        _stat('Worst ring fill', '${r.worstRingFillPercent}%'),
        if (r.feedbackSeen) ...[
          _stat('Worst deviation',
              '${r.worstDeviationPercent!.toStringAsFixed(4)}%'),
          _stat('Drift spread', '${r.rateSpreadPercent!.toStringAsFixed(4)}%'),
        ] else
          _stat('Measured rate', 'not reported'),
        const SizedBox(height: 14),
        if (r.meetsBar)
          const Text('Clears the ten-minute zero-dropout bar.',
              style: TextStyle(color: Colors.greenAccent, fontSize: 12.5))
        else if (r.isClean && r.actual < kSoakBar)
          const Text(
            'Short of the ten-minute bar, so it says nothing yet about the '
            'faults that only appear once the hardware is warm.',
            style: TextStyle(color: Colors.amberAccent, fontSize: 12.5),
          ),
        const SizedBox(height: 14),
        FilledButton.tonalIcon(
          onPressed: _copy,
          icon: const Icon(Icons.copy),
          label: const Text('Copy report'),
        ),
      ],
    );
  }

  String _khz(int rate) {
    final k = rate / 1000.0;
    return k == k.truncateToDouble()
        ? '${k.toInt()} kHz'
        : '${k.toStringAsFixed(1)} kHz';
  }

  String _hms(Duration d) {
    if (d.inHours > 0 && d.inMinutes % 60 == 0) return '${d.inHours} h';
    if (d.inSeconds % 60 == 0 && d.inMinutes > 0) return '${d.inMinutes} min';
    final m = d.inMinutes;
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
