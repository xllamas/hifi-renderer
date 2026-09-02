import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() => runApp(const HifiRendApp());

class HifiRendApp extends StatelessWidget {
  const HifiRendApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'HiFi Renderer',
        theme: ThemeData.dark(useMaterial3: true),
        home: const SkeletonScreen(),
      );
}

/// M0 placeholder. Replaced by the now-playing screen in M5; it exists only to
/// confirm on-device that Dart reaches Kotlin reaches libhifirend.so.
class SkeletonScreen extends StatefulWidget {
  const SkeletonScreen({super.key});

  @override
  State<SkeletonScreen> createState() => _SkeletonScreenState();
}

class _SkeletonScreenState extends State<SkeletonScreen> {
  static const _channel = MethodChannel('com.hifirend/renderer');
  String _status = 'checking...';

  @override
  void initState() {
    super.initState();
    _runSelfTest();
  }

  Future<void> _runSelfTest() async {
    String status;
    try {
      status = await _channel.invokeMethod<String>('selfTest') ?? 'no response';
    } on PlatformException catch (e) {
      status = 'platform error: ${e.message}';
    } on MissingPluginException {
      status = 'channel not registered';
    }
    if (mounted) setState(() => _status = status);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('HiFi Renderer', style: TextStyle(fontSize: 28)),
                const SizedBox(height: 8),
                const Text('M0 skeleton', style: TextStyle(color: Colors.white54)),
                const SizedBox(height: 32),
                SelectableText(
                  _status,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      );
}
