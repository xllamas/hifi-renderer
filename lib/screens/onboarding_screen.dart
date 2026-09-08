import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
/// First-run setup: the permissions a renderer needs to behave like an
/// appliance, offered once and never insisted on.
///
/// The generic Android path is necessary but not sufficient — most OEMs kill
/// background services regardless — and the vendor screens that fix that are
/// undocumented Intents that can vanish between OS versions. So every step is
/// offered, checked live, and skippable, and Finish is always available. A
/// device where a step is simply impossible must still be able to leave setup;
/// the settings screen keeps every check afterwards.
class OnboardingScreen extends StatefulWidget {
  /// Shown from settings rather than at first run, which only changes the
  /// wording: nothing here is destructive to repeat.
  final bool rerun;

  const OnboardingScreen({super.key, this.rerun = false});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with WidgetsBindingObserver {
  static const _channel = MethodChannel('com.hifirend/renderer');

  Map<String, dynamic> _status = const {};
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
    // Every step here is granted in a system screen or dialog, so the answer
    // arrives while this screen is in the background. Polling is what makes a
    // tick appear without the user having to work out that it should have.
    _poll = Timer.periodic(const Duration(seconds: 1), (_) => _refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final raw = await _channel.invokeMethod<String>('onboardingStatus') ?? '{}';
    if (!mounted) return;
    try {
      setState(() => _status = Map<String, dynamic>.from(jsonDecode(raw) as Map));
    } catch (_) {
      // Status is guidance, not state anything depends on.
    }
  }

  bool _flag(String key) => _status[key] == true;
  String get _manufacturer => (_status['manufacturer'] as String?) ?? '';

  Future<void> _finish() async {
    await _channel.invokeMethod('setOnboardingDone', {'done': true});
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final notifications = _flag('notifications');
    final battery = _flag('ignoringBatteryOptimizations');
    final hasVendor = _flag('hasVendorSettings');
    final ready = notifications && battery;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.rerun
            ? AppLocalizations.of(context).onboardingTitleRerun
            : AppLocalizations.of(context).onboardingTitle),
        automaticallyImplyLeading: widget.rerun,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            AppLocalizations.of(context).onboardingIntro,
            style: const TextStyle(
                fontSize: 14, height: 1.4, color: Colors.white70),
          ),
          const SizedBox(height: 8),
          Text(
            AppLocalizations.of(context).onboardingOptional,
            style: const TextStyle(fontSize: 12.5, color: Colors.white38),
          ),
          const SizedBox(height: 24),

          _step(
            n: 1,
            done: notifications,
            title: AppLocalizations.of(context).onboardingNotifications,
            detail: notifications
                ? AppLocalizations.of(context).onboardingNotificationsGranted
                : AppLocalizations.of(context).onboardingNotificationsWhy,
            action: notifications
                ? null
                : AppLocalizations.of(context).onboardingAllow,
            onAction: () async {
              // Resolved before the await. Afterwards this State may be gone,
              // and the strings are needed precisely on the paths where the
              // platform call took a while.
              final t = AppLocalizations.of(context);
              final what =
                  await _channel.invokeMethod<String>('requestNotifications');
              if (!mounted) return;
              if (what == 'unavailable') {
                _say(t.onboardingNoNotificationScreen);
              } else if (what == 'settings') {
                _say(t.onboardingNotificationsInSettings);
              }
              _refresh();
            },
          ),

          _step(
            n: 2,
            done: battery,
            title: AppLocalizations.of(context).onboardingBattery,
            detail: battery
                ? AppLocalizations.of(context).onboardingBatteryGranted
                : AppLocalizations.of(context).onboardingBatteryWhy,
            action: battery
                ? null
                : AppLocalizations.of(context).settingsGrant,
            onAction: () async {
              await _channel.invokeMethod('requestBatteryExemption');
              _refresh();
            },
          ),

          // Not a checkable step. These screens report nothing back, so the
          // app cannot know whether the user granted anything -- and claiming
          // a tick it has not earned would be worse than leaving it open.
          _step(
            n: 3,
            done: null,
            title: hasVendor
                ? (_manufacturer.isEmpty
                    ? AppLocalizations.of(context).onboardingVendorKnownNoName
                    : AppLocalizations.of(context)
                        .onboardingVendorKnown(_manufacturer))
                : AppLocalizations.of(context).onboardingVendorUnknown,
            detail: hasVendor
                ? AppLocalizations.of(context).onboardingVendorKnownDetail
                : AppLocalizations.of(context).onboardingVendorUnknownDetail,
            action: hasVendor
                ? AppLocalizations.of(context).settingsOpenSettings
                : null,
            onAction: () async {
              final couldNotOpen =
                  AppLocalizations.of(context).settingsCouldNotOpen;
              final opened =
                  await _channel.invokeMethod<String>('openVendorAutostart') ?? '';
              if (!mounted) return;
              if (opened.isEmpty) {
                _say(couldNotOpen);
              }
            },
          ),

          _step(
            n: 4,
            done: null,
            title: AppLocalizations.of(context).onboardingDac,
            detail: AppLocalizations.of(context).onboardingDacDetail,
            action: null,
            onAction: null,
          ),

          const SizedBox(height: 12),
          FilledButton(
            onPressed: _finish,
            child: Text(ready
                ? AppLocalizations.of(context).onboardingDone
                : AppLocalizations.of(context).onboardingFinishAnyway),
          ),
          const SizedBox(height: 10),
          Text(
            ready
                ? AppLocalizations.of(context).onboardingAllGranted
                : AppLocalizations.of(context).onboardingSkippingIsFine,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ],
      ),
    );
  }

  void _say(String message) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));

  /// [done] null means "cannot be checked", which is a third state and not a
  /// failure: the vendor screens report nothing back.
  Widget _step({
    required int n,
    required bool? done,
    required String title,
    required String detail,
    required String? action,
    required Future<void> Function()? onAction,
  }) {
    final (icon, colour) = switch (done) {
      true => (Icons.check_circle, Colors.greenAccent),
      false => (Icons.radio_button_unchecked, Colors.white38),
      null => (Icons.info_outline, Colors.white38),
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: colour, size: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(AppLocalizations.of(context).onboardingStep(n, title),
                      style: const TextStyle(
                          fontSize: 15.5, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Text(detail,
                      style: const TextStyle(
                          fontSize: 12.5, height: 1.35, color: Colors.white60)),
                  if (action != null && onAction != null) ...[
                    const SizedBox(height: 10),
                    FilledButton.tonal(
                      onPressed: onAction,
                      child: Text(action),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
