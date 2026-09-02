import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hifirend/main.dart';
import 'package:hifirend/usb/dac_capabilities.dart';

/// Modelled on the real AL400 probe output: UAC2, no feature unit, HID in-only,
/// no 16-bit alt-setting, async with feedback.
const _al400 = '''
{"ok":true,"claimedAudioControl":true,"attachedDevices":2,"dac":{"ok":true,
"vendorIdHex":"0x152a","productIdHex":"0x85dd","manufacturer":"SMSL",
"product":"SMSL USB AUDIO","usbVersion":"2.00","speed":"high","configurations":2,
"uacVersion":"2.0",
"clock":{"sourceId":41,"selectorId":40,"programmable":true,"currentRate":48000,
"rates":[44100,48000,88200,96000,176400,192000,352800,384000,705600,768000],"error":""},
"volume":{"hostControllable":false,"featureUnitId":-1,"detail":"","hidPresent":true,
"hidHasOutputEndpoint":false},
"formats":[
{"interface":1,"alt":1,"format":"PCM","bits":32,"subslot":4,"channels":2,
 "endpoint":{"address":"0x01","iso":true,"sync":"async","maxPacket":776,"interval":1},
 "feedbackEndpoint":{"address":"0x81","maxPacket":4,"interval":4}},
{"interface":1,"alt":2,"format":"PCM","bits":24,"subslot":4,"channels":2,
 "endpoint":{"address":"0x01","iso":true,"sync":"async","maxPacket":776,"interval":1},
 "feedbackEndpoint":{"address":"0x81","maxPacket":4,"interval":4}},
{"interface":1,"alt":3,"format":"DSD","bits":32,"subslot":4,"channels":2,
 "endpoint":{"address":"0x01","iso":true,"sync":"async","maxPacket":776,"interval":1},
 "feedbackEndpoint":{"address":"0x81","maxPacket":4,"interval":4}}],
"interfaces":[],"audioControlRawHex":"0924"}}
''';

void main() {
  group('DacCapabilities', () {
    test('parses a real UAC2 device', () {
      final c = DacCapabilities.parse(_al400);
      expect(c.ok, isTrue);
      expect(c.displayName, 'SMSL SMSL USB AUDIO');
      expect(c.uacVersion, '2.0');
      expect(c.maxRate, 768000);
      expect(c.minRate, 44100);
      expect(c.pcmBitDepths, [24, 32]);
      expect(c.supportsDsd, isTrue);
      expect(c.isAsync, isTrue);
      expect(c.hasFeedback, isTrue);
    });

    test('flags a DAC with no host volume control', () {
      final c = DacCapabilities.parse(_al400);
      expect(c.volumeHostControllable, isFalse);
      final note = c.notes.firstWhere((n) => n.title.contains('Volume'));
      expect(note.severity, NoteSeverity.important);
      // The HID interface is input-only, so the wording must not imply the
      // user can send volume to the DAC.
      expect(note.detail, contains('one-way'));
    });

    test('warns that 16-bit will be padded when no 16-bit mode exists', () {
      final c = DacCapabilities.parse(_al400);
      expect(c.requiresPaddingFor16Bit, isTrue);
      final note = c.notes.firstWhere((n) => n.title.contains('16-bit'));
      // Padding must be described as still bit-perfect, or it reads as a defect.
      expect(note.detail, contains('bit-perfect'));
      expect(note.title, contains('24-bit'));
    });

    test('surfaces structured errors', () {
      final c = DacCapabilities.parse(
          '{"ok":false,"error":"no_device","message":"No USB device detected."}');
      expect(c.ok, isFalse);
      expect(c.error, 'no_device');
      expect(c.errorMessage, contains('No USB device'));
    });

    test('survives a non-JSON response', () {
      final c = DacCapabilities.parse('boom');
      expect(c.ok, isFalse);
      expect(c.error, 'bad_response');
    });
  });

  group('UI', () {
    const channel = MethodChannel('com.hifirend/renderer');
    TestWidgetsFlutterBinding.ensureInitialized();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    testWidgets('shows the DAC and opens its capability screen', (tester) async {
      messenger.setMockMethodCallHandler(channel, (call) async => switch (call.method) {
            'selfTest' => 'abi=arm64-v8a libusb=1.0.28 oboe=OK bits=64',
            'probeUsb' => _al400,
            _ => null,
          });

      await tester.pumpWidget(const HifiRendApp());
      await tester.pumpAndSettle();

      expect(find.text('SMSL SMSL USB AUDIO'), findsOneWidget);

      await tester.tap(find.text('SMSL SMSL USB AUDIO'));
      await tester.pumpAndSettle();

      expect(find.text('DAC capabilities'), findsOneWidget);
      expect(find.textContaining('44.1 kHz'), findsWidgets);
      expect(find.textContaining('Volume is controlled by the DAC'), findsOneWidget);
    });

    testWidgets('reports no DAC without crashing', (tester) async {
      messenger.setMockMethodCallHandler(channel, (call) async => switch (call.method) {
            'selfTest' => 'abi=arm64-v8a',
            'probeUsb' =>
              '{"ok":false,"error":"no_device","message":"No USB device detected."}',
            _ => null,
          });

      await tester.pumpWidget(const HifiRendApp());
      await tester.pumpAndSettle();

      expect(find.text('No DAC connected'), findsOneWidget);
    });
  });
}
