import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// M2 harness: play a local WAV bit-perfectly and watch the stream health.
///
/// The numbers matter more than the sound here. Underruns and transfer errors
/// are how dropouts show up before they are audible, and the measured rate from
/// the DAC's feedback endpoint is the evidence that clock tracking is working.
class PlaybackTestScreen extends StatefulWidget {
  const PlaybackTestScreen({super.key});

  @override
  State<PlaybackTestScreen> createState() => _PlaybackTestScreenState();
}

class _PlaybackTestScreenState extends State<PlaybackTestScreen> {
  static const _channel = MethodChannel('com.hifirend/renderer');

  List<String> _files = [];
  String _message = '';
  Map<String, dynamic> _status = const {};
  Timer? _poll;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadFiles();
    _poll = Timer.periodic(const Duration(milliseconds: 500), (_) => _refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _loadFiles() async {
    final raw = await _channel.invokeMethod<String>('listTestFiles') ?? '';
    setState(() {
      _files = raw.split('\n').where((s) => s.trim().isNotEmpty).toList();
    });
  }

  Future<void> _refresh() async {
    final raw = await _channel.invokeMethod<String>('playbackStatus') ?? '{}';
    if (!mounted) return;
    setState(() => _status = _decode(raw));
  }

  Map<String, dynamic> _decode(String s) {
    try {
      return Map<String, dynamic>.from(jsonDecode(s) as Map);
    } catch (_) {
      return {'raw': s};
    }
  }

  Future<void> _play(String path) async {
    setState(() {
      _busy = true;
      _message = 'starting...';
    });
    final r = await _channel.invokeMethod<String>(
        'playWav', {'path': path, 'loop': true});
    if (!mounted) return;
    setState(() {
      _message = r ?? '';
      _busy = false;
    });
  }

  Future<void> _stop() async {
    await _channel.invokeMethod('stopPlayback');
    if (mounted) setState(() => _message = 'stopped');
  }

  @override
  Widget build(BuildContext context) {
    final running = _status['running'] == true;
    return Scaffold(
      appBar: AppBar(title: const Text('Bit-perfect playback test')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_files.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Text('No test files found.\n\nPush WAVs with:\n'
                    'adb push test.wav /sdcard/Android/data/com.hifirend/cache/',
                    style: TextStyle(fontFamily: 'monospace', fontSize: 12)),
              ),
            ),
          for (final f in _files)
            Card(
              child: ListTile(
                leading: const Icon(Icons.play_arrow),
                title: Text(f.split('/').last),
                enabled: !_busy,
                onTap: () => _play(f),
              ),
            ),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: _stop,
            icon: const Icon(Icons.stop),
            label: const Text('Stop'),
          ),
          const SizedBox(height: 20),
          Text('Stream health', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: running ? Colors.green.withValues(alpha: 0.12) : Colors.white10,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _row('Running', running ? 'yes' : 'no'),
                _row('Source', '${_status['sourceRate'] ?? '-'} Hz '
                    '${_status['sourceBits'] ?? '-'}-bit'),
                _row('DAC container',
                    '${_status['deviceBits'] ?? '-'}-bit in '
                    '${_status['subslot'] ?? '-'} bytes (alt ${_status['altSetting'] ?? '-'})'),
                _row('Measured rate', '${_status['measuredRateHz'] ?? '-'} Hz'),
                _row('Frames sent', '${_status['framesSubmitted'] ?? 0}'),
                _row('Underruns', '${_status['underruns'] ?? 0}',
                    bad: (_status['underruns'] as num? ?? 0) > 0),
                _row('Transfer errors', '${_status['transferErrors'] ?? 0}',
                    bad: (_status['transferErrors'] as num? ?? 0) > 0),
                _row('Buffer fill', '${_status['ringFillPercent'] ?? 0}%'),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SelectableText(_message,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
        ],
      ),
    );
  }

  Widget _row(String k, String v, {bool bad = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          SizedBox(width: 130, child: Text(k, style: const TextStyle(color: Colors.white60))),
          Expanded(
            child: Text(v,
                style: TextStyle(
                    fontFamily: 'monospace',
                    color: bad ? Colors.redAccent : null)),
          ),
        ]),
      );
}
