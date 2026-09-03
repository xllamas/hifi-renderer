import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../renderer_state.dart';
import '../usb/dac_capabilities.dart';
import 'dac_capabilities_screen.dart';
import 'playback_test_screen.dart';

/// Configuration: the renderer's network name, plus everything operational
/// that does not belong on the now-playing screen.
class SettingsScreen extends StatefulWidget {
  final RendererStatus status;
  final DacCapabilities? caps;
  final VoidCallback onRefreshCaps;

  const SettingsScreen({
    super.key,
    required this.status,
    required this.caps,
    required this.onRefreshCaps,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _channel = MethodChannel('com.hifirend/renderer');

  late final TextEditingController _name =
      TextEditingController(text: widget.status.rendererName);
  Map<String, dynamic> _appliance = const {};
  List<dynamic> _dacs = const [];
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    _loadAppliance();
    _loadDacs();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _loadAppliance() async {
    try {
      final raw = await _channel.invokeMethod<String>('applianceStatus') ?? '{}';
      if (mounted) setState(() => _appliance = jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      // Optional diagnostics; absence is not an error.
    }
  }

  Future<void> _loadDacs() async {
    try {
      final raw = await _channel.invokeMethod<String>('listDacs') ?? '{}';
      final j = jsonDecode(raw) as Map<String, dynamic>;
      if (mounted) setState(() => _dacs = (j['devices'] as List?) ?? const []);
    } catch (_) {
      // Listing is best-effort; the rest of the screen still works.
    }
  }

  Future<void> _selectDac(String? key) async {
    await _channel.invokeMethod('selectDac', {'key': key});
    await _loadDacs();
    widget.onRefreshCaps();
  }

  Future<void> _saveName() async {
    final ok = await _channel.invokeMethod<bool>(
        'setRendererName', {'name': _name.text}) ?? false;
    if (!mounted) return;
    setState(() => _saved = ok);
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Renamed. Restart the app for controllers to see it.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final health = _appliance['health'] as Map<String, dynamic>? ?? const {};
    final deaths = (health['unexpectedDeaths'] as num?)?.toInt() ?? 0;
    final ignoringBattery = _appliance['ignoringBatteryOptimizations'] as bool? ?? false;
    final hasVendor = _appliance['hasVendorSettings'] as bool? ?? false;
    final manufacturer = _appliance['manufacturer'] as String? ?? '';

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Network name', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          const Text(
            'How this renderer appears in DLNA controllers.',
            style: TextStyle(color: Colors.white54, fontSize: 13),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _name,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (_) => setState(() => _saved = false),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton(
              onPressed: _saved ? null : _saveName,
              child: Text(_saved ? 'Saved' : 'Save'),
            ),
          ]),

          const SizedBox(height: 28),
          Text('Audio device', style: Theme.of(context).textTheme.titleMedium),
          if (_dacs.length > 1) ...[
            const SizedBox(height: 4),
            Text(
              '${_dacs.length} USB audio devices are attached. Choose which one '
              'to play through; the choice is remembered across reboots.',
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ],
          const SizedBox(height: 8),
          // Only worth showing a chooser when there is something to choose.
          if (_dacs.length > 1)
            RadioGroup<String>(
              groupValue: _dacs
                      .cast<Map<String, dynamic>>()
                      .firstWhere((e) => e['active'] == true,
                          orElse: () => const {'key': ''})['key'] as String? ??
                  '',
              onChanged: _selectDac,
              child: Column(
                children: _dacs.map((d) {
                  final m = d as Map<String, dynamic>;
                  return Card(
                    margin: const EdgeInsets.only(bottom: 6),
                    child: RadioListTile<String>(
                      value: m['key'] as String? ?? '',
                      title: Text(m['name'] as String? ?? 'USB audio device'),
                      subtitle: Text(
                        '${m['vendorId']}:${m['productId']}'
                        '${m['hasPermission'] == true ? '' : ' — permission not granted'}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          Card(
            child: ListTile(
              leading: Icon(
                widget.caps?.ok == true ? Icons.usb : Icons.usb_off,
                color: widget.caps?.ok == true ? Colors.greenAccent : Colors.white38,
              ),
              title: Text(widget.caps?.ok == true
                  ? widget.caps!.displayName
                  : 'No DAC connected'),
              subtitle: Text(widget.caps?.ok == true
                  ? 'USB Audio Class ${widget.caps!.uacVersion} — tap for what it supports'
                  : 'Connect a USB DAC and tap to probe'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => DacCapabilitiesScreen(
                  caps: widget.caps,
                  loading: false,
                  onRefresh: widget.onRefreshCaps,
                ),
              )),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.speed),
              title: const Text('Playback verification'),
              subtitle: const Text('Check what this DAC can really do'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const PlaybackTestScreen(),
              )),
            ),
          ),

          const SizedBox(height: 28),
          Text('Always on', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          const Text(
            'A dedicated renderer has to keep running with the screen off and '
            'come back after a reboot. Android and most phone makers block that '
            'by default.',
            style: TextStyle(color: Colors.white54, fontSize: 13),
          ),
          const SizedBox(height: 12),
          _check(
            ok: ignoringBattery,
            title: 'Battery optimisation exemption',
            detail: ignoringBattery
                ? 'Granted — Android will not suspend the renderer.'
                : 'Not granted. Android may suspend the renderer when idle.',
            action: ignoringBattery ? null : 'Grant',
            onAction: () async {
              await _channel.invokeMethod('requestBatteryExemption');
              _loadAppliance();
            },
          ),
          if (hasVendor)
            _check(
              ok: null,
              title: 'Autostart (${manufacturer.isEmpty ? "vendor" : manufacturer})',
              detail: 'Your phone has its own background-app restrictions, '
                  'separate from Android\'s. Without this the renderer will not '
                  'start after a reboot.',
              action: 'Open settings',
              onAction: () async {
                final messenger = ScaffoldMessenger.of(context);
                final opened =
                    await _channel.invokeMethod<String>('openVendorAutostart') ?? '';
                if (opened.isEmpty) {
                  messenger.showSnackBar(const SnackBar(
                    content: Text('Could not open that screen on this phone.'),
                  ));
                }
              },
            ),
          if (deaths > 0)
            _check(
              ok: false,
              title: 'The renderer has been stopped $deaths time(s)',
              detail: 'Something on this phone is killing it in the background. '
                  'Granting the permissions above usually fixes it.',
            ),
        ],
      ),
    );
  }

  Widget _check({
    required bool? ok,
    required String title,
    required String detail,
    String? action,
    VoidCallback? onAction,
  }) {
    final (icon, colour) = switch (ok) {
      true => (Icons.check_circle_outline, Colors.greenAccent),
      false => (Icons.warning_amber_outlined, Colors.amberAccent),
      null => (Icons.info_outline, Colors.lightBlueAccent),
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: colour, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(detail,
                  style: const TextStyle(color: Colors.white70, height: 1.4)),
              if (action != null) ...[
                const SizedBox(height: 8),
                FilledButton.tonal(onPressed: onAction, child: Text(action)),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}
