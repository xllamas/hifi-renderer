import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../locale_setting.dart';
import '../renderer_state.dart';
import '../usb/dac_capabilities.dart';
import 'dac_capabilities_screen.dart';
import 'dac_verification_screen.dart';
import 'onboarding_screen.dart';

/// Configuration: the renderer's network name, plus everything operational
/// that does not belong on the now-playing screen.
class SettingsScreen extends StatefulWidget {
  final RendererStatus status;
  final ValueNotifier<DacProbeState> probe;
  final Future<void> Function() onRefreshCaps;

  const SettingsScreen({
    super.key,
    required this.status,
    required this.probe,
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
  bool _serverConversion = false;

  /// Minutes of quiet before the screen is let go; 0 means never.
  int _screenTimeout = 5;

  @override
  void initState() {
    super.initState();
    _loadAppliance();
    _loadDacs();
    _loadServerConversion();
    _loadScreenTimeout();
  }

  Future<void> _loadScreenTimeout() async {
    try {
      final m = await _channel.invokeMethod<int>('getScreenTimeout') ?? 5;
      if (mounted) setState(() => _screenTimeout = m);
    } catch (_) {
      // Absent means the default, which is what the field already holds.
    }
  }

  Future<void> _setScreenTimeout(int minutes) async {
    setState(() => _screenTimeout = minutes);
    await _channel.invokeMethod('setScreenTimeout', {'minutes': minutes});
  }

  static String _describeTimeout(AppLocalizations t, int minutes) =>
      minutes == 0 ? t.settingsTimeoutNever : t.settingsTimeoutMinutes(minutes);

  Future<void> _loadServerConversion() async {
    try {
      final on = await _channel.invokeMethod<bool>('getServerConversion') ?? false;
      if (mounted) setState(() => _serverConversion = on);
    } catch (_) {
      // Absent means off, which is the default anyway.
    }
  }

  Future<void> _setServerConversion(bool on) async {
    setState(() => _serverConversion = on);
    await _channel.invokeMethod('setServerConversion', {'enabled': on});
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
    // The capability panel below describes the *selected* device, so it has to
    // be re-measured here. Choosing a DAC and being shown the other one's
    // capabilities is worse than showing none.
    await widget.onRefreshCaps();
  }

  Future<void> _saveName() async {
    final ok = await _channel.invokeMethod<bool>(
        'setRendererName', {'name': _name.text}) ?? false;
    if (!mounted) return;
    setState(() => _saved = ok);
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).settingsRenamed),
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
    // Shown only when it has actually been seen failing. Warning every owner of
    // a Xiaomi phone about a permission they may not need is how a settings
    // screen becomes something people scroll past.
    final wakeRefused = _appliance['screenWakeRefused'] as bool? ?? false;

    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.of(context).settingsTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(AppLocalizations.of(context).settingsNetworkName,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            AppLocalizations.of(context).settingsNetworkNameHelp,
            style: const TextStyle(color: Colors.white54, fontSize: 13),
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
              child: Text(_saved
                  ? AppLocalizations.of(context).settingsSaved
                  : AppLocalizations.of(context).settingsSave),
            ),
          ]),

          const SizedBox(height: 28),
          Text(AppLocalizations.of(context).settingsAudioDevice,
              style: Theme.of(context).textTheme.titleMedium),
          if (_dacs.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              _dacs.length > 1
                  ? AppLocalizations.of(context).settingsDacsMultiple(_dacs.length)
                  : AppLocalizations.of(context).settingsDacsSingle,
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ],
          const SizedBox(height: 8),
          // Shown for a single device too, not just a choice between several.
          //
          // The chooser used to appear only with two or more attached, on the
          // reasoning that one device is no choice at all. But selecting is
          // also how access gets granted and how the capability panel below is
          // pointed at a device -- so an owner with one DAC that had not been
          // authorised was left looking at a screen that named no device and
          // offered nothing to tap, which reads as the app not seeing the
          // hardware. The row's own subtitle carries a "permission not
          // granted" state that could never be displayed.
          if (_dacs.isNotEmpty)
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
                      title: Text(m['name'] as String? ??
                          AppLocalizations.of(context).settingsUsbAudioDevice),
                      subtitle: Text(
                        '${m['vendorId']}:${m['productId']}'
                        '${m['hasPermission'] == true ? '' : AppLocalizations.of(context).settingsPermissionNotGranted}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ValueListenableBuilder<DacProbeState>(
            valueListenable: widget.probe,
            builder: (context, probe, _) {
              final caps = probe.caps;
              final ok = caps?.ok == true;
              return Card(
                child: ListTile(
                  leading: probe.probing
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(ok ? Icons.usb : Icons.usb_off,
                          color: ok ? Colors.greenAccent : Colors.white38),
                  title: Text(probe.probing
                      ? AppLocalizations.of(context).settingsReadingDevice
                      : ok
                          ? caps!.displayName
                          : AppLocalizations.of(context).idleNoDac),
                  subtitle: Text(probe.probing
                      ? AppLocalizations.of(context).settingsProbing
                      : ok
                          ? AppLocalizations.of(context)
                              .settingsUacTap(caps!.uacVersion.toString())
                          : AppLocalizations.of(context).settingsConnectToProbe),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => DacCapabilitiesScreen(
                      probe: widget.probe,
                      onRefresh: widget.onRefreshCaps,
                    ),
                  )),
                ),
              );
            },
          ),
          Card(
            child: SwitchListTile(
              value: _serverConversion,
              onChanged: _setServerConversion,
              secondary: Icon(
                _serverConversion ? Icons.transform : Icons.verified_outlined,
                color: _serverConversion ? Colors.amberAccent : Colors.greenAccent,
              ),
              isThreeLine: true,
              title: Text(AppLocalizations.of(context).settingsPcmOnly),
              subtitle: Text(
                _serverConversion
                    ? AppLocalizations.of(context).settingsPcmOnlyOn
                    : AppLocalizations.of(context).settingsPcmOnlyOff,
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
          Card(
            child: ListTile(
              leading: Icon(_screenTimeout == 0
                  ? Icons.brightness_high
                  : Icons.brightness_medium),
              title: Text(AppLocalizations.of(context).settingsScreenOffAfter),
              subtitle: Text(
                _screenTimeout == 0
                    ? AppLocalizations.of(context).settingsScreenOffNever
                    : AppLocalizations.of(context).settingsScreenOffTimed,
                style: const TextStyle(fontSize: 12),
              ),
              trailing: DropdownButton<int>(
                value: _screenTimeout,
                underline: const SizedBox.shrink(),
                items: const [1, 2, 5, 10, 30, 0]
                    .map((m) => DropdownMenuItem(
                          value: m,
                          child: Text(_describeTimeout(
                              AppLocalizations.of(context), m)),
                        ))
                    .toList(),
                onChanged: (m) {
                  if (m != null) _setScreenTimeout(m);
                },
              ),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.speed),
              title: Text(AppLocalizations.of(context).settingsDacVerification),
              subtitle: Text(
                  AppLocalizations.of(context).settingsDacVerificationSubtitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const DacVerificationScreen(),
              )),
            ),
          ),

          const SizedBox(height: 28),
          Text(AppLocalizations.of(context).settingsAlwaysOn,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            AppLocalizations.of(context).settingsAlwaysOnHelp,
            style: const TextStyle(color: Colors.white54, fontSize: 13),
          ),
          const SizedBox(height: 12),
          // Above the fixes, because it is the reason to be reading them. This
          // is also the only manufacturer-independent signal here: everything
          // else on this screen is inferred from the phone's make, while this
          // is the app observing that it was actually killed.
          if (deaths > 0)
            _check(
              ok: false,
              title: AppLocalizations.of(context).settingsDeaths(deaths),
              detail: AppLocalizations.of(context).settingsDeathsDetail,
            ),
          _check(
            ok: ignoringBattery,
            title: AppLocalizations.of(context).settingsBattery,
            detail: ignoringBattery
                ? AppLocalizations.of(context).settingsBatteryGranted
                : AppLocalizations.of(context).settingsBatteryNotGranted,
            action: ignoringBattery
                ? null
                : AppLocalizations.of(context).settingsGrant,
            onAction: () async {
              await _channel.invokeMethod('requestBatteryExemption');
              _loadAppliance();
            },
          ),
          if (hasVendor)
            _check(
              ok: null,
              title: AppLocalizations.of(context).settingsAutostart(
                  manufacturer.isEmpty
                      ? AppLocalizations.of(context)
                          .settingsAutostartVendorFallback
                      : manufacturer),
              detail: AppLocalizations.of(context).settingsAutostartDetail,
              action: AppLocalizations.of(context).settingsOpenSettings,
              onAction: () async {
                final messenger = ScaffoldMessenger.of(context);
                // Resolved before the await. After it this State may be gone,
                // and reading strings from a dead context is the crash this
                // lint exists to prevent.
                final couldNotOpen =
                    AppLocalizations.of(context).settingsCouldNotOpen;
                final opened =
                    await _channel.invokeMethod<String>('openVendorAutostart') ?? '';
                if (opened.isEmpty) {
                  messenger.showSnackBar(SnackBar(
                    content: Text(couldNotOpen),
                  ));
                }
              },
            ),
          if (wakeRefused)
            _check(
              ok: false,
              title: AppLocalizations.of(context).settingsWakeScreen,
              detail: AppLocalizations.of(context).settingsWakeScreenDetail,
              action: AppLocalizations.of(context).settingsOpenSettings,
              onAction: () async {
                final messenger = ScaffoldMessenger.of(context);
                final couldNotOpen =
                    AppLocalizations.of(context).settingsCouldNotOpen;
                final opened =
                    await _channel.invokeMethod<String>('openBackgroundWindow') ?? '';
                if (opened.isEmpty) {
                  messenger.showSnackBar(SnackBar(
                    content: Text(couldNotOpen),
                  ));
                }
              },
            ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.checklist),
              title: Text(AppLocalizations.of(context).settingsRunSetup),
              subtitle:
                  Text(AppLocalizations.of(context).settingsRunSetupSubtitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                await Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const OnboardingScreen(rerun: true),
                ));
                _loadAppliance();
              },
            ),
          ),
          const SizedBox(height: 28),
          Text(AppLocalizations.of(context).settingsLanguage,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            AppLocalizations.of(context).settingsLanguageHelp,
            style: const TextStyle(color: Colors.white54, fontSize: 13),
          ),
          const SizedBox(height: 8),
          _language(context),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  /// The language chooser.
  ///
  /// Every language is listed in its own script, because that is the only
  /// naming that works: someone looking for their language recognises it
  /// written their way, not translated into the one they cannot read. The
  /// default sits at the top and is phrased as following the phone rather
  /// than as a language, since it is not one.
  Widget _language(BuildContext context) => DropdownButtonFormField<String>(
        initialValue: LocaleSetting.instance.locale?.toString() ?? '',
        isExpanded: true,
        decoration: const InputDecoration(border: OutlineInputBorder()),
        items: [
          DropdownMenuItem(
            value: '',
            child: Text(AppLocalizations.of(context).settingsLanguageSystem),
          ),
          ...LocaleSetting.supported.map(
            (l) => DropdownMenuItem(
              value: l.toString(),
              child: Text(LocaleSetting.nameOf(l)),
            ),
          ),
        ],
        onChanged: (value) {
          final locale = (value == null || value.isEmpty)
              ? null
              : LocaleSetting.supported
                  .firstWhere((l) => l.toString() == value);
          LocaleSetting.instance.set(locale);
        },
      );

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
