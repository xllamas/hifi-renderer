import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hifirend/main.dart';
import 'package:hifirend/renderer_state.dart';
import 'package:hifirend/usb/dac_capabilities.dart';

/// Modelled on the real AL400 probe output.
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
{"interface":1,"alt":2,"format":"PCM","bits":24,"subslot":4,"channels":2,
 "endpoint":{"address":"0x01","iso":true,"sync":"async","maxPacket":776,"interval":1},
 "feedbackEndpoint":{"address":"0x81","maxPacket":4,"interval":4}}],
"interfaces":[],"audioControlRawHex":"0924"}}
''';

const _playing = '''
{"rendererName":"HiFi Renderer","transportState":"PLAYING","title":"Excursions",
"artist":"A Tribe Called Quest","album":"The Low End Theory","albumArtUri":null,
"durationSeconds":235,"positionSeconds":42,"formatBadge":"FLAC 16/44.1",
"sourceFormat":"FLAC","sourceRate":44100,"sourceBits":16,"channels":2,
"deviceBits":24,"altSetting":2,"dacName":"SMSL","dacConnected":true,
"bitPerfect":true,"underruns":0,"lastError":null}
''';

void main() {
  group('RendererStatus', () {
    test('parses a playing track', () {
      final s = RendererStatus.parse(_playing);
      expect(s.isPlaying, isTrue);
      expect(s.title, 'Excursions');
      expect(s.formatBadge, 'FLAC 16/44.1');
      expect(s.bitPerfect, isTrue);
      expect(s.progress, closeTo(42 / 235, 0.001));
    });

    test('formats times with and without hours', () {
      expect(RendererStatus.formatTime(42), '0:42');
      expect(RendererStatus.formatTime(235), '3:55');
      expect(RendererStatus.formatTime(3725), '1:02:05');
    });

    test('survives malformed state rather than throwing', () {
      final s = RendererStatus.parse('not json');
      expect(s.transportState, 'NO_MEDIA_PRESENT');
      expect(s.hasTrack, isFalse);
    });
  });

  group('DacCapabilities', () {
    test('flags a DAC with no host volume control', () {
      final c = DacCapabilities.parse(_al400);
      expect(c.ok, isTrue);
      expect(c.volumeHostControllable, isFalse);
      final note = c.notes.firstWhere((n) => n.title.contains('Volume'));
      expect(note.detail, contains('one-way'));
    });

    test('warns that 16-bit is padded when no 16-bit mode exists', () {
      final c = DacCapabilities.parse(_al400);
      expect(c.requiresPaddingFor16Bit, isTrue);
      expect(
        c.notes.firstWhere((n) => n.title.contains('16-bit')).detail,
        contains('bit-perfect'),
      );
    });
  });

  group('UI', () {
    const channel = MethodChannel('com.hifirend/renderer');
    TestWidgetsFlutterBinding.ensureInitialized();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    testWidgets('now playing shows track, format and bit-perfect', (tester) async {
      messenger.setMockMethodCallHandler(channel, (call) async => switch (call.method) {
            'rendererState' => _playing,
            'probeUsb' => _al400,
            _ => null,
          });

      await tester.pumpWidget(const HifiRendApp());
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.text('Excursions'), findsOneWidget);
      expect(find.text('A Tribe Called Quest'), findsOneWidget);
      expect(find.text('FLAC 16/44.1'), findsOneWidget);
      expect(find.text('bit-perfect'), findsOneWidget);
    });

    testWidgets('idle state names the renderer without crashing', (tester) async {
      messenger.setMockMethodCallHandler(channel, (call) async => switch (call.method) {
            'rendererState' =>
              '{"rendererName":"Living Room","transportState":"NO_MEDIA_PRESENT"}',
            'probeUsb' => '{"ok":false,"error":"no_device","message":"No USB device."}',
            _ => null,
          });

      await tester.pumpWidget(const HifiRendApp());
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.text('Living Room'), findsOneWidget);
      expect(find.text('No DAC connected'), findsOneWidget);
    });
  });
}
