import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/dac_capabilities_screen.dart';
import 'usb/dac_capabilities.dart';

void main() => runApp(const HifiRendApp());

class HifiRendApp extends StatelessWidget {
  const HifiRendApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'HiFi Renderer',
        theme: ThemeData.dark(useMaterial3: true),
        home: const HomeScreen(),
      );
}

/// Placeholder for the now-playing screen (M5). For now it carries the entry
/// point into the DAC capability view, which is the M1 deliverable.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _channel = MethodChannel('com.hifirend/renderer');

  String _build = 'checking...';
  DacCapabilities? _caps;
  bool _probing = false;

  @override
  void initState() {
    super.initState();
    _invoke('selfTest').then((v) {
      if (mounted) setState(() => _build = v);
      _probe();
    });
  }

  Future<String> _invoke(String method) async {
    try {
      return await _channel.invokeMethod<String>(method) ?? '';
    } on PlatformException catch (e) {
      return '{"ok":false,"error":"platform","message":"${e.message}"}';
    } on MissingPluginException {
      return '{"ok":false,"error":"no_channel","message":"channel not registered"}';
    }
  }

  Future<void> _probe() async {
    setState(() => _probing = true);
    final raw = await _invoke('probeUsb');
    if (!mounted) return;
    setState(() {
      _caps = DacCapabilities.parse(raw);
      _probing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = _caps;
    return Scaffold(
      appBar: AppBar(title: const Text('HiFi Renderer')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Renderer not running yet — M1 build.',
              style: TextStyle(color: Colors.white60)),
          const SizedBox(height: 24),
          Card(
            child: ListTile(
              leading: Icon(
                c != null && c.ok ? Icons.usb : Icons.usb_off,
                color: c != null && c.ok ? Colors.greenAccent : Colors.white38,
              ),
              title: Text(c != null && c.ok ? c.displayName : 'No DAC connected'),
              subtitle: Text(_probing
                  ? 'Probing…'
                  : c != null && c.ok
                      ? 'USB Audio Class ${c.uacVersion} — tap for details'
                      : c?.errorMessage ?? 'Tap to probe'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => DacCapabilitiesScreen(
                  caps: _caps,
                  loading: _probing,
                  onRefresh: _probe,
                ),
              )),
            ),
          ),
          const SizedBox(height: 24),
          Text('Build', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          SelectableText(_build,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
        ],
      ),
    );
  }
}
