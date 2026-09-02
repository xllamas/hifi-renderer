import 'package:flutter/material.dart';

import '../usb/dac_capabilities.dart';

/// Shows what the connected DAC can actually do, measured from its own USB
/// descriptors rather than taken from its documentation.
///
/// This exists because manufacturer documentation routinely omits the things
/// that matter -- the reference AL400's manual never mentions that the host
/// cannot set its volume, which is exactly the sort of thing a user otherwise
/// discovers only after a long stretch of fruitless configuration.
class DacCapabilitiesScreen extends StatelessWidget {
  final DacCapabilities? caps;
  final bool loading;
  final VoidCallback onRefresh;

  const DacCapabilitiesScreen({
    super.key,
    required this.caps,
    required this.loading,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('DAC capabilities'),
        actions: [
          IconButton(
            onPressed: loading ? null : onRefresh,
            icon: const Icon(Icons.refresh),
            tooltip: 'Re-probe',
          ),
        ],
      ),
      body: _body(context),
    );
  }

  Widget _body(BuildContext context) {
    final c = caps;
    if (loading && c == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (c == null) {
      return _centered(context, Icons.usb_off, 'Not probed yet',
          'Connect a USB DAC and tap refresh.');
    }
    if (!c.ok) {
      return _centered(context, Icons.error_outline,
          _errorTitle(c.error), c.errorMessage ?? 'Unknown error.');
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _identity(context, c),
        const SizedBox(height: 20),
        _whatItSupports(context, c),
        const SizedBox(height: 20),
        Text('Things worth knowing',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        ...c.notes.map((n) => _note(context, n)),
        const SizedBox(height: 20),
        _technical(context, c),
      ],
    );
  }

  String _errorTitle(String? code) => switch (code) {
        'no_device' => 'No DAC found',
        'permission_denied' => 'Permission needed',
        'open_failed' => 'Could not open the DAC',
        _ => 'Probe failed',
      };

  Widget _centered(BuildContext context, IconData icon, String title, String detail) =>
      Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 48, color: Colors.white38),
              const SizedBox(height: 16),
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(detail,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white60)),
            ],
          ),
        ),
      );

  Widget _identity(BuildContext context, DacCapabilities c) => Card(
        child: ListTile(
          leading: const Icon(Icons.speaker, size: 36),
          title: Text(c.displayName,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text('USB Audio Class ${c.uacVersion} · '
              '${c.speed}-speed · ${c.vendorIdHex}:${c.productIdHex}'),
        ),
      );

  Widget _whatItSupports(BuildContext context, DacCapabilities c) {
    final rates = c.rates;
    final depths = c.pcmBitDepths;

    String rateText;
    if (rates.isEmpty) {
      rateText = 'Unknown';
    } else if (rates.length <= 6) {
      rateText = rates.map(_khz).join(', ');
    } else {
      rateText = '${_khz(c.minRate!)} – ${_khz(c.maxRate!)} '
          '(${rates.length} rates)';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('What it supports', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        _row('Sample rates', rateText),
        _row('Bit depths',
            depths.isEmpty ? 'Unknown' : depths.map((d) => '$d-bit').join(', ')),
        _row('Channels',
            c.formats.isEmpty ? 'Unknown' : '${c.formats.first.channels}'),
        if (c.currentRate > 0) _row('Currently running at', _khz(c.currentRate)),
        _row('USB timing', c.isAsync ? 'Asynchronous (DAC clock)' : 'Synchronous'),
        _row('Volume control',
            c.volumeHostControllable ? 'Supported over USB' : 'On the device only'),
        if (c.supportsDsd) _row('DSD', 'Supported by the hardware'),
      ],
    );
  }

  static String _khz(int hz) {
    final k = hz / 1000.0;
    final s = k == k.roundToDouble() ? k.toStringAsFixed(0) : k.toStringAsFixed(1);
    return '$s kHz';
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 150,
              child: Text(label, style: const TextStyle(color: Colors.white60)),
            ),
            Expanded(child: Text(value)),
          ],
        ),
      );

  Widget _note(BuildContext context, CapabilityNote n) {
    final (icon, colour) = switch (n.severity) {
      NoteSeverity.good => (Icons.check_circle_outline, Colors.greenAccent),
      NoteSeverity.info => (Icons.info_outline, Colors.lightBlueAccent),
      NoteSeverity.important => (Icons.warning_amber_outlined, Colors.amberAccent),
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: colour, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(n.title,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(n.detail,
                      style: const TextStyle(color: Colors.white70, height: 1.4)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _technical(BuildContext context, DacCapabilities c) => ExpansionTile(
        title: const Text('Technical details'),
        subtitle: const Text('For support reports'),
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final f in c.formats)
                  Text(
                    'alt ${f.alt}: ${f.format} ${f.bits}-bit ${f.channels}ch  '
                    '${f.sync}${f.hasFeedback ? " +feedback" : ""}  '
                    'maxPacket=${f.maxPacket}',
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  ),
                const SizedBox(height: 12),
                SelectableText(
                  c.rawJson,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 10),
                ),
              ],
            ),
          ),
        ],
      );
}
