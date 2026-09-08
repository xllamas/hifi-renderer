import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../usb/rate_sweep.dart';
import '../l10n/app_localizations.dart';

/// M8's other source: play one of the user's own files and watch it.
///
/// The sweep and the soak use generated tones, which is the only way to reach
/// rates nobody owns music at. This answers the different question — "does my
/// actual library play cleanly" — and it is restricted to whatever rates that
/// material happens to contain, which is the point of having both.
///
/// A picked file goes through the *streaming* engine rather than the file
/// player, because that is where the decoders are: the file player only knows
/// WAV, and a real library is FLAC. The WAV list below it is the M2 harness,
/// kept because it is the only remote-debugging tool for a DAC we do not own.
class PlaybackTestScreen extends StatefulWidget {
  const PlaybackTestScreen({super.key});

  @override
  State<PlaybackTestScreen> createState() => _PlaybackTestScreenState();
}

/// Which engine is running, and so which counters mean anything.
enum _Source { none, picked, cached }

class _PlaybackTestScreenState extends State<PlaybackTestScreen> {
  static const _channel = MethodChannel('com.hifirend/renderer');

  List<String> _files = [];
  String _message = '';
  Map<String, dynamic> _status = const {};
  _Source _source = _Source.none;
  String? _pickedName;
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
    // A file left playing would hold the DAC open behind a screen that has
    // gone.
    _channel.invokeMethod('stopPlayback');
    super.dispose();
  }

  Future<void> _loadFiles() async {
    final raw = await _channel.invokeMethod<String>('listTestFiles') ?? '';
    if (!mounted) return;
    setState(() {
      _files = raw.split('\n').where((s) => s.trim().isNotEmpty).toList();
    });
  }

  Future<void> _refresh() async {
    if (_source == _Source.none) return;
    final method =
        _source == _Source.picked ? 'fileStatus' : 'playbackStatus';
    final raw = await _channel.invokeMethod<String>(method) ?? '{}';
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

  int _int(String k) => (_status[k] as num?)?.toInt() ?? 0;

  Future<void> _pick() async {
    setState(() => _busy = true);
    final raw = await _channel.invokeMethod<String>('pickAudioFile') ?? '{}';
    final picked = _decode(raw);
    final uri = picked['uri'] as String?;
    if (uri == null || uri.isEmpty) {
      if (mounted) setState(() => _busy = false);
      return; // cancelled
    }

    setState(() {
      _pickedName = picked['name'] as String?;
      _message = 'starting...';
      _status = const {};
    });
    final r = await _channel.invokeMethod<String>('playFile', {
          'uri': uri,
          'mime': picked['mime'] ?? '',
        }) ??
        '';
    if (!mounted) return;
    final result = _decode(r);
    setState(() {
      _busy = false;
      _source = result['ok'] == true ? _Source.picked : _Source.none;
      _message = result['ok'] == true
          ? 'playing ${_pickedName ?? ''}'
          : (result['message'] as String?) ?? r;
    });
  }

  Future<void> _playCached(String path) async {
    setState(() {
      _busy = true;
      _message = 'starting...';
      _status = const {};
    });
    final r = await _channel
        .invokeMethod<String>('playWav', {'path': path, 'loop': true});
    if (!mounted) return;
    final result = _decode(r ?? '');
    setState(() {
      _busy = false;
      _source = result['ok'] == true ? _Source.cached : _Source.none;
      _pickedName = path.split('/').last;
      _message = r ?? '';
    });
  }

  Future<void> _stop() async {
    await _channel.invokeMethod('stopPlayback');
    if (mounted) setState(() => _message = 'stopped');
  }

  /// The run so far, expressed the same way a swept rate is.
  ///
  /// A file check asks exactly what one rate of a sweep asks — did it
  /// configure, did it stay clean, and did the clock land where it was asked —
  /// so it gets the same three verdicts, including `unverified` for a DAC with
  /// no feedback endpoint to answer with.
  RateResult? get _result {
    if (_source == _Source.none || _status.isEmpty) return null;
    if (_status['running'] != true) return null;
    return RateResult(
      rate: _int('rate'),
      requestedBits: _int('sourceBits'),
      configured: true,
      altSetting: _int('altSetting'),
      deviceBits: _int('deviceBits'),
      subslot: _int('subslot'),
      measuredRateHz: (_status['measuredRateHz'] as num?)?.toDouble() ?? 0,
      feedbackSeen: _int('feedbackAccepted') > 0,
      underruns: _int('underruns'),
      transferErrors: _int('transferErrors'),
      packetErrors: _int('packetErrors'),
      packetsSubmitted: _int('packetsSubmitted'),
    );
  }

  Future<void> _copy() async {
    final r = _result;
    if (r == null) return;
    final b = StringBuffer()
      ..writeln('HiFi Renderer -- file check')
      ..writeln(_pickedName ?? 'file')
      ..writeln(DateTime.now().toIso8601String())
      ..writeln()
      ..writeln('Source     ${_status['sourceFormat'] ?? '-'} '
          '${r.requestedBits}-bit ${_int('channels')}ch at ${r.rate} Hz')
      ..writeln('Container  ${r.deviceBits}-bit in ${r.subslot} bytes, '
          'alt ${r.altSetting}')
      ..writeln('Measured   ${r.feedbackSeen ? '${r.measuredRateHz.toStringAsFixed(1)} Hz' : 'not reported'}')
      ..writeln('Underruns  ${r.underruns}')
      ..writeln('Transfer   ${r.transferErrors}')
      ..writeln('Packets    ${r.packetErrors} bad of ${r.packetsSubmitted}')
      ..writeln()
      ..writeln(r.summary)
      ..writeln()
      ..writeln('Digital path only. If this reads clean and still sounds '
          'wrong, the data reached')
      ..writeln('the DAC intact and the fault is after conversion.');
    await Clipboard.setData(ClipboardData(text: b.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).reportCopied)));
  }

  @override
  Widget build(BuildContext context) {
    final running = _status['running'] == true;
    final r = _result;
    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.of(context).playFileTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            AppLocalizations.of(context).playFileIntro,
            style: const TextStyle(
                color: Colors.white54, fontSize: 12.5, height: 1.35),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : _pick,
            icon: const Icon(Icons.folder_open),
            label: Text(AppLocalizations.of(context).playFileChoose),
          ),
          const SizedBox(height: 8),
          Text(
            AppLocalizations.of(context).playFileFormats,
            style: const TextStyle(color: Colors.white38, fontSize: 11.5),
          ),

          if (_files.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text(AppLocalizations.of(context).playFileCache,
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              AppLocalizations.of(context).playFileCacheDetail,
              style: const TextStyle(color: Colors.white38, fontSize: 11.5),
            ),
            const SizedBox(height: 8),
            for (final f in _files)
              Card(
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.play_arrow),
                  title: Text(f.split('/').last),
                  enabled: !_busy,
                  onTap: () => _playCached(f),
                ),
              ),
          ],

          const SizedBox(height: 16),
          FilledButton.tonalIcon(
            onPressed: _stop,
            icon: const Icon(Icons.stop),
            label: Text(AppLocalizations.of(context).stop),
          ),

          const SizedBox(height: 24),
          Text(AppLocalizations.of(context).playFileStreamHealth,
              style: Theme.of(context).textTheme.titleMedium),
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
                if (_source == _Source.picked)
                  _row('Decoded as', '${_status['sourceFormat'] ?? '-'}'),
                _row('Source', '${_status['sourceRate'] ?? _status['rate'] ?? '-'} Hz '
                    '${_status['sourceBits'] ?? '-'}-bit'),
                _row('DAC container',
                    '${_status['deviceBits'] ?? '-'}-bit in '
                    '${_status['subslot'] ?? '-'} bytes (alt ${_status['altSetting'] ?? '-'})'),
                _row('Measured rate', '${_status['measuredRateHz'] ?? '-'} Hz'),
                _row('Underruns', '${_status['underruns'] ?? 0}',
                    bad: (_status['underruns'] as num? ?? 0) > 0),
                _row('Transfer errors', '${_status['transferErrors'] ?? 0}',
                    bad: (_status['transferErrors'] as num? ?? 0) > 0),
                _row('Bad packets', '${_status['packetErrors'] ?? 0}',
                    bad: (_status['packetErrors'] as num? ?? 0) > 0),
                _row('Buffer fill', '${_status['ringFillPercent'] ?? 0}%'),
              ],
            ),
          ),

          if (r != null) ...[
            const SizedBox(height: 14),
            Row(children: [
              Icon(
                switch (r.verdict) {
                  SweepVerdict.pass => Icons.check_circle,
                  SweepVerdict.fail => Icons.error,
                  SweepVerdict.unverified => Icons.help_outline,
                },
                color: switch (r.verdict) {
                  SweepVerdict.pass => Colors.greenAccent,
                  SweepVerdict.fail => Colors.redAccent,
                  SweepVerdict.unverified => Colors.amberAccent,
                },
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(r.summary,
                  style: const TextStyle(fontSize: 13))),
            ]),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: _copy,
              icon: const Icon(Icons.copy),
              label: Text(AppLocalizations.of(context).copyReport),
            ),
          ],

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
