import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hifirend/l10n/app_localizations.dart';
import 'package:hifirend/locale_setting.dart';

import 'package:hifirend/main.dart';
import 'package:hifirend/renderer_state.dart';
import 'package:hifirend/screens/dac_verification_screen.dart';
import 'package:hifirend/screens/onboarding_screen.dart';
import 'package:hifirend/screens/playback_test_screen.dart';
import 'package:hifirend/screens/settings_screen.dart';
import 'package:hifirend/screens/now_playing_screen.dart';
import 'package:hifirend/usb/dac_capabilities.dart';
import 'package:hifirend/usb/rate_sweep.dart';
import 'package:hifirend/usb/stability_soak.dart';

/// Wraps a screen the way the real app does.
///
/// Every screen now reads its text through AppLocalizations, which is an
/// inherited widget: a bare MaterialApp does not provide one and the screen
/// throws while building. Tests must therefore stand up the same delegates the
/// app does, or they test a configuration that never ships.
Future<AppLocalizations> englishStrings() =>
    AppLocalizations.delegate.load(const Locale('en'));

Widget localizedApp({required Widget home}) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: home,
    );


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
"deviceBits":24,"altSetting":2,"dacName":"SMSL USB AUDIO","dacConnected":true,"dacCount":1,
"bitPerfect":true,"dacVolume":-1,"dacVolumeSupported":false,
"underruns":0,"lastError":null}
''';

/// Modelled on the real SPACETOUCH probe output: a UAC1 headset adapter, whose
/// interface 1 is capture-only and whose interface 2 is the playback path.
const _uac1 = '''
{"ok":true,"claimedAudioControl":true,"attachedDevices":2,"dac":{"ok":true,
"vendorIdHex":"0x0666","productIdHex":"0x0880","manufacturer":"SPACETOUCH",
"product":"USB Audio","usbVersion":"2.00","speed":"full","configurations":1,
"uacVersion":"1.0",
"clock":{"sourceId":-1,"selectorId":-1,"programmable":false,"currentRate":0,
"rates":[],"error":""},
"volume":{"hostControllable":true,"featureUnitId":10,"detail":"UAC1 feature unit",
"hidPresent":true,"hidHasOutputEndpoint":false},
"formats":[
{"interface":1,"alt":1,"format":"PCM","bits":16,"subslot":2,"channels":2,
 "rates":[44100,48000],
 "endpoint":{"address":"0x00","iso":false,"sync":"none","maxPacket":0,"interval":0},
 "feedbackEndpoint":null},
{"interface":2,"alt":1,"format":"PCM","bits":16,"subslot":2,"channels":2,
 "rates":[44100,48000],
 "endpoint":{"address":"0x02","iso":true,"sync":"adaptive","maxPacket":600,"interval":1},
 "feedbackEndpoint":null},
{"interface":2,"alt":2,"format":"PCM","bits":24,"subslot":3,"channels":2,
 "rates":[44100,48000],
 "endpoint":{"address":"0x02","iso":true,"sync":"adaptive","maxPacket":600,"interval":1},
 "feedbackEndpoint":null}],
"interfaces":[],"audioControlRawHex":"0a24"}}
''';

/// A USB microphone: audio class, but nothing that can play.
const _captureOnly = '''
{"ok":true,"claimedAudioControl":true,"attachedDevices":1,"dac":{"ok":true,
"vendorIdHex":"0x1111","productIdHex":"0x2222","manufacturer":"Acme",
"product":"USB Mic","usbVersion":"1.10","speed":"full","configurations":1,
"uacVersion":"1.0",
"clock":{"sourceId":-1,"selectorId":-1,"programmable":false,"currentRate":0,
"rates":[],"error":""},
"volume":{"hostControllable":false,"featureUnitId":-1,"detail":"",
"hidPresent":false,"hidHasOutputEndpoint":false},
"formats":[
{"interface":1,"alt":1,"format":"PCM","bits":16,"subslot":2,"channels":2,
 "rates":[48000],
 "endpoint":{"address":"0x81","iso":false,"sync":"none","maxPacket":0,"interval":0},
 "feedbackEndpoint":null}],
"interfaces":[],"audioControlRawHex":"0a24"}}
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

    test('reports how many DACs are attached', () {
      final s = RendererStatus.parse(
          '{"transportState":"PLAYING","dacConnected":true,"dacCount":2,'
          '"dacName":"SMSL USB AUDIO"}');
      expect(s.dacCount, 2);
      expect(s.dacName, 'SMSL USB AUDIO');
    });

    test('hides volume control when the DAC has none', () {
      final s = RendererStatus.parse(_playing);
      expect(s.dacVolumeSupported, isFalse);
      expect(s.canControlVolume, isFalse);
    });

    test('offers volume control when the DAC reports a level', () {
      final s = RendererStatus.parse(
          '{"transportState":"PLAYING","dacVolume":55,"dacVolumeSupported":true}');
      expect(s.canControlVolume, isTrue);
      expect(s.dacVolume, 55);
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

  group('Onboarding', () {
    const channel = MethodChannel('com.hifirend/renderer');
    late TestDefaultBinaryMessenger messenger;

    setUp(() {
      messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    });

    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    void mock(String status, {List<String>? calls}) {
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls?.add(call.method);
        return switch (call.method) {
          'onboardingStatus' => status,
          'requestNotifications' => 'requested',
          'openVendorAutostart' => 'com.miui.securitycenter/...',
          _ => null,
        };
      });
    }

    testWidgets('offers every step, and lets the user leave without any',
        (tester) async {
      mock('{"hasRun":false,"notifications":false,'
          '"ignoringBatteryOptimizations":false,"manufacturer":"xiaomi",'
          '"hasVendorSettings":true,"unexpectedDeaths":0}');

      await tester.pumpWidget(localizedApp(home: const OnboardingScreen()));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.textContaining('Show a notification'), findsOneWidget);
      expect(find.textContaining('Stop Android suspending it'), findsOneWidget);
      expect(find.textContaining('Autostart (xiaomi)'), findsOneWidget);

      // The rest is below the fold on a test-sized screen.
      await tester.scrollUntilVisible(find.textContaining('Your DAC'), 200,
          scrollable: find.byType(Scrollable));
      expect(find.textContaining('Your DAC'), findsOneWidget);

      // Nothing granted, and leaving is still offered rather than blocked: a
      // step can be impossible on hardware nobody here owns.
      await tester.scrollUntilVisible(
          find.textContaining('Skipping is fine'), 200,
          scrollable: find.byType(Scrollable));
      expect(find.text('Finish anyway'), findsOneWidget);
      expect(find.textContaining('Skipping is fine'), findsOneWidget);
    });

    testWidgets('ticks what is granted and says so when all of it is',
        (tester) async {
      mock('{"hasRun":false,"notifications":true,'
          '"ignoringBatteryOptimizations":true,"manufacturer":"xiaomi",'
          '"hasVendorSettings":true,"unexpectedDeaths":0}');

      await tester.pumpWidget(localizedApp(home: const OnboardingScreen()));
      await tester.pump(const Duration(milliseconds: 100));

      // Granted steps stop offering their button.
      expect(find.text('Allow'), findsNothing);
      expect(find.text('Grant'), findsNothing);
      // The vendor step never ticks: those screens report nothing back, so a
      // tick would be a claim the app cannot support.
      expect(find.text('Open settings'), findsOneWidget);
      expect(find.textContaining('cannot tell whether you granted'),
          findsOneWidget);

      await tester.scrollUntilVisible(find.text('Done'), 200,
          scrollable: find.byType(Scrollable));
      expect(find.text('Done'), findsOneWidget);
      expect(find.textContaining('Everything the app can check'),
          findsOneWidget);
    });

    testWidgets('writes instructions instead when the phone is unknown',
        (tester) async {
      mock('{"hasRun":false,"notifications":true,'
          '"ignoringBatteryOptimizations":true,"manufacturer":"acme",'
          '"hasVendorSettings":false,"unexpectedDeaths":0}');

      await tester.pumpWidget(localizedApp(home: const OnboardingScreen()));
      await tester.pump(const Duration(milliseconds: 100));

      // No Intent to offer, so it must say what to look for by hand rather
      // than present a button that does nothing.
      expect(find.text('Open settings'), findsNothing);
      expect(find.textContaining('no known settings screen'), findsOneWidget);
      expect(find.textContaining('protected apps'), findsOneWidget);
    });

    testWidgets('marks setup done on finishing', (tester) async {
      final calls = <String>[];
      mock('{"hasRun":false,"notifications":true,'
          '"ignoringBatteryOptimizations":true,"manufacturer":"",'
          '"hasVendorSettings":false,"unexpectedDeaths":0}', calls: calls);

      await tester.pumpWidget(localizedApp(home: const OnboardingScreen()));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.scrollUntilVisible(find.text('Done'), 200,
          scrollable: find.byType(Scrollable));
      await tester.tap(find.text('Done'));
      await tester.pump();

      expect(calls, contains('setOnboardingDone'));
    });
  });

  group('FileSource', () {
    const channel = MethodChannel('com.hifirend/renderer');
    late TestDefaultBinaryMessenger messenger;

    setUp(() {
      messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    });

    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    /// A clean FLAC on a DAC that reports its clock.
    const streaming = '{"running":true,"rate":96000,"altSetting":2,'
        '"deviceBits":24,"subslot":4,"measuredRateHz":95999.0,'
        '"feedbackAccepted":900,"underruns":0,"transferErrors":0,'
        '"packetErrors":0,"packetsSubmitted":40000,"sourceFormat":"FLAC",'
        '"sourceBits":24,"channels":2,"ringFillPercent":98}';

    testWidgets('plays a picked file and judges it like a swept rate',
        (tester) async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return switch (call.method) {
          'listTestFiles' => '',
          'pickAudioFile' =>
            '{"uri":"content://x/1","name":"Babel.flac","mime":"audio/flac"}',
          'playFile' => '{"ok":true}',
          'fileStatus' => streaming,
          _ => null,
        };
      });

      await tester.pumpWidget(localizedApp(home: const PlaybackTestScreen()));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('Choose a file'));
      await tester.pump(const Duration(milliseconds: 600));

      // The picked MIME must reach the engine: the decoder is chosen from it,
      // and a wrong one silently falls back to "try FLAC, then give up".
      final play = calls.firstWhere((c) => c.method == 'playFile');
      expect(play.arguments['uri'], 'content://x/1');
      expect(play.arguments['mime'], 'audio/flac');

      // Status comes from the streaming engine, not the WAV file player.
      expect(calls.any((c) => c.method == 'fileStatus'), isTrue);
      expect(calls.any((c) => c.method == 'playbackStatus'), isFalse);

      // 'FLAC' also appears in the blurb listing supported formats, so match
      // the status row's value exactly.
      expect(find.text('FLAC'), findsOneWidget);
      await tester.scrollUntilVisible(
          find.textContaining('clean, clock within'), 200,
          scrollable: find.byType(Scrollable).first);
      expect(find.textContaining('clean, clock within'), findsOneWidget);
    });

    testWidgets('cancelling the picker changes nothing', (tester) async {
      final calls = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return switch (call.method) {
          'listTestFiles' => '',
          'pickAudioFile' => '{}',
          _ => null,
        };
      });

      await tester.pumpWidget(localizedApp(home: const PlaybackTestScreen()));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('Choose a file'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(calls, isNot(contains('playFile')));
      expect(find.text('Choose a file'), findsOneWidget);
    });

    testWidgets('shows why a file was refused rather than looking idle',
        (tester) async {
      messenger.setMockMethodCallHandler(channel, (call) async =>
          switch (call.method) {
            'listTestFiles' => '',
            'pickAudioFile' =>
              '{"uri":"content://x/2","name":"x.dsf","mime":"audio/dsd"}',
            'playFile' =>
              '{"ok":false,"message":"Stop playback before testing a file."}',
            _ => null,
          });

      await tester.pumpWidget(localizedApp(home: const PlaybackTestScreen()));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('Choose a file'));
      await tester.pump(const Duration(milliseconds: 300));

      await tester.scrollUntilVisible(
          find.textContaining('Stop playback before testing'), 200,
          scrollable: find.byType(Scrollable).first);
      expect(find.textContaining('Stop playback before testing'),
          findsOneWidget);
    });
  });

  group('SettingsScreen', () {
    const channel = MethodChannel('com.hifirend/renderer');
    late TestDefaultBinaryMessenger messenger;

    setUp(() {
      messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    });

    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    void mock({required int deaths, String manufacturer = 'xiaomi'}) {
      messenger.setMockMethodCallHandler(channel, (call) async =>
          switch (call.method) {
            'applianceStatus' =>
              '{"health":{"unexpectedDeaths":$deaths,"bootStarts":2,'
                  '"lastBootBlocked":null},"manufacturer":"$manufacturer",'
                  '"hasVendorSettings":true,'
                  '"ignoringBatteryOptimizations":false}',
            'getServerConversion' => false,
            'getScreenTimeout' => 5,
            'listDacs' => '{"devices":[]}',
            _ => null,
          });
    }

    testWidgets('reports being killed, above the settings that fix it',
        (tester) async {
      mock(deaths: 3);
      await tester.pumpWidget(localizedApp(
        home: SettingsScreen(
          status: const RendererStatus(),
          probe: ValueNotifier(const DacProbeState()),
          onRefreshCaps: () async {},
        ),
      ));
      await tester.pump(const Duration(milliseconds: 200));

      await tester.scrollUntilVisible(
          find.textContaining('stopped the renderer 3'), 200,
          scrollable: find.byType(Scrollable).first);
      expect(find.textContaining('stopped the renderer 3'), findsOneWidget);
      // Observed, not inferred from the make of the phone -- which is what
      // makes it the one signal that works on hardware nobody here owns.
      expect(find.textContaining('never recorded a clean stop'), findsOneWidget);
    });

    testWidgets('the screen timeout shows the stored value and can be changed',
        (tester) async {
      int? sent;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'setScreenTimeout') {
          sent = (call.arguments as Map)['minutes'] as int;
          return true;
        }
        return switch (call.method) {
          'applianceStatus' =>
            '{"health":{"unexpectedDeaths":0,"bootStarts":1,'
                '"lastBootBlocked":null},"manufacturer":"xiaomi",'
                '"hasVendorSettings":true,'
                '"ignoringBatteryOptimizations":true}',
          'getServerConversion' => false,
          // Stored as ten, so the control must not simply show its own default.
          'getScreenTimeout' => 10,
          'listDacs' => '{"devices":[]}',
          _ => null,
        };
      });

      await tester.pumpWidget(localizedApp(
        home: SettingsScreen(
          status: const RendererStatus(),
          probe: ValueNotifier(const DacProbeState()),
          onRefreshCaps: () async {},
        ),
      ));
      await tester.pump(const Duration(milliseconds: 200));

      await tester.scrollUntilVisible(
          find.text('Turn the screen off after'), 200,
          scrollable: find.byType(Scrollable).first);
      expect(find.text('10 minutes'), findsOneWidget);

      await tester.tap(find.byType(DropdownButton<int>));
      await tester.pumpAndSettle();
      // "Never" is offered, and is a real choice for a powered phone.
      await tester.tap(find.text('Never').last);
      await tester.pumpAndSettle();

      expect(sent, 0, reason: 'never is sent as zero minutes');
      expect(find.text('Never'), findsOneWidget);
      expect(find.textContaining('OLED panel'), findsOneWidget);
    });

    testWidgets('says nothing when it has never been killed', (tester) async {
      mock(deaths: 0);
      await tester.pumpWidget(localizedApp(
        home: SettingsScreen(
          status: const RendererStatus(),
          probe: ValueNotifier(const DacProbeState()),
          onRefreshCaps: () async {},
        ),
      ));
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.textContaining('stopped the renderer'), findsNothing);
    });

    testWidgets('states the vendor restriction as an inference, not a fact',
        (tester) async {
      mock(deaths: 0);
      await tester.pumpWidget(localizedApp(
        home: SettingsScreen(
          status: const RendererStatus(),
          probe: ValueNotifier(const DacProbeState()),
          onRefreshCaps: () async {},
        ),
      ));
      await tester.pump(const Duration(milliseconds: 200));

      await tester.scrollUntilVisible(
          find.textContaining('Phones from this maker'), 200,
          scrollable: find.byType(Scrollable).first);
      // The app knows the make and that a screen exists for it. It cannot
      // detect the restriction, and must not claim to.
      expect(find.textContaining('usually add background-app'), findsOneWidget);
      expect(find.textContaining('cannot detect them'), findsOneWidget);
    });
  });

  group('DacVerificationScreen', () {
    const channel = MethodChannel('com.hifirend/renderer');
    late TestDefaultBinaryMessenger messenger;

    setUp(() {
      messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    });

    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    /// Drives a whole sweep against a DAC that starts cleanly and reports no
    /// clock -- which is the UAC1 case, and the one real hardware here shows.
    Future<void> runSweep(WidgetTester tester) async {
      var statusCalls = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        switch (call.method) {
          case 'probeUsb':
            return _uac1;
          case 'playTone':
            return '{"ok":true}';
          case 'playbackStatus':
            statusCalls++;
            // Five glitches while filling, none afterwards, and no feedback:
            // the counters a device with no clock report actually produces.
            return '{"running":true,"altSetting":1,"deviceBits":16,'
                '"subslot":2,"measuredRateHz":0,"feedbackAccepted":0,'
                '"underruns":5,"transferErrors":0,"packetErrors":0,'
                '"packetsSubmitted":${statusCalls * 1000}}';
          default:
            return null;
        }
      });

      await tester.pumpWidget(
          localizedApp(home: const DacVerificationScreen()));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.text('Run rate sweep'));
      // Two rates, each settling then measuring. Stepped rather than jumped so
      // every await in the chain gets a turn.
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }
    }

    testWidgets('sweeps every rate and counts only steady-state glitches',
        (tester) async {
      await runSweep(tester);

      // The UAC1 fixture claims 44.1 and 48 kHz.
      expect(find.text('44.1 kHz'), findsOneWidget);
      expect(find.text('48 kHz'), findsOneWidget);

      // Clean after settling, and no clock to check it against.
      expect(find.text('unverified'), findsNWidgets(2));
      expect(find.text('pass'), findsNothing);
      expect(find.text('fail'), findsNothing);

      // The five start-up glitches are in the baseline, so they must not have
      // been counted against the device.
      expect(find.textContaining('underrun'), findsNothing);
      expect(
          find.textContaining('no feedback endpoint'), findsNWidgets(2));
    });

    testWidgets('follows the sweep down the list as rates complete',
        (tester) async {
      // The AL400 claims ten rates, which is enough rows to push the running
      // one off the bottom -- the case that had the user scrolling by hand.
      messenger.setMockMethodCallHandler(channel, (call) async =>
          switch (call.method) {
            'probeUsb' => _al400,
            'playTone' => '{"ok":true}',
            'playbackStatus' =>
              '{"running":true,"altSetting":2,"deviceBits":24,"subslot":4,'
                  '"measuredRateHz":0,"feedbackAccepted":0,"underruns":0,'
                  '"transferErrors":0,"packetErrors":0,"packetsSubmitted":9000}',
            _ => null,
          });

      await tester.pumpWidget(
          localizedApp(home: const DacVerificationScreen()));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('Run rate sweep'));
      for (var i = 0; i < 240; i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }

      final scrollable = tester.widget<ListView>(find.byType(ListView));
      final position = scrollable.controller!.position;
      expect(position.maxScrollExtent, greaterThan(0),
          reason: 'ten rates should overflow the viewport');
      expect(position.pixels, closeTo(position.maxScrollExtent, 1),
          reason: 'the view should have followed the results down');
    });

    testWidgets('stops following once the user scrolls back to look',
        (tester) async {
      messenger.setMockMethodCallHandler(channel, (call) async =>
          switch (call.method) {
            'probeUsb' => _al400,
            'playTone' => '{"ok":true}',
            'playbackStatus' =>
              '{"running":true,"altSetting":2,"deviceBits":24,"subslot":4,'
                  '"measuredRateHz":0,"feedbackAccepted":0,"underruns":0,'
                  '"transferErrors":0,"packetErrors":0,"packetsSubmitted":9000}',
            _ => null,
          });

      await tester.pumpWidget(
          localizedApp(home: const DacVerificationScreen()));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('Run rate sweep'));
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }

      // The user drags back up to read an earlier rate. From here the sweep
      // must leave the view where they put it.
      await tester.drag(find.byType(ListView), const Offset(0, 400));
      await tester.pump();
      final afterDrag =
          tester.widget<ListView>(find.byType(ListView)).controller!.position;
      final parked = afterDrag.pixels;
      expect(parked, lessThan(afterDrag.maxScrollExtent),
          reason: 'the drag should have moved off the bottom');

      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }

      final position =
          tester.widget<ListView>(find.byType(ListView)).controller!.position;
      expect(position.pixels, closeTo(parked, 1),
          reason: 'later results must not snatch the view back');
      // And the way back is offered rather than left to guesswork.
      expect(find.text('Follow'), findsOneWidget);

      // Wind the sweep up rather than leaving its timers running past the end
      // of the test.
      await tester.tap(find.text('Stop'));
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }
    });

    testWidgets('offers the report once the sweep is done', (tester) async {
      await runSweep(tester);
      expect(find.text('Copy report'), findsOneWidget);
      expect(find.textContaining('reports no clock'), findsOneWidget);
      // "Follow" belongs to a running sweep, not a finished one.
      expect(find.text('Follow'), findsNothing);
    });

    testWidgets('leaving mid-sweep stops the tone and does not throw',
        (tester) async {
      final stopped = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        stopped.add(call.method);
        return switch (call.method) {
          'probeUsb' => _uac1,
          'playTone' => '{"ok":true}',
          'playbackStatus' => '{"running":true}',
          _ => null,
        };
      });

      await tester.pumpWidget(
          localizedApp(home: const DacVerificationScreen()));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('Run rate sweep'));
      await tester.pump(const Duration(milliseconds: 600));

      // Replace the screen while a rate is still streaming: every setState
      // after this point is happening on a dead widget.
      await tester.pumpWidget(localizedApp(home: const SizedBox()));
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }

      expect(stopped, contains('stopPlayback'));
      expect(tester.takeException(), isNull);
    });
  });

  group('RateSweep', () {
    RateResult clean({
      int rate = 96000,
      double measured = 96000,
      bool feedback = true,
      int underruns = 0,
      int packetErrors = 0,
    }) =>
        RateResult(
          rate: rate,
          requestedBits: 24,
          configured: true,
          altSetting: 2,
          deviceBits: 24,
          subslot: 4,
          measuredRateHz: measured,
          feedbackSeen: feedback,
          underruns: underruns,
          packetErrors: packetErrors,
          packetsSubmitted: 100000,
        );

    test('passes a rate that streamed clean and clocked where it was asked', () {
      expect(clean().verdict, SweepVerdict.pass);
    });

    test('fails a DAC that accepted a rate and clocked another', () {
      // The failure this exists to catch: 96 kHz accepted, 48 delivered.
      final r = clean(rate: 96000, measured: 48000);
      expect(r.verdict, SweepVerdict.fail);
      expect(r.summary, contains('not 96000 Hz'));
    });

    test('tolerates the drift a correctly tracking DAC actually shows', () {
      // 0.002% was measured over 30 minutes on the reference hardware.
      expect(clean(measured: 96001.92).verdict, SweepVerdict.pass);
    });

    test('a clean stream with no feedback endpoint is unverified, not passed', () {
      final r = clean(feedback: false, measured: 0);
      expect(r.verdict, SweepVerdict.unverified);
      expect(r.deviationPercent, isNull);
      expect(r.summary, contains('no feedback endpoint'));
    });

    test('errors fail the rate even when the clock was right', () {
      expect(clean(underruns: 3).verdict, SweepVerdict.fail);
      expect(clean(packetErrors: 12).summary, contains('12 bad packets'));
    });

    test('a rate that would not configure fails with its reason', () {
      const r = RateResult(
        rate: 768000,
        requestedBits: 24,
        configured: false,
        failure: 'configure: device does not support 768000 Hz',
      );
      expect(r.verdict, SweepVerdict.fail);
      expect(r.summary, contains('does not support'));
    });

    test('the report says plainly when nothing could measure the clock', () {
      final report = SweepReport(
        deviceName: 'SPACETOUCH USB Audio',
        uacVersion: '1.0',
        when: DateTime(2026, 9, 5),
        seconds: 4,
        results: [
          clean(rate: 44100, feedback: false, measured: 0),
          clean(rate: 48000, feedback: false, measured: 0),
        ],
      );
      expect(report.nothingMeasured, isTrue);
      expect(report.failed, 0);
      expect(report.headline, contains('reports no clock'));

      final text = report.asText();
      expect(text, contains('SPACETOUCH USB Audio'));
      expect(text, contains('UNVERIFIED'));
      // The report must never let a clean sweep be read as proof of the clock.
      expect(text, contains('no measurement here'));
      // And it must say what it cannot see at all.
      expect(text, contains('after conversion'));
    });

    test('a mixed report counts each verdict separately', () {
      final report = SweepReport(
        deviceName: 'AL400',
        uacVersion: '2.0',
        when: DateTime(2026, 9, 5),
        seconds: 4,
        results: [
          clean(rate: 44100, measured: 44100),
          clean(rate: 96000, measured: 48000),
          clean(rate: 192000, feedback: false, measured: 0),
        ],
      );
      expect(report.passed, 1);
      expect(report.failed, 1);
      expect(report.unverified, 1);
      expect(report.nothingMeasured, isFalse);
      expect(report.headline, contains('1 of 3 rates failed'));
    });
  });

  group('StabilitySoak', () {
    /// A run of [minutes] with a sample every 5 s, clean unless told otherwise.
    SoakResult soak({
      int minutes = 10,
      int rate = 768000,
      double measured = 768000,
      bool feedback = true,
      bool completed = true,
      String? failure,
      Map<int, int> underrunsAt = const {},
      double drift = 0,
    }) {
      final samples = <SoakSample>[];
      final ticks = minutes * 12;
      var underruns = 0;
      for (var i = 1; i <= ticks; i++) {
        underruns += underrunsAt[i * 5] ?? 0;
        samples.add(SoakSample(
          at: Duration(seconds: i * 5),
          // Drift ramps across the run, which is the shape a warming clock has.
          measuredRateHz:
              feedback ? measured + drift * (i / ticks) : 0,
          underruns: underruns,
          ringFillPercent: 90,
        ));
      }
      return SoakResult(
        deviceName: 'AL400',
        uacVersion: '2.0',
        rate: rate,
        bits: 32,
        altSetting: 1,
        planned: Duration(minutes: minutes),
        when: DateTime(2026, 9, 5),
        completed: completed,
        failure: failure,
        samples: samples,
      );
    }

    test('a clean ten minutes clears the bar the project set itself', () {
      final r = soak();
      expect(r.verdict, SweepVerdict.pass);
      expect(r.isClean, isTrue);
      expect(r.meetsBar, isTrue);
      expect(r.actual, const Duration(minutes: 10));
      expect(r.asText(), contains('Clears the ten-minute'));
    });

    test('a clean short run is explicitly not a shorter version of the bar', () {
      final r = soak(minutes: 2);
      expect(r.isClean, isTrue);
      expect(r.meetsBar, isFalse);
      expect(r.asText(), contains('Short of the ten-minute bar'));
    });

    test('places the first fault in time, which is the point of a soak', () {
      // One underrun eight minutes in: the kind a four-second test cannot see.
      final r = soak(underrunsAt: {480: 1});
      expect(r.verdict, SweepVerdict.fail);
      expect(r.firstFaultAt, const Duration(seconds: 480));
      expect(r.meetsBar, isFalse);
      expect(r.headline, contains('first at 08:00'));
      expect(r.asText(), contains('Faults appeared at:'));
    });

    test('reports drift as a spread, not just a worst case', () {
      // 20 Hz of wander at 768 kHz is far inside tolerance but worth seeing:
      // a soak that reported only the worst reading would hide the shape.
      // The ramp starts one tick in, so it spans drift * (ticks - 1) / ticks.
      const ticks = 10 * 12;
      const span = 20 * (ticks - 1) / ticks;
      final r = soak(drift: 20);
      expect(r.verdict, SweepVerdict.pass);
      expect(r.rateMax! - r.rateMin!, closeTo(span, 0.01));
      expect(r.rateSpreadPercent, closeTo(span / 768000 * 100, 1e-9));
    });

    test('a clock that wanders outside tolerance fails even with no glitches',
        () {
      final r = soak(measured: 768000, drift: 8000);
      expect(r.isClean, isTrue);
      expect(r.verdict, SweepVerdict.fail);
    });

    test('no feedback endpoint is unverified over any length of run', () {
      final r = soak(minutes: 30, feedback: false);
      expect(r.verdict, SweepVerdict.unverified);
      expect(r.meetsBar, isTrue, reason: 'the digital path was still faultless');
      expect(r.asText(), contains('no feedback endpoint'));
      expect(r.headline, contains('reports no clock'));
    });

    test('a stream that stops on its own is a fault, not an ending', () {
      final r = soak(minutes: 3, completed: false,
          failure: 'the stream stopped on its own');
      expect(r.isClean, isFalse);
      expect(r.verdict, SweepVerdict.fail);
      expect(r.headline, contains('stopped on its own'));
    });

    test('stopping early keeps what was proven and says it was stopped', () {
      final r = soak(minutes: 12, completed: false);
      expect(r.meetsBar, isTrue);
      expect(r.headline, contains('Stopped at 12:00'));
      expect(r.asText(), contains('stopped early'));
    });

    test('the report never lets a pass stand for hardware it never saw', () {
      expect(soak().asText(), contains('describes this one device'));
      expect(soak().asText(), contains('a failure is worth reporting'));
    });
  });

  group('DacCapabilities', () {
    test('flags a DAC with no host volume control', () async {
      final t = await englishStrings();
      final c = DacCapabilities.parse(_al400);
      expect(c.ok, isTrue);
      expect(c.volumeHostControllable, isFalse);
      final note = c.notes(t).firstWhere((n) => n.title.contains('Volume'));
      expect(note.detail, contains('one-way'));
    });

    test('warns that 16-bit is padded when no 16-bit mode exists', () async {
      final t = await englishStrings();
      final c = DacCapabilities.parse(_al400);
      expect(c.requiresPaddingFor16Bit, isTrue);
      expect(
        c.notes(t).firstWhere((n) => n.title.contains('16-bit')).detail,
        contains('bit-perfect'),
      );
    });

    test('accepts a UAC1 device rather than rejecting it on class version', () {
      final c = DacCapabilities.parse(_uac1);
      expect(c.ok, isTrue);
      expect(c.uacVersion, '1.0');
      expect(c.isSupported, isTrue);
    });

    test('takes UAC1 rates from the alt-settings, not the absent clock', () {
      final c = DacCapabilities.parse(_uac1);
      // UAC1 has no clock entity, so the clock list is empty on a device that
      // plays perfectly well.
      expect(c.rates, isEmpty);
      expect(c.playableRates, [44100, 48000]);
      expect(c.maxRate, 48000);
    });

    test('ignores the capture alt-setting when reporting bit depths', () {
      final c = DacCapabilities.parse(_uac1);
      // Interface 1 is the microphone path; only interface 2 can play.
      expect(c.pcmBitDepths, [16, 24]);
    });

    test('notes that an adaptive device follows the phone clock', () async {
      final t = await englishStrings();
      final c = DacCapabilities.parse(_uac1);
      expect(c.isAdaptiveOnly, isTrue);
      expect(
        c.notes(t).any((n) => n.title.contains('clock')),
        isTrue,
      );
      expect(c.hasFeedback, isFalse);
    });

    test('reports a capture-only device as unusable, whatever its class', () async {
      final t = await englishStrings();
      final c = DacCapabilities.parse(_captureOnly);
      expect(c.ok, isTrue);
      expect(c.isSupported, isFalse);
      expect(
        c.notes(t).first.detail,
        contains('microphone'),
      );
    });
  });

  group('Language', () {
    test('every shipped language is named in its own script', () {
      // A picker that lists a language in a script the reader cannot read is
      // no use to the person looking for it, and the default fallback --
      // toLanguageTag() -- silently produces "ko" instead of "한국어" when a
      // locale is added and this switch is not.
      for (final locale in LocaleSetting.supported) {
        final name = LocaleSetting.nameOf(locale);
        expect(name, isNotEmpty);
        expect(name, isNot(locale.toLanguageTag()),
            reason: 'no native name for $locale');
      }
    });

    test('both Portuguese variants ship and are told apart', () {
      // Brazilian and European Portuguese differ enough in ordinary vocabulary
      // to be worth separating, and a picker that showed two entries with the
      // same label would be worse than one.
      final tags = LocaleSetting.supported.map((l) => l.toString()).toList();
      expect(tags, contains('pt_BR'));
      expect(tags, contains('pt_PT'));
      expect(LocaleSetting.nameOf(const Locale('pt', 'BR')),
          isNot(LocaleSetting.nameOf(const Locale('pt', 'PT'))));
    }, skip: 'Pending: only app_en.arb exists so far, so supportedLocales is '
        'English alone. Delete this skip when the translations land — the test '
        'is what says they did.');

    test('empty or missing means follow the phone', () {
      expect(LocaleSetting.parseTag(null), isNull);
      expect(LocaleSetting.parseTag(''), isNull);
    });

    test('either separator is understood', () {
      // This app writes pt_BR; Android hands back pt-BR. Both mean the same
      // thing and a picker that lost the choice on one of them would look like
      // the setting simply did not save.
      expect(LocaleSetting.parseTag('pt_BR').toString(), 'pt_BR');
      expect(LocaleSetting.parseTag('pt-BR').toString(), 'pt_BR');
      expect(LocaleSetting.parseTag('es').toString(), 'es');
    }, skip: 'Pending: parseTag only returns languages actually shipped, and '
        'so far that is English alone. Delete this skip with the other one.');

    test('a tag naming a language we no longer ship falls back to the phone', () {
      // A stored choice outlives the translation it names. Returning it anyway
      // would leave the app in a language that does not exist, showing English
      // through a locale that resolves to nothing.
      expect(LocaleSetting.parseTag('xx'), isNull);
      expect(LocaleSetting.parseTag('en_AU'), isNull);
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
      // Play/pause is always available; the AL400 has no volume control, so no
      // slider should be offered.
      expect(find.byIcon(Icons.pause), findsOneWidget);
      expect(find.byType(Slider), findsNothing);
      // The output device must be named: with a hub, Ethernet adapter and
      // possibly several DACs attached, "playing" is not enough information.
      expect(find.text('SMSL USB AUDIO'), findsOneWidget);
    });

    testWidgets('a refused track explains itself in plain language', (tester) async {
      messenger.setMockMethodCallHandler(channel, (call) async => switch (call.method) {
            'rendererState' =>
              '{"rendererName":"Living Room","transportState":"STOPPED",'
                  '"title":"Below My Feet","artist":"Mumford & Sons",'
                  '"dacConnected":true,"dacName":"SPACETOUCH USB Audio","dacCount":1,'
                  '"lastError":"This track is in a format the renderer cannot decode.",'
                  '"lastErrorDetail":"unsupported or unrecognised audio format '
                  '(audio/L16;rate=44100;channels=2)"}',
            'probeUsb' => _al400,
            _ => null,
          });

      await tester.pumpWidget(const HifiRendApp());
      await tester.pump(const Duration(milliseconds: 600));

      // The headline is what has to carry across a room; the engine's own
      // wording is there for whoever walks over, not instead of a sentence.
      expect(find.text('This track is in a format the renderer cannot decode.'),
          findsOneWidget);
      expect(
          find.text('unsupported or unrecognised audio format '
              '(audio/L16;rate=44100;channels=2)'),
          findsOneWidget);
      // And it must not have replaced the track it failed on.
      expect(find.text('Below My Feet'), findsOneWidget);
    });

    testWidgets('skip buttons appear only for a playlist the renderer holds',
        (tester) async {
      // A DLNA controller sends one track at a time, so the renderer does not
      // know what comes next. Offering a next button there would either do
      // nothing or do something surprising.
      final dlna = RendererStatus.parse(
        '{"rendererName":"Living Room","transportState":"PLAYING",'
        '"title":"Chameleon","dacConnected":true,"dacName":"SMSL USB AUDIO",'
        '"dacCount":1,"playlistLength":0}',
      );
      expect(dlna.hasLocalPlaylist, isFalse);

      await tester.pumpWidget(localizedApp(
        home: NowPlayingScreen(
          status: dlna,
          onOpenSettings: () {},
          onPlayPause: () {},
          onNext: () {},
          onPrevious: () {},
          onVolumeChanged: (_) {},
        ),
      ));
      expect(find.byIcon(Icons.skip_next), findsNothing);
      expect(find.byIcon(Icons.skip_previous), findsNothing);
    });

    testWidgets('skip buttons are live, and disabled at the ends of the list',
        (tester) async {
      Future<void> show(RendererStatus s, {VoidCallback? onNext}) =>
          tester.pumpWidget(localizedApp(
            home: NowPlayingScreen(
              status: s,
              onOpenSettings: () {},
              onPlayPause: () {},
              onNext: onNext ?? () {},
              onPrevious: () {},
              onVolumeChanged: (_) {},
            ),
          ));

      String state(int position, int length, {bool repeat = false}) =>
          '{"rendererName":"Living Room","transportState":"PLAYING",'
          '"title":"Chameleon","dacConnected":true,"dacName":"SMSL USB AUDIO",'
          '"dacCount":1,"playlistLength":$length,"playlistPosition":$position,'
          '"playlistRepeat":$repeat}';

      // Middle of the list: both ways available, and next actually fires.
      var tapped = false;
      await show(RendererStatus.parse(state(2, 3)), onNext: () => tapped = true);
      expect(find.byIcon(Icons.skip_next), findsOneWidget);
      await tester.tap(find.byIcon(Icons.skip_next));
      expect(tapped, isTrue);

      // First track: previous is disabled but still shown -- the controls must
      // not change shape under a thumb as the playlist advances.
      await show(RendererStatus.parse(state(1, 3)));
      expect(find.byIcon(Icons.skip_previous), findsOneWidget);
      expect(
          tester.widget<IconButton>(find.ancestor(
              of: find.byIcon(Icons.skip_previous),
              matching: find.byType(IconButton))).onPressed,
          isNull);

      // Last track: next is disabled.
      await show(RendererStatus.parse(state(3, 3)));
      expect(
          tester.widget<IconButton>(find.ancestor(
              of: find.byIcon(Icons.skip_next),
              matching: find.byType(IconButton))).onPressed,
          isNull);

      // Repeat makes both ends reachable again.
      final wrapping = RendererStatus.parse(state(3, 3, repeat: true));
      expect(wrapping.canGoNext, isTrue);
      expect(wrapping.canGoPrevious, isTrue);
    });

    testWidgets('a stopped renderer shows no format badge and no bit-perfect claim',
        (tester) async {
      // The badge describes a running stream. Once playback stops there is
      // none, and "FLAC 24/96 - bit-perfect" left on screen states something
      // about an idle DAC -- the one claim this app must not make loosely.
      // The track it stopped on is still named, so a failure has something to
      // point at.
      final stopped = RendererStatus.parse(
        '{"rendererName":"Living Room","transportState":"STOPPED",'
        '"title":"Dead 3","artist":"Test Signals","dacConnected":true,'
        '"dacName":"SMSL USB AUDIO","dacCount":1,"bitPerfect":false,'
        '"lastError":"Stopped after 3 tracks in a row could not be played."}',
      );

      await tester.pumpWidget(localizedApp(
        home: NowPlayingScreen(
          status: stopped,
          onOpenSettings: () {},
          onPlayPause: () {},
          onNext: () {},
          onPrevious: () {},
          onVolumeChanged: (_) {},
        ),
      ));

      expect(stopped.formatBadge, isNull);
      expect(find.textContaining('FLAC'), findsNothing);
      expect(find.text('bit-perfect'), findsNothing);
      expect(find.text('Dead 3'), findsOneWidget);
    });

    testWidgets('a paused renderer keeps its badge, because the stream is open',
        (tester) async {
      final paused = RendererStatus.parse(
        '{"rendererName":"Living Room","transportState":"PAUSED_PLAYBACK",'
        '"title":"Chameleon","dacConnected":true,"dacName":"SMSL USB AUDIO",'
        '"dacCount":1,"formatBadge":"FLAC 24/96","sourceFormat":"FLAC",'
        '"sourceRate":96000,"sourceBits":24,"bitPerfect":true,"output":"usb"}',
      );

      await tester.pumpWidget(localizedApp(
        home: NowPlayingScreen(
          status: paused,
          onOpenSettings: () {},
          onPlayPause: () {},
          onNext: () {},
          onPrevious: () {},
          onVolumeChanged: (_) {},
        ),
      ));

      expect(find.textContaining('FLAC'), findsOneWidget);
      expect(find.text('bit-perfect'), findsOneWidget);
    });

    testWidgets('the problem banner fits on the screen it appears on',
        (tester) async {
      // A real failure overflowed the bottom of a 1080x2400 phone by 20px, and
      // Flutter drew its overflow stripes straight across the message the user
      // needed to read. The art has to give way to the banner, not the other
      // way round.
      // The Redmi it happened on: 1080x2400 at density 440 (DPR 2.75), less
      // the status and navigation bars that SafeArea takes out. Guessing the
      // geometry instead produces a *different* overflow -- a narrower logical
      // width overflows horizontally, which is not the bug being fixed.
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.75;
      tester.view.padding = const FakeViewPadding(top: 108, bottom: 130);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPadding);

      final status = RendererStatus.parse(
        '{"rendererName":"Living Room","transportState":"STOPPED",'
        '"title":"Chameleon","artist":"Herbie Hancock","album":"Head Hunters",'
        '"durationSeconds":945,"formatBadge":"FLAC 16/44.1","sourceFormat":"FLAC",'
        '"sourceRate":44100,"sourceBits":16,"bitPerfect":true,'
        '"dacConnected":true,"dacName":"SMSL USB AUDIO","dacCount":1,'
        '"lastError":"The renderer lost contact with the media server.",'
        '"lastErrorDetail":"the media server could not be reached: '
        'Failed to connect to /192.168.100.41:57645"}',
      );

      await tester.pumpWidget(localizedApp(
        home: NowPlayingScreen(
          status: status,
          onOpenSettings: () {},
          onPlayPause: () {},
          onNext: () {},
          onPrevious: () {},
          onVolumeChanged: (_) {},
        ),
      ));

      expect(tester.takeException(), isNull,
          reason: 'the banner must not overflow the layout');
      expect(find.text('The renderer lost contact with the media server.'),
          findsOneWidget);
    });

    testWidgets('a problem with no technical detail shows only the sentence',
        (tester) async {
      messenger.setMockMethodCallHandler(channel, (call) async => switch (call.method) {
            'rendererState' =>
              '{"rendererName":"Living Room","transportState":"STOPPED",'
                  '"title":"Bird Machine","dacConnected":true,'
                  '"dacName":"SPACETOUCH USB Audio","dacCount":1,'
                  '"lastError":"This DAC cannot play 192 kHz; its highest rate is 48 kHz."}',
            'probeUsb' => _al400,
            _ => null,
          });

      await tester.pumpWidget(const HifiRendApp());
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.text('This DAC cannot play 192 kHz; its highest rate is 48 kHz.'),
          findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('keeps the kill notice off the now-playing screen',
        (tester) async {
      messenger.setMockMethodCallHandler(channel, (call) async => switch (call.method) {
            'rendererState' =>
              '{"rendererName":"Living Room","transportState":"PLAYING",'
                  '"title":"Excursions","dacConnected":true,'
                  '"dacName":"SMSL USB AUDIO","dacCount":1}',
            'probeUsb' => _al400,
            _ => null,
          });

      await tester.pumpWidget(const HifiRendApp());
      await tester.pump(const Duration(milliseconds: 600));

      // Being killed in the background is a standing configuration fault, and
      // it lives in settings with the fixes for it. This screen is for the
      // music.
      expect(find.textContaining('stopped the renderer'), findsNothing);
      expect(find.text('Excursions'), findsOneWidget);
    });

    testWidgets('idle screen names the connected DAC', (tester) async {
      messenger.setMockMethodCallHandler(channel, (call) async => switch (call.method) {
            'rendererState' =>
              '{"rendererName":"Living Room","transportState":"NO_MEDIA_PRESENT",'
                  '"dacConnected":true,"dacName":"SMSL USB AUDIO","dacCount":1}',
            'probeUsb' => _al400,
            _ => null,
          });

      await tester.pumpWidget(const HifiRendApp());
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.text('Living Room'), findsOneWidget);
      expect(find.text('Ready — waiting for a controller'), findsOneWidget);
      expect(find.text('SMSL USB AUDIO'), findsOneWidget);
    });

    testWidgets('shows a volume slider only when the DAC supports it', (tester) async {
      messenger.setMockMethodCallHandler(channel, (call) async => switch (call.method) {
            'rendererState' =>
              '{"rendererName":"R","transportState":"PLAYING","title":"T",'
                  '"formatBadge":"FLAC 16/44.1","dacVolume":40,'
                  '"dacVolumeSupported":true,"bitPerfect":true}',
            'probeUsb' => _al400,
            _ => null,
          });

      await tester.pumpWidget(const HifiRendApp());
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.byType(Slider), findsOneWidget);
      expect(find.text('40'), findsOneWidget);
    });

    testWidgets('lays out horizontally in landscape', (tester) async {
      tester.view.physicalSize = const Size(2400, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      messenger.setMockMethodCallHandler(channel, (call) async => switch (call.method) {
            'rendererState' => _playing,
            'probeUsb' => _al400,
            _ => null,
          });

      await tester.pumpWidget(const HifiRendApp());
      await tester.pump(const Duration(milliseconds: 600));

      // Art and details side by side: the art's centre must sit left of the
      // title's centre.
      final art = tester.getCenter(find.byType(ClipRRect).first);
      final title = tester.getCenter(find.text('Excursions'));
      expect(art.dx, lessThan(title.dx));
      expect(find.text('FLAC 16/44.1'), findsOneWidget);
    });

    testWidgets('marks the fallback as system audio, not bit-perfect', (tester) async {
      const playing = '''
{"rendererName":"HiFi Renderer","transportState":"PLAYING","title":"Fallback",
"artist":"Test","album":"Test","durationSeconds":100,"positionSeconds":10,
"formatBadge":"FLAC 16/44.1","sourceFormat":"FLAC","sourceRate":44100,
"sourceBits":16,"channels":2,"dacConnected":false,"dacCount":0,
"bitPerfect":false,"output":"android","dacVolume":-1,
"dacVolumeSupported":false,"underruns":0}
''';
      final status = RendererStatus.parse(playing);
      expect(status.usingSystemAudio, isTrue);
      expect(status.bitPerfect, isFalse);
      await tester.pumpWidget(localizedApp(
        home: NowPlayingScreen(
          status: status,
          onOpenSettings: () {},
          onPlayPause: () {},
          onNext: () {},
          onPrevious: () {},
          onVolumeChanged: (_) {},
        ),
      ));
      expect(find.text('system audio'), findsOneWidget);
      expect(find.text('bit-perfect'), findsNothing);
      expect(find.textContaining('resampled by Android'), findsOneWidget);
    });

    testWidgets('an AirPlay guest is named, not silently un-ticked', (tester) async {
      // The guest path reaches the DAC by exactly the same untouched route as
      // a local file, so the sink is honest in reporting itself bit-perfect --
      // and the renderer must still not claim it, because the sender resampled
      // to 44.1 kHz and applied its own volume before a byte arrived. Dropping
      // the tick is necessary but not sufficient: a missing tick is equally
      // consistent with the fallback output and with nothing playing, and the
      // owner is owed the actual reason.
      const guest = '''
{"rendererName":"HiFi Renderer","transportState":"PLAYING","title":"Guest Track",
"artist":"Someone's Phone","durationSeconds":210,"positionSeconds":12,
"formatBadge":"ALAC 16/44.1","sourceFormat":"ALAC","sourceRate":44100,
"sourceBits":16,"channels":2,"dacConnected":true,"dacName":"SMSL USB AUDIO",
"dacCount":1,"bitPerfect":false,"senderAltered":true,"output":"usb",
"dacVolume":50,"dacVolumeSupported":true,"underruns":0}
''';
      final status = RendererStatus.parse(guest);
      expect(status.senderAltered, isTrue);
      expect(status.bitPerfect, isFalse);
      // Not the fallback: the DAC really is carrying this, so the system-audio
      // warning would be a different and wrong statement.
      expect(status.usingSystemAudio, isFalse);

      await tester.pumpWidget(localizedApp(
        home: NowPlayingScreen(
          status: status,
          onOpenSettings: () {},
          onPlayPause: () {},
          onNext: () {},
          onPrevious: () {},
          onVolumeChanged: (_) {},
        ),
      ));

      expect(find.text('bit-perfect'), findsNothing);
      expect(find.text('system audio'), findsNothing);
      expect(find.textContaining('sender resampled'), findsOneWidget);
      expect(find.text('ALAC 16/44.1'), findsOneWidget);
    });

    testWidgets('a guest with no track name is named by its sender', (tester) async {
      // macOS routes system audio through a sender with no concept of a track,
      // so the DAAP body arrives with every string field empty and the screen
      // has no title to show. Naming who has the output is the better answer,
      // and for an owner hearing music start unexpectedly it is the more
      // useful one.
      const guest = """
{"transportState":"PLAYING","formatBadge":"ALAC 16/44.1","sourceFormat":"ALAC",
"sourceRate":44100,"sourceBits":16,"bitPerfect":false,"senderAltered":true,
"output":"usb","dacConnected":true,"dacName":"SMSL USB AUDIO","dacCount":1,
"senderName":"Walrus"}
""";
      final status = RendererStatus.parse(guest);
      expect(status.title, isNull);
      expect(status.displayTitle(await englishStrings()), 'AirPlay from Walrus');

      await tester.pumpWidget(localizedApp(
        home: NowPlayingScreen(
          status: status,
          onOpenSettings: () {},
          onPlayPause: () {},
          onNext: () {},
          onPrevious: () {},
          onVolumeChanged: (_) {},
        ),
      ));
      expect(find.text('AirPlay from Walrus'), findsOneWidget);
      expect(find.text('Unknown track'), findsNothing);
    });

    test('a real title always outranks the sender name', () async {
      // The fallback is for the case with no title. An iPhone that does send
      // one must not have it hidden behind the name of the phone.
      final named = RendererStatus.parse(
        '{"title":"Chameleon","senderName":"Walrus","output":"usb"}',
      );
      expect(named.displayTitle(await englishStrings()), 'Chameleon');

      // And with neither, the wording is unchanged from before.
      final bare = RendererStatus.parse('{"output":"usb"}');
      expect(bare.displayTitle(await englishStrings()), 'Unknown track');
    });

    test('a volume change does not quietly restore the bit-perfect claim', () {
      // copyWithVolume rebuilds the whole record field by field, so a field it
      // forgets silently reverts to its default -- and this field's default is
      // the claiming one. Turning the knob during a guest's stream would have
      // put the tick back.
      final guest = RendererStatus.parse(
        '{"transportState":"PLAYING","formatBadge":"ALAC 16/44.1",'
        '"bitPerfect":false,"senderAltered":true,"output":"usb"}',
      );
      expect(guest.copyWithVolume(42).senderAltered, isTrue);
      expect(guest.copyWithVolume(42).bitPerfect, isFalse);
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
