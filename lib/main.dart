import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() => runApp(const HifiRendApp());

class HifiRendApp extends StatelessWidget {
  const HifiRendApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'HiFi Renderer',
        theme: ThemeData.dark(useMaterial3: true),
        home: const DiagnosticsScreen(),
      );
}

/// USB diagnostics. Kept permanently past M1: it is the only way to debug a
/// user's DAC that we do not physically have.
class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  static const _channel = MethodChannel('com.hifirend/renderer');

  String _build = 'checking...';
  String _usb = 'not probed yet';
  bool _probing = false;

  @override
  void initState() {
    super.initState();
    _invoke('selfTest').then((v) {
      if (mounted) setState(() => _build = v);
      // Once USB permission has been granted the probe raises no dialog, so
      // run it automatically -- each rebuild otherwise costs a manual tap.
      _probeUsb();
    });
  }

  Future<String> _invoke(String method) async {
    try {
      return await _channel.invokeMethod<String>(method) ?? 'no response';
    } on PlatformException catch (e) {
      return 'platform error: ${e.message}';
    } on MissingPluginException {
      return 'channel not registered';
    }
  }

  Future<void> _probeUsb() async {
    setState(() {
      _probing = true;
      _usb = 'probing (accept the USB permission dialog)...';
    });
    final r = await _invoke('probeUsb');
    if (mounted) {
      setState(() {
        _usb = r;
        _probing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('HiFi Renderer — USB diagnostics')),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _probing ? null : _probeUsb,
          icon: _probing
              ? const SizedBox(
                  width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.usb),
          label: Text(_probing ? 'Probing' : 'Probe DAC'),
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _section('Build', _build),
            const SizedBox(height: 16),
            _section('USB Audio Class capabilities', _usb),
            const SizedBox(height: 80),
          ],
        ),
      );

  Widget _section(String title, String body) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white10,
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(
              body,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.4),
            ),
          ),
        ],
      );
}
