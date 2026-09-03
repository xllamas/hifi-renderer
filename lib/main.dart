import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'renderer_state.dart';
import 'screens/now_playing_screen.dart';
import 'screens/settings_screen.dart';
import 'usb/dac_capabilities.dart';

void main() => runApp(const HifiRendApp());

class HifiRendApp extends StatelessWidget {
  const HifiRendApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'HiFi Renderer',
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(useMaterial3: true),
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
  DacCapabilities? _caps;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _probeDac();
    _refresh();
    // Twice a second is enough for a progress bar and costs nothing; the
    // renderer is not driven from here.
    _poll = Timer.periodic(const Duration(milliseconds: 500), (_) => _refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final raw = await _channel.invokeMethod<String>('rendererState') ?? '{}';
      if (!mounted) return;
      final next = RendererStatus.parse(raw);
      // A DAC that appears after startup -- or permission granted later -- must
      // trigger a re-probe, or the capability screen stays stuck on the failed
      // first attempt for the life of the app.
      final gained = next.dacConnected && !_status.dacConnected;
      setState(() => _status = next);
      if (gained || (next.dacConnected && (_caps == null || !_caps!.ok))) {
        _probeDac();
      }
    } catch (_) {
      // The service may not be up yet; the idle screen is the right fallback.
    }
  }

  Future<void> _probeDac() async {
    try {
      final raw = await _channel.invokeMethod<String>('probeUsb') ?? '';
      if (mounted) setState(() => _caps = DacCapabilities.parse(raw));
    } on PlatformException {
      // Leave capabilities unknown rather than claiming no DAC.
    }
  }

  Future<void> _playPause() async {
    await _channel.invokeMethod('playPause');
    _refresh();
  }

  Future<void> _setVolume(int percent) async {
    // Optimistic: the poll corrects it from the hardware a moment later, which
    // matters on a DAC whose own knob can move independently.
    setState(() => _status = _status.copyWithVolume(percent));
    await _channel.invokeMethod('setDacVolume', {'percent': percent});
  }

  @override
  Widget build(BuildContext context) => NowPlayingScreen(
        status: _status,
        onPlayPause: _playPause,
        onVolumeChanged: _setVolume,
        onOpenSettings: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => SettingsScreen(
            status: _status,
            caps: _caps,
            onRefreshCaps: _probeDac,
          ),
        )),
      );
}
