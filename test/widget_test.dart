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
      if (call.method == 'selfTest') {
        return 'abi=arm64-v8a libusb=1.0.28 oboe=OK bits=64';
      }
      return null;
    });

    await tester.pumpWidget(const HifiRendApp());
    await tester.pumpAndSettle();

    expect(find.textContaining('libusb=1.0.28'), findsOneWidget);
    expect(find.text('not probed yet'), findsOneWidget);
  });

  testWidgets('renders the USB probe report', (tester) async {
    messenger.setMockMethodCallHandler(channel, (call) async => switch (call.method) {
          'selfTest' => 'abi=arm64-v8a libusb=1.0.28 oboe=OK bits=64',
          'probeUsb' => 'UAC version   : 2.0\nvolume control: none found',
          _ => null,
        });

    await tester.pumpWidget(const HifiRendApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Probe DAC'));
    await tester.pumpAndSettle();

    expect(find.textContaining('UAC version   : 2.0'), findsOneWidget);
  });

  testWidgets('surfaces a native failure instead of throwing', (tester) async {
    // The path on a device where libhifirend.so fails to load.
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'ERR', message: 'native library failed to load');
    });

    await tester.pumpWidget(const HifiRendApp());
    await tester.pumpAndSettle();

    expect(find.textContaining('native library failed to load'), findsOneWidget);
  });
}
