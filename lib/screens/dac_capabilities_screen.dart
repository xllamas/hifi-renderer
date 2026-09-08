import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../usb/dac_capabilities.dart';

/// Shows what the connected DAC can actually do, measured from its own USB
/// descriptors rather than taken from its documentation.
///
/// This exists because manufacturer documentation routinely omits the things
/// that matter -- the reference AL400's manual never mentions that the host
/// cannot set its volume, which is exactly the sort of thing a user otherwise
/// discovers only after a long stretch of fruitless configuration.
class DacCapabilitiesScreen extends StatelessWidget {
  /// Watched rather than passed by value: this is a pushed route, so it is
  /// built once and would otherwise keep showing whatever was current when it
  /// was opened -- including after its own refresh button re-probed.
  final ValueNotifier<DacProbeState> probe;
  final Future<void> Function() onRefresh;

  const DacCapabilitiesScreen({
    super.key,
    required this.probe,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<DacProbeState>(
      valueListenable: probe,
      builder: (context, state, _) => Scaffold(
        appBar: AppBar(
          title: Text(AppLocalizations.of(context).dacCapsTitle),
          actions: [
            IconButton(
              onPressed: state.probing ? null : onRefresh,
              icon: const Icon(Icons.refresh),
              tooltip: AppLocalizations.of(context).dacCapsReprobe,
            ),
          ],
        ),
        body: _body(context, state),
      ),
    );
  }

  Widget _body(BuildContext context, DacProbeState state) {
    final c = state.caps;
    // Show the spinner for the whole probe, not only the first one. After a
    // device change the capabilities still in hand belong to the *other* DAC,
    // and leaving them on screen is precisely the confusion this screen exists
    // to prevent.
    if (state.probing) {
      return const Center(child: CircularProgressIndicator());
    }
    if (c == null) {
      return _centered(
          context,
          Icons.usb_off,
          AppLocalizations.of(context).dacCapsNotProbed,
          AppLocalizations.of(context).dacCapsNotProbedDetail);
    }
    if (!c.ok) {
      return _centered(
          context,
          Icons.error_outline,
          _errorTitle(context, c.error),
          c.errorMessage ?? AppLocalizations.of(context).dacCapsUnknownError);
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _identity(context, c),
        if (!c.isSupported) ...[
          const SizedBox(height: 12),
          Card(
            color: Colors.amber.withValues(alpha: 0.15),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                const Icon(Icons.block, color: Colors.amberAccent),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(AppLocalizations.of(context).dacCapsNotUsable,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
              ]),
            ),
          ),
        ],
        const SizedBox(height: 20),
        _whatItSupports(context, c),
        const SizedBox(height: 20),
        Text(AppLocalizations.of(context).dacCapsWorthKnowing,
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        ...c.notes.map((n) => _note(context, n)),
        const SizedBox(height: 20),
        _technical(context, c),
      ],
    );
  }

  String _errorTitle(BuildContext context, String? code) {
    final t = AppLocalizations.of(context);
    return switch (code) {
      'no_device' => t.dacCapsNoDevice,
      'permission_denied' => t.dacCapsPermissionNeeded,
      'open_failed' => t.dacCapsOpenFailed,
      _ => t.dacCapsProbeFailed,
    };
  }

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
          subtitle: Text(AppLocalizations.of(context).dacCapsIdentity(
              c.uacVersion.toString(),
              c.speed,
              c.vendorIdHex,
              c.productIdHex)),
        ),
      );

  Widget _whatItSupports(BuildContext context, DacCapabilities c) {
    // playableRates, not rates: UAC1 has no clock entity and reports its rates
    // per alt-setting, so the clock list is empty on a device that plays fine.
    final rates = c.playableRates;
    final depths = c.pcmBitDepths;

    final t = AppLocalizations.of(context);
    String rateText;
    if (rates.isEmpty) {
      rateText = t.dacCapsUnknown;
    } else if (rates.length <= 6) {
      rateText = rates.map((hz) => _khz(context, hz)).join(', ');
    } else {
      rateText = t.dacCapsRateRange(
          _khz(context, c.minRate!), _khz(context, c.maxRate!), rates.length);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(t.dacCapsWhatItSupports,
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        _row(t.dacCapsSampleRates, rateText),
        _row(
            t.dacCapsBitDepths,
            depths.isEmpty
                ? t.dacCapsUnknown
                : depths.map(t.dacCapsBitDepth).join(', ')),
        _row(
            t.dacCapsChannels,
            c.formats.isEmpty
                ? t.dacCapsUnknown
                : '${c.formats.first.channels}'),
        if (c.currentRate > 0)
          _row(t.dacCapsCurrentlyAt, _khz(context, c.currentRate)),
        _row(t.dacCapsUsbTiming,
            c.isAsync ? t.dacCapsAsync : t.dacCapsSync),
        _row(
            t.dacCapsVolumeControl,
            c.volumeHostControllable
                ? t.dacCapsVolumeOverUsb
                : t.dacCapsVolumeDeviceOnly),
        if (c.supportsDsd) _row(t.dacCapsDsd, t.dacCapsDsdSupported),
      ],
    );
  }

  static String _khz(BuildContext context, int hz) {
    final k = hz / 1000.0;
    final s = k == k.roundToDouble() ? k.toStringAsFixed(0) : k.toStringAsFixed(1);
    return AppLocalizations.of(context).dacCapsKhz(s);
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
        title: Text(AppLocalizations.of(context).dacCapsTechnical),
        subtitle:
            Text(AppLocalizations.of(context).dacCapsTechnicalSubtitle),
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
