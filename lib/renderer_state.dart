import 'dart:convert';

/// What the renderer is doing, as published by the Android service.
///
/// The service owns playback and keeps running with no UI, so this is a
/// read-only view — the screen never holds authoritative state.
class RendererStatus {
  final String rendererName;
  final String transportState;
  final String? title;
  final String? artist;
  final String? album;
  final String? albumArtUri;
  final int durationSeconds;
  final int positionSeconds;
  final String? formatBadge;
  final String? sourceFormat;
  final int sourceRate;
  final int sourceBits;
  final int channels;
  final int deviceBits;
  final String? dacName;
  final bool dacConnected;
  final int dacCount;
  final bool bitPerfect;

  /// Which output is carrying audio: 'usb' or 'android'.
  final String output;
  final int dacVolume;
  final bool dacVolumeSupported;

  /// trusted | untrusted | unknown -- whether the DAC reports its own volume.
  final String dacVolumeReadback;
  final int underruns;
  final String? lastError;

  const RendererStatus({
    this.rendererName = 'HiFi Renderer',
    this.transportState = 'NO_MEDIA_PRESENT',
    this.title,
    this.artist,
    this.album,
    this.albumArtUri,
    this.durationSeconds = 0,
    this.positionSeconds = 0,
    this.formatBadge,
    this.sourceFormat,
    this.sourceRate = 0,
    this.sourceBits = 0,
    this.channels = 0,
    this.deviceBits = 0,
    this.dacName,
    this.dacConnected = false,
    this.dacCount = 0,
    this.bitPerfect = false,
    this.output = 'usb',
    this.dacVolume = -1,
    this.dacVolumeSupported = false,
    this.dacVolumeReadback = 'unknown',
    this.underruns = 0,
    this.lastError,
  });

  static RendererStatus parse(String source) {
    try {
      final j = jsonDecode(source) as Map<String, dynamic>;
      return RendererStatus(
        rendererName: j['rendererName'] as String? ?? 'HiFi Renderer',
        transportState: j['transportState'] as String? ?? 'NO_MEDIA_PRESENT',
        title: j['title'] as String?,
        artist: j['artist'] as String?,
        album: j['album'] as String?,
        albumArtUri: j['albumArtUri'] as String?,
        durationSeconds: j['durationSeconds'] as int? ?? 0,
        positionSeconds: j['positionSeconds'] as int? ?? 0,
        formatBadge: j['formatBadge'] as String?,
        sourceFormat: j['sourceFormat'] as String?,
        sourceRate: j['sourceRate'] as int? ?? 0,
        sourceBits: j['sourceBits'] as int? ?? 0,
        channels: j['channels'] as int? ?? 0,
        deviceBits: j['deviceBits'] as int? ?? 0,
        dacName: j['dacName'] as String?,
        dacConnected: j['dacConnected'] as bool? ?? false,
        dacCount: (j['dacCount'] as num?)?.toInt() ?? 0,
        bitPerfect: j['bitPerfect'] as bool? ?? false,
        output: j['output'] as String? ?? 'usb',
        dacVolume: (j['dacVolume'] as num?)?.toInt() ?? -1,
        dacVolumeSupported: j['dacVolumeSupported'] as bool? ?? false,
        dacVolumeReadback: j['dacVolumeReadback'] as String? ?? 'unknown',
        underruns: (j['underruns'] as num?)?.toInt() ?? 0,
        lastError: j['lastError'] as String?,
      );
    } catch (_) {
      return const RendererStatus();
    }
  }

  bool get isPlaying => transportState == 'PLAYING';
  bool get isPaused => transportState == 'PAUSED_PLAYBACK';
  /// True only when the DAC will actually accept a volume change. Many DACs
  /// expose none at all, and showing a slider that does nothing is worse than
  /// showing no slider.
  bool get canControlVolume => dacVolumeSupported && dacVolume >= 0;

  /// Playing through Android's mixer instead of a DAC, so nothing is
  /// bit-perfect and the screen must not imply otherwise.
  bool get usingSystemAudio => output == 'android';

  /// The DAC takes a volume but will not report one, so its own knob or remote
  /// cannot be followed and this shows the last value sent.
  bool get volumeIsWriteOnly => canControlVolume && dacVolumeReadback == 'untrusted';

  bool get hasTrack => title != null || transportState != 'NO_MEDIA_PRESENT';

  double get progress => durationSeconds > 0
      ? (positionSeconds / durationSeconds).clamp(0.0, 1.0)
      : 0.0;

  /// Local echo while a volume change is in flight to the DAC.
  RendererStatus copyWithVolume(int volume) => RendererStatus(
        rendererName: rendererName,
        transportState: transportState,
        title: title,
        artist: artist,
        album: album,
        albumArtUri: albumArtUri,
        durationSeconds: durationSeconds,
        positionSeconds: positionSeconds,
        formatBadge: formatBadge,
        sourceFormat: sourceFormat,
        sourceRate: sourceRate,
        sourceBits: sourceBits,
        channels: channels,
        deviceBits: deviceBits,
        dacName: dacName,
        dacConnected: dacConnected,
        dacCount: dacCount,
        bitPerfect: bitPerfect,
        output: output,
        dacVolume: volume,
        dacVolumeSupported: dacVolumeSupported,
        dacVolumeReadback: dacVolumeReadback,
        underruns: underruns,
        lastError: lastError,
      );

  static String formatTime(int seconds) {
    if (seconds < 0) return '0:00';
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    return h > 0
        ? '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}'
        : '$m:${s.toString().padLeft(2, '0')}';
  }
}
