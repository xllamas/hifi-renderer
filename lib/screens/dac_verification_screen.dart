import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../usb/dac_capabilities.dart';
import '../usb/rate_sweep.dart';
import 'stability_soak_screen.dart';
import 'playback_test_screen.dart';

/// M8: walk every rate the DAC claims and report what it actually did.
///
/// The audience for this app is people who want evidence rather than assurance,
/// and the app is uniquely placed to give it: it already talks to the DAC
/// directly and knows what the hardware says about itself. This is the
/// companion to the capabilities screen -- that one reports the claim, this one
/// tests it.
class DacVerificationScreen extends StatefulWidget {
  const DacVerificationScreen({super.key});

  @override
  State<DacVerificationScreen> createState() => _DacVerificationScreenState();
}

class _DacVerificationScreenState extends State<DacVerificationScreen> {
  static const _channel = MethodChannel('com.hifirend/renderer');

  /// Long enough for a stall to show up, short enough that a ten-rate DAC does
  /// not take five minutes. The soak test is where minutes belong.
  static const _secondsPerRate = 4;

  /// The stream is still filling for the first moment after start, and an
  /// isochronous engine that has not caught up reports glitches that say
  /// nothing about the hardware. Measurement begins after this.
  static const _settle = Duration(milliseconds: 1500);

  DacCapabilities? _caps;
  String? _probeError;

  final List<RateResult> _results = [];
  int? _running;
  bool _sweeping = false;
  bool _cancelled = false;
  String _step = '';

  final _scroll = ScrollController();

  /// Whether new results should pull the view down with them.
  ///
  /// True until the user scrolls away from the bottom, and true again as soon
  /// as they come back. A sweep that always jumped to the newest row would
  /// snatch the screen away from someone reading an earlier one, which is a
  /// worse fault than the one this fixes.
  bool _stick = true;

  @override
  void initState() {
    super.initState();
    _probe();
  }

  @override
  void dispose() {
    // A sweep left running would hold the DAC open with a tone playing into a
    // screen that no longer exists.
    _cancelled = true;
    _channel.invokeMethod('stopPlayback');
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _probe() async {
    final raw = await _channel.invokeMethod<String>('probeUsb') ?? '';
    if (!mounted) return;
    final caps = DacCapabilities.parse(raw);
    setState(() {
      _caps = caps;
      _probeError = caps.ok ? null : (caps.errorMessage ?? caps.error);
    });
  }

  Map<String, dynamic> _decode(String s) {
    try {
      return Map<String, dynamic>.from(jsonDecode(s) as Map);
    } catch (_) {
      return const {};
    }
  }

  Future<Map<String, dynamic>> _status() async =>
      _decode(await _channel.invokeMethod<String>('playbackStatus') ?? '{}');

  int _int(Map<String, dynamic> m, String k) => (m[k] as num?)?.toInt() ?? 0;

  bool get _atBottom {
    if (!_scroll.hasClients) return true;
    final p = _scroll.position;
    return p.pixels >= p.maxScrollExtent - 40;
  }

  /// Follows the sweep down the list, once the new row has been laid out.
  ///
  /// The extent is only known after the frame is built, so this cannot run
  /// inside the setState that added the row.
  void _followTail() {
    if (!_stick) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients || !_stick) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  /// A sweep is a long chain of awaits, and the screen can be left at any point
  /// in it. Every update after an await has to survive that.
  void _set(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
    _followTail();
  }

  Future<void> _sweep() async {
    final caps = _caps;
    if (caps == null) return;
    final rates = caps.playableRates;
    final depths = caps.pcmBitDepths;
    if (rates.isEmpty || depths.isEmpty) return;

    // The deepest container the DAC offers. Asking for a depth it does not have
    // fails at configure, and would be reported as the rate failing when the
    // rate was never the problem.
    final bits = depths.last;

    _set(() {
      _sweeping = true;
      _cancelled = false;
      _stick = true;   // a fresh sweep starts by following again
      _results.clear();
    });

    for (final rate in rates) {
      if (_cancelled || !mounted) break;
      _set(() {
        _running = rate;
        _step = 'starting';
      });

      final started = _decode(await _channel.invokeMethod<String>('playTone', {
            'rate': rate,
            'bits': bits,
            'channels': 2,
            'hz': 1000,
          }) ??
          '{}');

      if (started['ok'] != true) {
        _results.add(RateResult(
          rate: rate,
          requestedBits: bits,
          configured: false,
          failure: (started['message'] as String?) ?? 'would not start',
        ));
        _set(() {});
        continue;
      }

      // Let the ring fill and the feedback filter converge before anything is
      // counted against the device.
      _set(() => _step = 'settling');
      await Future<void>.delayed(_settle);
      final baseline = await _status();

      _set(() => _step = 'measuring');
      for (var i = 0; i < _secondsPerRate * 2 && !_cancelled; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
      final end = await _status();
      await _channel.invokeMethod('stopPlayback');

      if (_cancelled) break;

      _results.add(RateResult(
        rate: rate,
        requestedBits: bits,
        configured: true,
        altSetting: _int(end, 'altSetting'),
        deviceBits: _int(end, 'deviceBits'),
        subslot: _int(end, 'subslot'),
        measuredRateHz: (end['measuredRateHz'] as num?)?.toDouble() ?? 0,
        feedbackSeen: _int(end, 'feedbackAccepted') > 0,
        underruns: _int(end, 'underruns') - _int(baseline, 'underruns'),
        transferErrors:
            _int(end, 'transferErrors') - _int(baseline, 'transferErrors'),
        packetErrors: _int(end, 'packetErrors') - _int(baseline, 'packetErrors'),
        packetsSubmitted:
            _int(end, 'packetsSubmitted') - _int(baseline, 'packetsSubmitted'),
        startupGlitches: _int(baseline, 'underruns') +
            _int(baseline, 'transferErrors') +
            _int(baseline, 'packetErrors'),
      ));
      _set(() {});
    }

    await _channel.invokeMethod('stopPlayback');
    _set(() {
      _sweeping = false;
      _running = null;
      _step = '';
    });
  }

  SweepReport? get _report {
    final caps = _caps;
    if (caps == null || _results.isEmpty) return null;
    return SweepReport(
      deviceName: caps.displayName,
      uacVersion: caps.uacVersion,
      when: DateTime.now(),
      seconds: _secondsPerRate,
      results: _results,
    );
  }

  Future<void> _copy() async {
    final text = _report?.asText();
    if (text == null) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Report copied')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final caps = _caps;
    return Scaffold(
      appBar: AppBar(
        title: const Text('DAC verification'),
        actions: [
          IconButton(
            tooltip: 'Play one of my files',
            icon: const Icon(Icons.audio_file_outlined),
            onPressed: _sweeping
                ? null
                : () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const PlaybackTestScreen(),
                    )),
          ),
        ],
      ),
      // A drag is the user taking over; a programmatic scroll is not. Only the
      // former should stop the view following the sweep, which is why this
      // watches drags and settling rather than the controller's own offset.
      body: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if ((n is ScrollUpdateNotification && n.dragDetails != null) ||
              n is ScrollEndNotification) {
            final atBottom = _atBottom;
            if (atBottom != _stick) setState(() => _stick = atBottom);
          }
          return false;
        },
        child: ListView(
          controller: _scroll,
          padding: const EdgeInsets.all(16),
          children: [
            if (caps == null)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              )
            else ...[
              _device(caps),
              const SizedBox(height: 16),
              if (_probeError != null)
                _note(_probeError!, Colors.redAccent)
              else if (!caps.isSupported)
                _note('This device has no PCM output, so there is nothing to '
                    'sweep.', Colors.orangeAccent)
              else ...[
                _note(
                  'Plays a 1 kHz tone at -20 dBFS through the DAC, a few '
                  'seconds at each rate it claims. Audible -- turn the '
                  'amplifier down first.',
                  Colors.white54,
                ),
                const SizedBox(height: 12),
                _controls(caps),
                const SizedBox(height: 12),
                // The sweep answers bandwidth; the soak answers endurance.
                // Offered here because this is where someone has just seen
                // four seconds a rate and may want rather more than that.
                OutlinedButton.icon(
                  onPressed: _sweeping
                      ? null
                      : () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => StabilitySoakScreen(caps: caps),
                          )),
                  icon: const Icon(Icons.timer_outlined),
                  label: const Text('Stability soak'),
                ),
              ],
              const SizedBox(height: 20),
              if (_results.isNotEmpty || _running != null) ...[
                _resultsHeader(context),
                const SizedBox(height: 8),
                for (final r in _results) _resultRow(r),
                if (_running != null) _pendingRow(_running!),
                const SizedBox(height: 16),
                if (_report != null && !_sweeping) ...[
                  _note(
                      _report!.headline,
                      _report!.failed > 0
                          ? Colors.redAccent
                          : Colors.greenAccent),
                  const SizedBox(height: 12),
                  FilledButton.tonalIcon(
                    onPressed: _copy,
                    icon: const Icon(Icons.copy),
                    label: const Text('Copy report'),
                  ),
                  const SizedBox(height: 12),
                  _note(
                    'This covers the digital path only. If a rate passes here '
                    'and still sounds wrong, the data reached the DAC intact '
                    'and the fault is after conversion -- cabling, grounding, '
                    'or the amplifier.',
                    Colors.white38,
                  ),
                ],
              ],
            ],
          ],
        ),
      ),
    );
  }

  /// Offered only when it would do something: mid-sweep, with the user parked
  /// somewhere the new rows are not.
  Widget _resultsHeader(BuildContext context) => Row(
        children: [
          Text('Results', style: Theme.of(context).textTheme.titleMedium),
          const Spacer(),
          if (_sweeping && !_stick)
            TextButton.icon(
              onPressed: () {
                setState(() => _stick = true);
                _followTail();
              },
              icon: const Icon(Icons.arrow_downward, size: 16),
              label: const Text('Follow'),
            ),
        ],
      );

  Widget _device(DacCapabilities caps) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(caps.displayName,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text(
                'UAC ${caps.uacVersion} · '
                '${caps.playableRates.length} rates · '
                '${caps.pcmBitDepths.join("/")}-bit',
                style: const TextStyle(color: Colors.white54, fontSize: 13),
              ),
              if (!caps.hasFeedback && caps.isSupported) ...[
                const SizedBox(height: 8),
                const Text(
                  'No feedback endpoint: this DAC never reports the rate it is '
                  'actually clocking, so the sweep can prove the stream was '
                  'faultless but not that the clock was right.',
                  style: TextStyle(color: Colors.amberAccent, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      );

  Widget _controls(DacCapabilities caps) => Row(
        children: [
          FilledButton.icon(
            onPressed: _sweeping ? null : _sweep,
            icon: const Icon(Icons.play_arrow),
            label: Text(_sweeping ? 'Sweeping...' : 'Run rate sweep'),
          ),
          const SizedBox(width: 12),
          if (_sweeping)
            TextButton.icon(
              onPressed: () => setState(() => _cancelled = true),
              icon: const Icon(Icons.stop),
              label: const Text('Stop'),
            ),
        ],
      );

  Widget _pendingRow(int rate) => Card(
        color: Colors.blueGrey.withValues(alpha: 0.18),
        child: ListTile(
          leading: const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          title: Text(_khz(rate)),
          subtitle: Text(_step),
        ),
      );

  Widget _resultRow(RateResult r) {
    final (icon, colour, label) = switch (r.verdict) {
      SweepVerdict.pass => (Icons.check_circle, Colors.greenAccent, 'pass'),
      SweepVerdict.fail => (Icons.error, Colors.redAccent, 'fail'),
      SweepVerdict.unverified =>
        (Icons.help_outline, Colors.amberAccent, 'unverified'),
    };
    return Card(
      child: ListTile(
        leading: Icon(icon, color: colour),
        title: Row(children: [
          Text(_khz(r.rate),
              style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(width: 10),
          Text(label, style: TextStyle(color: colour, fontSize: 12)),
        ]),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(r.summary, style: const TextStyle(fontSize: 12)),
            if (r.configured)
              Text(
                'alt ${r.altSetting} · ${r.requestedBits}-bit in '
                '${r.subslot} bytes · ${r.packetsSubmitted} packets',
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
          ],
        ),
      ),
    );
  }

  Widget _note(String text, Color colour) => Text(
        text,
        style: TextStyle(color: colour, fontSize: 12.5, height: 1.35),
      );

  String _khz(int rate) {
    final k = rate / 1000.0;
    return k == k.truncateToDouble()
        ? '${k.toInt()} kHz'
        : '${k.toStringAsFixed(1)} kHz';
  }
}
