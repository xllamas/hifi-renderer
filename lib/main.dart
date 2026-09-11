import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'l10n/app_localizations.dart';
import 'licenses.dart';
import 'locale_setting.dart';
import 'renderer_state.dart';
import 'screens/now_playing_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/settings_screen.dart';
import 'usb/dac_capabilities.dart';

void main() {
  // Before runApp, because the licence page can be reached from settings
  // at any time and the registry is consulted lazily when it opens.
  registerThirdPartyLicenses();
  runApp(const HifiRendApp());
}

class HifiRendApp extends StatefulWidget {
  const HifiRendApp({super.key});

  @override
  State<HifiRendApp> createState() => _HifiRendAppState();
}

class _HifiRendAppState extends State<HifiRendApp> {
  @override
  void initState() {
    super.initState();
    // Rebuild the whole app when the language changes, because every string
    // on every pushed route was resolved at build time.
    LocaleSetting.instance.addListener(_onLocaleChanged);
    LocaleSetting.instance.load();
  }

  @override
  void dispose() {
    LocaleSetting.instance.removeListener(_onLocaleChanged);
    super.dispose();
  }

  void _onLocaleChanged() => setState(() {});

  @override
  Widget build(BuildContext context) => MaterialApp(
        // Not localised. It is the appliance's name, the same one that appears
        // on the network and in controllers, and translating it would make the
        // box answer to two different names.
        title: 'HiFi Renderer',
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(useMaterial3: true),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        // Null means "follow the phone", which is the default and the right
        // one for an appliance a guest may pick up.
        locale: LocaleSetting.instance.locale,
        home: const RendererHome(),
      );
}

/// Polls the Android service for state.
///
/// The service owns everything and must run with no UI at all, so this is a
/// viewer: it never holds authoritative state and never drives playback.
class RendererHome extends StatefulWidget {
  const RendererHome({super.key});

  @override
  State<RendererHome> createState() => _RendererHomeState();
}

class _RendererHomeState extends State<RendererHome> {
  static const _channel = MethodChannel('com.hifirend/renderer');

  RendererStatus _status = const RendererStatus();
  Timer? _poll;

  /// The probe result, as one value every screen watches.
  ///
  /// A plain field cannot work here: the settings and capability screens are
  /// pushed routes, built once from whatever was current at push time, and a
  /// setState on this state does not rebuild them. Selecting the second of two
  /// DACs therefore re-probed correctly and then displayed the first one's
  /// capabilities for the life of the screen.
  final ValueNotifier<DacProbeState> _probe =
      ValueNotifier(const DacProbeState());

  /// Automatic re-probes are rate limited. A failed probe leaves caps.ok
  /// false, and without this the 500 ms poll would reopen the device twice a
  /// second for as long as it kept failing.
  static const _retryGap = Duration(seconds: 5);
  DateTime? _lastProbe;

  @override
  void initState() {
    super.initState();
    _probeDac();
    _refresh();
    // Twice a second is enough for a progress bar and costs nothing; the
    // renderer is not driven from here.
    _poll = Timer.periodic(const Duration(milliseconds: 500), (_) => _refresh());
    _maybeOnboard();
  }

  /// Shows setup once, on the first run.
  ///
  /// Pushed over the now-playing screen rather than replacing it as a route,
  /// so nothing behind it has to know setup exists and dismissing it lands
  /// exactly where the app would otherwise have started. A failure to ask is
  /// not worth breaking startup over -- the same checks live in Settings.
  Future<void> _maybeOnboard() async {
    try {
      final raw =
          await _channel.invokeMethod<String>('onboardingStatus') ?? '{}';
      final status = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      if (status['hasRun'] == true || !mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => const OnboardingScreen(),
        fullscreenDialog: true,
      ));
    } catch (_) {
      // Never let setup stop the renderer from being usable.
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    _probe.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final raw = await _channel.invokeMethod<String>('rendererState') ?? '{}';
      if (!mounted) return;
      var next = RendererStatus.parse(raw);
      // Hold the value the user just chose until the write has had time to
      // land and be read back.
      final pending = _pendingVolume;
      if (pending != null) {
        if (_volumeSettling) {
          next = next.copyWithVolume(pending);
        } else {
          _pendingVolume = null;
        }
      }
      // A DAC that appears after startup -- or permission granted later -- must
      // trigger a re-probe, or the capability screen stays stuck on the failed
      // first attempt for the life of the app.
      final gained = next.dacConnected && !_status.dacConnected;
      setState(() => _status = next);
      if (_shouldProbe(next, gained)) _probeDac();
    } catch (_) {
      // The service may not be up yet; the idle screen is the right fallback.
    }
  }

  bool _shouldProbe(RendererStatus next, bool gained) {
    if (gained) return true;
    if (!next.dacConnected) return false;
    final caps = _probe.value.caps;
    if (caps != null && caps.ok) return false;
    final last = _lastProbe;
    return last == null || DateTime.now().difference(last) >= _retryGap;
  }

  /// Probes whichever DAC is currently selected and publishes the result.
  ///
  /// Also the callback the settings screen uses after changing the selection,
  /// which is why it goes through the notifier rather than returning: the
  /// screen that asked is not necessarily the only one showing the answer.
  Future<void> _probeDac() async {
    _lastProbe = DateTime.now();
    _probe.value = _probe.value.asProbing();
    try {
      final raw = await _channel.invokeMethod<String>('probeUsb') ?? '';
      _probe.value = DacProbeState(caps: DacCapabilities.parse(raw));
    } on PlatformException {
      // Leave capabilities unknown rather than claiming no DAC.
      _probe.value = DacProbeState(caps: _probe.value.caps);
    }
  }

  Future<void> _playPause() async {
    await _channel.invokeMethod('playPause');
    _refresh();
  }

  Future<void> _skip(bool forward) async {
    await _channel.invokeMethod(forward ? 'nextTrack' : 'previousTrack');
    _refresh();
  }

  /// While a drag is settling, the poll must not overwrite the slider.
  ///
  /// The hardware is still the authority -- a DAC's own knob can move
  /// independently -- but a read that crosses with our write returns the old
  /// value, and applying it makes the slider jump back to where it was and
  /// then forward again. That reads as the app fighting the user.
  int? _pendingVolume;
  DateTime? _volumeChangedAt;
  static const _volumeSettle = Duration(milliseconds: 1500);

  bool get _volumeSettling {
    final at = _volumeChangedAt;
    return at != null && DateTime.now().difference(at) < _volumeSettle;
  }

  Future<void> _setVolume(int percent) async {
    setState(() {
      _pendingVolume = percent;
      _volumeChangedAt = DateTime.now();
      _status = _status.copyWithVolume(percent);
    });
    await _channel.invokeMethod('setDacVolume', {'percent': percent});
  }

  @override
  Widget build(BuildContext context) => NowPlayingScreen(
        status: _status,
        onPlayPause: _playPause,
        onNext: () => _skip(true),
        onPrevious: () => _skip(false),
        onVolumeChanged: _setVolume,
        onOpenSettings: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => SettingsScreen(
            status: _status,
            probe: _probe,
            onRefreshCaps: _probeDac,
          ),
        )),
      );
}
