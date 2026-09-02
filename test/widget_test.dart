import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hifirend/main.dart';

void main() {
  const channel = MethodChannel('com.hifirend/renderer');

  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  testWidgets('shows the native self-test result', (tester) async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'selfTest');
      return 'abi=arm64-v8a libusb=1.0.28 oboe=OK bits=64';
    });

    await tester.pumpWidget(const HifiRendApp());
    await tester.pumpAndSettle();

    expect(find.text('HiFi Renderer'), findsOneWidget);
    expect(find.textContaining('libusb=1.0.28'), findsOneWidget);
  });

  testWidgets('reports a native failure instead of throwing', (tester) async {
    // The path taken on a device where libhifirend.so fails to load -- the UI
    // must surface it, because on unknown hardware this is the only diagnostic.
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'ERR', message: 'native library failed to load');
    });

    await tester.pumpWidget(const HifiRendApp());
    await tester.pumpAndSettle();

    expect(find.textContaining('native library failed to load'), findsOneWidget);
  });
}
